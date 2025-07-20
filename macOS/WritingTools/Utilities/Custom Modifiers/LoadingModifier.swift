import SwiftUI

struct LoadingBorderModifier: ViewModifier {
    let isLoading: Bool
    @State private var rotation: Double = 0
    @Environment(\.colorScheme) var colorScheme
    
    private let accentColor = Color.blue
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isLoading {
                        ZStack {
                            // Subtle background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.05))
                            
                            // Progress spinner that matches macOS style
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        }
                    }
                }
            )
            .disabled(isLoading)
            .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}
// Shared color extension
extension Color {
    static let aiPink = Color(red: 255/255, green: 197/255, blue: 211/255)
}

// LoadingButtonStyle is now moved to CommandButton.swift

// Extension to handle loading state buttons
extension View {
    func loadingBorder(isLoading: Bool) -> some View {
        modifier(LoadingBorderModifier(isLoading: isLoading))
    }
}

