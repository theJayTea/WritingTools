import SwiftUI
import MarkdownView
import Observation

// MARK: - String Extension for Markdown Processing

/// Compiled-once regexes for markdown fence normalization.
///
/// These patterns are constant literals, so compilation cannot fail and the
/// objects are safe to reuse across threads for matching. Caching them avoids
/// rebuilding an `NSRegularExpression` on every render pass while streaming.
private enum MarkdownFenceRegex {
    /// Matches an entire response wrapped in ```markdown / ```md fences.
    static let outerCodeBlock = try! NSRegularExpression(
        pattern: #"^```(?:markdown|md)\s*\n([\s\S]*?)\n```$"#,
        options: [.caseInsensitive]
    )

    /// Matches a partial, not-yet-closed ```markdown / ```md fence (streaming).
    static let partialOuterFence = try! NSRegularExpression(
        pattern: #"^```(?:markdown|md)\s*\n([\s\S]*)$"#,
        options: [.caseInsensitive]
    )
}

extension String {
    /// Strips outer markdown code block wrapper if the entire response is wrapped in one.
    /// Some AI models wrap their entire response in ```markdown fences.
    fileprivate func strippingOuterCodeBlock() -> String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only unwrap markdown wrappers so legitimate code fences (e.g. ```swift) stay intact.
        let regex = MarkdownFenceRegex.outerCodeBlock
        guard let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
              let contentRange = Range(match.range(at: 1), in: trimmed) else {
            return self
        }

        return String(trimmed[contentRange])
    }
    
    /// Applies all markdown normalizations for completed AI responses.
    func normalizedForMarkdown() -> String {
        return self.strippingOuterCodeBlock()
    }

    /// Produces markdown that is safe to hand to the renderer while a response is still streaming.
    /// This does not change the stored response; it only makes incomplete fences render predictably.
    func renderableMarkdownForResponse(isStreaming: Bool) -> String {
        guard isStreaming else {
            return normalizedForMarkdown()
        }

        return strippingPartialOuterMarkdownFence()
            .balancingUnclosedCodeFenceForDisplay()
    }

    private func strippingPartialOuterMarkdownFence() -> String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)

        let regex = MarkdownFenceRegex.partialOuterFence
        guard let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)),
              let contentRange = Range(match.range(at: 1), in: trimmed) else {
            return self
        }

        var content = String(trimmed[contentRange])
        if content.hasSuffix("\n```") {
            content.removeLast(4)
        }
        return content
    }

    private func balancingUnclosedCodeFenceForDisplay() -> String {
        let fenceCount = self.components(separatedBy: .newlines).reduce(0) { count, line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("```") ? count + 1 : count
        }

        guard fenceCount.isMultiple(of: 2) == false else {
            return self
        }

        return self + "\n```"
    }
}

// MARK: - Chat Message Model

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: String // "user" or "assistant"
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    
    init(role: String, content: String, isStreaming: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isStreaming = isStreaming
    }
    
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.content == rhs.content &&
        lhs.timestamp == rhs.timestamp &&
        lhs.isStreaming == rhs.isStreaming
    }
}

// MARK: - Response View

struct ResponseView: View {
    @State private var viewModel: ResponseViewModel
    @Bindable private var settings = AppSettings.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    /// Seeds the markdown base font size from the Dynamic Type `.body` metric so
    /// the default scales with the user's preferred text size. The user's +/-
    /// delta is applied on top of this scaled base.
    @ScaledMetric(relativeTo: .body) private var baseFontSize: Double = 14
    @State private var inputText: String = ""
    @State private var isRegenerating: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var isPinnedToLatest: Bool = true
    @State private var scrollViewportHeight: CGFloat = 0

    private let bottomAnchorId = "response-scroll-bottom-anchor"
    private let scrollCoordinateSpaceName = "response-scroll-coordinate-space"
    
    init(
        content: String,
        selectedText: String,
        option: WritingOption? = nil,
        provider: any AIProvider,
        continuationSystemPrompt: String? = nil
    ) {
        self._viewModel = State(initialValue: ResponseViewModel(
            content: content,
            selectedText: selectedText,
            option: option,
            provider: provider,
            continuationSystemPrompt: continuationSystemPrompt
        ))
    }

