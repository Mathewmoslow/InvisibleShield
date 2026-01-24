//
//  invisguardApp.swift
//  invisguard
//
//  Created by Mathew Moslow on 1/23/26.
//

import SwiftUI
import AppIntents
import Speech

@main
struct invisguardApp: App {
    @StateObject private var guardian = GuardianManager.shared

    var body: some Scene {
        WindowGroup {
            GuardianView()
                .environmentObject(guardian)
                .onAppear {
                    guardian.setupEverything()
                }
        }
        .commands {
            CommandMenu("Whisper Wire") {
                Button("Ghost Mode Toggle") {
                    guardian.toggleGhostMode()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                
                Button("Start Focus 1 Hour") {
                    guardian.startFocus(duration: 3600)
                }
            }
        }
    }
}
