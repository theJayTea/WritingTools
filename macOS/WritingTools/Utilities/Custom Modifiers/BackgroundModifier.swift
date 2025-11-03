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
                        MeshLikeGradientBackground()
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

struct MeshLikeGradientBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        if colorScheme == .light {
            ZStack {
                Color(hex: "f1f5f9")

                GeometryReader { proxy in
                    let size = max(proxy.size.width, proxy.size.height)
                    
                    ZStack {
                        // Top left slate blob
                        Circle()
                            .fill(Color(hex: "f1f5f9").opacity(0.8))
                            .frame(width: size * 0.9, height: size * 0.9)
                            .position(
                                x: proxy.size.width * 0.15,
                                y: proxy.size.height * 0.15
                            )

                        // Bottom left slate blob
                        Circle()
                            .fill(Color(hex: "f1f5f9").opacity(0.8))
                            .frame(width: size * 0.9, height: size * 0.9)
                            .position(
                                x: proxy.size.width * 0.15,
                                y: proxy.size.height * 0.85
                            )

                        // Top middle cyan blob
                        Circle()
                            .fill(Color(hex: "a5f3fc").opacity(0.8))
                            .frame(width: size * 1.0, height: size * 1.0)
                            .position(
                                x: proxy.size.width * 0.5,
                                y: proxy.size.height * 0.15
                            )

                        // Bottom middle cyan blob
                        Circle()
                            .fill(Color(hex: "a5f3fc").opacity(0.8))
                            .frame(width: size * 1.0, height: size * 1.0)
                            .position(
                                x: proxy.size.width * 0.5,
                                y: proxy.size.height * 0.85
                            )

                        // Top right indigo blob
                        Circle()
                            .fill(Color(hex: "818cf8").opacity(0.8))
                            .frame(width: size * 0.9, height: size * 0.9)
                            .position(
                                x: proxy.size.width * 0.85,
                                y: proxy.size.height * 0.15
                            )

                        // Bottom right indigo blob
                        Circle()
                            .fill(Color(hex: "818cf8").opacity(0.8))
                            .frame(width: size * 0.9, height: size * 0.9)
                            .position(
                                x: proxy.size.width * 0.85,
                                y: proxy.size.height * 0.85
                            )
                    }
                }
                .blur(radius: 100)
            }
        } else {
            // Dark mode version
            ZStack {
                Color(hex: "083344")

                GeometryReader { proxy in
                    let size = max(proxy.size.width, proxy.size.height)
                    
                    ZStack {
                        // Top left dark slate blob
                        Circle()
                            .fill(Color(hex: "083344").opacity(0.8))
                            .frame(width: size * 0.9, height: size * 0.9)
                            .position(
                                x: proxy.size.width * 0.15,
                                y: proxy.size.height * 0.15
                            )

                        // Bottom left dark slate blob
                        Circle()
                            .fill(Color(hex: "083344").opacity(0.8))
                            .frame(width: size * 0.9, height: size * 0.9)
                            .position(
                                x: proxy.size.width * 0.15,
                                y: proxy.size.height * 0.85
                            )

                        // Top middle indigo blob
                        Circle()
                            .fill(Color(hex: "6366f1").opacity(0.8))
                            .frame(width: size * 1.0, height: size * 1.0)
                            .position(
                                x: proxy.size.width * 0.5,
                                y: proxy.size.height * 0.15
                            )

                        // Bottom middle indigo blob
                        Circle()
                            .fill(Color(hex: "6366f1").opacity(0.8))
                            .frame(width: size * 1.0, height: size * 1.0)
                            .position(
                                x: proxy.size.width * 0.5,
                                y: proxy.size.height * 0.85
                            )

                        // Top right rose blob
                        Circle()
                            .fill(Color(hex: "881337").opacity(0.8))
                            .frame(width: size * 0.9, height: size * 0.9)
                            .position(
                                x: proxy.size.width * 0.85,
                                y: proxy.size.height * 0.15
                            )

                        // Bottom right rose blob
                        Circle()
                            .fill(Color(hex: "881337").opacity(0.8))
                            .frame(width: size * 0.9, height: size * 0.9)
                            .position(
                                x: proxy.size.width * 0.85,
                                y: proxy.size.height * 0.85
                            )
                    }
                }
                .blur(radius: 100)
            }
        }
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



#Preview {
    MeshLikeGradientBackground()
}
