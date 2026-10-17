//
//  SidebarManager.swift
//  AndroidFileSync
//
//  Manages sidebar Quick Access items — built-in + user-defined custom items.
//  Custom items and hidden built-ins are persisted to UserDefaults.
//

import Foundation
import SwiftUI  // Array.move(fromOffsets:toOffset:)
internal import Combine

class SidebarManager: ObservableObject {

    // MARK: - Published State

    /// All user-visible items in sidebar order: built-ins (minus hidden) and custom
    /// folders, as arranged and customised by the user. The SD card is not stored
    /// here; it is injected dynamically by `visibleItems`.
    @Published var items: [QuickAccessItem] = []

    /// Paths of built-in items the user has hidden
    @Published var hiddenBuiltInPaths: Set<String> = []

    /// Paths confirmed to exist on the connected device
    @Published var existingPaths: Set<String> = []

    /// Paths that have been checked at least once (so we can distinguish "unchecked" from "missing")
    @Published var checkedPaths: Set<String> = []

    /// Dynamically injected SD card item (nil when no card detected)
    @Published var sdCardItem: QuickAccessItem? = nil

    // MARK: - Computed

    /// Storage root of the active device user (owner, clone space…). Built-in
    /// folders are stored with the owner's paths and shown under this root.
    @Published var storageRoot = DeviceUsers.ownerStorageRoot {
        didSet {
            guard storageRoot != oldValue else { return }
            Task { await checkExistence() }
        }
    }

    /// All currently visible sidebar items (stored order + SD card if present)
    var visibleItems: [QuickAccessItem] {
        var result = items.map(displayed)
        // Insert SD card right after Internal Storage if detected
        if let sd = sdCardItem {
            let insertIndex = result.firstIndex(where: { $0.path == storageRoot }).map { $0 + 1 } ?? 1
            result.insert(sd, at: min(insertIndex, result.count))
        }
        return result
    }

    /// A stored item as shown: built-in folders follow the active user's storage
    /// root; custom folders keep their exact path.
    private func displayed(_ item: QuickAccessItem) -> QuickAccessItem {
        let owner = DeviceUsers.ownerStorageRoot
        guard item.isBuiltIn, storageRoot != owner,
              item.path == owner || item.path.hasPrefix(owner + "/") else { return item }
        return QuickAccessItem(
            name: item.name,
            icon: item.icon,
            path: storageRoot + String(item.path.dropFirst(owner.count)),
            color: item.color,
            isBuiltIn: true
        )
    }

    /// Index in `items` of the stored item behind a displayed path.
    private func storedIndex(forDisplayedPath path: String) -> Int? {
        items.firstIndex { displayed($0).path == path }
    }

    /// True when at least one built-in item is hidden (so user can restore)
    var hasHiddenBuiltIns: Bool { !hiddenBuiltInPaths.isEmpty }

    /// Stored items can be renamed/recoloured; the dynamic SD card entry cannot.
    func isEditable(_ item: QuickAccessItem) -> Bool {
        storedIndex(forDisplayedPath: item.path) != nil
    }

    // MARK: - Init

    init() { load() }

    // MARK: - Existence Checking

    /// True while an existence check is running (rows show a spinner only then).
    @Published private(set) var isCheckingExistence = false
    /// Set when a check is requested while one is running; it re-runs once after.
    private var existenceCheckPending = false

    /// Checks which sidebar paths actually exist on the connected device via ADB.
    /// Overlapping requests are merged, and a failed check (device not ready, adb
    /// hiccup) changes nothing: folders are hidden only when confirmed missing.
    func checkExistence() async {
        if isCheckingExistence {
            existenceCheckPending = true
            return
        }
        isCheckingExistence = true
        repeat {
            existenceCheckPending = false
            await runExistenceCheck()
        } while existenceCheckPending
        isCheckingExistence = false
    }

    private func runExistenceCheck() async {
        let paths = visibleItems.map(\.path)
        guard !paths.isEmpty else { return }

        let adbPath = ADBManager.getADBPath()
        guard !adbPath.isEmpty else { return }

        // One shell command for all paths, one "1"/"0" line per path, so the check
        // costs a single adb round-trip instead of one process per folder.
        let script = paths.map { path in
            let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
            return "[ -d '\(escaped)' ] && echo 1 || echo 0"
        }.joined(separator: "; ")

        let (code, output, _) = await Shell.runAsyncWithTimeout(
            adbPath,
            args: ADBManager.deviceArgs(["shell", script]),
            timeoutSeconds: 8.0
        )
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard code == 0, lines.count == paths.count, lines.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            print("📂 Sidebar: existence check inconclusive (code \(code), \(lines.count)/\(paths.count) lines) — keeping current state.")
            return
        }

        var newExisting: Set<String> = []
        for (path, line) in zip(paths, lines) where line == "1" {
            newExisting.insert(path)
        }

