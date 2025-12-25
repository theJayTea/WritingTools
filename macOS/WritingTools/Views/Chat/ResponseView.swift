import SwiftUI
import MarkdownView

// MARK: - String Extension for Markdown Processing

extension String {
    /// Normalizes LaTeX delimiters to markdown-friendly versions
    /// Converts \[...\] to $$...$$ and \(...\) to $...$
    fileprivate func normalizedLatex() -> String {
        var result = self
        
        // Convert \[...\] to $$...$$
        result = result.replacingOccurrences(of: #"\\\["#, with: "\n$$", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\\\]"#, with: "$$\n", options: .regularExpression)
        
        // Convert \(...\) to $...$
        result = result.replacingOccurrences(of: #"\\\("#, with: "$", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\\\)"#, with: "$", options: .regularExpression)
        
        return result
    }
    
    /// Strips outer code block wrapper if the entire response is wrapped in one.
    /// Some AI models wrap their entire response in ```markdown or ``` fences.
    fileprivate func strippingOuterCodeBlock() -> String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Pattern to match content wrapped in a single outer code block
        // Matches: ```<optional language>\n<content>\n```
        // The (?s) flag makes . match newlines
        let pattern = #"^```(?:\w+)?\s*\n([\s\S]*?)\n```$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
              let contentRange = Range(match.range(at: 1), in: trimmed) else {
            return self
        }
        
        // Only strip if this is truly a single outer wrapper (no other content outside)
        let content = String(trimmed[contentRange])
        return content
    }
    
    /// Applies all markdown normalizations for AI responses
    fileprivate func normalizedForMarkdown() -> String {
        return self
            .strippingOuterCodeBlock()
            .normalizedLatex()
    }
}

// MARK: - Chat Message Model

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

// MARK: - Response View

struct ResponseView: View {
    @StateObject private var viewModel: ResponseViewModel
    @Bindable private var settings = AppSettings.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var inputText: String = ""
    @State private var isRegenerating: Bool = false
    @State private var scrollProxy: ScrollViewProxy?
    @State private var latestMessageId: UUID?
    @State private var showSettings = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    
    init(content: String, selectedText: String, option: WritingOption? = nil, provider: any AIProvider) {
        self._viewModel = StateObject(wrappedValue: ResponseViewModel(
            content: content,
            selectedText: selectedText,
            option: option,
            provider: provider
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
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
                        
                        // Show loading indicator
                        if viewModel.isProcessing {
                            HStack(alignment: .top, spacing: 12) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color(.controlBackgroundColor))
                                )
                                Spacer(minLength: 15)
                            }
                            .padding(.top, 4)
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
                        .disabled(viewModel.isProcessing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(.windowBackgroundColor))
        }
        .windowBackground(useGradient: settings.useGradientTheme)
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty, !viewModel.isProcessing else { return }
        let question = inputText
        inputText = ""
        isRegenerating = true
        
        Task {
            do {
                try await viewModel.processFollowUpQuestion(question)
                await MainActor.run {
                    isRegenerating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isRegenerating = false
                }
            }
        }
    }
}

// MARK: - Chat Message View

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
            RichMarkdownView(text: message.content, fontSize: fontSize)
                .textSelection(.enabled)
                .chatBubbleStyle(isFromUser: message.role == "user")
                .accessibilityLabel(message.role == "user" ? "Your message" : "Assistant's response")
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
                    .foregroundStyle(.secondary)
                
                Button(action: copyEntireMessage) {
                    if showCopiedFeedback {
                        Text("Copied")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: [])
        pasteboard.writeObjects([message.content as NSString])
        
        showCopiedFeedback = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            showCopiedFeedback = false
        }
    }
}

// MARK: - View Model

@MainActor
final class ResponseViewModel: ObservableObject {
    
    // UserDefaults key for persistent font size storage
    private static let fontSizeKey = "ResponseView.fontSize"
    private static let defaultFontSize: CGFloat = 14
    
