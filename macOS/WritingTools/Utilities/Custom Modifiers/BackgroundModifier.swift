import SwiftUI
import AppKit

enum AppTheme: String {
    case standard
    case gradient
    case glass
    case oled
}

struct WindowBackground: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var settings = AppSettings.shared
    let useGradient: Bool
    let cornerRadius: CGFloat?

    init(useGradient: Bool, cornerRadius: CGFloat? = nil) {
        self.useGradient = useGradient
        self.cornerRadius = cornerRadius
    }

    var currentTheme: AppTheme {
        if !useGradient {
            return .standard
        }
        return AppTheme(rawValue: settings.themeStyle) ?? .gradient
    }

    func body(content: Content) -> some View {
        content
            .background(
                Group {
                    switch currentTheme {
                    case .standard:
                        Color(.windowBackgroundColor)
                    case .gradient:
                        colorScheme == .light
                            ? LinearGradient(
                                colors: [Color(hex: "f1c6bc"), Color(hex: "b4bbef"),
                                         Color(hex: "e9d686"), Color(hex: "b9c7ee")],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(
                                colors: [Color(hex: "18323D"), Color(hex: "164066"),
                                         Color(hex: "35423E"), Color(hex: "4E4246")],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                    case .glass:
                        GlassmorphicBackground()
                    case .oled:
                        Color.black
                    }
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: cornerRadius ?? 0,
                        style: .continuous)
                )
            )
    }
}

struct GlassmorphicBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        // Respect Reduce Transparency accessibility setting
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        ZStack {
            if reduceTransparency {
                // Fall back to a solid, high-contrast background
                colorScheme == .light ? Color(.windowBackgroundColor) : Color.black
            } else {
                // Base subtle tint for both light and dark
                (colorScheme == .light ? Color.white.opacity(0.06) : Color.white.opacity(0.03))

                // Soft white highlight from top-left to center to enhance "glass" sheen
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .light ? 0.22 : 0.12),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .blendMode(.plusLighter)

                // Gentle color tint for depth (subtle and theme-agnostic)
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.10),
                        Color.purple.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .blendMode(.softLight)

                // Core blur/translucency material
                Rectangle()
                    .fill(.ultraThinMaterial)

                // Subtle inner border to define edges of the glass
                Rectangle()
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .light ? 0.25 : 0.12),
                        lineWidth: 1
                    )
                    .blendMode(.overlay)
            }
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
    func windowBackground(useGradient: Bool, cornerRadius: CGFloat? = nil) -> some View {
        modifier(WindowBackground(useGradient: useGradient, cornerRadius: cornerRadius))
    }
}
