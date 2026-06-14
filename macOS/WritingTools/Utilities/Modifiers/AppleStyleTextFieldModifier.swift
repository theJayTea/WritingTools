import SwiftUI

struct AppleStyleTextFieldModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let isLoading: Bool
    let text: String
    let onSubmit: () -> Void

    @State private var isAnimating: Bool = false
    @State private var isHovered: Bool = false
    @FocusState private var isFocused: Bool
    
    private let animationDuration = 0.3
    private let animationDelay: Duration = .milliseconds(300)
    
    /// Returns nil when Reduce Motion is enabled to disable animations
    private var animation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: animationDuration)
    }
    
    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                content
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(12)
                    .focused($isFocused)
                    .onSubmit {
                        performSubmitAnimation()
                    }
                
                Spacer(minLength: 0)
            }
            
            // Integrated send button with more subtle styling
            if !text.isEmpty {
                Button(action: performSubmitAnimation) {
                    Image(systemName: isLoading ? "hourglass" : "paperplane.fill")
                        .foregroundStyle(.white)
                        .font(.callout)
                        .frame(width: 24, height: 24)
                        .background(isLoading ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                        .clipShape(.circle)
                        .scaleEffect(isHovered ? 1.05 : 1.0)
                        .opacity(isHovered ? 1.0 : 0.9)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .padding(.trailing, 8)
                .transition(.opacity)
                .onHover { hovering in
                    isHovered = hovering
                }
                .help(isLoading ? "Processing…" : "Send message")
                .accessibilityLabel(isLoading ? "Processing" : "Send message")
            }
        }
        .frame(height: 36)
        .background(
            ZStack {
                Color(.textBackgroundColor)

                if isLoading {
                    Color(.controlBackgroundColor)
                }
            }
        )
        .clipShape(.rect(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    (isAnimating || isFocused)
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color(.separatorColor)),
                    lineWidth: (isAnimating || isFocused) ? 2 : 0.5
                )
                .animation(animation, value: isAnimating)
                .animation(.easeInOut(duration: 0.15), value: isFocused)
        )
    }
    
    private func performSubmitAnimation() {
        withAnimation(animation) {
            isAnimating = true
        }
        
        onSubmit()
        
        Task { @MainActor in
            // Skip delay if reduce motion is enabled
            if !reduceMotion {
                try? await Task.sleep(for: animationDelay)
            }
            withAnimation(animation) {
                isAnimating = false
            }
        }
    }
}

extension View {
    func appleStyleTextField(
        text: String,
        isLoading: Bool = false,
        onSubmit: @escaping () -> Void
    ) -> some View {
        self.modifier(AppleStyleTextFieldModifier(isLoading: isLoading, text: text, onSubmit: onSubmit))
    }
}
