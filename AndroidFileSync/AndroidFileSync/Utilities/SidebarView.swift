import SwiftUI
import AppKit

struct SidebarView: View {
    @ObservedObject var sidebarManager: SidebarManager
    let currentPath: String
    let onNavigate: (String) -> Void
    var trashCount: Int = 0
    var onOpenTrash: (() -> Void)? = nil
    var onRestoreAllTrash: (() -> Void)? = nil
    var onEmptyTrash: (() -> Void)? = nil
    var activeAppFilter: AppFilter? = nil
    var onSelectAppFilter: ((AppFilter) -> Void)? = nil
    var storageStats: [String: DeviceManager.StorageInfo] = [:]

    @State private var showRestoreAlert = false
    @State private var showEmptyTrashAlert = false
    @State private var editingItem: QuickAccessItem? = nil
    
    enum SidebarItem: Hashable {
        case folder(String)
        case apps
    }
    
    // Derived binding to map external state to List selection
    private var selectionBinding: Binding<SidebarItem?> {
        Binding {
            if onSelectAppFilter != nil && activeAppFilter != nil { return .apps }
            return .folder(currentPath)
        } set: { newValue in
            guard let val = newValue else { return }
            switch val {
            case .folder(let path):
                onNavigate(path)
            case .apps:
                onSelectAppFilter?(.user)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selectionBinding) {

                // ── Quick Access ────────────────────────────────────────────────
                Section {
                    ForEach(displayedQuickAccessItems) { item in
                        QuickAccessRow(
                            item: item,
                            isChecking: !sidebarManager.checkedPaths.contains(item.path),
                            storageInfo: storageStats[item.path],
                            onEdit: editAction(for: item),
                            onRemove: { sidebarManager.removeItem(item) },
                            onRestoreHidden: restoreHiddenAction
                        )
                        .tag(SidebarItem.folder(item.path))
                    }
                    // Drag to reorder, like Finder's Favorites
                    .onMove { source, destination in
                        sidebarManager.move(
                            displayed: displayedQuickAccessItems,
                            fromOffsets: source,
                            toOffset: destination
                        )
                    }
                } header: {
                    Text("Quick Access")
                }
                
                // ── Apps Section ─────────────────────────────────────────────────
                if onSelectAppFilter != nil {
                    Section("Apps") {
                        SidebarRowLabel(title: "Apps", systemImage: "square.grid.2x2.fill", iconColor: .accentColor)
                            .tag(SidebarItem.apps)
                    }
                }
                
                if let openTrash = onOpenTrash {
                    Section("Trash") {
                        Button(action: openTrash) {
                            HStack {
                                SidebarRowLabel(
                                    title: "Trash",
                                    systemImage: trashCount > 0 ? "trash.fill" : "trash",
                                    iconColor: trashCount > 0 ? .red : .secondary
                                )
                                Spacer()
                                if trashCount > 0 {
                                    Text("\(trashCount)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red)
                                        .cornerRadius(8)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Open Trash") { openTrash() }
                            Divider()
                            Button("Restore All") { onRestoreAllTrash?() }
                                .disabled(trashCount == 0 || onRestoreAllTrash == nil)
                            Button("Empty Trash…", role: .destructive) { showEmptyTrashAlert = true }
                                .disabled(trashCount == 0 || onEmptyTrash == nil)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 200)
        .sheet(item: $editingItem) { item in
            SidebarItemEditor(item: item) { name, icon, color in
                sidebarManager.updateItem(path: item.path, name: name, icon: icon, color: color)
            }
        }
        .alert("Empty Trash?", isPresented: $showEmptyTrashAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Empty Trash", role: .destructive) { onEmptyTrash?() }
        } message: {
            Text("All \(trashCount) items will be permanently deleted from the device. This cannot be undone.")
        }
        .alert("Restore Default Folders?", isPresented: $showRestoreAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Restore") { sidebarManager.restoreBuiltIns() }
        } message: {
            Text("All hidden default folders will reappear in the sidebar.")
        }
        .onAppear {
            Task { await sidebarManager.checkExistence() }
        }
        .onChange(of: sidebarManager.visibleItems.count) { _ in
            Task { await sidebarManager.checkExistence() }
        }
    }

    /// Quick Access items as shown: folders confirmed missing on the device are hidden.
    private var displayedQuickAccessItems: [QuickAccessItem] {
        sidebarManager.visibleItems.filter { item in
            !sidebarManager.checkedPaths.contains(item.path)
                || sidebarManager.existingPaths.contains(item.path)
        }
    }

    /// Context-menu action that brings back hidden default folders; nil when none are hidden.
    private var restoreHiddenAction: (() -> Void)? {
        guard sidebarManager.hasHiddenBuiltIns else { return nil }
        return { showRestoreAlert = true }
    }

    /// Edit handler for the row's context menu; nil for the dynamic SD card entry.
    private func editAction(for item: QuickAccessItem) -> (() -> Void)? {
        guard sidebarManager.isEditable(item) else { return nil }
        return { editingItem = item }
    }

    // appsSection removed because it's inline in the List
} // end SidebarView

// MARK: - Row

struct QuickAccessRow: View {
    let item: QuickAccessItem
    /// True while the ADB existence check is still in flight for this item
    let isChecking: Bool
    var storageInfo: DeviceManager.StorageInfo? = nil
    var onEdit: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var onRestoreHidden: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                SidebarRowLabel(title: item.name, systemImage: item.icon, iconColor: Color(item.color.color))

                Spacer(minLength: 4)

                if isChecking {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                }
            }

                // Storage gauge — only shown when stats are available
                if let storage = storageInfo {
                    VStack(alignment: .leading, spacing: 2) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(storageBarColor(fraction: storage.usedFraction))
                                    .frame(width: geo.size.width * storage.usedFraction, height: 3)
                            }
                        }
                        .frame(height: 3)
                        .padding(.leading, SidebarRowLabel.textInset)

                        Text(storage.usedText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.leading, SidebarRowLabel.textInset)
                    }
                }
            }
        .contextMenu {
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit…", systemImage: "pencil")
                }
                Divider()
            }
            if item.isBuiltIn {
                Button(role: .destructive) {
                    onRemove?()
                } label: {
                    Label("Hide from Sidebar", systemImage: "eye.slash")
                }
            } else {
                Button(role: .destructive) {
                    onRemove?()
                } label: {
                    Label("Remove from Sidebar", systemImage: "minus.circle")
                }
            }
            if let onRestoreHidden {
                Divider()
                Button {
                    onRestoreHidden()
                } label: {
                    Label("Restore Hidden Folders…", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }

    private func storageBarColor(fraction: Double) -> Color {
        if fraction > 0.9 { return .red }
        if fraction > 0.8 { return .orange }
        return .blue
    }
}

// MARK: - Row Label

/// Icon + title with a fixed-width icon column, so every sidebar title starts
/// at the same x position regardless of the SF Symbol's natural width.
struct SidebarRowLabel: View {
    static let iconWidth: CGFloat = 20
    static let spacing: CGFloat = 6
    /// Leading offset of the title, for content laid out under it (e.g. storage bar).
    static let textInset: CGFloat = iconWidth + spacing

    let title: String
    let systemImage: String
    var iconColor: Color = .accentColor

    var body: some View {
        HStack(spacing: Self.spacing) {
            Image(systemName: systemImage)
                .foregroundColor(iconColor)
                .frame(width: Self.iconWidth, alignment: .center)
            Text(title)
                .lineLimit(1)
        }
    }
}

// MARK: - Item Editor

/// Sheet for renaming a sidebar folder and choosing its icon and colour.
struct SidebarItemEditor: View {
    let item: QuickAccessItem
    let onSave: (_ name: String, _ icon: String, _ color: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var color: String

    init(item: QuickAccessItem, onSave: @escaping (String, String, String) -> Void) {
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _icon = State(initialValue: item.icon)
        _color = State(initialValue: item.color)
    }

    private let iconColumns = Array(repeating: GridItem(.fixed(32), spacing: 6), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(Color(color.color))
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Sidebar Item")
                        .font(.headline)
                    Text(item.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            Text("Icon")
                .font(.subheadline)
                .foregroundColor(.secondary)
            LazyVGrid(columns: iconColumns, alignment: .leading, spacing: 6) {
                ForEach(QuickAccessItem.iconChoices, id: \.self) { symbol in
                    Button {
                        icon = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 14))
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(icon == symbol ? Color.accentColor.opacity(0.25) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(symbol)
                }
            }

            Text("Color")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                ForEach(QuickAccessItem.colorChoices, id: \.self) { choice in
                    Button {
                        color = choice
                    } label: {
                        Circle()
                            .fill(Color(choice.color))
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: color == choice ? 2 : 0)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(choice.capitalized)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name, icon, color)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