    @Published var messages: [ChatMessage] = []
    @Published var fontSize: CGFloat = 14 {
            didSet {
                // Save font size to UserDefaults whenever it changes
                UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey)
            }
    }
    @Published var showCopyConfirmation = false
    @Published var isProcessing = false
    
    private let content: String
    private let selectedText: String
    private let option: WritingOption?
    private let provider: any AIProvider
    
    // Store conversation history for context
    private var conversationHistory: [(role: String, content: String)] = []
    
    init(content: String, selectedText: String, option: WritingOption?, provider: any AIProvider) {
        // 🔧 Normalize markdown content (strip outer code blocks + normalize LaTeX)
        self.content = content.normalizedForMarkdown()
        self.selectedText = selectedText
        self.option = option
        self.provider = provider
        
        // Load saved font size from UserDefaults, or use default
        let savedFontSize = UserDefaults.standard.object(forKey: Self.fontSizeKey) as? CGFloat
        self.fontSize = savedFontSize ?? Self.defaultFontSize
        
        // Add initial assistant message
        messages.append(ChatMessage(role: "assistant", content: self.content))
        
        // Initialize conversation history
        if !selectedText.isEmpty {
            conversationHistory.append((role: "user", content: selectedText))
        }
        conversationHistory.append((role: "assistant", content: self.content))
    }
    
    func processFollowUpQuestion(_ question: String) async throws {
        // Add user message to UI
        messages.append(ChatMessage(role: "user", content: question))
        
        // Add to conversation history
        conversationHistory.append((role: "user", content: question))
        
        isProcessing = true
        
        do {
            // Build context-aware system prompt
            let systemPrompt = buildSystemPrompt()
            
            // Build user prompt with conversation context
            let userPrompt = buildUserPrompt(question: question)
            
            // Call the actual AI provider
            let rawResponse = try await provider.processText(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: [], // Follow-up questions don't include images
                streaming: false
            )
            
            // 🔧 Normalize markdown content (strip outer code blocks + normalize LaTeX)
            let normalizedResponse = rawResponse.normalizedForMarkdown()
            
            // Add to UI
            messages.append(ChatMessage(role: "assistant", content: normalizedResponse))
            
            // Add to conversation history
            conversationHistory.append((role: "assistant", content: normalizedResponse))
            
            isProcessing = false
        } catch {
            isProcessing = false
            throw error
        }
    }
    
    private func buildSystemPrompt() -> String {
        // Use the original option's system prompt if available, otherwise use a general one
        if let option = option {
            return """
            You are a helpful AI assistant continuing a conversation about text modification.
            
            Original task: \(option.systemPrompt)
            
            The user may ask follow-up questions or request modifications. Provide helpful, 
            contextual responses based on the conversation history. Use Markdown formatting 
            where appropriate.
            """
        } else {
            return """
            You are a helpful AI assistant. Answer the user's questions thoughtfully and 
            comprehensively. Maintain context from the conversation history. Use Markdown 
            formatting where appropriate.
            """
        }
    }
    
    private func buildUserPrompt(question: String) -> String {
        // Include recent conversation history for context (last 5 exchanges)
        let recentHistory = conversationHistory.suffix(10) // Last 5 exchanges (user + assistant)
        
        var prompt = ""
        
        // Add conversation history
        if recentHistory.count > 2 { // More than just the initial exchange
            prompt += "Conversation history:\n\n"
            for (_, exchange) in recentHistory.dropLast(1).enumerated() {
                let role = exchange.role == "user" ? "User" : "Assistant"
                prompt += "\(role): \(exchange.content)\n\n"
            }
            prompt += "---\n\n"
        }
        
        // Add current question
        prompt += "User's follow-up question: \(question)"
        
        return prompt
    }
    
    func copyContent() {
        let conversationText = messages.map { message in
            return "\(message.role.capitalized): \(message.content)"
        }.joined(separator: "\n\n")
        
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: [])
        pasteboard.writeObjects([conversationText as NSString])
        
        showCopyConfirmation = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.showCopyConfirmation = false
        }
    }
}

// MARK: - Rich Markdown View

struct RichMarkdownView: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        MarkdownView(text)
            .markdownMathRenderingEnabled()
            // Body text (paragraphs, list items, etc.)
            .font(.system(size: fontSize), for: .body)
            // Headings - scaled relative to base font size
            .font(.system(size: fontSize * 1.4, weight: .bold), for: .h1)
            .font(.system(size: fontSize * 1.25, weight: .bold), for: .h2)
            .font(.system(size: fontSize * 1.15, weight: .semibold), for: .h3)
            .font(.system(size: fontSize * 1.1, weight: .semibold), for: .h4)
            .font(.system(size: fontSize * 1.05, weight: .medium), for: .h5)
            .font(.system(size: fontSize, weight: .medium), for: .h6)
            // Code blocks
            .font(.system(size: fontSize, design: .monospaced), for: .codeBlock)
            // Block quotes
            .font(.system(size: fontSize), for: .blockQuote)
            // Tables
            .font(.system(size: fontSize, weight: .semibold), for: .tableHeader)
            .font(.system(size: fontSize), for: .tableBody)
            // Math
            .font(.system(size: fontSize), for: .inlineMath)
            .font(.system(size: fontSize + 2), for: .displayMath)
            // Tint for inline code
            .tint(.primary, for: .inlineCodeBlock)
    }
}
