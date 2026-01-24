import SwiftUI

extension View {
    func neonGlow(color: Color = .cyan) -> some View {
        self.shadow(color: color, radius: 10)
            .shadow(color: color, radius: 20)
    }
}

struct NeonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.purple.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.purple, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .shadow(color: .purple.opacity(0.5), radius: 5)
    }
}
