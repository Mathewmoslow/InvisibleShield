import SwiftUI
import CryptoKit

struct VaultView: View {
    @EnvironmentObject private var guardian: GuardianManager
    @StateObject private var authManager = AuthenticationManager.shared

    @State private var notes: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false
    @State private var successMessage = ""

    private var vaultURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(".ghost_vault")
    }

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            if authManager.state.isAuthenticated {
                authenticatedView
            } else {
                lockedView
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") { }
        } message: {
            Text(successMessage)
        }
    }

    // MARK: - Authenticated View

    private var authenticatedView: some View {
        VStack {
            // Session indicator
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                Text("Vault Unlocked")
                    .font(.caption)
                    .foregroundColor(.green)

                Spacer()

                if case .authenticated(let expiresAt) = authManager.state {
                    Text(timeRemaining(until: expiresAt))
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Button("Lock") {
                    authManager.invalidateSession()
                }
                .foregroundColor(.red)
                .font(.caption)
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            TextEditor(text: $notes)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.green)
                .onChange(of: notes) { _ in
                    // Extend session on user activity
                    guardian.extendSession()
                }

            HStack(spacing: 20) {
                Button(action: saveEncrypted) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Save Encrypted")
                    }
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(isLoading)

                Button("Reload") {
                    loadEncrypted()
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(isLoading)
            }
        }
        .padding()
        .onAppear { loadEncrypted() }
    }

    // MARK: - Locked View

    private var lockedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.cyan)
                .neonGlow()

            Text("SECURE IDEA VAULT")
                .font(.title2)
                .bold()
                .foregroundColor(.white)

            if case .authenticating = authManager.state {
                ProgressView("Authenticating...")
                    .foregroundColor(.white)
            } else {
                Button("Unlock Vault") {
                    unlockVault()
                }
                .buttonStyle(NeonButtonStyle())
            }

            // Show biometric type hint
            biometricHint

            // Show last error if any
            if let error = authManager.lastError {
                VStack(spacing: 4) {
                    Text(error.errorDescription ?? "Authentication failed")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)

                    if let recovery = error.recoverySuggestion {
                        Text(recovery)
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
        }
    }

    private var biometricHint: some View {
        Group {
            switch authManager.biometricType() {
            case .touchID:
                Label("Touch ID or Passcode", systemImage: "touchid")
            case .faceID:
                Label("Face ID or Passcode", systemImage: "faceid")
            case .opticID:
                Label("Optic ID or Passcode", systemImage: "opticid")
            default:
                Label("Passcode Required", systemImage: "key")
            }
        }
        .font(.caption)
        .foregroundColor(.gray)
    }

    // MARK: - Helpers

    private func timeRemaining(until date: Date) -> String {
        let remaining = max(0, date.timeIntervalSinceNow)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Actions

    private func unlockVault() {
        Task {
            do {
                _ = try await authManager.authenticate()
            } catch {
                // Error is handled by authManager.lastError
            }
        }
    }

    private func saveEncrypted() {
        isLoading = true

        Task {
            do {
                guard let data = notes.data(using: .utf8) else {
                    throw VaultError.encryptionFailed
                }

                let keyData = try await guardian.getVaultKey()
                let key = SymmetricKey(data: keyData)

                guard let sealed = try? AES.GCM.seal(data, using: key),
                      let sealedData = sealed.combined else {
                    throw VaultError.encryptionFailed
                }

                do {
                    try sealedData.write(to: vaultURL)
                } catch {
                    throw VaultError.fileWriteFailed(error)
                }

                await MainActor.run {
                    isLoading = false
                    successMessage = "Vault saved securely"
                    showSuccess = true
                    guardian.whisperAlert("Idea vault sealed")
                }

            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func loadEncrypted() {
        isLoading = true

        Task {
            do {
                let keyData = try await guardian.getVaultKey()
                let key = SymmetricKey(data: keyData)

                let sealedData: Data
                do {
                    sealedData = try Data(contentsOf: vaultURL)
                } catch {
                    // File doesn't exist yet - not an error for first use
                    await MainActor.run {
                        isLoading = false
                        notes = ""
                    }
                    return
                }

                guard let box = try? AES.GCM.SealedBox(combined: sealedData),
                      let decrypted = try? AES.GCM.open(box, using: key) else {
                    throw VaultError.decryptionFailed
                }

                await MainActor.run {
                    isLoading = false
                    notes = String(data: decrypted, encoding: .utf8) ?? ""
                }

            } catch {
                await MainActor.run {
                    isLoading = false
                    if case VaultError.decryptionFailed = error {
                        errorMessage = "Failed to decrypt vault. The encryption key has changed for security. Previous vault data cannot be recovered."
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    showError = true
                }
            }
        }
    }
}
