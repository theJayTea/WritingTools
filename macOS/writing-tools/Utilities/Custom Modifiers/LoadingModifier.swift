import SwiftUI

struct LoadingBorderModifier: ViewModifier {
    let isLoading: Bool
    @State private var rotation: Double = 0
    
    private let aiPink = Color(red: 255/255, green: 197/255, blue: 211/255)
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: [aiPink.opacity(0.3), aiPink]),
                            center: .center,
                            startAngle: .degrees(rotation),
                            endAngle: .degrees(rotation + 360)
                        ),
                        lineWidth: 2
                    )
                    .opacity(isLoading ? 1 : 0)
            )
            .onChange(of: isLoading) { _, newValue in
                if newValue {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                } else {
                    rotation = 0
                }
            }
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

