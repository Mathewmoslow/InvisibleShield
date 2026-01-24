import SwiftUI

struct GuardianView: View {
    @EnvironmentObject private var guardian: GuardianManager
    
    // UI State for Tabs
    enum Tab {
        case dashboard, vault, defense
    }
    
    var body: some View {
        TabView {
            DashboardTab()
                .tabItem { Label("Dashboard", systemImage: "shield") }
            
            VaultView()
                .tabItem { Label("Idea Vault", systemImage: "lock.doc") }
            
            if guardian.showDefenseMode {
                DefenseGameView()
                    .tabItem { Label("Defense Arena", systemImage: "gamecontroller") }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.black)
        .accentColor(.cyan)
    }
}

struct DashboardTab: View {
    @EnvironmentObject private var guardian: GuardianManager
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                // Status Header
                Text(guardian.ghostModeActive ? "GHOST MODE ACTIVE" :
                     guardian.focusActive ? "FOCUS ACTIVE" : "Whisper Wire Ready")
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundColor(guardian.ghostModeActive ? .purple : .cyan)
                    .neonGlow(color: guardian.ghostModeActive ? .purple : .cyan)
                    .multilineTextAlignment(.center)
                    .padding(.top, 50)
                
                // Timer
                if guardian.focusActive {
                    Text("Time Left: \(guardian.formattedTime)")
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                        .neonGlow(color: .green)
                } else {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .font(.system(size: 100))
                        .foregroundColor(.gray)
                        .opacity(0.5)
                }
                
                Spacer()
                
                // Controls
                HStack(spacing: 20) {
                    Button(action: { guardian.toggleGhostMode() }) {
                        HStack {
                            Image(systemName: "network.badge.shield.half.filled")
                            Text("Toggle Ghost Mode")
                        }
                    }
                    .buttonStyle(NeonButtonStyle())
                    
                    Button(action: { guardian.startFocus(duration: 3600) }) {
                        HStack {
                            Image(systemName: "timer")
                            Text("Start Focus (1 Hour)")
                        }
                    }
                    .buttonStyle(NeonButtonStyle())
                    
                    Button(action: { guardian.endAll() }) {
                        Text("End All")
                    }
                    .buttonStyle(NeonButtonStyle())
                }
                
                // Gamification Toggle
                Button("Toggle Defense Arena") {
                    withAnimation {
                        guardian.showDefenseMode.toggle()
                    }
                }
                .foregroundColor(.gray)
                .padding(.top)
                
                // Status Log
                Text("Status: \(guardian.statusMessage)")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.bottom, 20)
            }
            .padding()
        }
    }
}
