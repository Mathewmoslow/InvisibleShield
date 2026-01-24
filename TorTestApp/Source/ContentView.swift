import SwiftUI

struct ContentView: View {
    @State private var torProcess: Process?
    @State private var ghostModeActive = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        VStack {
            Button(action: {
                if ghostModeActive {
                    stopGhostMode()
                } else {
                    startGhostMode()
                }
            }) {
                Text(ghostModeActive ? "Stop Ghost Mode" : "Start Ghost Mode")
                    .padding()
                    .background(ghostModeActive ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding()
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Tor Status"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    private func whisperAlert(_ message: String) {
        self.alertMessage = message
        self.showAlert = true
    }

    private func startGhostMode() {
        guard let torPath = Bundle.main.path(forResource: "tor", ofType: nil) else {
            whisperAlert("Tor binary not found in bundle. Check Build Phases → Copy Bundle Resources.")
            print("Tor path: nil")
            return
        }

        guard let torrcPath = Bundle.main.path(forResource: "torrc", ofType: nil) else {
            whisperAlert("torrc config not found in bundle.")
            print("torrc path: nil")
            return
        }

        print("Tor binary path: \(torPath)")
        print("torrc path: \(torrcPath)")

        // Check if executable
        if !FileManager.default.isExecutableFile(atPath: torPath) {
             whisperAlert("Tor binary not executable – you may need to run 'chmod +x' on the file before adding it to your project.")
             print("Permissions issue")
             return
        }

        torProcess = Process()
        torProcess?.executableURL = URL(fileURLWithPath: torPath)
        torProcess?.arguments = ["-f", torrcPath]
        torProcess?.standardOutput = Pipe()
        torProcess?.standardError = Pipe()

        do {
            try torProcess?.run()
            print("Tor launched successfully")

            // Wait for Tor to bootstrap
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                self.ghostModeActive = true
                self.whisperAlert("Ghost Mode ON – Traffic anonymized via Tor")
            }
        } catch {
            let errMsg = "Tor launch failed: \(error.localizedDescription)"
            print(errMsg)
            whisperAlert(errMsg)
        }
    }

    private func stopGhostMode() {
        torProcess?.terminate()
        torProcess = nil
        ghostModeActive = false
        whisperAlert("Ghost Mode OFF")
    }
}
