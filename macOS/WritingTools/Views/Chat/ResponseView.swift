import SwiftUI
import MarkdownUI

struct ChatMessage: Identifiable, Equatable, Sendable {
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
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var inputText: String = ""
    @State private var isRegenerating: Bool = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var latestMessageId: UUID?
    @State private var showSettings = false
    
    init(content: String, selectedText: String, option: WritingOption? = nil) {
        self._viewModel = StateObject(wrappedValue: ResponseViewModel(
            content: content,
            selectedText: selectedText,
            option: option
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Enhanced toolbar with more controls
            HStack(spacing: 16) {
                Button(action: { viewModel.copyContent() }) {
                    Label(viewModel.showCopyConfirmation ? "Copied!" : "Copy All",
                          systemImage: viewModel.showCopyConfirmation ? "checkmark" : "doc.on.doc")
                    .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .animation(.easeInOut, value: viewModel.showCopyConfirmation)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { viewModel.fontSize -= 1 }) {
                        Label("Decrease text size", systemImage: "textformat.size.smaller")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.fontSize <= 10)
                    .keyboardShortcut("-", modifiers: .command)
                    
                    Button(action: { viewModel.fontSize += 1 }) {
                        Label("Increase text size", systemImage: "textformat.size.larger")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.fontSize >= 20)
                    .keyboardShortcut("+", modifiers: .command)
                    
                    Button(action: {
                        viewModel.fontSize = 14
                    }) {
                        Label("Reset Font Size", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .padding()
            .background(Color.clear)
            
            // Chat messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageView(message: message, fontSize: viewModel.fontSize)
                                .id(message.id)
                                .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
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
        .windowBackground(useGradient: settings.useGradientTheme)
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
    @State private var isHovering: Bool = false
    @State private var showCopiedFeedback: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == "assistant" {
                bubbleView(role: message.role).transition(.move(edge: .leading))
                Spacer(minLength: 15)
            } else {
                Spacer(minLength: 15)
                bubbleView(role: message.role).transition(.move(edge: .trailing))
            }
        }
        .padding(.top, 4)
        .animation(.spring(), value: message.role)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    @ViewBuilder
    private func bubbleView(role: String) -> some View {
        VStack(alignment: role == "assistant" ? .leading : .trailing, spacing: 2) {
            Markdown(message.content)
                .markdownTextStyle(\.text){
                    FontSize(fontSize)
                }
                .markdownTextStyle(\.code){
                    
                }
                .textSelection(.enabled)
                .chatBubbleStyle(isFromUser: message.role == "user")
                .accessibilityLabel(role == "user" ? "Your message" : "Assistant's response")
                .accessibilityValue(message.content)
                .contextMenu {
                    Button("Copy Selection") {
                        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    }
                    Button("Copy Message") {
                        copyEntireMessage()
                    }
                }
            
            // Timestamp and copy button
            HStack(spacing: 8) {
                Text(message.timestamp.formatted(.dateTime.hour().minute()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Button(action: copyEntireMessage) {
                    if showCopiedFeedback {
                        Text("Copied")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help(showCopiedFeedback ? "" : "Copy Message")
            }
            .padding(.bottom, 2)
        }
        .frame(maxWidth: 500, alignment: role == "assistant" ? .leading : .trailing)
    }
    
    private func copyEntireMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        
        showCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showCopiedFeedback = false
        }
    }
}

// A small convenience enum for clarity (optional)
fileprivate enum MessageRole {
    case user, assistant
}


extension View {
    func maxWidth(_ width: CGFloat) -> some View {
        frame(maxWidth: width)
    }
}

// Update ResponseViewModel to handle chat messages
@MainActor
final class ResponseViewModel: ObservableObject, Sendable {
    
    @Published var messages: [ChatMessage] = []
    @Published var fontSize: CGFloat = 14
    @Published var showCopyConfirmation: Bool = false
    let initialContent: String
    
    let selectedText: String
    let option: WritingOption?
    
    init(content: String, selectedText: String, option: WritingOption? = nil) {
        self.initialContent = content
        self.selectedText = selectedText
        self.option = option
        
        // Initialize with the first message
        self.messages.append(ChatMessage(
            role: "assistant",
            content: content
        ))
    }
    
    func processFollowUpQuestion(_ question: String, completion: @escaping () -> Void) {
        // Add user message (already on MainActor)
        self.messages.append(ChatMessage(
            role: "user",
            content: question
        ))
        
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
                    You are a writing and coding assistant. Your sole task is to respond to the user's instruction thoughtfully and comprehensively.
                    If the instruction is a question, provide a detailed answer. But always return the best and most accurate answer and not different options. 
                    If it's a request for help, provide clear guidance and examples where appropriate. Make sure to use the language used or specified by the user instruction.
                    Use Markdown formatting to make your response more readable.
                    DO NOT ANSWER OR RESPOND TO THE USER'S TEXT CONTENT.
                    """,
                    userPrompt: contextualPrompt,
                    images: AppState.shared.selectedImages,
                    streaming: true
                )
                
                await MainActor.run {
                    self.messages.append(ChatMessage(
                        role: "assistant",
                        content: result
                    ))
                    completion()
                }
            } catch {
                print("Error processing follow-up: \(error)")
                await MainActor.run { completion() }
            }
        }
    }
    
    func clearConversation() {
        messages.removeAll()
    }
    
    func copyContent() {
        // Concatenate all messages in the conversation
        let conversationText = messages.map { message in
            return "\(message.role.capitalized): \(message.content)" // Format each message with role
        }.joined(separator: "\n\n") // Join messages with double newlines for readability
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(conversationText, forType: .string)
        
        showCopyConfirmation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showCopyConfirmation = false
        }
    }
}

