import SwiftUI

struct LoadingBorderModifier: ViewModifier {
    let isLoading: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isLoading {
                        ZStack {
                            // Subtle background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.controlBackgroundColor))
                            
                            // Progress spinner that matches macOS style
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        }
                    }
                }
            )
            .disabled(isLoading)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isLoading)
    }
}
// LoadingButtonStyle is now moved to CommandButton.swift

// Extension to handle loading state buttons
extension View {
    func loadingBorder(isLoading: Bool) -> some View {
        modifier(LoadingBorderModifier(isLoading: isLoading))
    }
}

