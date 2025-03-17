import SwiftUI

struct FloatingIconView: View {
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.primary)
                .padding(4)
                .background {
                    Circle()
                        .fill(colorScheme == .dark ? 
                              Color.black.opacity(0.8) : 
                              Color.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Writing Tools")
        .help("Open Writing Tools")
    }
}
