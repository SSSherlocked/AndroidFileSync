//
//  BrowserCommands.swift
//  AndroidFileSync
//
//  Finder-style menu bar commands (File, View, Go). The focused window's file
//  browser publishes its actions as a focused scene value; the menus read them
//  and are disabled when no browser window is focused.
//

import SwiftUI

/// Browser view modes, persisted under `BrowserPreferences.viewModeKey`.
enum BrowserViewMode: String, CaseIterable {
    case list
    case icons
}

/// UserDefaults keys shared by the menus, the Settings window and the browser.
enum BrowserPreferences {
    static let showHiddenFilesKey = "showHiddenFiles"
    static let showStatusBarKey = "showStatusBar"
    static let showPreviewPaneKey = "showPreviewPane"
    static let viewModeKey = "browserViewMode"
}

/// Everything the menu bar can do to the focused file browser.
struct BrowserActions {
    /// False while the Apps view is showing instead of files.
    var isFileBrowser: Bool
    var hasSelection: Bool
    var hasSingleSelection: Bool
    var canGoBack: Bool
    var canGoForward: Bool
    var canGoUp: Bool

    var newFolder: () -> Void
    var newFile: () -> Void
    var openSelection: () -> Void
    var quickLook: () -> Void
    var getInfo: () -> Void
    var rename: () -> Void
    var download: () -> Void
    var upload: () -> Void
    var moveToTrash: () -> Void
    var deleteImmediately: () -> Void
    var deselectAll: () -> Void
    var refresh: () -> Void
    var goBack: () -> Void
    var goForward: () -> Void
    var goUp: () -> Void
    var goToFolder: () -> Void
    var goToPath: (String) -> Void
    var sort: (ActionToolbar.SortOption) -> Void
}

private struct BrowserActionsKey: FocusedValueKey {
    typealias Value = BrowserActions
}

extension FocusedValues {
    var browserActions: BrowserActions? {
        get { self[BrowserActionsKey.self] }
        set { self[BrowserActionsKey.self] = newValue }
    }
}

struct BrowserCommands: Commands {
    @FocusedValue(\.browserActions) private var actions
    @AppStorage(BrowserPreferences.showHiddenFilesKey) private var showHiddenFiles = false
    @AppStorage(BrowserPreferences.showStatusBarKey) private var showStatusBar = true
    @AppStorage(BrowserPreferences.showPreviewPaneKey) private var showPreviewPane = false
    @AppStorage(BrowserPreferences.viewModeKey) private var viewMode = BrowserViewMode.list.rawValue

    private var files: Bool { actions?.isFileBrowser ?? false }
    private var selection: Bool { files && (actions?.hasSelection ?? false) }
    private var singleSelection: Bool { files && (actions?.hasSingleSelection ?? false) }

    /// Checkmark binding for one view mode; turning it on selects that mode.
    private func viewModeBinding(_ mode: BrowserViewMode) -> Binding<Bool> {
        Binding(
            get: { viewMode == mode.rawValue },
            set: { if $0 { viewMode = mode.rawValue } }
        )
    }

    var body: some Commands {
        // ── File ────────────────────────────────────────────────────────────
        CommandGroup(after: .newItem) {
            Button("New Folder") { actions?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!files)
            Button("New File") { actions?.newFile() }
                .disabled(!files)

            Divider()

            Button("Open") { actions?.openSelection() }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!singleSelection)
            Button("Quick Look") { actions?.quickLook() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(!singleSelection)
            Button("Get Info") { actions?.getInfo() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!singleSelection)
            Button("Rename…") { actions?.rename() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!singleSelection)

            Divider()

            Button("Download to Mac…") { actions?.download() }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .disabled(!selection)
            Button("Upload from Mac…") { actions?.upload() }
                .keyboardShortcut("u", modifiers: .command)
                .disabled(!files)

            Divider()

            Button("Move to Trash") { actions?.moveToTrash() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!selection)
            Button("Delete Immediately…") { actions?.deleteImmediately() }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(!selection)
        }

        // ── Edit ────────────────────────────────────────────────────────────
        // Cut/Copy/Paste/Select All stay in the system Edit menu so they keep
        // working in text fields; the browser handles them when it has focus.
        CommandGroup(after: .pasteboard) {
            Button("Deselect All") { actions?.deselectAll() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(!selection)
        }

        // ── View ────────────────────────────────────────────────────────────
        CommandGroup(before: .toolbar) {
            Toggle("as List", isOn: viewModeBinding(.list))
                .keyboardShortcut("1", modifiers: .command)
            Toggle("as Icons", isOn: viewModeBinding(.icons))
                .keyboardShortcut("2", modifiers: .command)

            Divider()

            Menu("Sort By") {
                ForEach(ActionToolbar.SortOption.allCases, id: \.self) { option in
                    Button(option.rawValue) { actions?.sort(option) }
                }
            }
            .disabled(!files)

            Toggle("Show Hidden Files", isOn: $showHiddenFiles)
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Toggle("Show Status Bar", isOn: $showStatusBar)
                .keyboardShortcut("/", modifiers: .command)
            Toggle("Show Preview", isOn: $showPreviewPane)
                .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Button("Refresh") { actions?.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions == nil)

            Divider()
        }

        // ── Go ──────────────────────────────────────────────────────────────
        CommandMenu("Go") {
            Button("Back") { actions?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(actions?.canGoBack ?? false))
            Button("Forward") { actions?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(actions?.canGoForward ?? false))
            Button("Enclosing Folder") { actions?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!(actions?.canGoUp ?? false))

            Divider()

            ForEach(QuickAccessItem.commonFolders) { folder in
                Button(folder.name) { actions?.goToPath(folder.path) }
                    .disabled(actions == nil)
            }

            Divider()

            Button("Go to Folder…") { actions?.goToFolder() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
    }
}
