//
//  DeviceUsers.swift
//  AndroidFileSync
//
//  Android users on the connected phone (owner, work profile, clone / private
//  spaces…) and what adb can actually do with each one's storage.
//
//  Vendors restrict other users differently, so nothing is assumed: every user is
//  tested before it is offered. A plain `ls` of a blocked user's storage root can
//  succeed and simply return nothing, so a user only counts as browsable when a
//  folder *inside* its root can be listed.
//

import Foundation
internal import Combine

struct DeviceUser: Identifiable, Equatable {
    enum Access: Equatable {
        /// Not tested yet.
        case unknown
        /// Its storage can be browsed through the file system.
        case files(writable: Bool)
        /// Files are blocked, but its media library (MediaStore) answers
        /// cross-user queries. Not browsable yet.
        case mediaOnly
        /// Nothing works; the reason is shown in the menu.
        case unavailable(String)
    }

    let id: Int
    let name: String
    let isRunning: Bool
    var access: Access = .unknown

    var storageRoot: String { "/storage/emulated/\(id)" }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "User \(id)" : trimmed
    }

    var canBrowseFiles: Bool {
        if case .files = access { return true }
        return false
    }

    /// Short status for menus, e.g. "Read only" or "Not running".
    var accessDescription: String {
        switch access {
        case .unknown: return "Checking…"
        case .files(let writable): return writable ? "" : "Read only"
        case .mediaOnly: return "Media library only — not supported yet"
        case .unavailable(let reason): return reason
        }
    }
}

@MainActor
final class DeviceUsers: ObservableObject {
    static let shared = DeviceUsers()

    static let ownerStorageRoot = "/storage/emulated/0"

    @Published private(set) var users: [DeviceUser] = []
    /// The user whose storage the browser shows.
    @Published private(set) var activeUserID: Int = 0
    @Published private(set) var isRefreshing = false

    var activeUser: DeviceUser? { users.first { $0.id == activeUserID } }

    var activeStorageRoot: String {
        activeUser?.storageRoot ?? Self.ownerStorageRoot
    }

    /// The switcher is only worth showing when there is more than one user.
    var hasMultipleUsers: Bool { users.count > 1 }

    private init() {}

    func select(_ user: DeviceUser) {
        guard user.canBrowseFiles else { return }
        activeUserID = user.id
    }

    func reset() {
        users = []
        activeUserID = 0
    }

    /// Lists the users, tests each one's access and selects the phone's foreground
    /// user when it is browsable (otherwise keeps the current choice or the owner).
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let adbPath = ADBManager.getADBPath()
        guard !adbPath.isEmpty else { return }

        var listed = await Self.listUsers(adbPath: adbPath)
        guard !listed.isEmpty else {
            // Older phones or restricted shells: behave as a single-user device.
            users = []
            activeUserID = 0
            return
        }

        for index in listed.indices {
            listed[index].access = await Self.probeAccess(of: listed[index], adbPath: adbPath)
        }
        let foreground = await Self.foregroundUserID(adbPath: adbPath)

        users = listed
        if let foreground, listed.contains(where: { $0.id == foreground && $0.canBrowseFiles }) {
            activeUserID = foreground
        } else if !listed.contains(where: { $0.id == activeUserID && $0.canBrowseFiles }) {
            activeUserID = 0
        }
        print("👥 Users: " + listed.map { "\($0.id) \($0.displayName) [\($0.access)]" }.joined(separator: ", "))
    }

    // MARK: - adb queries

    /// Parses `UserInfo{11:Name:1030} running` lines from `cmd user list`
    /// (falling back to `pm list users`).
    nonisolated private static func listUsers(adbPath: String) async -> [DeviceUser] {
        for command in ["cmd user list", "pm list users"] {
            let (code, output, _) = await Shell.runAsyncWithTimeout(
                adbPath, args: ADBManager.deviceArgs(["shell", command]), timeoutSeconds: 5.0
            )
            guard code == 0 else { continue }
            let users = parseUsers(output)
            if !users.isEmpty { return users }
        }
        return []
    }

    nonisolated static func parseUsers(_ output: String) -> [DeviceUser] {
        var users: [DeviceUser] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard let open = text.range(of: "UserInfo{"),
                  let close = text.range(of: "}", range: open.upperBound..<text.endIndex) else { continue }
            // "<id>:<name>:<flags>" — the name may itself contain colons.
            let inner = text[open.upperBound..<close.lowerBound]
            guard let firstColon = inner.firstIndex(of: ":"),
                  let lastColon = inner.lastIndex(of: ":"),
                  firstColon < lastColon,
                  let id = Int(inner[..<firstColon]) else { continue }
            let name = String(inner[inner.index(after: firstColon)..<lastColon])
            let running = text[close.upperBound...].contains("running")
            users.append(DeviceUser(id: id, name: name, isRunning: running))
        }
        return users.sorted { $0.id < $1.id }
    }

    nonisolated private static func foregroundUserID(adbPath: String) async -> Int? {
        let (code, output, _) = await Shell.runAsyncWithTimeout(
            adbPath, args: ADBManager.deviceArgs(["shell", "am get-current-user"]), timeoutSeconds: 4.0
        )
        guard code == 0 else { return nil }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Tests what adb can do with one user's storage. The write test creates and
    /// immediately removes a hidden file in the user's storage root.
    nonisolated private static func probeAccess(of user: DeviceUser, adbPath: String) async -> DeviceUser.Access {
        guard user.isRunning else {
            return .unavailable("Not running")
        }
        let root = user.storageRoot
        let script = """
        d='\(root)'; first=$(ls -A "$d" 2>/dev/null | head -n 1); \
        if [ -n "$first" ] && ls "$d/$first" >/dev/null 2>&1; then \
          p="$d/.afs_access_probe_$$"; \
          if touch "$p" 2>/dev/null; then rm -f "$p"; echo files-rw; else echo files-ro; fi; \
        else \
          out=$(content query --user \(user.id) --uri content://media/external/file --projection _id --where '_id=-1' 2>&1); \
          case "$out" in *xception*|*rror*|*ermission*) echo none;; *) echo media;; esac; \
        fi
        """
        let (code, output, _) = await Shell.runAsyncWithTimeout(
            adbPath, args: ADBManager.deviceArgs(["shell", script]), timeoutSeconds: 8.0
        )
        guard code == 0 else { return .unavailable("Could not be checked") }
        switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "files-rw": return .files(writable: true)
        case "files-ro": return .files(writable: false)
        case "media": return .mediaOnly
        default: return .unavailable("Blocked by the phone")
        }
    }
}
