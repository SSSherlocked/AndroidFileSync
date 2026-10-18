//
//  FileBrowserView.swift
//  AndroidFileSync
//

import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View, Equatable {
    let files: [UnifiedFile]
    let currentPath: String
    let isLoading: Bool
    let canGoBack: Bool
    @Binding var selectedFiles: Set<String>
    let onNavigate: (String) -> Void
    let onGoBack: () -> Void
    let onDownload: (UnifiedFile) -> Void
    let onUpload: ([URL]) -> Void
    let onDelete: ((UnifiedFile) -> Void)?
    let onRename: ((UnifiedFile, String) -> Void)?
    var onPreview: ((UnifiedFile) -> Void)? = nil
    var isPerformingAction: Bool = false
    var currentActionText: String = ""
    /// Called when the user taps the Stop button during an ongoing operation
    var onCancelAction: (() -> Void)? = nil
    let onBatchDelete: (() -> Void)?
    let onBatchDownload: (() -> Void)?
    let onBatchChangeExtension: ((String) -> Void)?
    var onCopy: (([UnifiedFile]) -> Void)? = nil
    var onCut: (([UnifiedFile]) -> Void)? = nil
    var onDownloadFolder: ((UnifiedFile) -> Void)? = nil
    /// Called when the user chooses "Add to Sidebar" from the folder context menu
    var onAddToSidebar: ((UnifiedFile) -> Void)? = nil
    /// Called when the user chooses "Delete Permanently" from the selection toolbar
    var onPermanentDelete: (() -> Void)? = nil
    
    // Clipboard support
    var clipboardCount: Int = 0
    var clipboardOperation: FileActionManager.ClipboardOperation = .none
    var onPaste: (() -> Void)? = nil
    var onClearClipboard: (() -> Void)? = nil
    
    // Deletion support
    var activeDeletions: [LiveDeletion] = []
    var onCancelDeletion: ((UUID) -> Void)? = nil
    var onCancelAllDeletions: (() -> Void)? = nil
    
    // Sorting support
    var sortOption: ActionToolbar.SortOption = .name
    var sortAscending: Bool = true
    /// Monotonically increasing counter — incremented every time ContentView re-sorts.
    /// Guarantees the Equatable detects order changes even when first/last IDs happen to be the same.
    var sortVersion: Int = 0
    var onSortChange: ((ActionToolbar.SortOption, Bool) -> Void)? = nil
    
    // Folder sizes fetched asynchronously — keyed by folder path
    var folderSizes: [String: UInt64] = [:]
    
    // Metadata loading progress (for large directories)
    var isLoadingMetadata: Bool = false
    var metadataLoadedCount: Int = 0
    var metadataTotalCount: Int = 0
    
    // Progressive loading (paginated content:// fallback)
    var isLoadingMoreFiles: Bool = false
    
    // Thumbnail provider for inline file thumbnails
    var thumbnailProvider: ThumbnailProvider? = nil
    
    /// Enables dragging rows out to Finder (downloads on drop)
    var downloadManager: DownloadManager? = nil

    /// List (table) or icon (grid) presentation
    var viewMode: BrowserViewMode = .list

    /// Device items dropped onto a folder: (source paths, destination folder)
    var onMoveItems: (([String], String) -> Void)? = nil
    /// Mac files dropped onto a folder: (local URLs, destination folder)
    var onUploadToFolder: (([URL], String) -> Void)? = nil
    /// Double-click on a file (Finder: open it with its default app)
    var onOpenFile: ((UnifiedFile) -> Void)? = nil
    
    // Equatable — compare data that affects rendering.
    // sortVersion detects user-initiated sort changes.
    // File boundary checks detect metadata enrichment and navigation changes.
    static func == (lhs: FileBrowserView, rhs: FileBrowserView) -> Bool {
        lhs.files.count == rhs.files.count &&
        lhs.sortVersion == rhs.sortVersion &&
        lhs.viewMode == rhs.viewMode &&
        lhs.files.first?.id == rhs.files.first?.id &&
        lhs.files.last?.id == rhs.files.last?.id &&
        lhs.files.first?.size == rhs.files.first?.size &&
        lhs.currentPath == rhs.currentPath &&
        lhs.isLoading == rhs.isLoading &&
        lhs.canGoBack == rhs.canGoBack &&
        lhs.selectedFiles == rhs.selectedFiles &&
        lhs.isPerformingAction == rhs.isPerformingAction &&
        lhs.currentActionText == rhs.currentActionText &&
        lhs.sortOption == rhs.sortOption &&
        lhs.sortAscending == rhs.sortAscending &&
        lhs.folderSizes.count == rhs.folderSizes.count &&
        lhs.isLoadingMetadata == rhs.isLoadingMetadata &&
        lhs.metadataLoadedCount == rhs.metadataLoadedCount &&
        lhs.isLoadingMoreFiles == rhs.isLoadingMoreFiles &&
        lhs.clipboardCount == rhs.clipboardCount &&
        lhs.clipboardOperation == rhs.clipboardOperation &&
        lhs.activeDeletions == rhs.activeDeletions
    }
    
    // Guard against re-entrant sort loop:
    // Column header click → onChange(sortOrder) → onSortChange → ContentView updates displayedFiles
    // → Table re-renders → could trigger onChange(sortOrder) again.
    @State private var isSyncingSortOrder = false
    
    // Deletion Popover States
    @State private var showDeletionPopover = false
    @State private var dismissTask: Task<Void, Never>? = nil
    
    // Table sort state — derived from sortOption/sortAscending props so it survives
    // Table rebuilds from .id(sortVersion). Using @State would reset on rebuild.
    @State private var sortOrder: [KeyPathComparator<UnifiedFile>] = [
        .init(\.name, order: .forward)
    ]
    
    /// Compute the expected sortOrder from current sortOption + sortAscending.
    private var expectedSortOrder: [KeyPathComparator<UnifiedFile>] {
        let order: SortOrder = sortAscending ? .forward : .reverse
        switch sortOption {
        case .name: return [.init(\.name, order: order)]
        case .size: return [.init(\.size, order: order)]
        case .date: return [.init(\.sortableDate, order: order)]
        case .type: return [.init(\.sortableType, order: order)]
        }
    }
    
    // Drag-and-drop visual feedback
    @State private var isDraggingOver = false
    
    // Delete confirmation state
    @State private var showDeleteConfirmation = false
    @State private var fileToDelete: UnifiedFile? = nil
    @State private var showBatchDeleteConfirmation = false
    @State private var batchDeleteCount = 0

    // Change extension state (for context menu)
    @State private var showExtensionDialog = false
    @State private var newExtension = ""
    
    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            fileListOrEmptyState
            
            // Selection toolbar - only show when there are selected files in current view
            let selectedFilesList = files.filter { selectedFiles.contains($0.id) }
            if !selectedFilesList.isEmpty {
                SelectionToolbar(
                    selectedFiles: selectedFilesList,
                    onClearSelection: { selectedFiles.removeAll() },
                    onDelete: { onBatchDelete?() },
                    onDownload: { onBatchDownload?() },
                    onRename: onRename,
                    onChangeExtension: onBatchChangeExtension,
                    onPermanentDelete: onPermanentDelete
                )
            }
        }
        .alert("Move \(fileToDelete?.name ?? "item") to Trash?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                fileToDelete = nil
            }
            Button("Move to Trash", role: .destructive) {
                if let file = fileToDelete {
                    onDelete?(file)
                }
                fileToDelete = nil
            }
        } message: {
            Text("You can restore this item from the Trash.")
        }
        // Change extension alert (no pre-fill needed, so SwiftUI alert works fine here)
        .alert("Change Extension", isPresented: $showExtensionDialog) {
            TextField("New Extension", text: $newExtension)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {
                newExtension = ""
            }
            Button("Change") {
                if !newExtension.isEmpty {
                    onBatchChangeExtension?(newExtension)
                }
                newExtension = ""
            }
        } message: {
            Text("Enter new extension (e.g. txt, jpg) for \(selectedFiles.count) files.")
        }
        // Batch delete confirmation alert
        .alert("Move \(batchDeleteCount) items to Trash?", isPresented: $showBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                batchDeleteCount = 0
            }
            Button("Move to Trash", role: .destructive) {
                onBatchDelete?()
                batchDeleteCount = 0
            }
        } message: {
            Text("You can restore these items from the Trash.")
        }
    }
    
    // MARK: - View Components
    
    private var pathBar: some View {
        HStack(spacing: 0) {
            // Back/Forward live in the window toolbar; the path is clickable.
            // Breadcrumb path
            breadcrumbPath
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()

            HStack(spacing: 8) {
                clipboardStatus
                inlineActionStatus
            }
            
            // Loading progress (the item count lives in the status bar)
            if isLoading {
                ProgressView().controlSize(.small)
            } else if isLoadingMoreFiles {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("\(files.count) items")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .help("Loading more files from MediaStore...")
            } else if isLoadingMetadata {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text("\(metadataLoadedCount)/\(metadataTotalCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .help("Loading file details...")
            }
            
            Divider().frame(height: 16).padding(.horizontal, 10)
            
            // Upload button — accent-tinted, non-intrusive Apple style
            Button(action: showUploadDialog) {
                Label("Upload to Android", systemImage: "arrow.up.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.accentColor)
            .fixedSize()
            .help("Upload files to this folder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    // Breadcrumb segments built from current path
    /// One clickable breadcrumb: display title + the device path it opens.
    private struct PathCrumb: Hashable {
        let title: String
        let path: String
    }

    /// Breadcrumbs for the current path; storage roots get friendly names.
    private var pathCrumbs: [PathCrumb] {
        let parts = currentPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var crumbs: [PathCrumb] = []
        var accumulated = ""
        var index = 0

        if parts.starts(with: ["storage", "emulated", "0"]) {
            accumulated = "/storage/emulated/0"
            crumbs.append(PathCrumb(title: "Internal Storage", path: accumulated))
            index = 3
        } else if parts.count >= 2, parts[0] == "storage", parts[1] != "emulated", parts[1] != "self" {
            accumulated = "/storage/" + parts[1]
            crumbs.append(PathCrumb(title: "SD Card", path: accumulated))
            index = 2
        }

        while index < parts.count {
            accumulated += "/" + parts[index]
            crumbs.append(PathCrumb(title: parts[index], path: accumulated))
            index += 1
        }
        return crumbs
    }

    private var breadcrumbPath: some View {
        let crumbs = pathCrumbs
        // Deep paths collapse the middle into a menu: first › … › parent › current
        let collapsed: [PathCrumb] = crumbs.count > 4 ? Array(crumbs[1..<(crumbs.count - 2)]) : []
        let visible: [PathCrumb] = crumbs.count > 4
            ? [crumbs[0], crumbs[crumbs.count - 2], crumbs[crumbs.count - 1]]
            : crumbs

        return HStack(spacing: 2) {
            if crumbs.isEmpty {
                Text("/")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            ForEach(Array(visible.enumerated()), id: \.element) { index, crumb in
                if index > 0 {
                    breadcrumbSeparator
                }
                if index == 1, !collapsed.isEmpty {
                    Menu {
                        ForEach(collapsed, id: \.self) { hidden in
                            Button(hidden.title) { onNavigate(hidden.path) }
                        }
                    } label: {
                        Text("…")
                            .font(.system(size: 14))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Show enclosing folders")
                    breadcrumbSeparator
                }
                breadcrumbButton(crumb, isCurrent: index == visible.count - 1)
            }
        }
    }

    private var breadcrumbSeparator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Color(NSColor.tertiaryLabelColor))
    }

    @ViewBuilder
    private func breadcrumbButton(_ crumb: PathCrumb, isCurrent: Bool) -> some View {
        if isCurrent {
            // Current folder — never truncate
            Text(crumb.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Button {
                onNavigate(crumb.path)
            } label: {
                Text(crumb.title)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 20, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help(crumb.path)
        }
    }

    
    @ViewBuilder
    private var statusIndicator: some View {
        if isLoading {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
        } else {
            Text("\(files.count) items")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var inlineActionAccentColor: Color {
        let action = currentActionText.lowercased()
        if action.contains("delete") || action.contains("deleting") || action.contains("trash") { return .red }
        if action.contains("restore") { return .green }
        if action.contains("rename") { return .blue }
        if action.contains("paste") || action.contains("pasting") ||
            action.contains("copy") || action.contains("copying") ||
            action.contains("move") || action.contains("moving") ||
            action.contains("cut") || action.contains("cutting") {
            return .orange
        }
        return .secondary
    }

    private var inlineActionStatus: some View {
        HStack(spacing: 6) {
            if isPerformingAction {
                ProgressView()
                    .tint(inlineActionAccentColor)
                    .scaleEffect(0.55)
                    .frame(width: 12, height: 12)
                Text(currentActionText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(inlineActionAccentColor.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 156, alignment: currentActionText.count > 18 ? .leading : .center)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(
                        Capsule()
                            .fill(inlineActionAccentColor.opacity(0.08))
                    )
                    .onHover { hovering in
                        if isDeletionAction {
                            updateHoverState(isHovering: hovering)
                        }
                    }
                    .popover(isPresented: $showDeletionPopover, arrowEdge: .bottom) {
                        deletionDetailsPopover
                    }
                
                // Stop button
                if onCancelAction != nil {
                    Button {
                        onCancelAction?()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Stop operation")
                }
            }
        }
        .frame(width: isPerformingAction ? 250 : 0, alignment: .trailing)
        .clipped()
        .padding(.trailing, isPerformingAction ? 10 : 0)
    }
    
    private var isDeletionAction: Bool {
        let action = currentActionText.lowercased()
        return action.contains("delete") || action.contains("deleting") || action.contains("trash")
    }
    
    private func updateHoverState(isHovering: Bool) {
        if isHovering {
            dismissTask?.cancel()
            dismissTask = nil
            showDeletionPopover = true
        } else {
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                if !Task.isCancelled {
                    showDeletionPopover = false
                }
            }
        }
    }
    
    private var deletionDetailsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Deletion Progress")
                .font(.system(size: 13, weight: .bold))
                .padding(.bottom, 4)
            
            let deletions = activeDeletions.filter { !$0.isComplete }
            if deletions.isEmpty {
                Text("No active deletions")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(deletions) { deletion in
                            HStack(spacing: 8) {
                                Image(systemName: deletion.isPermanent ? "trash.slash.fill" : "trash.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 11))
                                
                                Text(deletion.fileName)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 160, alignment: .leading)
                                
                                Spacer()
                                
                                if deletion.isRunning {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Text("Pending")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                
                                Button {
                                    onCancelDeletion?(deletion.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
                
                Divider()
                
                Button(role: .destructive) {
                    onCancelAllDeletions?()
                    showDeletionPopover = false
                } label: {
                    Text("Cancel All Deletions")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 250)
        .onHover { hovering in
            updateHoverState(isHovering: hovering)
        }
    }
    
    private var clipboardStatus: some View {
        HStack(spacing: 4) {
            if clipboardCount > 0 && !isPerformingAction {
                HStack(spacing: 6) {
             
                    Button {
                        onPaste?()
                    } label: {
                        HStack(spacing: 2) {
                         
                            Image(systemName: clipboardOperation == .cut ? "scissors" : "doc.on.clipboard")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    
                    Text("\(clipboardCount) ")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.blue.opacity(0.85))
                        }
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.borderless)
                    
                    Button {
                        onClearClipboard?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.08))
                )
            }
        }
    }
    
    @ViewBuilder
    private var fileListOrEmptyState: some View {
        ZStack {
            if files.isEmpty && !isLoading {
                emptyFolderView
            } else if viewMode == .icons {
                fileGrid
            } else {
                fileList
            }

            if isDraggingOver {
                dropOverlay
            }
        }
        // FIX 2: Use the standard .onDrop with proper URL extraction
        .onDrop(of: [.fileURL], isTargeted: $isDraggingOver) { providers in
            Task {
                // In-app items dropped on empty space are ignored; loading them
                // would trigger their lazy drag-out download for nothing.
                let urls = await DraggedDeviceItem.loadFileURLs(from: providers)
                if !urls.isEmpty {
                    await MainActor.run {
                        onUpload(urls)
                    }
                }
            }
            return true
        }
    }
    
    private func handleDeleteShortcut() {
        let items = files.filter { selectedFiles.contains($0.id) }
        guard !items.isEmpty else { return }
        
        if items.count == 1 {
            fileToDelete = items.first
            showDeleteConfirmation = true
        } else {
            batchDeleteCount = items.count
            showBatchDeleteConfirmation = true
        }
    }
    
    private var emptyFolderView: some View {
        VStack(spacing: 16) {
            Image(systemName: isDraggingOver ? "arrow.down.doc.fill" : "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(isDraggingOver ? .blue : .secondary)
            
            Text(isDraggingOver ? "Drop files to upload" : "Folder is empty")
                .foregroundColor(isDraggingOver ? .blue : .secondary)
            
            if !isDraggingOver {
                Text("Drag files here or click the Upload button")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var fileList: some View {
        Table(of: UnifiedFile.self, selection: $selectedFiles, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { file in
                HStack(spacing: 8) {
                    if let provider = thumbnailProvider {
                        FileThumbnailView(
                            file: file,
                            thumbnailProvider: provider,
                            fallbackIcon: getFileIcon(for: file),
                            fallbackColor: getFileColor(for: file)
                        )
                        .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: getFileIcon(for: file))
                            .foregroundStyle(getFileColor(for: file))
                            .frame(width: 18)
                    }
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .folderDropTarget(file, onMoveItems: onMoveItems, onUploadURLs: onUploadToFolder)
            }
            
            TableColumn("Size", value: \.size) { file in
                sizeColumnContent(for: file)
            }
            .width(min: 70, ideal: 90, max: 110)
            
            TableColumn("Date", value: \.sortableDate) { file in
                dateColumnContent(for: file)
            }
            .width(min: 160, ideal: 170, max: 200)
            
            TableColumn("Type", value: \.sortableType) { file in
                Text(file.isDirectory ? "Folder" : getFileType(for: file))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            // No .width() — fills remaining space, eliminates trailing column separator
        } rows: {
            ForEach(files) { file in
                // Drag rows out to Finder — the file is pulled from the device on drop
                TableRow(file)
                    .itemProvider { dragItemProvider(for: file) }
            }
        }
        .id(sortVersion) // Force Table rebuild when sort changes — SwiftUI Table won't re-order rows otherwise
        .tableStyle(.inset)
        .scrollContentBackground(.hidden)
        .onAppear {
            // Sync sortOrder when Table is (re)created by .id(sortVersion)
            isSyncingSortOrder = true
            sortOrder = expectedSortOrder
            DispatchQueue.main.async { isSyncingSortOrder = false }
        }
        .onChange(of: sortOrder) { newOrder in
            // Column header was clicked → extract sort params → tell ContentView
            guard !isSyncingSortOrder else { return }
            guard let first = newOrder.first else { return }
            
            isSyncingSortOrder = true
            let ascending = first.order == .forward
            if first.keyPath == \UnifiedFile.name { onSortChange?(.name, ascending) }
            else if first.keyPath == \UnifiedFile.size { onSortChange?(.size, ascending) }
            else if first.keyPath == \UnifiedFile.sortableDate { onSortChange?(.date, ascending) }
            else if first.keyPath == \UnifiedFile.sortableType { onSortChange?(.type, ascending) }
            
            DispatchQueue.main.async { isSyncingSortOrder = false }
        }
        // Use contextMenu with primaryAction for double-click - this is the macOS-native approach
                // that works with selection (macOS 13+)
        .contextMenu(forSelectionType: String.self, menu: { selectedIds in
            selectionContextMenu(selectedIds)
        }, primaryAction: { selectedIds in
            openPrimary(selectedIds)
        })
    }

    private var fileGrid: some View {
        FileGridView(
            files: files,
            selection: $selectedFiles,
            thumbnailProvider: thumbnailProvider,
            onOpen: { file in openPrimary([file.id]) },
            dragProvider: { file in dragItemProvider(for: file) },
            onMoveItems: onMoveItems,
            onUploadToFolder: onUploadToFolder,
            contextMenu: { ids in selectionContextMenu(ids) }
        )
    }

    /// Context menu for a set of selected item ids (shared by list and icon views).
    @ViewBuilder
    private func selectionContextMenu(_ selectedIds: Set<String>) -> some View {
        // Context menu for selected items
        let selectedItems = files.filter { selectedIds.contains($0.id) }
        let isSingleSelection = selectedIds.count <= 1
        let hasOnlyFiles = !selectedItems.isEmpty && selectedItems.allSatisfy { !$0.isDirectory }
        
        if let firstItem = selectedItems.first {
            // Preview option (for single previewable files)
            if isSingleSelection && !firstItem.isDirectory && FilePreviewManager.isPreviewable(firstItem) {
                Button {
                    onPreview?(firstItem)
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                Divider()
            }
            
            // Download
            if !firstItem.isDirectory || !isSingleSelection {
                Button(isSingleSelection ? "Download to Mac" : "Download Selected to Mac") {
                    if isSingleSelection, let file = selectedItems.first, !file.isDirectory {
                        onDownload(file)
                    } else {
                        onBatchDownload?()
                    }
                }
                Divider()
            }
            
            // Folder download option
            if isSingleSelection && firstItem.isDirectory {
                Button {
                    onDownloadFolder?(firstItem)
                } label: {
                    Label("Download Folder to Mac", systemImage: "folder.badge.gearshape")
                }

                // ── Add to Sidebar ──────────────────────────────
                Button {
                    onAddToSidebar?(firstItem)
                } label: {
                    Label("Add to Sidebar", systemImage: "sidebar.left")
                }

                Divider()
            }
            
            // Copy
            Button(isSingleSelection ? "Copy" : "Copy \(selectedIds.count) items") {
                let items = isSingleSelection ? [firstItem] : selectedItems
                onCopy?(items)
            }
            
            // Cut
            Button(isSingleSelection ? "Cut" : "Cut \(selectedIds.count) items") {
                let items = isSingleSelection ? [firstItem] : selectedItems
                onCut?(items)
            }
            
            Divider()
            
            // Rename - only for single selection
            if isSingleSelection {
                Button("Rename") {
                    let kind = firstItem.isDirectory ? "Folder" : "File"
                    if let newName = TextInputDialog.show(
                        title: "Rename \(kind)",
                        message: "Enter a new name for \"\(firstItem.name)\"",
                        placeholder: firstItem.name,
                        initialValue: firstItem.name,
                        confirmLabel: "Rename"
                    ), newName != firstItem.name {
                        onRename?(firstItem, newName)
                    }
                }
                .disabled(onRename == nil)
            }
            
            // Change Extension - only for multiple files (no folders)
            if selectedIds.count > 1 && hasOnlyFiles {
                Button("Change Extension...") {
                    showExtensionDialog = true
                }
                .disabled(onBatchChangeExtension == nil)
            }
            
            // Move to Trash
            Button(isSingleSelection ? "Move to Trash" : "Move \(selectedIds.count) items to Trash", role: .destructive) {
                if isSingleSelection {
                    fileToDelete = firstItem
                    showDeleteConfirmation = true
                } else {
                    batchDeleteCount = selectedIds.count
                    showBatchDeleteConfirmation = true
                }
            }
        }
    }

    /// Double-click / ⌘↓ behaviour: open folders, preview or download files.
    private func openPrimary(_ selectedIds: Set<String>) {
        // Double-click action
        if let firstId = selectedIds.first,
           let file = files.first(where: { $0.id == firstId }) {
            if file.isDirectory {
                onNavigate(file.path)
            } else if let onOpenFile {
                onOpenFile(file)
            } else if FilePreviewManager.isPreviewable(file) {
                onPreview?(file)
            } else {
                onDownload(file)
            }
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(for file: UnifiedFile) -> some View {
        let selectedItems = files.filter { selectedFiles.contains($0.id) }
        let isSingleSelection = selectedFiles.count <= 1
        let hasOnlyFiles = !selectedItems.isEmpty && selectedItems.allSatisfy { !$0.isDirectory }
        
        // Download - show for files
        if !file.isDirectory {
            Button(isSingleSelection ? "Download to Mac" : "Download Selected to Mac") {
                if isSingleSelection {
                    onDownload(file)
                } else {
                    onBatchDownload?()
                }
            }
            Divider()
        }
        
        // Download folder
        if file.isDirectory && isSingleSelection {
            Button {
                onDownloadFolder?(file)
            } label: {
                Label("Download Folder to Mac", systemImage: "folder.badge.gearshape")
            }
            Divider()
        }
        
        // Copy
        Button(isSingleSelection ? "Copy" : "Copy \(selectedFiles.count) items") {
            let items = isSingleSelection ? [file] : selectedItems
            onCopy?(items)
        }
        
        // Cut
        Button(isSingleSelection ? "Cut" : "Cut \(selectedFiles.count) items") {
            let items = isSingleSelection ? [file] : selectedItems
            onCut?(items)
        }
        
        Divider()
        
        // Rename - only for single selection
        if isSingleSelection {
            Button("Rename") {
                let kind = file.isDirectory ? "Folder" : "File"
                if let newName = TextInputDialog.show(
                    title: "Rename \(kind)",
                    message: "Enter a new name for \"\(file.name)\"",
                    placeholder: file.name,
                    initialValue: file.name,
                    confirmLabel: "Rename"
                ), newName != file.name {
                    onRename?(file, newName)
                }
            }
            .disabled(onRename == nil)
        }
        
        // Change Extension - only for multiple files (no folders)
        if selectedFiles.count > 1 && hasOnlyFiles {
            Button("Change Extension...") {
                showExtensionDialog = true
            }
            .disabled(onBatchChangeExtension == nil)
        }
        
        // Move to Trash - always available
        Button(isSingleSelection ? "Move to Trash" : "Move \(selectedFiles.count) items to Trash", role: .destructive) {
            if isSingleSelection {
                fileToDelete = file
                showDeleteConfirmation = true
            } else {
                batchDeleteCount = selectedFiles.count
                showBatchDeleteConfirmation = true
            }
        }
        .disabled(onDelete == nil)
    }
    
    // MARK: - Column Content Helpers
    
    @ViewBuilder
    private func sizeColumnContent(for file: UnifiedFile) -> some View {
        if file.isDirectory {
            if let size = folderSizes[file.path] {
                Text(formatBytes(size))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("--")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        } else if file.size == 0 && file.modificationDate == nil && isLoadingMetadata {
            Text("···")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.tertiary)
        } else if file.size == 0 && file.modificationDate == nil {
            Text("--")
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.secondary)
        } else {
            Text(formatBytes(file.size))
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private func dateColumnContent(for file: UnifiedFile) -> some View {
        if let date = file.modificationDate {
            Text(Self.dateFormatter.string(from: date))
                .font(.system(.callout, design: .default))
                .foregroundColor(.secondary)
        } else if !file.isDirectory && file.size == 0 && isLoadingMetadata {
            Text("···")
                .font(.system(.callout, design: .default))
                .foregroundStyle(.tertiary)
        } else {
            Text("--")
                .font(.system(.callout, design: .default))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Functions
    
    private func getFileIcon(for file: UnifiedFile) -> String {
        FileIcon.symbol(for: file)
    }
    
    private func getFileColor(for file: UnifiedFile) -> Color {
        FileIcon.color(for: file)
    }
    
    private func dragItemProvider(for file: UnifiedFile) -> NSItemProvider? {
        guard let downloadManager else { return nil }
        return DragOutProvider.makeItemProvider(for: file, downloadManager: downloadManager)
    }
    
    private func getFileType(for file: UnifiedFile) -> String {
        FileIcon.kind(for: file)
    }
    
    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Color.blue, lineWidth: 3)
            .background(Color.blue.opacity(0.1))
            .padding(8)
            .transition(.opacity)
    }
    
    // MARK: - Actions
    
    private func showUploadDialog() {
        let openPanel = NSOpenPanel()
        openPanel.configureForPerformance() // Assuming you have this extension
        openPanel.title = "Select Files to Upload"
        openPanel.message = "Choose files to upload to \(currentPath)"
        
        openPanel.begin { response in
            if response == .OK {
                onUpload(openPanel.urls)
            }
        }
    }
}
// MARK: - Window Drag Area
// Allows dragging the app window from the path bar (like the title bar)
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableNSView { DraggableNSView() }
    func updateNSView(_ nsView: DraggableNSView, context: Context) {}
    
    class DraggableNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
