import SwiftUI
import MarkdownUI
import LaTeXSwiftUI

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

struct RichTextSegment: Identifiable {
    enum Kind {
        case markdown(String)
        case inlineMath(String)
        case blockMath(String)
    }

    let id = UUID()
    let kind: Kind
}

enum RichTextParser {

    static func parse(_ text: String) -> [RichTextSegment] {
        var segments: [RichTextSegment] = []

        var index = text.startIndex
        var currentTextStart = index

        func flushMarkdown(upTo end: String.Index) {
            guard currentTextStart < end else { return }
            let slice = String(text[currentTextStart..<end])
            if !slice.isEmpty {
                segments.append(.init(kind: .markdown(slice)))
            }
            currentTextStart = end
        }

        func advance(_ i: inout String.Index, by n: Int) {
            i = text.index(i, offsetBy: n, limitedBy: text.endIndex) ?? text.endIndex
        }

        while index < text.endIndex {
            let ch = text[index]

            // MARK: - Backslash-based delimiters: \( \), \[ \], \begin{...}\end{...}
            if ch == "\\" {
                let remaining = text[index...]

                // 1) \(
                if remaining.hasPrefix(#"\("#) {
                    let start = index
                    let contentStart = text.index(start, offsetBy: 2) // after "\("
                    if let closeRange = text.range(of: #"\\)"#, range: contentStart..<text.endIndex) {
                        flushMarkdown(upTo: start)
                        let content = String(text[contentStart..<closeRange.lowerBound])
                        segments.append(.init(kind: .inlineMath(content)))
                        index = closeRange.upperBound
                        currentTextStart = index
                        continue
                    }
                }

                // 2) \[
                if remaining.hasPrefix(#"\["#) {
                    let start = index
                    let contentStart = text.index(start, offsetBy: 2) // after "\["
                    if let closeRange = text.range(of: #"\\]"#, range: contentStart..<text.endIndex) {
                        flushMarkdown(upTo: start)
                        let content = String(text[contentStart..<closeRange.lowerBound])
                        segments.append(.init(kind: .blockMath(content)))
                        index = closeRange.upperBound
                        currentTextStart = index
                        continue
                    }
                }

                // 3) \begin{...} ... \end{...}
                if remaining.hasPrefix(#"\begin{"#) {
                    let start = index
                    let envNameStart = text.index(start, offsetBy: 7) // after "\begin{"

                    if let envNameEnd = text[envNameStart...].firstIndex(of: "}") {
                        let envName = String(text[envNameStart..<envNameEnd])
                        let endToken = "\\end{\(envName)}"
                        let searchStart = text.index(after: envNameEnd)

                        if let endRange = text.range(of: endToken, range: searchStart..<text.endIndex) {
                            flushMarkdown(upTo: start)

                            // Keep the full environment (begin + content + end)
                            let blockRange = start..<endRange.upperBound
                            let content = String(text[blockRange])

                            segments.append(.init(kind: .blockMath(content)))
                            index = endRange.upperBound
                            currentTextStart = index
                            continue
                        }
                    }
                }

                // No known LaTeX token → just move on
                advance(&index, by: 1)
                continue
            }

            // MARK: - Dollar-based delimiters: $...$, $$...$$
            if ch == "$" {
                let start = index
                let next = text.index(after: index)
                let hasNext = next < text.endIndex

                // Block math: $$...$$
                if hasNext, text[next] == "$" {
                    flushMarkdown(upTo: start)

                    let contentStart = text.index(start, offsetBy: 2) // after "$$"
                    if let endRange = text.range(of: "$$", range: contentStart..<text.endIndex) {
                        let content = String(text[contentStart..<endRange.lowerBound])
                        segments.append(.init(kind: .blockMath(content)))
                        index = endRange.upperBound
                        currentTextStart = index
                        continue
                    } else {
                        // No closing $$ → treat as plain text
                        // (fall through)
                    }
                } else {
                    // Inline math: $...$
                    flushMarkdown(upTo: start)

                    if let closing = findClosingDollar(in: text, start: next) {
                        let content = String(text[next..<closing])
                        segments.append(.init(kind: .inlineMath(content)))
                        index = text.index(after: closing) // skip closing $
                        currentTextStart = index
                        continue
                    } else {
                        // No closing $ → treat as plain text
                        // (fall through)
                    }
                }
            }

            // DEFAULT: just move forward
            advance(&index, by: 1)
        }

        // Flush trailing markdown
        flushMarkdown(upTo: text.endIndex)
        return segments
    }

    /// Finds a matching `$` that is not escaped (i.e. not preceded by `\`).
    private static func findClosingDollar(in text: String, start: String.Index) -> String.Index? {
        var i = start
        while i < text.endIndex {
            let ch = text[i]
            if ch == "$" {
                if i == text.startIndex {
                    return i
                }
                let prev = text.index(before: i)
                if text[prev] != "\\" {
                    return i
                }
                // If it *is* escaped (`\$`), just skip and continue
            }
            i = text.index(after: i)
        }
        return nil
    }
}


struct RichMarkdownView: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        let segments = RichTextParser.parse(text)

        VStack(alignment: .leading, spacing: 4) {
            ForEach(segments) { segment in
                switch segment.kind {
                case .markdown(let md):
                    Markdown(md)
                        .markdownTextStyle(\.text) {
                            FontSize(fontSize)
                        }

                case .inlineMath(let latex):
                    // Inline math: keep same size as text
                    LaTeX(latex)
                        .font(.system(size: fontSize))

                case .blockMath(let latex):
                    // Block math: slightly bigger and full-width
                    LaTeX(latex)
                        .font(.system(size: fontSize + 2))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
            }
        }
    }
}
