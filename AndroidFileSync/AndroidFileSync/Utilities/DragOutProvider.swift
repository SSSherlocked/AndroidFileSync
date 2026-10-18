//
//  DragOutProvider.swift
//  AndroidFileSync
//
//  Everything a dragged device file carries, and the one way to read it back.
//
//  DRAG AND DROP RULES — every drag source and drop target goes through here.
//  They are checked by DragAndDropContractTests; change the tests with the rules.
//
//  1. A dragged device item carries exactly two representations, in this order:
//     a. the file itself, lazily: nothing is pulled from the phone until a
//        receiver (Finder) asks for it. Files are always declared as plain data
//        (`public.data`) and folders as `public.folder`, never as their specific
//        type: Finder treats typed drags specially (text becomes a clipping and a
//        file is refused), so one generic type behaves the same for every file.
//        The suggested name carries the extension.
//     b. the in-app payload (`DraggedDeviceItem`, the device path), visible to
//        this process only. It must come second: a file-promise receiver writes
//        out the FIRST representation.
//  2. In-app drop targets never read the file representation. Reading it starts
//     a download that needs the main thread, so a synchronous read from inside
//     the app deadlocks. Use `DraggedDeviceItem.load(from:)` for device items and
//     `DraggedDeviceItem.loadFileURLs(from:)` for Mac files; both skip the file
//     representation of our own items. As a last line of defence the file
//     representation refuses to download while the main thread is blocked.
//

import Foundation
import UniformTypeIdentifiers

// nonisolated: the project defaults to MainActor isolation, but the file
// representation load handler is invoked by the system on a background thread.
nonisolated enum DragOutProvider {

    /// Root folder for staged drag-out downloads.
    static let stagingRoot: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("AndroidFileSync-DragOut", isDirectory: true)

    /// Staged items older than this are purged when a new drag starts.
    private static let stagingMaxAge: TimeInterval = 60 * 60

    /// True when the URL points into the drag-out staging area — used to ignore
    /// drops of our own dragged items back onto the browser (would re-upload).
    static func isStagedURL(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(stagingRoot.standardizedFileURL.path)
    }

    static func makeItemProvider(for file: UnifiedFile, downloadManager: DownloadManager) -> NSItemProvider {
        purgeOldStagingFolders()
        return makeItemProvider(for: file) { file in
            try await stage(file, downloadManager: downloadManager)
        }
    }

    /// The declared type of a dragged item's file representation (rule 1a).
    static func fileTypeIdentifier(for file: UnifiedFile) -> String {
        file.isDirectory ? UTType.folder.identifier : UTType.data.identifier
    }

    /// Builds the provider; `stage` pulls the item to a local URL when a receiver
    /// asks for the file. Separate from the DownloadManager wiring for tests.
    static func makeItemProvider(
        for file: UnifiedFile,
        stage: @escaping @Sendable (UnifiedFile) async throws -> URL
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = file.name

        provider.registerFileRepresentation(
            forTypeIdentifier: fileTypeIdentifier(for: file),
            fileOptions: [],
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 1)
            Task.detached {
                // The download runs through the main actor. When this representation
                // is read synchronously inside our own process (SwiftUI's List drop
                // insertion, an onDrop that loads a URL from the item), the main
                // thread is parked waiting for the result, so the download could never
                // finish and the app froze for good. Refuse the file in that case:
                // in-app drops only need the device-path payload below.
                guard await mainThreadResponds(within: mainThreadProbeTimeout) else {
                    print("⚠️ Drag-out for \(file.name) requested while the main thread is blocked — refusing")
                    completion(nil, false, mainThreadBlockedError)
                    return
                }
                do {
                    let url = try await stage(file)
                    progress.completedUnitCount = 1
                    // coordinated = false: the receiver copies the file before we delete it
                    completion(url, false, nil)
                } catch {
                    print("❌ Drag-out failed for \(file.name): \(error)")
                    completion(nil, false, error)
                }
            }
            return progress
        }

        // In-app payload (rule 1b), registered AFTER the file representation.
        if let payload = try? JSONEncoder().encode(DraggedDeviceItem(path: file.path, isDirectory: file.isDirectory)) {
            provider.registerDataRepresentation(
                forTypeIdentifier: DraggedDeviceItem.typeIdentifier,
                visibility: .ownProcess
            ) { completion in
                completion(payload, nil)
                return nil
            }
        }

        return provider
    }

    /// How long the main thread gets to answer the probe before a file request is refused.
    /// An idle main thread answers in well under a millisecond; a thread that is blocked
    /// in a synchronous pasteboard read never answers.
    private static let mainThreadProbeTimeout: TimeInterval = 0.5

    private static let mainThreadBlockedError = NSError(
        domain: "DragOut", code: -2,
        userInfo: [NSLocalizedDescriptionKey: "File requested while the app's main thread is blocked"]
    )

    /// True when the main thread runs a block within `timeout`. Never blocks the caller.
    private static func mainThreadResponds(within timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ResumeOnce(continuation)
            DispatchQueue.main.async { once.resume(returning: true) }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                once.resume(returning: false)
            }
        }
    }

    /// Resumes a continuation at most once, from whichever of two queues gets there first.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?

        init(_ continuation: CheckedContinuation<Bool, Never>) {
            self.continuation = continuation
        }

        func resume(returning value: Bool) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    /// Pulls the file or folder into a unique staging folder and returns its local URL.
    private static func stage(_ file: UnifiedFile, downloadManager: DownloadManager) async throws -> URL {
        let stagingDir = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let localURL = stagingDir.appendingPathComponent(file.name, isDirectory: file.isDirectory)

        if file.isDirectory {
            try FileManager.default.createDirectory(at: localURL, withIntermediateDirectories: true)
            await downloadManager.downloadFolder(
                devicePath: file.path,
                folderName: file.name,
                to: localURL
            )
        } else {
            try await downloadManager.downloadFile(
                devicePath: file.path,
                fileName: file.name,
                fileSize: file.size,
                to: localURL.path
            )
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                throw NSError(domain: "DragOut", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Download was cancelled"])
            }
        }
        return localURL
    }

    private static let purgeQueue = DispatchQueue(label: "com.androidfilesync.dragout-purge", qos: .utility)

    /// Removes old staged downloads in the background: this runs at the start of
    /// every drag, and deleting large staged files must not block the main thread.
    private static func purgeOldStagingFolders() {
        purgeQueue.async { purgeOldStagingFoldersNow() }
    }

    private static func purgeOldStagingFoldersNow() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-stagingMaxAge)
        for entry in entries {
            let created = (try? entry.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }
}

/// A device file or folder dragged inside the app.
nonisolated struct DraggedDeviceItem: Codable, Sendable {
    static let typeIdentifier = "com.androidfilesync.device-item"
    static let type = UTType(exportedAs: typeIdentifier)

    let path: String
    let isDirectory: Bool

    /// Decodes every in-app item carried by a drop.
    static func load(from providers: [NSItemProvider]) async -> [DraggedDeviceItem] {
        var items: [DraggedDeviceItem] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            let data: Data? = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            if let data, let item = try? JSONDecoder().decode(DraggedDeviceItem.self, from: data) {
                items.append(item)
            }
        }
        return items
    }

    /// Local file URLs carried by a drop (from Finder), skipping our own staged drag-outs.
    static func loadFileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers
        where !provider.hasItemConformingToTypeIdentifier(typeIdentifier)
            && provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            if let url, !DragOutProvider.isStagedURL(url) {
                urls.append(url)
            }
        }
        return urls
    }
}
