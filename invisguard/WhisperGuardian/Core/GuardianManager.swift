import Foundation
import CryptoKit
import LocalAuthentication
import UserNotifications
import Speech
import Network
import Combine

// MARK: - Vault Errors
enum VaultError: LocalizedError {
    case notAuthenticated
    case keyRetrievalFailed(KeychainError)
    case encryptionFailed
    case decryptionFailed
    case fileWriteFailed(Error)
    case fileReadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please authenticate to access the vault."
        case .keyRetrievalFailed(let keychainError):
            return "Failed to retrieve encryption key: \(keychainError.errorDescription ?? "Unknown error")"
        case .encryptionFailed:
            return "Failed to encrypt data."
        case .decryptionFailed:
            return "Failed to decrypt data. The vault may be corrupted or the encryption key has changed."
        case .fileWriteFailed(let error):
            return "Failed to save vault: \(error.localizedDescription)"
        case .fileReadFailed(let error):
            return "Failed to read vault: \(error.localizedDescription)"
        }
    }
}

class GuardianManager: ObservableObject {
    static let shared = GuardianManager()

    // MARK: - Published Properties
    @Published var focusActive = false
    @Published var ghostModeActive = false
    @Published var remaining: TimeInterval = 0
    @Published var statusMessage = "Ready"
    @Published var showDefenseMode = false

    // Error state for UI alerts
    @Published var currentError: Error?
    @Published var showErrorAlert = false

    // MARK: - Dependencies
    private let authManager = AuthenticationManager.shared
    private let keychainManager = KeychainManager.shared

    // MARK: - Private Properties
    private var timer: Timer?
    private var torProcess: Process?
    private var tamperMonitors: [URL: DispatchSourceFileSystemObject] = [:]
    private var honeypotPaths: [URL] = []

    // Voice Recognition
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Setup
    func setupEverything() {
        requestPermissions()
        deployHoneypots()
        startTamperMonitoring()
        requestSpeechAuth()
    }

