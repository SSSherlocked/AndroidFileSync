//
//  DragAndDropContractTests.swift
//  AndroidFileSyncTests
//
//  The drag and drop rules documented at the top of DragOutProvider.swift.
//  Each rule here once broke in practice (a JSON file instead of the real one in
//  Finder, text files refused by Finder, the app freezing on in-app drops).
//

import XCTest
import UniformTypeIdentifiers
@testable import AndroidFileSync

@MainActor
final class DragAndDropContractTests: XCTestCase {

    /// Counts how often a test provider was asked to pull its file from the phone.
    private final class StageSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var calls: Int {
            lock.lock(); defer { lock.unlock() }
            return count
        }

        func record() {
            lock.lock(); count += 1; lock.unlock()
        }
    }

    private func deviceFile(_ name: String, isDirectory: Bool = false) -> UnifiedFile {
        UnifiedFile(
            name: name,
            path: "/storage/emulated/0/Download/\(name)",
            isDirectory: isDirectory,
            size: 1024
        )
    }

    private func provider(for file: UnifiedFile, spy: StageSpy = StageSpy()) -> NSItemProvider {
        DragOutProvider.makeItemProvider(for: file) { _ in
            spy.record()
            throw CancellationError()
        }
    }

    // MARK: - Rule 1: what a dragged item carries

    func testEveryFileIsOfferedAsGenericDataFirst() {
        let names = [
            "notes.txt", "app.log", "data.json", "table.csv", "page.html",
            "photo.jpg", "movie.mp4", "song.mp3", "archive.zip", "app.apk",
            "link.webloc", "shortcut.url", "README", ".hidden",
        ]
        for name in names {
            let item = provider(for: deviceFile(name))
            XCTAssertEqual(
                item.registeredTypeIdentifiers.first, UTType.data.identifier,
                "\(name) must be offered as plain data first, or Finder may refuse it or write the wrong content"
            )
            XCTAssertEqual(item.suggestedName, name, "\(name) must keep its name and extension")
        }
    }

    func testFolderIsOfferedAsFolderFirst() {
        let item = provider(for: deviceFile("DCIM", isDirectory: true))
        XCTAssertEqual(item.registeredTypeIdentifiers.first, UTType.folder.identifier)
    }

    func testInAppPayloadIsTheOnlyOtherRepresentationAndComesLast() {
        let item = provider(for: deviceFile("notes.txt"))
        XCTAssertEqual(item.registeredTypeIdentifiers.count, 2)
        XCTAssertEqual(item.registeredTypeIdentifiers.last, DraggedDeviceItem.typeIdentifier)
    }

    // MARK: - Rule 2: in-app drops never read the file

    func testInAppPayloadLoadsWithoutPullingTheFile() async {
        let spy = StageSpy()
        let file = deviceFile("DCIM", isDirectory: true)
        let items = await DraggedDeviceItem.load(from: [provider(for: file, spy: spy)])

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.path, file.path)
        XCTAssertEqual(items.first?.isDirectory, true)
        XCTAssertEqual(spy.calls, 0, "Reading the in-app payload must not pull the file from the phone")
    }

    func testFileURLLoaderSkipsInAppItems() async {
        let spy = StageSpy()
        let urls = await DraggedDeviceItem.loadFileURLs(from: [provider(for: deviceFile("notes.txt"), spy: spy)])

        XCTAssertTrue(urls.isEmpty, "An in-app item dropped on an upload target must be ignored")
        XCTAssertEqual(spy.calls, 0, "Ignoring an in-app item must not pull it from the phone")
    }

    func testFileURLLoaderReadsFilesFromFinder() async {
        let url = URL(fileURLWithPath: "/tmp/AndroidFileSyncTests/report.txt")
        let finderItem = NSItemProvider(object: url as NSURL)

        let urls = await DraggedDeviceItem.loadFileURLs(from: [finderItem])
        XCTAssertEqual(urls.map(\.path), [url.path])
    }

    func testDeviceItemLoaderIgnoresFinderFiles() async {
        let finderItem = NSItemProvider(object: URL(fileURLWithPath: "/tmp/a.txt") as NSURL)
        let items = await DraggedDeviceItem.load(from: [finderItem])
        XCTAssertTrue(items.isEmpty)
    }

    func testStagedDragOutsAreRecognised() {
        let staged = DragOutProvider.stagingRoot.appendingPathComponent("abc/notes.txt")
        XCTAssertTrue(DragOutProvider.isStagedURL(staged))
        XCTAssertFalse(DragOutProvider.isStagedURL(URL(fileURLWithPath: "/Users/someone/Desktop/notes.txt")))
    }
}
