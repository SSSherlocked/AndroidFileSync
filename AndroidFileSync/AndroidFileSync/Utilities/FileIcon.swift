//
//  FileIcon.swift
//  AndroidFileSync
//
//  SF Symbol, tint and kind label for a device file, shared by the list view,
//  the icon view and the preview pane.
//

import SwiftUI

enum FileIcon {
    static func symbol(for file: UnifiedFile) -> String {
        if file.isDirectory {
            switch file.name.lowercased() {
            case "dcim", "camera": return "camera.fill"
            case "download", "downloads": return "arrow.down.circle.fill"
            case "pictures", "photos": return "photo.fill"
            case "music": return "music.note"
            case "movies", "videos": return "film.fill"
            case "documents": return "doc.fill"
            default: return "folder.fill"
            }
        }

        switch fileExtension(of: file) {
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "pdf": return "doc.text"
        case "zip", "rar", "7z": return "doc.zipper"
        case "apk": return "app.badge"
        default: return "doc"
        }
    }

    static func color(for file: UnifiedFile) -> Color {
        if file.isDirectory { return .blue }

        switch fileExtension(of: file) {
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return .purple
        case "mp4", "mov", "avi", "mkv": return .red
        case "mp3", "m4a", "wav", "flac": return .pink
        case "pdf": return .orange
        case "apk": return .green
        default: return .secondary
        }
    }

    /// Short kind label, e.g. "Folder", "JPG", "File".
    static func kind(for file: UnifiedFile) -> String {
        if file.isDirectory { return "Folder" }
        let ext = fileExtension(of: file)
        return ext.isEmpty ? "File" : ext.uppercased()
    }

    private static func fileExtension(of file: UnifiedFile) -> String {
        (file.name as NSString).pathExtension.lowercased()
    }
}
