import Foundation
internal import Combine

enum QRPairingState: Equatable {
    case idle
    case advertising
    case pairing
    case connected
    case failed(String)
}

@MainActor
final class QRPairingService: ObservableObject {
    @Published var state: QRPairingState = .idle
    @Published var qrPayload: String = ""
    @Published var serviceName: String = ""
    @Published var password: String = ""

    var onConnected: (() -> Void)?

    private var pollTask: Task<Void, Never>?
    private var regenerateTimer: Timer?
    private let qrLifetimeSecs: TimeInterval = 60.0

    private var ignoredEndpoints = Set<String>()

    func start() {
        stopInternal()
        ignoredEndpoints.removeAll()
        generateCredentials()
        // Block background mDNS auto-connect attempts for the complete QR flow,
        // including the period before the phone opens its pairing service.
        ADBPairingBrowser.isPairingActive = true
        // Ask for macOS Local Network access now, before the phone scans, so the
        // system prompt does not race the pairing handshake.
        LocalNetworkAccess.shared.startMonitoring()
        state = .advertising
        print("📷 [QRPairing] Service started. State set to .advertising. Starting poll task.")
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.pairWhenPhoneAppears()
        }
        scheduleRegenerateTimer()
    }

    private func scheduleRegenerateTimer() {
        regenerateTimer?.invalidate()
        regenerateTimer = Timer.scheduledTimer(withTimeInterval: qrLifetimeSecs, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.state == .advertising else { return }
                // A phone that scanned while the Local Network prompt was open is
                // still waiting on this code — keep it until access is sorted out.
                guard LocalNetworkAccess.shared.isUsable else {
                    print("📷 [QRPairing] QR lifetime expired while waiting for Local Network access — keeping current code.")
                    self.scheduleRegenerateTimer()
                    return
                }
                print("📷 [QRPairing] QR lifetime expired (60s). Regenerating...")
                self.start()
            }
        }
    }

    /// Errors where the phone never completed the handshake, so its pairing code is
    /// still valid: Local Network access missing, Wi-Fi hiccups, service not up yet.
    nonisolated static func isTransientNetworkFailure(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.isEmpty ||
               lower.contains("no route to host") ||
               lower.contains("network is unreachable") ||
               lower.contains("connection refused") ||
               lower.contains("timed out") ||
               lower.contains("timeout") ||
               lower.contains("unable to start pairing client")
    }

    func stop() {
        print("📷 [QRPairing] Service stopped by user/caller.")
        stopInternal()
        state = .idle
    }

    func regenerate() {
        print("📷 [QRPairing] Manual regenerate requested.")
        start()
    }

    private func generateCredentials() {
        let hex = "0123456789abcdef"
        let suffix = String((0..<8).map { _ in hex.randomElement()! })
        serviceName = "afs-\(suffix)"
        password = String(format: "%06d", Int.random(in: 0..<1_000_000))
        qrPayload = "WIFI:T:ADB;S:\(serviceName);P:\(password);;"
        print("📷 [QRPairing] Generated credentials: serviceName=\(serviceName), code=\(password), payload=\(qrPayload)")
    }

    private func pairWhenPhoneAppears() async {
        let adbPath = ADBManager.getADBPath()
        guard !adbPath.isEmpty else {
            print("📷 [QRPairing] ERROR: ADB binary path is empty!")
            await MainActor.run { state = .failed("ADB not found.") }
            return
        }

        let code = await MainActor.run { password }
        let sName = await MainActor.run { serviceName }
        print("📷 [QRPairing] Starting mDNS poll loop for phone pairing service (serviceName: \(sName), code: \(code))...")

        // Snapshot pre-existing pairing endpoints to prevent false positives from stale mDNS
        let (_, initialOut, _) = await ADBManager.mdnsServicesWithRecovery(allowRecovery: false)
        var preExisting = Set<String>()
        for line in initialOut.split(separator: "\n") {
            let str = String(line)
            guard str.contains("_adb-tls-pairing._tcp") else { continue }
            let parts = str.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            if let ipPort = parts.first(where: { p in
                let c = p.split(separator: ":")
                return c.count >= 2 && UInt16(c.last ?? "") != nil
            }) {
                preExisting.insert(ipPort)
            }
        }
        if !preExisting.isEmpty {
            print("📷 [QRPairing] Ignoring \(preExisting.count) pre-existing pairing endpoints: \(preExisting)")
            ignoredEndpoints.formUnion(preExisting)
        }

        var attempt = 0
        var waitingForNetworkAccess = false
        var restartedForNetworkRoute = false
        while attempt < 60 {
            guard !Task.isCancelled else {
                print("📷 [QRPairing] Poll loop cancelled at attempt \(attempt)")
                return
            }
            if attempt > 0 || waitingForNetworkAccess { try? await Task.sleep(nanoseconds: 1_000_000_000) }

            // Without Local Network access every mDNS lookup and `adb pair` fails.
            // Wait for the user's answer instead of burning the 60 s budget.
            if !LocalNetworkAccess.shared.isUsable {
                if !waitingForNetworkAccess {
                    print("📷 [QRPairing] Waiting for macOS Local Network access before pairing...")
                }
                waitingForNetworkAccess = true
                continue
            }
            if waitingForNetworkAccess {
                waitingForNetworkAccess = false
                // The private ADB daemon was started without network access;
                // recreate it so it picks up the newly granted permission.
                print("📷 [QRPairing] Local Network access granted — restarting ADB server before pairing.")
                restartedForNetworkRoute = await ADBManager.restartServer()
            }
            attempt += 1

            // Check if DeviceManager already connected a device while we
            // were polling. This handles the case where pairing failed
            // (e.g. server restart failed) but DeviceManager reconnected
            // the device on its own via mDNS auto-discovery.
            if let activeSerial = ADBManager.activeDeviceSerial, !activeSerial.isEmpty {
                print("📷 [QRPairing] Device already connected by DeviceManager: \(activeSerial). Transitioning to .connected.")
                await MainActor.run {
                    state = .connected
                    onConnected?()
                }
                return
            }

            let (exitCode, output, stderr) = await ADBManager.mdnsServicesWithRecovery(allowRecovery: false)
            let trimmedOut = output.trimmingCharacters(in: .whitespacesAndNewlines)

            if attempt == 1 || attempt % 5 == 0 || trimmedOut.contains("_adb-tls-pairing._tcp") {
                print("📷 [QRPairing] Poll \(attempt)/60: mdns exitCode=\(exitCode), output=\(trimmedOut.isEmpty ? "<empty>" : trimmedOut)")
            }

            guard exitCode == 0 else {
                if attempt % 10 == 0 {
                    print("📷 [QRPairing] adb mdns services returned non-zero code \(exitCode): \(stderr)")
                }
                continue
            }

            for line in output.split(separator: "\n") {
                let str = String(line)
                guard str.contains("_adb-tls-pairing._tcp") else { continue }

                let parts = str.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
                guard let ipPortStr = parts.first(where: { part in
                    let c = part.split(separator: ":")
                    return c.count >= 2 && UInt16(c.last ?? "") != nil
                }) else { continue }

                if ignoredEndpoints.contains(ipPortStr) {
                    continue
                }

                let comps = ipPortStr.split(separator: ":")
                guard let portStr = comps.last, UInt16(portStr) != nil else { continue }
                let ip = comps.dropLast().joined(separator: ":")
                guard !ip.isEmpty else { continue }

                print("📷 [QRPairing] Found new pairing target: \(ipPortStr) (IP: \(ip), Port: \(portStr))")

                await MainActor.run {
                    if state == .advertising {
                        state = .pairing
                        regenerateTimer?.invalidate()
                        regenerateTimer = nil
                        print("📷 [QRPairing] State transitioned to .pairing")
                    }
                }

                print("📷 [QRPairing] Executing command: adb pair \(ipPortStr) \(code)")

                // Protect the TLS handshake from background ADB server restarts.
                // Without these flags, DeviceManager/mDNS recovery can kill the
                // daemon mid-handshake, causing "protocol fault" errors.
                ADBManager.isPairingInProgress = true
                ADBPairingBrowser.isPairingActive = true

                var (pairCode, pairOut, pairErr) = await Shell.runAsyncWithTimeout(
                    adbPath, args: ["pair", ipPortStr, code], timeoutSeconds: 12.0
                )
                var pairCombined = (pairOut + " " + pairErr).trimmingCharacters(in: .whitespacesAndNewlines)
                var pairSuccess = pairCode == 0 && pairCombined.lowercased().contains("successfully paired")
                print("📷 [QRPairing] adb pair exitCode=\(pairCode), success=\(pairSuccess), output='\(pairCombined)'")

                // Protocol fault = local ADB daemon failure; the phone never saw
                // the attempt so the pairing code is still valid.
                // Restart the daemon and retry once (mirrors ADBManager.pairDevice).
                if !pairSuccess && ADBManager.isProtocolError(pairCombined) {
                    print("📷 [QRPairing] Protocol fault detected — restarting ADB server and retrying...")
                    ADBManager.isPairingInProgress = false
                    var restarted = await ADBManager.restartServer()

                    // If the first restart failed (e.g. concurrent mDNS recovery
                    // interfered), wait briefly and try once more.
                    if !restarted {
                        print("📷 [QRPairing] First restart failed — retrying restart after 2s...")
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        restarted = await ADBManager.restartServer()
                    }

                    ADBManager.isPairingInProgress = true

                    if restarted {
                        print("📷 [QRPairing] Retrying: adb pair \(ipPortStr) \(code)")
                        (pairCode, pairOut, pairErr) = await Shell.runAsyncWithTimeout(
                            adbPath, args: ["pair", ipPortStr, code], timeoutSeconds: 12.0
                        )
                        pairCombined = (pairOut + " " + pairErr).trimmingCharacters(in: .whitespacesAndNewlines)
                        pairSuccess = pairCode == 0 && pairCombined.lowercased().contains("successfully paired")
                        print("📷 [QRPairing] adb pair retry exitCode=\(pairCode), success=\(pairSuccess), output='\(pairCombined)'")
                    }
                }

                // The ADB daemon may be used again after the pair command, but keep
                // browser auto-connect suppressed until connectAfterPair completes.
                ADBManager.isPairingInProgress = false

                if pairSuccess {
                    await connectAfterPair(ip: ip, adbPath: adbPath)
                    ADBPairingBrowser.isPairingActive = false
                    return
                } else {
                    // Only permanently ignore this endpoint if it was NOT a
                    // protocol fault. Protocol faults are ADB daemon issues —
                    // the phone's pairing code is still valid and may succeed
                    // once the daemon stabilizes on the next poll iteration.
                    if Self.isTransientNetworkFailure(pairCombined) {
                        // The phone never saw the handshake; its code is still valid.
                        print("📷 [QRPairing] Pairing to \(ipPortStr) hit a network error (\(pairCombined)). Will retry on next poll.")
                        let lower = pairCombined.lowercased()
                        if !restartedForNetworkRoute,
                           lower.contains("no route to host") || lower.contains("network is unreachable") {
                            // A daemon started before access was granted keeps a dead route.
                            restartedForNetworkRoute = true
                            print("📷 [QRPairing] Restarting ADB server once to refresh its network route...")
                            _ = await ADBManager.restartServer()
                        }
                    } else if !ADBManager.isProtocolError(pairCombined) {
                        print("📷 [QRPairing] Pairing to \(ipPortStr) failed (\(pairCombined)). Ignoring endpoint.")
                        ignoredEndpoints.insert(ipPortStr)
                    } else {
                        print("📷 [QRPairing] Pairing to \(ipPortStr) failed with protocol fault (\(pairCombined)). Will retry on next poll.")
                    }
                    await MainActor.run {
                        if state == .pairing {
                            state = .advertising
                            print("📷 [QRPairing] Reverted state to .advertising to keep QR code active for scan.")
                        }
                    }
                }
            }
        }

        await MainActor.run {
            if state == .advertising || state == .pairing {
                print("📷 [QRPairing] Poll loop finished (60s) without successful pairing.")
                state = .failed("Phone not detected within 60s. Make sure 'Pair device with QR code' was used and both devices are on the same Wi-Fi.")
            }
        }
    }

    /// Looks up the phone's `_adb-tls-connect._tcp` port via mDNS. The phone
    /// registers this service a moment after pairing, so poll a few times.
    private func resolveConnectPort(ip: String, attempts: Int) async -> String? {
        for attempt in 1...max(1, attempts) {
            guard !Task.isCancelled else { return nil }
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let (code, output, _) = await ADBManager.mdnsServicesWithRecovery(allowRecovery: false)
            let trimmedOut = output.trimmingCharacters(in: .whitespacesAndNewlines)
            print("📷 [QRPairing] connectAfterPair poll \(attempt)/\(attempts): mdns output: '\(trimmedOut)'")
            guard code == 0 else { continue }

            for line in output.split(separator: "\n") {
                let str = String(line)
                guard str.contains("_adb-tls-connect._tcp"), str.contains(ip) else { continue }

                let parts = str.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
                guard let ipPortStr = parts.first(where: { part in
                    let c = part.split(separator: ":")
                    return c.count >= 2 && UInt16(c.last ?? "") != nil
                }) else { continue }

                if let p = ipPortStr.split(separator: ":").last, UInt16(p) != nil {
                    print("📷 [QRPairing] Resolved connect port: \(p) for IP \(ip)")
                    return String(p)
                }
            }
        }
        return nil
    }

    private func connectAfterPair(ip: String, adbPath: String) async {
        print("📷 [QRPairing] Starting connectAfterPair for IP: \(ip)...")

        // Right after pairing the phone may not have published its connect
        // service yet, or the first TLS connect can be refused. Retry a few
        // rounds, re-resolving the port each time, before giving up.
        let rounds = 4
        var serial = ""
        var lastOutput = ""
        var connected = false

        for round in 1...rounds {
            guard !Task.isCancelled else { return }
            let port = await resolveConnectPort(ip: ip, attempts: round == 1 ? 10 : 3) ?? "5555"
            serial = "\(ip):\(port)"

            print("📷 [QRPairing] Connect round \(round)/\(rounds): adb connect \(serial)")
            let result = await ADBManager.connectAndVerifyWirelessTarget(serial, connectTimeout: 8.0)
            lastOutput = result.output
            print("📷 [QRPairing] Connect round \(round) success=\(result.success), output='\(result.output)'")
            if result.success {
                connected = true
                break
            }
            if round < rounds {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        guard connected else {
            await MainActor.run {
                print("📷 [QRPairing] Could not connect to \(serial) after \(rounds) rounds: \(lastOutput)")
                state = .failed("Paired, but could not connect to \(serial). Try again, or use the Auto-Discovery tab.")
            }
            return
        }

        await MainActor.run {
            print("📷 [QRPairing] Connected & Verified ✅ \(serial)")
            ADBManager.switchToDevice(serial: serial)
            ADBManager.markAppManagedWirelessTarget(serial)
            var saved = UserDefaults.standard.stringArray(forKey: "connectedWirelessDevices") ?? []
            if !saved.contains(ip) { saved.append(ip) }
            UserDefaults.standard.set(saved, forKey: "connectedWirelessDevices")
            state = .connected
            onConnected?()
        }
    }

    private func stopInternal() {
        pollTask?.cancel()
        pollTask = nil
        regenerateTimer?.invalidate()
        regenerateTimer = nil
        // Clear protection flags in case we're stopped mid-handshake,
        // so they don't remain stuck and block future ADB restarts.
        ADBManager.isPairingInProgress = false
        ADBPairingBrowser.isPairingActive = false
    }

    deinit {
        pollTask?.cancel()
        regenerateTimer?.invalidate()
    }
}
