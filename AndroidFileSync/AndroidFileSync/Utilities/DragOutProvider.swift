//
//  DragOutProvider.swift
//  AndroidFileSync
//
//  Drag files/folders from the file browser out to Finder (or any app that
//  accepts file drops). The item provider registers a lazy file representation:
//  nothing is transferred until the drop target asks for the data, at which
//  point the item is pulled from the device into a temporary staging folder
//  (with progress shown in the normal transfer UI) and handed to the receiver,
//  which copies it to its final location.
//

import Foundation
import UniformTypeIdentifiers

enum DragOutProvider {

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

        let provider = NSItemProvider()
        provider.suggestedName = file.name

        let typeIdentifier: String
        if file.isDirectory {
            typeIdentifier = UTType.folder.identifier
        } else {
            let ext = (file.name as NSString).pathExtension
            typeIdentifier = (UTType(filenameExtension: ext) ?? .data).identifier
        }

        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 1)
            Task.detached {
                do {
                    let url = try await stage(file, downloadManager: downloadManager)
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

        return provider
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

    private static func purgeOldStagingFolders() {
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
