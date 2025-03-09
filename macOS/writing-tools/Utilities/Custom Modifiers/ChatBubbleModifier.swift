import SwiftUI

struct ChatBubbleModifier: ViewModifier {
    let isFromUser: Bool
    
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                ChatBubble(isFromUser: isFromUser)
                    .fill(isFromUser ? Color.blue.opacity(0.15) :  Color(.controlBackgroundColor))
            )
    }
}

extension View {
    func chatBubbleStyle(isFromUser: Bool) -> some View {
        self.modifier(ChatBubbleModifier(isFromUser: isFromUser))
    }
}
