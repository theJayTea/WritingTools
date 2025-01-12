import SwiftUI

enum AppTheme: String {
    case standard = "standard"
    case gradient = "gradient"
    case glass = "glass"
}

struct WindowBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let useGradient: Bool
    
    var currentTheme: AppTheme {
        if !useGradient {
            return .standard
        }
        return UserDefaults.standard.string(forKey: "theme_style") == "glass" ? .glass : .gradient
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    switch currentTheme {
                    case .standard:
                        Color(.windowBackgroundColor)
                    case .gradient:
                        if colorScheme == .light {
                            LinearGradient(
                                colors: [
                                    Color(hex: "f1c6bc"),
                                    Color(hex: "b4bbef"),
                                    Color(hex: "e9d686"),
                                    Color(hex: "b9c7ee")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            LinearGradient(
                                colors: [
                                    Color(hex: "18323D"),
                                    Color(hex: "164066"),
                                    Color(hex: "35423E"),
                                    Color(hex: "4E4246")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    case .glass:
                        GlassmorphicBackground()
                    }
                }
            )
    }
}

struct GlassmorphicBackground: View {
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Base color and Gradient overlay in light mode (Dark mode looks good)
            if (colorScheme == .light){
                Color(.windowBackgroundColor)
                    .opacity(0.2)
                
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
            }
            
            // Blur effect
            Rectangle()
                .fill(.ultraThinMaterial)
            
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension View {
    func windowBackground(useGradient: Bool) -> some View {
        modifier(WindowBackground(useGradient: useGradient))
    }
}
