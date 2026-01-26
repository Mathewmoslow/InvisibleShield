import AppIntents
import SwiftUI

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus Session"
    
    @Parameter(title: "Duration in Minutes")
    var duration: Int
    
    func perform() async throws -> some IntentResult {
        // Must run on main actor if touching ObservableObject usually, 
        // but Intents run in background. 
        // Ideally we'd have a separate service layer, but for this structure:
        await MainActor.run {
            GuardianManager.shared.startFocus(duration: TimeInterval(duration * 60))
        }
        return .result(value: "Focus started for \(duration) minutes")
    }
}

struct WhisperFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Whisper Focus"
    
    @Parameter(title: "Minutes")
    var minutes: Int
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            GuardianManager.shared.startFocus(duration: TimeInterval(minutes * 60))
        }
        return .result(value: "Guardian whispers: Focus engaged")
    }
}
