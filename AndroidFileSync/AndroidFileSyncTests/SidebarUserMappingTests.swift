//
//  SidebarUserMappingTests.swift
//  AndroidFileSyncTests
//
//  Built-in Quick Access folders are stored with the owner's paths and shown
//  under the selected device user's storage root; custom folders keep theirs.
//

import XCTest
@testable import AndroidFileSync

@MainActor
final class SidebarUserMappingTests: XCTestCase {

    private let owner = "/storage/emulated/0"
    private let clone = "/storage/emulated/999"

    /// A settings suite of its own for each test, so nothing touches the app's
    /// real sidebar and tests don't affect each other.
    private func withManager(_ body: (_ makeManager: () -> SidebarManager) throws -> Void) rethrows {
        let suiteName = "AndroidFileSyncTests.SidebarUserMapping.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body { SidebarManager(defaults: defaults) }
    }

    func testBuiltInFoldersFollowTheSelectedUser() {
        withManager { makeManager in
            let manager = makeManager()
            manager.storageRoot = clone

            let paths = manager.visibleItems.map(\.path)
            XCTAssertTrue(paths.contains(clone))
            XCTAssertTrue(paths.contains(clone + "/Download"))
            XCTAssertFalse(paths.contains { $0 == owner || $0.hasPrefix(owner + "/") })
        }
    }

    func testCustomFoldersKeepTheirExactPath() {
        withManager { makeManager in
            let manager = makeManager()
            manager.addItem(name: "Pinned", path: owner + "/Pinned")
            manager.storageRoot = clone

            XCTAssertTrue(manager.visibleItems.contains { $0.path == owner + "/Pinned" })
        }
    }

    func testHidingAMappedBuiltInHidesTheStoredFolder() throws {
        try withManager { makeManager in
            let manager = makeManager()
            manager.storageRoot = clone
            let downloads = try XCTUnwrap(manager.visibleItems.first { $0.path == clone + "/Download" })

            manager.removeItem(downloads)

            XCTAssertTrue(manager.hiddenBuiltInPaths.contains(owner + "/Download"))
            XCTAssertFalse(manager.visibleItems.contains { $0.path.hasSuffix("/Download") })
            // Persisted under the owner path, so it stays hidden for every user.
            XCTAssertFalse(makeManager().visibleItems.contains { $0.path == owner + "/Download" })
        }
    }

    func testEditingAMappedBuiltInKeepsTheEdit() throws {
        try withManager { makeManager in
            let manager = makeManager()
            manager.storageRoot = clone
            let downloads = try XCTUnwrap(manager.visibleItems.first { $0.path == clone + "/Download" })
            XCTAssertTrue(manager.isEditable(downloads))

            manager.updateItem(path: downloads.path, name: "Clone Downloads", icon: "star.fill", color: "red")

            let edited = try XCTUnwrap(manager.visibleItems.first { $0.path == clone + "/Download" })
            XCTAssertEqual(edited.name, "Clone Downloads")
            manager.storageRoot = owner
            XCTAssertEqual(manager.visibleItems.first { $0.path == owner + "/Download" }?.name, "Clone Downloads")
        }
    }

    func testReorderingWhileMappedReordersTheStoredFolders() {
        withManager { makeManager in
            let manager = makeManager()
            manager.storageRoot = clone
            let displayed = manager.visibleItems
            let firstTwo = displayed.prefix(2).map(\.name)

            manager.move(displayed: displayed, fromOffsets: IndexSet(integer: 0), toOffset: 2)

            XCTAssertEqual(manager.visibleItems.prefix(2).map(\.name), Array(firstTwo.reversed()))
            XCTAssertEqual(makeManager().visibleItems.prefix(2).map(\.name), Array(firstTwo.reversed()))
        }
    }
}
