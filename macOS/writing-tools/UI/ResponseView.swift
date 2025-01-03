import SwiftUI
import MarkdownUI

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date = Date()
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.content == rhs.content &&
        lhs.timestamp == rhs.timestamp
    }
}

struct ResponseView: View {
    @StateObject private var viewModel: ResponseViewModel
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("use_gradient_theme") private var useGradientTheme = false
    @State private var inputText: String = ""
    @State private var isRegenerating: Bool = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var latestMessageId: UUID?
    
    init(content: String, selectedText: String, option: WritingOption) {
        self._viewModel = StateObject(wrappedValue: ResponseViewModel(
            content: content,
            selectedText: selectedText,
            option: option
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar with controls
            HStack {
                Button(action: { viewModel.copyContent() }) {
                    Label(viewModel.showCopyConfirmation ? "Copied!" : "Copy",
                          systemImage: viewModel.showCopyConfirmation ? "checkmark" : "doc.on.doc")
                }
                .animation(.easeInOut, value: viewModel.showCopyConfirmation)
                
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
            .background(Color(.windowBackgroundColor))
            
            // Chat messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageView(message: message, fontSize: viewModel.fontSize)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages, initial: true) { oldValue, newValue in
                    if let lastId = newValue.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input area
            VStack(spacing: 8) {
                Divider()
                
                HStack(spacing: 8) {
                    TextField("Ask a follow-up question...", text: $inputText)
                        .textFieldStyle(.plain)
                        .appleStyleTextField(
                            text: inputText,
                            isLoading: isRegenerating,
                            onSubmit: sendMessage
                        )
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(.windowBackgroundColor))
        }
        .windowBackground(useGradient: useGradientTheme)
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        let question = inputText
        inputText = ""
        isRegenerating = true
        viewModel.processFollowUpQuestion(question) {
            isRegenerating = false
        }
    }
}

struct ChatMessageView: View {
    let message: ChatMessage
    let fontSize: CGFloat
    
    var body: some View {
        HStack(alignment: .top) {
            if message.role == "user" {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Markdown(message.content)
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: 280, alignment: .leading) // Always left-align the text
                    .background(message.role == "user" ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                    .cornerRadius(12)
                
                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if message.role == "assistant" {
                Spacer(minLength: 60)
            }
        }
    }
}

extension View {
    func maxWidth(_ width: CGFloat) -> some View {
        frame(maxWidth: width)
    }
}

// Update ResponseViewModel to handle chat messages
final class ResponseViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var fontSize: CGFloat = 14
    @Published var showCopyConfirmation: Bool = false
    
    let selectedText: String
    let option: WritingOption
    
    init(content: String, selectedText: String, option: WritingOption) {
        self.selectedText = selectedText
        self.option = option
        
        // Initialize with the first message
        self.messages.append(ChatMessage(
            role: "assistant",
            content: content
        ))
    }
    
    func processFollowUpQuestion(_ question: String, completion: @escaping () -> Void) {
        // Add user message
        DispatchQueue.main.async {
            self.messages.append(ChatMessage(
                role: "user",
                content: question
            ))
        }
        
        Task {
            do {
                // Build conversation history
                let conversationHistory = messages.map { message in
                    return "\(message.role == "user" ? "User" : "Assistant"): \(message.content)"
                }.joined(separator: "\n\n")
                
                // Create prompt with context
                let contextualPrompt = """
                Previous conversation:
                \(conversationHistory)
                
                User's new question: \(question)
                
                Respond to the user's question while maintaining context from the previous conversation.
                """
                
                let result = try await AppState.shared.activeProvider.processText(
                    systemPrompt: """
                    You are a helpful AI assistant continuing a conversation. You have access to the entire conversation history and should maintain context when responding.
                    Provide clear and direct responses, maintaining the same format and style as your previous responses.
                    If appropriate, use Markdown formatting to make your response more readable.
                    Consider all previous messages when formulating your response.
                    """,
                    userPrompt: contextualPrompt
                )
                
                DispatchQueue.main.async {
                    self.messages.append(ChatMessage(
                        role: "assistant",
                        content: result
                    ))
                    completion()
                }
            } catch {
                print("Error processing follow-up: \(error)")
                completion()
            }
        }
    }
    
    func clearConversation() {
        messages.removeAll()
    }
    
    func copyContent() {
        // Only copy the latest AI response
        if let latestAiMessage = messages.last(where: { $0.role == "assistant" }) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(latestAiMessage.content, forType: .string)
            
            showCopyConfirmation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.showCopyConfirmation = false
            }
        }
    }
}
