//
//  FolderDropTarget.swift
//  AndroidFileSync
//
//  Makes a folder in the list or icon view a drop target, like Finder:
//  device items dragged onto it are moved into it, Mac files are uploaded into it.
//

import SwiftUI
import UniformTypeIdentifiers

struct FolderDropTarget: ViewModifier {
    let folder: UnifiedFile
    /// Device paths dropped onto the folder (move).
    let onMoveItems: ([String], String) -> Void
    /// Mac files dropped onto the folder (upload).
    let onUploadURLs: ([URL], String) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(isTargeted ? 0.25 : 0))
            )
            .onDrop(of: [DraggedDeviceItem.type, .fileURL], isTargeted: $isTargeted) { providers in
                let folderPath = folder.path
                Task {
                    let items = await DraggedDeviceItem.load(from: providers)
                    // Dropping a folder onto itself (or into its own subfolder) is a no-op.
                    let paths = items.map(\.path).filter { path in
                        path != folderPath && !folderPath.hasPrefix(path + "/")
                    }
                    let urls = await DraggedDeviceItem.loadFileURLs(from: providers)
                    await MainActor.run {
                        if !paths.isEmpty { onMoveItems(paths, folderPath) }
                        if !urls.isEmpty { onUploadURLs(urls, folderPath) }
                    }
                }
                return true
            }
    }
}

extension View {
    /// Accepts drops when `folder` is a directory; otherwise leaves the view unchanged.
    @ViewBuilder
    func folderDropTarget(
        _ folder: UnifiedFile,
        onMoveItems: (([String], String) -> Void)?,
        onUploadURLs: (([URL], String) -> Void)?
    ) -> some View {
        if folder.isDirectory, let onMoveItems, let onUploadURLs {
            modifier(FolderDropTarget(folder: folder, onMoveItems: onMoveItems, onUploadURLs: onUploadURLs))
        } else {
            self
        }
    }
}
