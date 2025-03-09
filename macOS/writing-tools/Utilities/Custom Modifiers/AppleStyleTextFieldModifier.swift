import SwiftUI

struct AppleStyleTextFieldModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    let isLoading: Bool
    let text: String
    let onSubmit: () -> Void
    
    @State private var isAnimating: Bool = false
    
    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                content
                    .font(.system(size: 14))
                    .foregroundColor(.white)
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
            
            // Integrated send button
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
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.2, green: 0.5, blue: 1.0),
                                    Color(red: 0.6, green: 0.3, blue: 0.9)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 2) 
                .transition(.opacity)
            }
        }
        .frame(height: 32)
        .background(
            ZStack {
                Color.black.opacity(0.3)
                    .blur(radius: 0.5)
                
                if isLoading {
                    Color.black.opacity(0.2)
                }
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.2, green: 0.5, blue: 1.0).opacity(isAnimating ? 0.8 : 0.1),
                            Color(red: 0.6, green: 0.3, blue: 0.9).opacity(isAnimating ? 0.8 : 0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
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
