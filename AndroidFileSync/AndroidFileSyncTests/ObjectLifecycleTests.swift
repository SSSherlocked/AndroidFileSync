//
//  ObjectLifecycleTests.swift
//  AndroidFileSyncTests
//
//  Objects the app creates and releases while running (sheets, windows, tests)
//  must be releasable on the main thread. With MainActor default isolation an
//  implicit deinit hops to the main actor through Swift's back-deployment shim,
//  which crashes the process on release (seen as a crash in
//  swift_task_deinitOnExecutorMainActorBackDeploy). Such classes declare an
//  explicit `nonisolated deinit`; a crash here means one lost it.
//

import XCTest
@testable import AndroidFileSync

@MainActor
final class ObjectLifecycleTests: XCTestCase {

    /// Creates an object, releases it, and checks it was actually freed.
    private func assertReleases<T: AnyObject>(_ make: () -> T, file: StaticString = #filePath, line: UInt = #line) {
        weak var released: T?
        do {
            let object = make()
            released = object
        }
        XCTAssertNil(released, "\(T.self) was not released", file: file, line: line)
    }

    func testSidebarManagerCanBeReleased() {
        let suiteName = "AndroidFileSyncTests.Lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        assertReleases { SidebarManager(defaults: defaults) }
    }

    /// Created by the WiFi window and released when it closes.
    func testWirelessWindowObjectsCanBeReleased() {
        assertReleases { ADBPairingBrowser() }
        assertReleases { QRPairingService() }
    }
}
