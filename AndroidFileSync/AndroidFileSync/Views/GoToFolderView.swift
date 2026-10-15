//
//  GoToFolderView.swift
//  AndroidFileSync
//
//  Finder's "Go to Folder…" (⌘⇧G) for device paths, with folder suggestions.
//

import SwiftUI

struct GoToFolderView: View {
    let currentPath: String
    let onGo: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var suggestions: [String] = []
    @State private var errorMessage: String?
    @State private var isChecking = false
    @State private var suggestionTask: Task<Void, Never>?

    private static let internalStorage = "/storage/emulated/0"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to Folder")
                .font(.headline)

            TextField("/storage/emulated/0/Download", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(go)
                .onChange(of: text) { _ in
                    errorMessage = nil
                    scheduleSuggestions()
                }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { path in
                        Button {
                            text = path + "/"
                        } label: {
                            Label((path as NSString).lastPathComponent, systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text("Tip: ~ is internal storage; paths without a leading / are relative to the current folder. Press Tab to complete the first suggestion.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Go", action: go)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isChecking)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(
            // Tab completes the first suggestion, like Finder.
            Button("") {
                if let first = suggestions.first { text = first + "/" }
            }
            .keyboardShortcut(.tab, modifiers: [])
            .hidden()
        )
        .onAppear {
            text = currentPath.hasSuffix("/") ? currentPath : currentPath + "/"
        }
        .onDisappear { suggestionTask?.cancel() }
    }

    // MARK: - Path handling

    /// Resolves `~`, relative paths, `.` and `..` against the current folder.
    private func resolvedPath(_ input: String) -> String {
        var path = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if path == "~" {
            path = Self.internalStorage
        } else if path.hasPrefix("~/") {
            path = Self.internalStorage + "/" + path.dropFirst(2)
        } else if !path.hasPrefix("/") {
            path = currentPath + "/" + path
        }

        var parts: [String] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".": continue
            case "..": _ = parts.popLast()
            default: parts.append(String(component))
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    private func go() {
        let path = resolvedPath(text)
        isChecking = true
        Task {
            let exists = await Self.directoryExists(path)
            await MainActor.run {
                isChecking = false
                if exists {
                    onGo(path)
                    dismiss()
                } else {
                    errorMessage = "The folder “\(path)” can't be found."
                }
            }
        }
    }

    /// Suggests sub-folders of the typed parent whose names start with the typed prefix.
    private func scheduleSuggestions() {
        suggestionTask?.cancel()
        let input = text
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            let endsWithSlash = input.hasSuffix("/")
            let resolved = resolvedPath(input)
            let parent = endsWithSlash ? resolved : (resolved as NSString).deletingLastPathComponent
            let prefix = endsWithSlash ? "" : (resolved as NSString).lastPathComponent

            let folders = await Self.subfolders(of: parent)
            guard !Task.isCancelled else { return }
            let base = parent == "/" ? "" : parent
            let matches = folders
                .filter { prefix.isEmpty || $0.lowercased().hasPrefix(prefix.lowercased()) }
                .filter { !$0.hasPrefix(".") || prefix.hasPrefix(".") }
                .prefix(8)
                .map { base + "/" + $0 }
            await MainActor.run { suggestions = Array(matches) }
        }
    }

    // MARK: - Device queries

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func directoryExists(_ path: String) async -> Bool {
        let adbPath = ADBManager.getADBPath()
        guard !adbPath.isEmpty else { return false }
        let (_, output, _) = await Shell.runAsyncWithTimeout(
            adbPath,
            args: ADBManager.deviceArgs(["shell", "[ -d \(shellQuoted(path)) ] && echo 1 || echo 0"]),
            timeoutSeconds: 4.0
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private static func subfolders(of path: String) async -> [String] {
        let adbPath = ADBManager.getADBPath()
        guard !adbPath.isEmpty else { return [] }
        // -p marks directories with a trailing slash; -a includes dot folders.
        let (code, output, _) = await Shell.runAsyncWithTimeout(
            adbPath,
            args: ADBManager.deviceArgs(["shell", "ls -1ap \(shellQuoted(path)) 2>/dev/null"]),
            timeoutSeconds: 3.0
        )
        guard code == 0 else { return [] }
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
            .filter { $0.hasSuffix("/") && $0 != "./" && $0 != "../" }
            .map { String($0.dropLast()) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
