//
//  PreviewPaneView.swift
//  AndroidFileSync
//
//  Finder-style preview pane (View › Show Preview, ⌘⇧P) on the right of the
//  file list: a large preview and details for the selection.
//

import SwiftUI

struct PreviewPaneView: View {
    let selectedFiles: [UnifiedFile]
    var thumbnailProvider: ThumbnailProvider?
    var folderSizes: [String: UInt64] = [:]
    let onQuickLook: (UnifiedFile) -> Void
    let onDownload: () -> Void
    let onGetInfo: (UnifiedFile) -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            if let file = selectedFiles.first, selectedFiles.count == 1 {
                singleFile(file)
            } else if selectedFiles.count > 1 {
                multipleFiles
            } else {
                Text("No Selection")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Single file

    private func singleFile(_ file: UnifiedFile) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                PreviewImage(file: file, thumbnailProvider: thumbnailProvider)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)

                VStack(spacing: 2) {
                    Text(file.name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Text(subtitle(for: file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Information")
                        .font(.subheadline.weight(.semibold))
                    infoRow("Kind", FileIcon.kind(for: file))
                    if let size = size(of: file) {
                        infoRow("Size", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    if let date = file.modificationDate {
                        infoRow("Modified", Self.dateFormatter.string(from: date))
                    }
                    infoRow("Where", (file.path as NSString).deletingLastPathComponent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if !file.isDirectory && FilePreviewManager.isPreviewable(file) {
                        Button("Quick Look") { onQuickLook(file) }
                    }
                    Button("Download…") { onDownload() }
                    Button("Get Info") { onGetInfo(file) }
                }
                .controlSize(.small)
            }
            .padding(16)
        }
    }

    // MARK: - Multiple files

    private var multipleFiles: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
            Text("\(selectedFiles.count) items")
                .font(.headline)
            if let total = totalSize {
                Text(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Button("Download…") { onDownload() }
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }

    private func subtitle(for file: UnifiedFile) -> String {
        let kind = FileIcon.kind(for: file)
        guard let size = size(of: file) else { return kind }
        return "\(kind) – \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))"
    }

    /// File size, or the folder size once it has been measured.
    private func size(of file: UnifiedFile) -> UInt64? {
        if file.isDirectory { return folderSizes[file.path] }
        return file.size > 0 || file.modificationDate != nil ? file.size : nil
    }

    private var totalSize: UInt64? {
        var total: UInt64 = 0
        for file in selectedFiles {
            guard let size = size(of: file) else { return nil }
            total += size
        }
        return total
    }
}

private struct PreviewImage: View {
    let file: UnifiedFile
    var thumbnailProvider: ThumbnailProvider?

    var body: some View {
        if let thumbnailProvider {
            ObservedPreviewImage(file: file, thumbnailProvider: thumbnailProvider)
        } else {
            PreviewSymbol(file: file)
        }
    }
}

private struct ObservedPreviewImage: View {
    let file: UnifiedFile
    @ObservedObject var thumbnailProvider: ThumbnailProvider

    var body: some View {
        if let image = thumbnailProvider.thumbnails[file.path] {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        } else {
            PreviewSymbol(file: file)
        }
    }
}

private struct PreviewSymbol: View {
    let file: UnifiedFile

    var body: some View {
        Image(systemName: FileIcon.symbol(for: file))
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 96))
            .foregroundStyle(FileIcon.color(for: file))
    }
}