    /// Streaming initializer: opens immediately and streams the AI response.
    init(
        selectedText: String,
        option: WritingOption? = nil,
        provider: any AIProvider,
        systemPrompt: String,
        userPrompt: String,
        images: [Data],
        continuationSystemPrompt: String? = nil
    ) {
        self._viewModel = State(initialValue: ResponseViewModel(
            selectedText: selectedText,
            option: option,
            provider: provider,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images,
            continuationSystemPrompt: continuationSystemPrompt
        ))
    }
    
    /// Effective markdown font size: the Dynamic Type-scaled base plus the
    /// user's +/- delta (relative to the stored default of 14). This keeps the
    /// user-facing font-size controls working while letting the default respond
    /// to the system text size.
    private var effectiveFontSize: CGFloat {
        let userDelta = viewModel.fontSize - ResponseViewModel.defaultFontSize
        return CGFloat(baseFontSize) + userDelta
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chat messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            ChatMessageView(message: message, fontSize: effectiveFontSize)
                                .id(message.id)
                                .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                        }

                        // Show loading indicator only when processing and no streaming message is visible
                        if viewModel.isProcessing && !(viewModel.messages.last?.isStreaming == true) {
                            HStack(alignment: .top, spacing: 12) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.body)
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
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Thinking")
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorId)
                            .background(
                                GeometryReader { marker in
                                    Color.clear.preference(
                                        key: ScrollBottomOffsetKey.self,
                                        value: marker.frame(in: .named(scrollCoordinateSpaceName)).maxY
                                    )
                                }
                            )
                    }
                    .padding()
                }
                .coordinateSpace(name: scrollCoordinateSpaceName)
                .background(
                    GeometryReader { viewport in
                        Color.clear.preference(key: ScrollViewportHeightKey.self, value: viewport.size.height)
                    }
                )
                .overlay(alignment: .bottomTrailing) {
                    if !isPinnedToLatest && viewModel.isProcessing {
                        Button {
                            scrollToLatest(proxy, animated: !reduceMotion)
                        } label: {
                            Label("Jump to Latest", systemImage: "arrow.down.to.line.compact")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding()
                        .help("Jump to Latest")
                    }
                }
                .onPreferenceChange(ScrollViewportHeightKey.self) { height in
                    updateScrollViewportHeight(height)
                }
                .onPreferenceChange(ScrollBottomOffsetKey.self) { bottomOffset in
                    updatePinnedToLatest(bottomOffset: bottomOffset)
                }
                .onChange(of: viewModel.messages) { oldValue, newValue in
                    guard newValue.count > oldValue.count, isPinnedToLatest else {
                        return
                    }

                    scrollToLatest(proxy, animated: !reduceMotion)
                }
                .onChange(of: viewModel.messages.last?.content) { _, _ in
                    guard viewModel.messages.last?.isStreaming == true, isPinnedToLatest else {
                        return
                    }

                    scrollToLatest(proxy, animated: !reduceMotion, duration: 0.1)
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
                        .accessibilityLabel("Follow-up question")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .auxiliaryWindowSurface(useGradient: settings.useGradientTheme)
        }
        .windowBackground(useGradient: settings.useGradientTheme)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { viewModel.copyContent() }) {
                    Label(viewModel.showCopyConfirmation ? "Copied!" : "Copy All",
                          systemImage: viewModel.showCopyConfirmation ? "checkmark" : "doc.on.doc")
                }
                .animation(reduceMotion ? nil : .easeInOut, value: viewModel.showCopyConfirmation)
            }

            ToolbarItemGroup(placement: .automatic) {
                Button(action: { viewModel.fontSize -= 1 }) {
                    Label("Decrease text size", systemImage: "textformat.size.smaller")
                }
                .disabled(viewModel.fontSize <= ResponseViewModel.minimumFontSize)
                .keyboardShortcut("-", modifiers: .command)
                .accessibilityLabel("Decrease text size")
                .accessibilityHint("Makes the response text smaller")

                Button(action: { viewModel.fontSize += 1 }) {
                    Label("Increase text size", systemImage: "textformat.size.larger")
                }
                .disabled(viewModel.fontSize >= ResponseViewModel.maximumFontSize)
                .keyboardShortcut("+", modifiers: .command)
                .accessibilityLabel("Increase text size")
                .accessibilityHint("Makes the response text larger")

                Button(action: {
                    viewModel.fontSize = ResponseViewModel.defaultFontSize
                }) {
                    Label("Reset Font Size", systemImage: "arrow.counterclockwise")
                }
                .keyboardShortcut("0", modifiers: .command)
                .accessibilityLabel("Reset text size")
                .accessibilityHint("Returns text size to the default")
            }
        }
        // The window uses fullSizeContentView + a transparent titlebar so the
        // themed background can extend edge-to-edge. Without an explicit toolbar
        // background, scrolled chat bubbles render up *through* the transparent
        // titlebar. A visible toolbar background lays a material strip across the
        // titlebar that the content scrolls cleanly beneath (standard macOS
        // behavior, e.g. Mail/Messages).
        .toolbarBackground(.visible, for: .windowToolbar)
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .onDisappear {
            viewModel.cancelOngoingTasks()
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool, duration: Double? = nil) {
        let action = {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }

        guard animated else {
            action()
            return
        }

        if let duration {
            withAnimation(.linear(duration: duration)) {
                action()
            }
        } else {
            withAnimation {
                action()
            }
        }
    }

    private func updateScrollViewportHeight(_ height: CGFloat) {
        guard height.isFinite, abs(scrollViewportHeight - height) > 0.5 else {
            return
        }
        scrollViewportHeight = height
    }

    private func updatePinnedToLatest(bottomOffset: CGFloat) {
        guard scrollViewportHeight > 0, bottomOffset.isFinite else {
            return
        }

        let nextValue = bottomOffset <= scrollViewportHeight + 80
        if isPinnedToLatest != nextValue {
            isPinnedToLatest = nextValue
        }
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty, !viewModel.isProcessing else { return }
        let question = inputText
        inputText = ""
        isRegenerating = true

        viewModel.startFollowUpQuestion(
            question,
            onCompletion: {
                isRegenerating = false
            },
            onFailure: { message in
                errorMessage = message
                showError = true
            }
        )
    }
}

