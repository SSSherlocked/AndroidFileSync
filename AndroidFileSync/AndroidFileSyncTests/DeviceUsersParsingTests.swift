//
//  DeviceUsersParsingTests.swift
//  AndroidFileSyncTests
//

import XCTest
@testable import AndroidFileSync

@MainActor
final class DeviceUsersParsingTests: XCTestCase {

    /// `cmd user list` from a OnePlus phone (Android 15) with clone and private spaces.
    private let onePlusOutput = """
    Users:
    \tUserInfo{0:机主:4c13} running
    \tUserInfo{10:system_clone:20000410}
    \tUserInfo{11: 壶中界 :1030} running
    \tUserInfo{999:MultiApp:4001010} running
    """

    func testParsesIDsRunningStateAndNames() {
        let users = DeviceUsers.parseUsers(onePlusOutput)

        XCTAssertEqual(users.map(\.id), [0, 10, 11, 999])
        XCTAssertEqual(users.map(\.isRunning), [true, false, true, true])
        XCTAssertEqual(users.map(\.displayName), ["机主", "system_clone", "壶中界", "MultiApp"])
        XCTAssertEqual(users[3].storageRoot, "/storage/emulated/999")
    }

    func testNameMayContainColons() {
        let users = DeviceUsers.parseUsers("UserInfo{12:Work: Profile:1030} running")
        XCTAssertEqual(users.first?.id, 12)
        XCTAssertEqual(users.first?.name, "Work: Profile")
    }

    func testEmptyNameFallsBackToUserNumber() {
        let users = DeviceUsers.parseUsers("UserInfo{13::1030}")
        XCTAssertEqual(users.first?.displayName, "User 13")
        XCTAssertEqual(users.first?.isRunning, false)
    }

    func testIgnoresOutputWithoutUsers() {
        XCTAssertTrue(DeviceUsers.parseUsers("").isEmpty)
        XCTAssertTrue(DeviceUsers.parseUsers("Error: java.lang.SecurityException").isEmpty)
    }

    func testOnlyUsersWithFileAccessCanBeBrowsed() {
        var user = DeviceUser(id: 11, name: "Space", isRunning: true)
        user.access = .mediaOnly
        XCTAssertFalse(user.canBrowseFiles)
        user.access = .unavailable("Blocked by the phone")
        XCTAssertFalse(user.canBrowseFiles)
        user.access = .files(writable: false)
        XCTAssertTrue(user.canBrowseFiles)
    }
}
