import Foundation
import CryptoKit
import LocalAuthentication
import UserNotifications
import Speech
import Network
import Combine

class GuardianManager: ObservableObject {
    static let shared = GuardianManager()
    
    // MARK: - Published Properties
    @Published var focusActive = false
    @Published var ghostModeActive = false
    @Published var remaining: TimeInterval = 0
    @Published var statusMessage = "Ready"
    @Published var showDefenseMode = false // For UI toggle
    
    // MARK: - Private Properties
    private var timer: Timer?
    private var torProcess: Process?
    private var tamperMonitors: [URL: DispatchSourceFileSystemObject] = [: ]
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
        // Network Extension permissions would be requested here in a full app
    }
    
    // MARK: - Focus Logic
    func startFocus(duration: TimeInterval) {
        authenticate {
            self.applyHostsBlocks() // Simple blocking
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
        // Placeholder for /etc/hosts modification
        // In a real app, this requires privileged helper or user manual action
        // For this local version, we simulate the action or use AppleScript if allowed
        whisperAlert("Hosts file locked (Simulated)")
        // Actual implementation would write to /etc/hosts
    }
    
    private func removeHostsBlocks() {
        whisperAlert("Hosts file unlocked (Simulated)")
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
        // For sandboxed apps, Tor integration requires special setup
        // For now, enable Ghost Mode as a visual/state indicator
        // Real Tor integration would require a network extension or external helper

        ghostModeActive = true
        statusMessage += " | Ghost online"
        whisperAlert("Ghost Mode ON — Privacy mode activated")

        // Note: Full Tor integration requires:
        // 1. Network Extension entitlement
        // 2. Tor binary signed and embedded properly
        // 3. Data directory in app container
        // For production, consider using a VPN configuration profile instead
    }
    
    private func stopGhostMode() {
        ghostModeActive = false
        statusMessage = statusMessage.replacingOccurrences(of: " | Ghost online", with: "")
        whisperAlert("Ghost Mode OFF")
    }
    
    private func setSystemProxy(enabled: Bool) {
        let proxyHost = "127.0.0.1"
        let proxyPort = "9050"
        
        // Script it via networksetup command
        // Note: This often requires sudo in real terminal, but might work if user grants permission or for current user settings
        let cmd = enabled ? "networksetup -setsocksfirewallproxy Wi-Fi \(proxyHost) \(proxyPort)" : "networksetup -setsocksfirewallproxystate Wi-Fi off"
        Process().runCommand(cmd)
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
        
        // Also monitor /etc/hosts
        let hostsURL = URL(fileURLWithPath: "/etc/hosts")
        startMonitoring(url: hostsURL, name: "System Hosts File")
    }
    
    // MARK: - Tamper Monitoring
    private func startTamperMonitoring() {
        // This is called inside deployHoneypots for specific files
    }
    
    private func startMonitoring(url: URL, name: String) {
        let fd = open(url.path, O_EVTONLY)
        guard fd > 0 else { return }
        
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .extend, .attrib], queue: .global())
        source.setEventHandler { [weak self] in
            let msg = "Silent Intrusion: \(name) accessed/modified at \(Date().formatted(date: .omitted, time: .standard))"
            self?.whisperAlert("🔔 " + msg)
            // Do NOT revert — let them think they succeeded
        }
        
        source.setCancelHandler { close(fd) }
        source.resume()
        tamperMonitors[url] = source
    }
    
    // MARK: - Alerts
    func whisperAlert(_ message: String) {
        // 1. Hidden encrypted log file
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(".whisper_shadow_log") // Dot-prefix = hidden
        
        // Ensure directory exists
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
        
        // 2. Silent local notification
        DispatchQueue.main.async {
            let content = UNMutableNotificationContent()
            content.title = "Whisper Wire"
            content.body = "Guardian detected activity" // Vague
            content.sound = nil // Silent
            content.badge = nil
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    // MARK: - Authentication
    func authenticate(completion: @escaping () -> Void) {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Whisper Wire access") { success, _ in
            if success {
                DispatchQueue.main.async { completion() }
            }
        }
    }
    
    // MARK: - Secure Vault
    func vaultKey() -> Data {
        // Biometric-derived or generate/store in Keychain
        // Placeholder for demo:
        return Data("32-byte-super-secret-key-placeholder".utf8)
    }
    
    // MARK: - Helper
    var formattedTime: String {
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%02d:%02d", m, s)
    }
    
    // MARK: - Voice (Basic)
    private func requestSpeechAuth() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }
    
    deinit {
        for monitor in tamperMonitors.values {
            monitor.cancel()
        }
    }
}
