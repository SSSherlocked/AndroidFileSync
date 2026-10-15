import Foundation
import AppKit

struct QuickAccessItem: Identifiable, Codable {
    /// Stable ID — use the path so items survive app restarts
    var id: String { path }
    var name: String
    var icon: String
    let path: String
    var color: String
    /// true = ships with the app (can be hidden but not deleted)
    let isBuiltIn: Bool

    init(name: String, icon: String, path: String, color: String, isBuiltIn: Bool = false) {
        self.name = name
        self.icon = icon
        self.path = path
        self.color = color
        self.isBuiltIn = isBuiltIn
    }

    static let commonFolders: [QuickAccessItem] = [
        QuickAccessItem(name: "Internal Storage", icon: "internaldrive.fill",    path: "/storage/emulated/0",           color: "blue",   isBuiltIn: true),
        QuickAccessItem(name: "Camera",           icon: "camera.fill",           path: "/storage/emulated/0/DCIM",      color: "purple", isBuiltIn: true),
        QuickAccessItem(name: "Downloads",        icon: "arrow.down.circle.fill",path: "/storage/emulated/0/Download",  color: "green",  isBuiltIn: true),
        QuickAccessItem(name: "Pictures",         icon: "photo.fill",            path: "/storage/emulated/0/Pictures",  color: "pink",   isBuiltIn: true),
        QuickAccessItem(name: "Music",            icon: "music.note",            path: "/storage/emulated/0/Music",     color: "red",    isBuiltIn: true),
        QuickAccessItem(name: "Movies",           icon: "film.fill",             path: "/storage/emulated/0/Movies",    color: "cyan",   isBuiltIn: true),
        QuickAccessItem(name: "Documents",        icon: "doc.fill",              path: "/storage/emulated/0/Documents", color: "yellow", isBuiltIn: true),
    ]
}

extension QuickAccessItem {
    /// Colors offered in the sidebar item editor (keys understood by `String.color`).
    static let colorChoices = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "cyan", "gray"]

    /// SF Symbols offered in the sidebar item editor.
    static let iconChoices = [
        "folder.fill", "internaldrive.fill", "sdcard.fill", "camera.fill", "photo.fill",
        "film.fill", "music.note", "doc.fill", "arrow.down.circle.fill", "tray.full.fill",
        "archivebox.fill", "book.fill", "star.fill", "heart.fill", "bookmark.fill",
        "tag.fill", "briefcase.fill", "gamecontroller.fill", "bubble.left.and.bubble.right.fill",
        "paperplane.fill", "app.badge.fill", "shippingbox.fill", "lock.fill", "cloud.fill",
    ]
}

extension String {
    var color: NSColor {
        switch self {
        case "blue":   return .systemBlue
        case "purple": return .systemPurple
        case "orange": return .systemOrange
        case "green":  return .systemGreen
        case "pink":   return .systemPink
        case "red":    return .systemRed
        case "cyan":   return .systemCyan
        case "yellow": return .systemYellow
        default:       return .systemGray
        }
    }
}
