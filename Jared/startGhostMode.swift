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
    let attrs = try? FileManager.default.attributesOfItem(atPath: torPath)
    if let perms = attrs?[.posixPermissions] as? NSNumber, perms.intValue & 0o111 == 0 {
        whisperAlert("Tor binary not executable – run chmod +x on it.")
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
        
        // Capture output for debugging
        if let pipe = torProcess?.standardOutput as? Pipe,
           let data = try? pipe.fileHandleForReading.readDataToEndOfFile() {
            let output = String(data: data, encoding: .utf8) ?? ""
            print("Tor stdout: \(output)")
        }
        
        // Wait longer for bootstrap (Tor can take 10–30s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.setSystemProxy(enabled: true)
            self?.ghostModeActive = true
            self?.whisperAlert("Ghost Mode ON – Traffic anonymized via Tor")
        }
    } catch {
        let errMsg = "Tor launch failed: \(error.localizedDescription)"
        print(errMsg)
        whisperAlert(errMsg)
    }
}