private struct ScrollViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Chat Message View

struct ChatMessageView: View {
    let message: ChatMessage
    let fontSize: CGFloat
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.legibilityWeight) private var legibilityWeight
    @State private var showCopiedFeedback: Bool = false
    /// Container-relative width for a single bubble. Caps at ~82% of the
    /// available width so bubbles use a generous, readable proportion of wide
    /// windows without running fully edge-to-edge.
    @State private var bubbleMaxWidth: CGFloat = 500

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
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { updateBubbleMaxWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        updateBubbleMaxWidth(newWidth)
                    }
            }
        )
        .padding(.top, 4)
        .animation(reduceMotion ? nil : .spring(), value: message.role)
    }
    
    @ViewBuilder
    private func bubbleView(role: String) -> some View {
        VStack(alignment: role == "assistant" ? .leading : .trailing, spacing: 2) {
            Group {
                if !message.content.isEmpty {
                    WidthConstrainedMarkdown(
                        text: message.content.renderableMarkdownForResponse(isStreaming: message.isStreaming && role == "assistant"),
                        fontSize: fontSize,
                        legibilityWeight: legibilityWeight
                    )
                }
            }
            .chatBubbleStyle(isFromUser: message.role == "user", isEmpty: message.isStreaming && message.content.isEmpty)
            .accessibilityLabel(message.role == "user" ? "Your message" : "Assistant's response")
            .accessibilityValue(message.content)
            .contextMenu {
                Button("Copy Message") {
                    copyEntireMessage()
                }
            }
            
            // Timestamp, streaming indicator, and copy button
            HStack(spacing: 8) {
                if message.isStreaming {
                    // Streaming indicator
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Generating...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Generating response")
                } else {
                    Text(message.timestamp.formatted(.dateTime.hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    copyButton
                }
            }
            .padding(.bottom, 2)
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: role == "assistant" ? .leading : .trailing)
    }

    /// Copy-message button. The `.help` tooltip is omitted entirely while the
    /// "Copied" confirmation is showing rather than passing an empty string.
    @ViewBuilder
    private var copyButton: some View {
        let button = Button(action: copyEntireMessage) {
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
        .accessibilityLabel("Copy message")
        .accessibilityHint("Copies this message to the clipboard")

        if showCopiedFeedback {
            button
        } else {
            button.help("Copy Message")
        }
    }

    private func updateBubbleMaxWidth(_ availableWidth: CGFloat) {
        let nextWidth = max(280, availableWidth * 0.82)
        if abs(bubbleMaxWidth - nextWidth) > 0.5 {
            bubbleMaxWidth = nextWidth
        }
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
@Observable
final class ResponseViewModel {

    // UserDefaults key for persistent font size storage
    private static let fontSizeKey = "ResponseView.fontSize"
    static let defaultFontSize: CGFloat = 14
    static let minimumFontSize: CGFloat = 10
    static let maximumFontSize: CGFloat = 20

    private static func clampedFontSize(_ fontSize: CGFloat) -> CGFloat {
        min(max(fontSize, minimumFontSize), maximumFontSize)
    }

    var messages: [ChatMessage] = []
    var fontSize: CGFloat = 14 {
        didSet {
            let clampedFontSize = Self.clampedFontSize(fontSize)
            if fontSize != clampedFontSize {
                fontSize = clampedFontSize
            }
            // Debounce font size saves to prevent race conditions from rapid slider movements
            scheduleFontSizeSave()
        }
    }
    var showCopyConfirmation = false
    var isProcessing = false

    private let content: String
    private let selectedText: String
    private let option: WritingOption?
    private let continuationSystemPrompt: String?
    private let provider: any AIProvider

    // Store conversation history for context
    private var conversationHistory: [(role: String, content: String)] = []

    // Debounce task for font size persistence
    @ObservationIgnored
    private var fontSizeSaveTask: Task<Void, Never>?
    @ObservationIgnored
    private var initialStreamingTask: Task<Void, Never>?
    @ObservationIgnored
    private var followUpStreamingTask: Task<Void, Never>?

    init(
        content: String,
        selectedText: String,
        option: WritingOption?,
        provider: any AIProvider,
        continuationSystemPrompt: String?
    ) {
        // 🔧 Normalize markdown content (strip outer code blocks + normalize LaTeX)
        self.content = content.normalizedForMarkdown()
        self.selectedText = selectedText
        self.option = option
        self.continuationSystemPrompt = continuationSystemPrompt ?? option?.systemPrompt
        self.provider = provider

        // Load saved font size from UserDefaults, or use default
        let savedFontSize = UserDefaults.standard.object(forKey: Self.fontSizeKey) as? CGFloat
        self.fontSize = Self.clampedFontSize(savedFontSize ?? Self.defaultFontSize)

        // Add initial assistant message
        messages.append(ChatMessage(role: "assistant", content: self.content))

        // Initialize conversation history
        if !selectedText.isEmpty {
            conversationHistory.append((role: "user", content: selectedText))
        }
        conversationHistory.append((role: "assistant", content: self.content))
    }

    /// Streaming initializer: opens with an empty streaming message and begins generating immediately.
    init(
        selectedText: String,
        option: WritingOption?,
        provider: any AIProvider,
        systemPrompt: String,
        userPrompt: String,
        images: [Data],
        continuationSystemPrompt: String?
    ) {
        self.content = ""
        self.selectedText = selectedText
        self.option = option
        self.continuationSystemPrompt = continuationSystemPrompt ?? option?.systemPrompt ?? systemPrompt
        self.provider = provider

        let savedFontSize = UserDefaults.standard.object(forKey: Self.fontSizeKey) as? CGFloat
        self.fontSize = Self.clampedFontSize(savedFontSize ?? Self.defaultFontSize)

        // Start with a streaming placeholder
        messages.append(ChatMessage(role: "assistant", content: "", isStreaming: true))
        isProcessing = true

        if !selectedText.isEmpty {
            conversationHistory.append((role: "user", content: selectedText))
        }

        startInitialStreaming(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images
        )
    }

    private func startInitialStreaming(
        systemPrompt: String,
        userPrompt: String,
        images: [Data]
    ) {
        initialStreamingTask?.cancel()
        initialStreamingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.streamInitialResponse(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: images
            )
            self.initialStreamingTask = nil
        }
    }

    func startFollowUpQuestion(
        _ question: String,
        onCompletion: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        followUpStreamingTask?.cancel()
        followUpStreamingTask = Task { @MainActor [weak self] in
            guard let self else {
                onCompletion()
                return
            }

            defer {
                self.followUpStreamingTask = nil
                onCompletion()
            }

            do {
                try await self.processFollowUpQuestion(question)
            } catch is CancellationError {
                return
            } catch {
                onFailure(error.localizedDescription)
            }
        }
    }

    func cancelOngoingTasks() {
        initialStreamingTask?.cancel()
        followUpStreamingTask?.cancel()
        fontSizeSaveTask?.cancel()
        initialStreamingTask = nil
        followUpStreamingTask = nil
        fontSizeSaveTask = nil
        provider.cancel()
        isProcessing = false
    }

    /// Streams the initial AI response into the first message.
    private func streamInitialResponse(systemPrompt: String, userPrompt: String, images: [Data]) async {
        // Track by message ID instead of index to avoid out-of-bounds if array mutates
        guard let messageId = messages.first?.id else { return }

        do {
            var accumulatedContent = ""
            var lastUIFlushTime = ContinuousClock.now
            let minUIFlushInterval: Duration = .milliseconds(80)

            try await provider.processTextStreaming(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: images
            ) { [weak self] chunk in
                guard let self else { return }
                accumulatedContent += chunk
                let now = ContinuousClock.now
                if now - lastUIFlushTime >= minUIFlushInterval {
                    if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[idx].content = accumulatedContent
                    }
                    lastUIFlushTime = now
                }
            }

            let normalizedResponse = accumulatedContent.normalizedForMarkdown()

            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                messages[idx].content = normalizedResponse
                messages[idx].isStreaming = false
            }

            conversationHistory.append((role: "assistant", content: normalizedResponse))
            isProcessing = false
        } catch is CancellationError {
            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                messages[idx].isStreaming = false
            }
            isProcessing = false
        } catch {
            // Show error in the streaming message rather than removing it
            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                messages[idx].content = "Error: \(error.localizedDescription)"
                messages[idx].isStreaming = false
            }
            isProcessing = false
        }
    }

    /// Debounced save of font size to UserDefaults
    private func scheduleFontSizeSave() {
        fontSizeSaveTask?.cancel()
        fontSizeSaveTask = Task { @MainActor [weak self] in
            // Wait 300ms before saving to debounce rapid slider movements
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            UserDefaults.standard.set(self.fontSize, forKey: Self.fontSizeKey)
        }
    }
    
    func processFollowUpQuestion(_ question: String) async throws {
        // Add user message to UI
        messages.append(ChatMessage(role: "user", content: question))
        
        // Add to conversation history
        conversationHistory.append((role: "user", content: question))
        
        isProcessing = true
        
        // Create a placeholder message for streaming, tracked by ID not index
        let streamingMessage = ChatMessage(role: "assistant", content: "", isStreaming: true)
        let messageId = streamingMessage.id
        messages.append(streamingMessage)
        
        do {
            // Build context-aware system prompt
            let systemPrompt = buildSystemPrompt()
            
            // Build user prompt with conversation context
            let userPrompt = buildUserPrompt(question: question)
            
            var accumulatedContent = ""
            var lastUIFlushTime = ContinuousClock.now
            let minUIFlushInterval: Duration = .milliseconds(80)
            
            // Use streaming API
            try await provider.processTextStreaming(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: [] // Follow-up questions don't include images
            ) { [weak self] chunk in
                guard let self else { return }
                accumulatedContent += chunk
                let now = ContinuousClock.now
                if now - lastUIFlushTime >= minUIFlushInterval {
                    // Throttle UI updates while streaming to reduce render pressure.
                    if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                        messages[idx].content = accumulatedContent
                    }
                    lastUIFlushTime = now
                }
            }
            
            // Normalize markdown content (strip outer code blocks + normalize LaTeX)
            let normalizedResponse = accumulatedContent.normalizedForMarkdown()
            
            // Finalize the message
            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                messages[idx].content = normalizedResponse
                messages[idx].isStreaming = false
            }
            
            // Add to conversation history, keeping only the last 20 entries
            // to prevent unbounded memory growth in long conversations
            conversationHistory.append((role: "assistant", content: normalizedResponse))
            if conversationHistory.count > 20 {
                conversationHistory.removeFirst(conversationHistory.count - 20)
            }
            
            // Cap displayed messages to prevent unbounded UI memory growth
            if messages.count > 100 {
                messages.removeFirst(messages.count - 100)
            }
            
            isProcessing = false
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == messageId }) {
                messages[idx].content = "Error: \(error.localizedDescription)"
                messages[idx].isStreaming = false
            }
            isProcessing = false
            throw error
        }
    }
    
    private func buildSystemPrompt() -> String {
        if let continuationSystemPrompt {
            return """
            You are a helpful AI assistant continuing a conversation about text modification.
            
            Original task: \(continuationSystemPrompt)
            
            The user may ask follow-up questions or request modifications. Provide helpful, 
            contextual responses based on the conversation history. Use Markdown formatting 
            where appropriate.
            """
        } else if let option = option {
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

    deinit {
        initialStreamingTask?.cancel()
        followUpStreamingTask?.cancel()
        fontSizeSaveTask?.cancel()
        // Ensure the provider's in-flight request is also cancelled even if
        // onDisappear didn't fire (e.g., parent dismissed the window directly).
        // deinit of a @MainActor class runs on the main actor, but the compiler
        // cannot prove it — use assumeIsolated to bridge the gap.
        MainActor.assumeIsolated {
            provider.cancel()
        }
    }
}

// MARK: - Width-Constrained Markdown Wrapper

/// Reads the available width via `GeometryReader` and proposes it as an
/// explicit constraint to `RichMarkdownView`, so that the MarkdownView
/// library's internal `FlowLayout` / `ViewThatFits` logic receives a
/// concrete container width and can wrap or scroll LaTeX images properly.
private struct WidthConstrainedMarkdown: View {
    let text: String
    let fontSize: CGFloat
    let legibilityWeight: LegibilityWeight?

    @State private var contentHeight: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            RichMarkdownView(text: text, fontSize: fontSize, legibilityWeight: legibilityWeight)
                .frame(width: max(geo.size.width, 1), alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .background(
                    GeometryReader { inner in
                        Color.clear
                            .preference(key: ContentHeightKey.self, value: inner.size.height)
                    }
                )
        }
        .frame(height: max(contentHeight, 1), alignment: .topLeading)
        .clipped()
        .onPreferenceChange(ContentHeightKey.self) { height in
            updateContentHeight(height)
        }
    }

    private func updateContentHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0, abs(contentHeight - height) > 0.5 else {
            return
        }
        contentHeight = height
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Rich Markdown View

struct RichMarkdownView: View {
    let text: String
    let fontSize: CGFloat
    let legibilityWeight: LegibilityWeight?

    private var bodyWeight: Font.Weight {
        legibilityWeight == .bold ? .semibold : .regular
    }

    private var supportingWeight: Font.Weight {
        legibilityWeight == .bold ? .bold : .semibold
    }

    var body: some View {
        MarkdownView(text)
            .markdownMathRenderingEnabled()
            // Body text (paragraphs, list items, etc.)
            .font(.system(size: fontSize, weight: bodyWeight), for: .body)
            // Headings - scaled relative to base font size
            .font(.system(size: fontSize * 1.4, weight: .bold), for: .h1)
            .font(.system(size: fontSize * 1.25, weight: .bold), for: .h2)
            .font(.system(size: fontSize * 1.15, weight: .semibold), for: .h3)
            .font(.system(size: fontSize * 1.1, weight: .semibold), for: .h4)
            .font(.system(size: fontSize * 1.05, weight: .medium), for: .h5)
            .font(.system(size: fontSize, weight: .medium), for: .h6)
            // Code blocks
            .font(.system(size: fontSize, weight: bodyWeight, design: .monospaced), for: .codeBlock)
            // Block quotes
            .font(.system(size: fontSize, weight: bodyWeight), for: .blockQuote)
            // Tables
            .font(.system(size: fontSize, weight: supportingWeight), for: .tableHeader)
            .font(.system(size: fontSize, weight: bodyWeight), for: .tableBody)
            // Math
            .font(.system(size: fontSize, weight: bodyWeight), for: .inlineMath)
            .font(.system(size: fontSize + 2, weight: bodyWeight), for: .displayMath)
            // Tint for inline code
            .tint(.primary, for: .inlineCodeBlock)
    }
}
