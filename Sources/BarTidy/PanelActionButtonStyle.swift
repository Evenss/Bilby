import SwiftUI

/// Local feedback stays inside the label's existing bounds.
struct PanelActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Feedback(configuration: configuration)
    }

    private struct Feedback: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled && (isHovered || configuration.isPressed || isFocused) ? .primary : .secondary)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.white.opacity(backgroundOpacity))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(isEnabled && isFocused ? 0.35 : 0), lineWidth: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .onHover { isHovered = $0 }
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }

        private var backgroundOpacity: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.12 }
            return isHovered || isFocused ? 0.06 : 0
        }
    }
}
