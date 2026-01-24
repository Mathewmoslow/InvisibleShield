import SwiftUI
import CryptoKit

struct VaultView: View {
    @State private var notes: String = ""
    @State private var isUnlocked = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if isUnlocked {
                VStack {
                    TextEditor(text: $notes)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                        .foregroundColor(.green) // Matrix/Cyber vibe
                    
                    Button("Save Encrypted") {
                        saveEncrypted()
                    }
                    .buttonStyle(NeonButtonStyle())
                }
                .padding()
                .onAppear { loadEncrypted() }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 60))
                        .foregroundColor(.cyan)
                        .neonGlow()
                    
                    Text("SECURE IDEA VAULT")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    
                    Button("Unlock Vault (Biometric)") {
                        GuardianManager.shared.authenticate {
                            isUnlocked = true
                        }
                    }
                    .buttonStyle(NeonButtonStyle())
                }
            }
        }
    }
    
    private func saveEncrypted() {
        guard let data = notes.data(using: .utf8) else { return }
        
        // Symmetric key from biometric-derived (or password)
        let keyData = GuardianManager.shared.vaultKey()
        let key = SymmetricKey(data: keyData)
        
        guard let sealed = try? AES.GCM.seal(data, using: key),
              let sealedData = sealed.combined else { return }
        
        let vaultURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(".ghost_vault") // Hidden file
        
        try? sealedData.write(to: vaultURL)
        GuardianManager.shared.whisperAlert("Idea vault sealed")
    }
    
    private func loadEncrypted() {
        let vaultURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(".ghost_vault")
        
        let keyData = GuardianManager.shared.vaultKey()
        let key = SymmetricKey(data: keyData)
        
        guard let sealedData = try? Data(contentsOf: vaultURL),
              let box = try? AES.GCM.open(try AES.GCM.SealedBox(combined: sealedData), using: key) else {
            return
        }
        
        notes = String(data: box, encoding: .utf8) ?? ""
    }
}
