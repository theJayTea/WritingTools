import SwiftUI

struct ChatBubble: Shape {
    var isFromUser: Bool

    func path(in rect: CGRect) -> Path {
        // A simple rounded rect with a corner radius
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .path(in: rect)    }
}