        await MainActor.run {
            self.existingPaths = newExisting
            self.checkedPaths = Set(paths)
        }
    }

    // MARK: - SD Card

    /// Call this whenever DeviceManager.sdCardPath changes.
    /// Pass nil to remove the SD card entry (device disconnected or no card).
    func updateSDCard(path: String?) {
        guard let path else {
            sdCardItem = nil
            // Remove any stale SD card paths from tracking sets
            let sdPaths = checkedPaths.filter { $0.hasPrefix("/storage/") && $0 != "/storage/emulated/0" }
            existingPaths.subtract(sdPaths)
            checkedPaths.subtract(sdPaths)
            return
        }
        sdCardItem = QuickAccessItem(
            name: "SD Card",
            icon: "sdcard.fill",
            path: path,
            color: "orange",
            isBuiltIn: false
        )
        // Mark it as existing immediately since DeviceManager already confirmed it
        existingPaths.insert(path)
        checkedPaths.insert(path)
    }

    // MARK: - Mutations

    /// Add the given Android path as a custom sidebar item.
    /// Silently ignores duplicates. Then re-checks existence.
    func addItem(name: String, path: String, icon: String = "folder.fill", color: String = "blue") {
        guard !visibleItems.contains(where: { $0.path == path }) else {
            // Already in the sidebar but possibly hidden by an earlier failed check:
            // confirm it again instead of silently ignoring the drop.
            Task { await checkExistence() }
            return
        }
        let item = QuickAccessItem(name: name, icon: icon, path: path, color: color, isBuiltIn: false)
        items.append(item)
        save()
        // Immediately check existence of the newly added item
        Task { await checkExistence() }
    }

    /// Remove a sidebar item. Built-ins are hidden (restorable); custom items are deleted.
    func removeItem(_ item: QuickAccessItem) {
        guard let index = storedIndex(forDisplayedPath: item.path) else { return }
        let stored = items.remove(at: index)
        if stored.isBuiltIn {
            hiddenBuiltInPaths.insert(stored.path)
        } else {
            existingPaths.remove(item.path)
            checkedPaths.remove(item.path)
        }
        save()
    }

    /// Change an item's display name, icon and colour. The path stays the same.
    func updateItem(path: String, name: String, icon: String, color: String) {
        guard let index = storedIndex(forDisplayedPath: path) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items[index].name = trimmed }
        items[index].icon = icon
        items[index].color = color
        save()
    }

    /// Reorder after a drag in the sidebar.
    /// `displayed` is the list exactly as shown (it may omit missing folders and
    /// include the SD card), so the move is applied to that list and the new
    /// relative order is written back into `items`; items not shown keep their slots.
    func move(displayed: [QuickAccessItem], fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = displayed
        reordered.move(fromOffsets: source, toOffset: destination)

        // `displayed` holds items as shown (built-ins under the active user's
        // root); map them back to the stored items before writing the order.
        let storedByDisplayedPath = Dictionary(
            items.map { (self.displayed($0).path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var queue = reordered.compactMap { storedByDisplayedPath[$0.path] }.makeIterator()
        let shownPaths = Set(displayed.map(\.path))

        items = items.map { item in
            guard shownPaths.contains(self.displayed(item).path), let next = queue.next() else { return item }
            return next
        }
        save()
    }

    /// Restore all hidden built-in items to their default positions
    func restoreBuiltIns() {
        for (defaultIndex, builtIn) in QuickAccessItem.commonFolders.enumerated()
        where hiddenBuiltInPaths.contains(builtIn.path) && !items.contains(where: { $0.path == builtIn.path }) {
            items.insert(builtIn, at: min(defaultIndex, items.count))
        }
        hiddenBuiltInPaths.removeAll()
        save()
        Task { await checkExistence() }
    }

    // MARK: - Persistence

    private let itemsKey   = "sidebar_items_v3"
    private let legacyCustomKey = "sidebar_customItems_v2"
    private let hiddenKey  = "sidebar_hiddenPaths_v2"

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: itemsKey)
        }
        UserDefaults.standard.set(Array(hiddenBuiltInPaths), forKey: hiddenKey)
    }

    private func load() {
        let hidden = Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
        hiddenBuiltInPaths = hidden

        if let data = UserDefaults.standard.data(forKey: itemsKey),
           let stored = try? JSONDecoder().decode([QuickAccessItem].self, from: data) {
            items = stored
            return
        }

        // Migrate from v2: default built-ins (minus hidden) followed by custom items.
        var migrated = QuickAccessItem.commonFolders.filter { !hidden.contains($0.path) }
        if let data = UserDefaults.standard.data(forKey: legacyCustomKey),
           let custom = try? JSONDecoder().decode([QuickAccessItem].self, from: data) {
            migrated += custom.filter { item in !migrated.contains { $0.path == item.path } }
        }
        items = migrated
        save()
    }
}
