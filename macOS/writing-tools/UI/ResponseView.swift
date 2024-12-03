import SwiftUI
import MarkdownUI

final class ResponseViewModel: ObservableObject {
    @Published var content: String
    @Published var fontSize: CGFloat = 14
    @Published var showCopyConfirmation: Bool = false
    
    let selectedText: String
    let option: WritingOption
    
    init(content: String, selectedText: String, option: WritingOption) {
        self.content = content
        self.selectedText = selectedText
        self.option = option
    }
    
    func regenerateContent() async {
        do {
            let result = try await AppState.shared.activeProvider.processText(
                systemPrompt: option.systemPrompt,
                userPrompt: selectedText
            )
            await MainActor.run {
                self.content = result
            }
        } catch {
            print("Error regenerating content: \(error.localizedDescription)")
        }
    }
    
    func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        
        // Show confirmation
        showCopyConfirmation = true
        
        // Hide confirmation after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showCopyConfirmation = false
        }
    }
}

/// Main ResponseView
struct ResponseView: View {
    @StateObject private var viewModel: ResponseViewModel
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("use_gradient_theme") private var useGradientTheme = false

    init(content: String, selectedText: String, option: WritingOption) {
        self._viewModel = StateObject(wrappedValue: ResponseViewModel(
            content: content,
            selectedText: selectedText,
            option: option
        ))
    }

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                Markdown(viewModel.content)
                    .font(.system(size: viewModel.fontSize))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                HStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await viewModel.regenerateContent()
                        }
                    }) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    
                    Button(action: {
                        viewModel.copyContent()
                    }) {
                        Label(viewModel.showCopyConfirmation ? "Copied!" : "Copy",
                              systemImage: viewModel.showCopyConfirmation ? "checkmark" : "doc.on.doc")
                    }
                    .animation(.easeInOut, value: viewModel.showCopyConfirmation)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { viewModel.fontSize = max(10, viewModel.fontSize - 2) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .disabled(viewModel.fontSize <= 10)

                    Button(action: { viewModel.fontSize = 14 }) {
                        Image(systemName: "arrow.clockwise")
                    }

                    Button(action: { viewModel.fontSize = min(24, viewModel.fontSize + 2) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .disabled(viewModel.fontSize >= 24)
                }
            }
            .padding()
        }
        .windowBackground(useGradient: useGradientTheme)
    }
}
