//
//  SettingsView.swift
//  AndroidFileSync
//
//  The app's Settings window (⌘,). Every option here is read live by the app.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ConnectionSettingsTab()
                .tabItem { Label("Connection", systemImage: "wifi") }
        }
        .frame(width: 460)
    }
}

private struct GeneralSettingsTab: View {
    @AppStorage(BrowserPreferences.viewModeKey) private var viewMode = BrowserViewMode.list.rawValue
    @AppStorage(BrowserPreferences.showHiddenFilesKey) private var showHiddenFiles = false
    @AppStorage(BrowserPreferences.showStatusBarKey) private var showStatusBar = true
    @AppStorage(BrowserPreferences.showPreviewPaneKey) private var showPreviewPane = false

    var body: some View {
        Form {
            Picker("Default view:", selection: $viewMode) {
                Text("List").tag(BrowserViewMode.list.rawValue)
                Text("Icons").tag(BrowserViewMode.icons.rawValue)
            }
            .pickerStyle(.radioGroup)

            Toggle("Show hidden files", isOn: $showHiddenFiles)
            Toggle("Show status bar", isOn: $showStatusBar)
            Toggle("Show preview pane", isOn: $showPreviewPane)
        }
        .padding(20)
    }
}

private struct ConnectionSettingsTab: View {
    @AppStorage("disconnectAllWirelessOnQuit") private var disconnectAllWirelessOnQuit = true
    @AppStorage("showQuitDebuggingReminder") private var showQuitDebuggingReminder = true
    @ObservedObject private var diagnostics = DiagnosticsControl.shared

    var body: some View {
        Form {
            Toggle("Disconnect wireless devices when quitting", isOn: $disconnectAllWirelessOnQuit)
            Text("Turn this off if another tool (e.g. Android Studio) shares the same ADB server.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Remind me to turn off debugging when quitting", isOn: $showQuitDebuggingReminder)

            Divider()

            Toggle("Enable diagnostic logging", isOn: $diagnostics.isEnabled)
            Text("Writes connection diagnostics to a local log file to help troubleshoot problems. Nothing is sent anywhere.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
    }
}