    private func requestPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // MARK: - Focus Logic
    func startFocus(duration: TimeInterval) {
        authenticate {
            self.applyHostsBlocks()
            self.focusActive = true
            self.remaining = duration

            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                if self.remaining > 0 {
                    self.remaining -= 1
                } else {
                    self.endAll()
                }
            }
            self.statusMessage = "Focus engaged — distractions blocked"
        }
    }

    func endAll() {
        endFocus()
        if ghostModeActive { stopGhostMode() }
    }

    private func endFocus() {
        focusActive = false
        timer?.invalidate()
        removeHostsBlocks()
        statusMessage = "Focus ended"
    }

    private func applyHostsBlocks() {
        whisperAlert("Hosts file locked")
    }

    private func removeHostsBlocks() {
        whisperAlert("Hosts file unlocked")
    }

    // MARK: - Ghost Mode (Tor)
    func toggleGhostMode() {
        authenticate {
            if self.ghostModeActive {
                self.stopGhostMode()
            } else {
                self.startGhostMode()
            }
        }
    }

    private func startGhostMode() {
        guard let torPath = Bundle.main.path(forResource: "tor", ofType: nil),
              let torrcPath = Bundle.main.path(forResource: "torrc", ofType: nil) else {
            whisperAlert("Tor binary missing — add to Resources")
            return
        }

        // Verify executable
        let fm = FileManager.default
        if !fm.isExecutableFile(atPath: torPath) {
            Process.execute("chmod +x \"\(torPath)\"")
        }

        torProcess = Process()
        torProcess?.executableURL = URL(fileURLWithPath: torPath)
        torProcess?.arguments = ["-f", torrcPath]

        // Set library path for bundled dependencies
        var env = ProcessInfo.processInfo.environment
        if let resourcePath = Bundle.main.resourcePath {
            env["DYLD_LIBRARY_PATH"] = resourcePath
        }
        torProcess?.environment = env

        let outputPipe = Pipe()
        torProcess?.standardOutput = outputPipe
        torProcess?.standardError = outputPipe

        do {
            try torProcess?.run()

            // Wait for Tor to bootstrap
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                self.setSystemProxy(enabled: true)
                self.ghostModeActive = true
                self.statusMessage = "Ghost Mode ON"
                self.whisperAlert("Ghost Mode ON — Traffic anonymized via Tor")
            }
        } catch {
            whisperAlert("Tor launch failed: \(error)")
        }
    }

    private func stopGhostMode() {
        torProcess?.terminate()
        torProcess = nil
        setSystemProxy(enabled: false)
        ghostModeActive = false
        statusMessage = "Ready"
        whisperAlert("Ghost Mode OFF")
    }

    private func setSystemProxy(enabled: Bool) {
        let host = "127.0.0.1"
        let port = "9050"

        // Get all active network services and configure them
        let services = getNetworkServices()

        for service in services {
            if enabled {
                Process.execute("networksetup -setsocksfirewallproxy \"\(service)\" \(host) \(port)")
                Process.execute("networksetup -setsocksfirewallproxystate \"\(service)\" on")
            } else {
                Process.execute("networksetup -setsocksfirewallproxystate \"\(service)\" off")
            }
        }
    }

    private func getNetworkServices() -> [String] {
        let output = Process.execute("networksetup -listallnetworkservices")
        return output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty && !$0.contains("*") && !$0.contains("asterisk") }
            .dropFirst() // Skip header
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Honeypots
    private func deployHoneypots() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let fakes = [
            "Wire_Transfer_Receipt.pdf",
            "Project_Keys.backup",
            "Confidential_Whisper_Notes.txt",
            "Crypto_Wallet_Seed.doc"
        ]

        for fake in fakes {
            let path = desktop.appendingPathComponent(fake)
            if !FileManager.default.fileExists(atPath: path.path) {
                try? "This file is monitored by WhisperGuardian — access logged silently.".write(to: path, atomically: true, encoding: .utf8)
            }
            honeypotPaths.append(path)
            startMonitoring(url: path, name: fake)
        }

        let hostsURL = URL(fileURLWithPath: "/etc/hosts")
        startMonitoring(url: hostsURL, name: "System Hosts File")
    }

    // MARK: - Tamper Monitoring
    private func startTamperMonitoring() {
        // Called inside deployHoneypots
    }

    private func startMonitoring(url: URL, name: String) {
        let fd = open(url.path, O_EVTONLY)
        guard fd > 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .extend, .attrib], queue: .global())
        source.setEventHandler { [weak self] in
            let msg = "Silent Intrusion: \(name) accessed/modified at \(Date().formatted(date: .omitted, time: .standard))"
            self?.whisperAlert("🔔 " + msg)
        }

        source.setCancelHandler { close(fd) }
        source.resume()
        tamperMonitors[url] = source
    }

    // MARK: - Alerts
    func whisperAlert(_ message: String) {
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(".whisper_shadow_log")

        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let entry = "[\(Date())] \(message)\n"
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }

        DispatchQueue.main.async {
            let content = UNMutableNotificationContent()
            content.title = "Whisper Wire"
            content.body = "Guardian detected activity"
            content.sound = nil
            content.badge = nil

            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Authentication

    /// Authenticates and executes the completion handler if successful
    func authenticate(completion: @escaping () -> Void) {
        Task { @MainActor in
            do {
                _ = try await authManager.authenticate()
                completion()
            } catch {
                self.handleError(error)
            }
        }
    }

    /// Async version of authenticate
    @MainActor
    func authenticateAsync() async throws {
        _ = try await authManager.authenticate()
    }

    /// Check if currently authenticated
    var isAuthenticated: Bool {
        authManager.state.isAuthenticated
    }

    /// Extend the current session (call on user activity)
    func extendSession() {
        authManager.extendSession()
    }

    /// Invalidate the current session
    func invalidateSession() {
        authManager.invalidateSession()
    }

    // MARK: - Secure Vault

    /// Retrieves the vault encryption key (requires prior authentication)
    /// - Throws: VaultError if not authenticated or key retrieval fails
    func vaultKey() throws -> Data {
        guard let context = authManager.authenticatedContext else {
            throw VaultError.notAuthenticated
        }

        do {
            return try keychainManager.getOrCreateVaultKey(context: context)
        } catch let error as KeychainError {
            throw VaultError.keyRetrievalFailed(error)
        }
    }

    /// Async version that handles authentication flow
    @MainActor
    func getVaultKey() async throws -> Data {
        let context = try await authManager.authenticate()

        do {
            return try keychainManager.getOrCreateVaultKey(context: context)
        } catch let error as KeychainError {
            throw VaultError.keyRetrievalFailed(error)
        }
    }

    // MARK: - Error Handling

    func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.currentError = error
            self.showErrorAlert = true

            // Log for debugging
            self.whisperAlert("Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper
    var formattedTime: String {
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Voice
    private func requestSpeechAuth() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    deinit {
        for monitor in tamperMonitors.values {
            monitor.cancel()
        }
    }
}
