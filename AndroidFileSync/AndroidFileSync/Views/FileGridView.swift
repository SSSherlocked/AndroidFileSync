//
//  FileGridView.swift
//  AndroidFileSync
//
//  Finder-style icon view (View › as Icons, ⌘2). Selection follows Finder:
//  click selects, ⌘-click toggles, ⇧-click extends a range, double-click opens,
//  clicking empty space deselects.
//

import SwiftUI
import AppKit

struct FileGridView<MenuContent: View>: View {
    let files: [UnifiedFile]
    @Binding var selection: Set<String>
    var thumbnailProvider: ThumbnailProvider?
    let onOpen: (UnifiedFile) -> Void
    let dragProvider: (UnifiedFile) -> NSItemProvider?
    var onMoveItems: (([String], String) -> Void)?
    var onUploadToFolder: (([URL], String) -> Void)?
    @ViewBuilder let contextMenu: (Set<String>) -> MenuContent

    /// Anchor for ⇧-click range selection.
    @State private var anchorID: String?

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 124), spacing: 10, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .center, spacing: 14) {
                ForEach(files) { file in
                    FileGridCell(
                        file: file,
                        isSelected: selection.contains(file.id),
                        thumbnailProvider: thumbnailProvider
                    )
                    .onTapGesture(count: 2) {
                        selection = [file.id]
                        anchorID = file.id
                        onOpen(file)
                    }
                    .simultaneousGesture(TapGesture().onEnded { select(file) })
                    .onDrag { dragProvider(file) ?? NSItemProvider() }
                    .folderDropTarget(file, onMoveItems: onMoveItems, onUploadURLs: onUploadToFolder)
                    .contextMenu {
                        contextMenu(menuSelection(for: file))
                    }
                }
            }
            .padding(16)
        }
        .background(
            // Clicking empty space clears the selection, like Finder.
            Color(NSColor.controlBackgroundColor)
                .contentShape(Rectangle())
                .onTapGesture { selection.removeAll() }
        )
    }

    private func select(_ file: UnifiedFile) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(file.id) {
                selection.remove(file.id)
            } else {
                selection.insert(file.id)
            }
            anchorID = file.id
        } else if flags.contains(.shift),
                  let anchorID,
                  let from = files.firstIndex(where: { $0.id == anchorID }),
                  let to = files.firstIndex(where: { $0.id == file.id }) {
            let range = min(from, to)...max(from, to)
            selection = Set(files[range].map(\.id))
        } else {
            selection = [file.id]
            anchorID = file.id
        }
    }

    /// Right-clicking a selected item acts on the whole selection; right-clicking
    /// anything else acts on that item alone (Finder behaviour).
    private func menuSelection(for file: UnifiedFile) -> Set<String> {
        selection.contains(file.id) ? selection : [file.id]
    }
}

private struct FileGridCell: View {
    let file: UnifiedFile
    let isSelected: Bool
    var thumbnailProvider: ThumbnailProvider?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let thumbnailProvider {
                    GridThumbnail(file: file, thumbnailProvider: thumbnailProvider)
                } else {
                    GridSymbol(file: file)
                }
            }
            .frame(width: 64, height: 64)
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.secondary.opacity(0.22) : Color.clear)
            )

            Text(file.name)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .frame(width: 104)
        .contentShape(Rectangle())
        .help(file.name)
    }
}

/// Large thumbnail when the provider has one, otherwise the file's symbol.
private struct GridThumbnail: View {
    let file: UnifiedFile
    @ObservedObject var thumbnailProvider: ThumbnailProvider

    var body: some View {
        if let image = thumbnailProvider.thumbnails[file.path] {
            Image(nsImage: image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
        } else {
            GridSymbol(file: file)
        }
    }
}

private struct GridSymbol: View {
    let file: UnifiedFile

    var body: some View {
        Image(systemName: FileIcon.symbol(for: file))
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 44))
            .foregroundStyle(FileIcon.color(for: file))
    }
}
