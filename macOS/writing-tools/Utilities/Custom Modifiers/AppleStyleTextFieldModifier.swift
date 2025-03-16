import SwiftUI

struct AppleStyleTextFieldModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let isLoading: Bool
    let text: String
    let onSubmit: () -> Void
    
    @State private var isAnimating: Bool = false
    @State private var isHovered: Bool = false
    
    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                content
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)
                    .padding(12)
                    .onSubmit {
                        withAnimation {
                            isAnimating = true
                        }
                        onSubmit()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            isAnimating = false
                        }
                    }
                
                Spacer(minLength: 0)
            }
            
            // Integrated send button with more subtle styling
            if !text.isEmpty {
                Button(action: {
                    withAnimation {
                        isAnimating = true
                    }
                    onSubmit()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isAnimating = false
                    }
                }) {
                    Image(systemName: isLoading ? "hourglass" : "paperplane.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .background(
                            colorScheme == .dark 
                                ? Color.blue
                                : Color.blue
                        )
                        .clipShape(Circle())
                        //.clipShape(RoundedRectangle(cornerRadius: 8))
                        .scaleEffect(isHovered ? 1.05 : 1.0)
                        .opacity(isHovered ? 1.0 : 0.9)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .transition(.opacity)
                .onHover { hovering in
                    isHovered = hovering
                }
            }
        }
        .frame(height: 36) // Slightly taller for better macOS alignment
        .background(
            ZStack {
                if colorScheme == .dark {
                    Color.black.opacity(0.2)
                        .blur(radius: 0.5)
                } else {
                    Color(.textBackgroundColor)
                }
                
                if isLoading {
                    Color.gray.opacity(0.1)
                }
            }
        )
        .cornerRadius(6) // macOS uses subtler corner radii
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isAnimating 
                        ? Color.blue.opacity(0.8)
                        : Color.gray.opacity(0.2),
                    lineWidth: isAnimating ? 2 : 0.5
                )
                .animation(.easeInOut(duration: 0.3), value: isAnimating)
        )
    }
}

extension View {
    func appleStyleTextField(text: String, isLoading: Bool = false, onSubmit: @escaping () -> Void) -> some View {
        self.modifier(AppleStyleTextFieldModifier(isLoading: isLoading, text: text, onSubmit: onSubmit))
    }
}
