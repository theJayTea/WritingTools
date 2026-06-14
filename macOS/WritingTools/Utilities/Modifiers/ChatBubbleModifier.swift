import SwiftUI

struct ChatBubbleModifier: ViewModifier {
    let isFromUser: Bool
    var isEmpty: Bool = false
    
    func body(content: Content) -> some View {
        let bubbleShape = ChatBubble()
        content
            .padding(isEmpty ? 0 : 16)
            .background(
                bubbleShape
                    .fill(isFromUser ? Color.accentColor.opacity(0.15) :  Color(.controlBackgroundColor))
                    .opacity(isEmpty ? 0 : 1)
            )
    }
}

extension View {
    func chatBubbleStyle(isFromUser: Bool, isEmpty: Bool = false) -> some View {
        self.modifier(ChatBubbleModifier(isFromUser: isFromUser, isEmpty: isEmpty))
    }
}

