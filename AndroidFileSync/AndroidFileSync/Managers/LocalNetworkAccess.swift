//
//  LocalNetworkAccess.swift
//  AndroidFileSync
//
//  macOS 15+ gates local network traffic behind a Local Network privacy prompt,
//  which the system shows the first time the app (or an adb process it spawns)
//  touches the LAN. Until the user clicks Allow, mDNS discovery and `adb pair` /
//  `adb connect` fail, typically with "No route to host".
//
//  There is no API to query this permission, so this probe advertises a tiny
//  Bonjour service from the app and browses for it: seeing our own service means
//  access is granted; a PolicyDenied browse error means it is denied or the
//  prompt is still pending. Starting the probe early (when the WiFi window opens)
//  shows the prompt before the user scans the QR code, and the probe keeps
//  retrying so a later "Allow" — in the prompt or in System Settings — is noticed.
//

import Foundation
import Network
import AppKit
internal import Combine

@MainActor
final class LocalNetworkAccess: ObservableObject {
    enum Status: Equatable {
        /// Probe not started, or it could not run — callers should not block on it.
        case unknown
        /// Probe running, no answer yet (the system prompt may be on screen).
        case checking
        case granted
        /// Denied, or the prompt has not been answered yet.
        case denied
    }

    static let shared = LocalNetworkAccess()

    @Published private(set) var status: Status = .unknown

    /// True when it is safe to talk to devices on the LAN, or when we cannot tell.
    var isUsable: Bool { status == .granted || status == .unknown }

    /// Bonjour type used only for this probe. Declared in Info.plist NSBonjourServices.
    private static let probeServiceType = "_afs-lnprobe._tcp"
    /// kDNSServiceErr_PolicyDenied
    private static let policyDeniedCode: Int32 = -65570
    private static let retryInterval: TimeInterval = 3.0

    private let probeName = "afs-probe-\(UUID().uuidString.prefix(8))"
    private let queue = DispatchQueue(label: "com.androidfilesync.localnetwork-probe")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var retryWork: DispatchWorkItem?

    private init() {}

    /// Starts probing (showing the system prompt if it has not been answered) and
    /// keeps watching until access is granted. Safe to call repeatedly.
    func startMonitoring() {
        guard status != .granted, listener == nil else { return }
        if status == .unknown { status = .checking }
        startProbe()
    }

    /// Stops the probe without forgetting the last known status.
    func stopMonitoring() {
        retryWork?.cancel()
        retryWork = nil
        tearDownProbe()
        if status == .checking { status = .unknown }
    }

    /// Opens System Settings › Privacy & Security › Local Network.
    func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork",
            "x-apple.systempreferences:com.apple.preference.security",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Probe

    private func startProbe() {
        tearDownProbe()

        let listenerParams = NWParameters.tcp
        listenerParams.includePeerToPeer = true
        guard let newListener = try? NWListener(using: listenerParams) else {
            print("🌐 [LocalNetwork] Could not create probe listener — not blocking on permission.")
            status = .unknown
            return
        }
        newListener.service = NWListener.Service(name: probeName, type: Self.probeServiceType)
        newListener.newConnectionHandler = { connection in connection.cancel() }
        newListener.start(queue: queue)
        listener = newListener

        // Plain locals: the Network callbacks below run off the main actor.
        let ownName = probeName
        let policyDenied = Self.policyDeniedCode
        let browserParams = NWParameters()
        browserParams.includePeerToPeer = true
        let newBrowser = NWBrowser(for: .bonjour(type: Self.probeServiceType, domain: nil), using: browserParams)

        newBrowser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .waiting(let error), .failed(let error):
                let denied: Bool
                if case .dns(let code) = error { denied = code == policyDenied } else { denied = false }
                Task { @MainActor [weak self] in
                    self?.handleProbeFailure(denied: denied)
                }
            default:
                break
            }
        }
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            let foundOwnService = results.contains { result in
                if case .service(let name, _, _, _) = result.endpoint { return name == ownName }
                return false
            }
            guard foundOwnService else { return }
            Task { @MainActor [weak self] in
                self?.handleGranted()
            }
        }
        newBrowser.start(queue: queue)
        browser = newBrowser
    }

    private func handleGranted() {
        guard status != .granted else { return }
        print("🌐 [LocalNetwork] Local network access granted.")
        status = .granted
        retryWork?.cancel()
        retryWork = nil
        tearDownProbe()
    }

    private func handleProbeFailure(denied: Bool) {
        guard status != .granted else { return }
        if denied, status != .denied {
            print("🌐 [LocalNetwork] Local network access denied or awaiting the user's answer.")
            status = .denied
        }
        // Rebuild the probe periodically: a browser created while access was
        // denied does not always recover by itself once the user allows it.
        guard retryWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.retryWork = nil
                guard self.status != .granted, self.listener != nil else { return }
                self.startProbe()
            }
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryInterval, execute: work)
    }

    private func tearDownProbe() {
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
    }
}
