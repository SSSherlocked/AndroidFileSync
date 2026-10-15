//
//  StatusBarView.swift
//  AndroidFileSync
//
//  Finder-style status bar under the file list (View › Show Status Bar, ⌘/).
//

import SwiftUI

struct StatusBarView: View {
    let itemCount: Int
    let selectedCount: Int
    let currentPath: String
    let storageStats: [String: DeviceManager.StorageInfo]

    var body: some View {
        HStack {
            Spacer()
            Text(summary)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var summary: String {
        var parts: [String] = [itemCount == 1 ? "1 item" : "\(itemCount) items"]
        if selectedCount > 0 {
            parts[0] = "\(selectedCount) of \(itemCount) selected"
        }
        if let free = freeSpaceText {
            parts.append("\(free) available")
        }
        return parts.joined(separator: ", ")
    }

    /// Free space of the storage volume that contains the current folder.
    private var freeSpaceText: String? {
        let volume = storageStats.keys
            .filter { currentPath == $0 || currentPath.hasPrefix($0 + "/") }
            .max { $0.count < $1.count }
        guard let volume, let info = storageStats[volume] else { return nil }
        let free = max(0, info.totalBytes - info.usedBytes)
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }
}
