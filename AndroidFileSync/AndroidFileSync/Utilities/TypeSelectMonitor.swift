//
//  TypeSelectMonitor.swift
//  AndroidFileSync
//
//  Finder's type-to-select: typing the start of a name selects the first item
//  that matches. Keys typed within a short interval build up one search string.
//

import SwiftUI
import AppKit

struct TypeSelectMonitor: NSViewRepresentable {
    /// Off while the browser isn't showing files (e.g. the Apps view).
    var isEnabled: Bool = true
    /// Called with the accumulated search string; returns the matched row and the
    /// list's row count (used to find and scroll the file table), or nil.
    let onTypeSelect: (String) -> (row: Int, rowCount: Int)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.onTypeSelect = onTypeSelect
        context.coordinator.isEnabled = isEnabled
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onTypeSelect = onTypeSelect
        context.coordinator.isEnabled = isEnabled
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        weak var view: NSView?
        var onTypeSelect: ((String) -> (row: Int, rowCount: Int)?)?
        var isEnabled = true
        private var monitor: Any?
        private var buffer = ""
        private var lastKeyTime = Date.distantPast
        private static let resetInterval: TimeInterval = 1.0

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handle(event) else { return event }
                return nil
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Returns true when the key was used for type-to-select.
        private func handle(_ event: NSEvent) -> Bool {
            guard isEnabled, let window = view?.window, event.window === window, window.isKeyWindow else { return false }
            // Leave text editing (search field, rename, dialogs) alone.
            if window.firstResponder is NSText { return false }
            // Plain typing only; shortcuts keep their meaning.
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .function])
            guard modifiers.isEmpty,
                  let characters = event.characters, !characters.isEmpty,
                  characters != " ",
                  characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols).contains($0) })
            else { return false }

            let now = Date()
            if now.timeIntervalSince(lastKeyTime) > Self.resetInterval { buffer = "" }
            lastKeyTime = now
            buffer += characters

            guard let match = onTypeSelect?(buffer) else { return true }
            scrollTable(in: window, to: match.row, rowCount: match.rowCount)
            return true
        }

        /// Scrolls the file table (identified by its row count, so the sidebar's
        /// table is never picked) to show the matched row.
        private func scrollTable(in window: NSWindow, to row: Int, rowCount: Int) {
            guard let table = Self.findTable(in: window.contentView, rowCount: rowCount),
                  row < table.numberOfRows else { return }
            table.scrollRowToVisible(row)
        }

        private static func findTable(in view: NSView?, rowCount: Int) -> NSTableView? {
            guard let view else { return nil }
            if let table = view as? NSTableView, !(table is NSOutlineView), table.numberOfRows == rowCount {
                return table
            }
            for subview in view.subviews {
                if let table = findTable(in: subview, rowCount: rowCount) { return table }
            }
            return nil
        }
    }
}
