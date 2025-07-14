import SwiftUI
import MarkdownUI

struct NonEditableModalView: View {
    let transformedText: String
    let originalText: String
    let closeAction: () -> Void
    
    @State private var showCopyConfirmation = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            VStack(spacing: 12) {
                // Text display area with markdown support
                ScrollView {
                    Markdown(transformedText)
                        .markdownTextStyle(\.text) {
                            FontSize(14)
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(minHeight: 300)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color(.controlBackgroundColor) : Color(.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separatorColor), lineWidth: 1)
                )
                
                // Button container aligned to the right
                HStack {
                    Spacer()
                    
                    // Copy button
                    Button(action: copyText) {
                        Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 16))
                            .foregroundColor(showCopyConfirmation ? .green : .primary)
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color(.controlColor) : Color(.controlBackgroundColor))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                    .help("Copy text")
                    .keyboardShortcut("c", modifiers: .command)
                    
                    // Close button
                    Button(action: closeAction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color(.controlColor) : Color(.controlBackgroundColor))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                    .help("Close")
                    .keyboardShortcut(.escape)
                }
                .padding(.top, 8)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        .frame(width: 600, height: 450)
        .onAppear {
            // Set focus to copy button equivalent (first responder)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)
            }
        }
    }
    
    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transformedText, forType: .string)
        
        // Show brief visual feedback
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopyConfirmation = true
        }
        
        // Reset confirmation after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopyConfirmation = false
            }
        }
    }
}

#Preview {
    NonEditableModalView(
        transformedText: "# Sample Markdown\n\nThis is a **sample** text with *markdown* formatting.\n\n- Item 1\n- Item 2\n- Item 3\n\n```swift\nlet code = \"example\"\n```",
        originalText: "Original text here",
        closeAction: {}
    )
    .frame(width: 600, height: 450)
}
