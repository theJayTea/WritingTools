import SwiftUI
import Observation

@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    var geminiProvider: GeminiProvider
    var openAIProvider: OpenAIProvider
    var mistralProvider: MistralProvider
    var anthropicProvider: AnthropicProvider
    var ollamaProvider: OllamaProvider
    var localLLMProvider: LocalModelProvider
    var openRouterProvider: OpenRouterProvider

    var customInstruction: String = ""
    var selectedText: String = ""
    var isPopupVisible: Bool = false
    var isProcessing: Bool = false
    var previousApplication: NSRunningApplication?
    var selectedImages: [Data] = []

    // Command management
    var commandManager = CommandManager()
    var customCommandsManager = CustomCommandsManager()

    // Current provider with UI binding support
    private(set) var currentProvider: String

    var selectedAttributedText: NSAttributedString? = nil

    var activeProvider: any AIProvider {
        switch currentProvider {
        case "openai":
            return openAIProvider
        case "gemini":
            return geminiProvider
        case "anthropic":
            return anthropicProvider
        case "ollama":
            return ollamaProvider
        case "mistral":
            return mistralProvider
        case "openrouter":
            return openRouterProvider
        default:
            return localLLMProvider
        }
    }

    // MARK: - Per-Command Provider Selection

    /// Get the appropriate provider for a command, respecting per-command overrides
    func getProvider(for command: CommandModel) -> any AIProvider {
        let providerName = command.providerOverride ?? currentProvider

        NSLog("AppState.getProvider: command=\(command.name), providerOverride=\(command.providerOverride ?? "nil"), providerName=\(providerName)")

        // Handle custom provider
        if providerName == "custom" {
            NSLog("AppState.getProvider: Custom provider selected")
            if let baseURL = command.customProviderBaseURL,
               let apiKey = command.customProviderApiKey,
               let model = command.customProviderModel {
                NSLog("AppState.getProvider: Creating CustomProvider with baseURL=\(baseURL), model=\(model)")
                let config = CustomProviderConfig(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: model
                )
                return CustomProvider(config: config)
            } else {
                NSLog("AppState.getProvider: Custom provider config incomplete - baseURL=\(command.customProviderBaseURL ?? "nil"), apiKey=\(command.customProviderApiKey != nil ? "set" : "nil"), model=\(command.customProviderModel ?? "nil")")
            }
            // Fallback to active provider if custom config is incomplete
            return activeProvider
        }

        // If there's a model override, create a temporary provider instance with that model
        if let modelOverride = command.modelOverride {
            return createProviderWithModel(providerName: providerName, model: modelOverride)
        }

        // Otherwise use the default provider instance
        switch providerName {
        case "openai":
            return openAIProvider
        case "gemini":
            return geminiProvider
        case "anthropic":
            return anthropicProvider
        case "ollama":
            return ollamaProvider
        case "mistral":
            return mistralProvider
        case "openrouter":
            return openRouterProvider
        case "local":
            return localLLMProvider
        default:
            return activeProvider
        }
    }

    /// Create a provider instance with a specific model override
    private func createProviderWithModel(providerName: String, model: String) -> any AIProvider {
        let asettings = AppSettings.shared

        switch providerName {
        case "openai":
            let config = OpenAIConfig(
                apiKey: asettings.openAIApiKey,
                baseURL: asettings.openAIBaseURL,
                model: model
            )
            return OpenAIProvider(config: config)

        case "gemini":
            let config = GeminiConfig(
                apiKey: asettings.geminiApiKey,
                modelName: model
            )
            return GeminiProvider(config: config)

        case "anthropic":
            let config = AnthropicConfig(
                apiKey: asettings.anthropicApiKey,
                model: model
            )
            return AnthropicProvider(config: config)

        case "ollama":
            let config = OllamaConfig(
                baseURL: asettings.ollamaBaseURL,
                model: model,
                keepAlive: asettings.ollamaKeepAlive
            )
            return OllamaProvider(config: config)

        case "mistral":
            let config = MistralConfig(
                apiKey: asettings.mistralApiKey,
                baseURL: asettings.mistralBaseURL,
                model: model
            )
            return MistralProvider(config: config)

        case "openrouter":
            let config = OpenRouterConfig(
                apiKey: asettings.openRouterApiKey,
                model: model
            )
            return OpenRouterProvider(config: config)

        case "local":
            return localLLMProvider

        default:
            return activeProvider
        }
    }

    private init() {
        // Read from AppSettings
        let asettings = AppSettings.shared
        self.currentProvider = asettings.currentProvider

        // Initialize Gemini with custom model support
        let geminiModelEnum = asettings.geminiModel
        let geminiModelName = (geminiModelEnum == .custom)
        ? asettings.geminiCustomModel
        : geminiModelEnum.rawValue
        let geminiConfig = GeminiConfig(
            apiKey: asettings.geminiApiKey,
            modelName: geminiModelName
        )
        self.geminiProvider = GeminiProvider(config: geminiConfig)

        // Initialize OpenAI
        let openAIConfig = OpenAIConfig(
            apiKey: asettings.openAIApiKey,
            baseURL: asettings.openAIBaseURL,
            model: asettings.openAIModel
        )
        self.openAIProvider = OpenAIProvider(config: openAIConfig)

        // Initialize Mistral
        let mistralConfig = MistralConfig(
            apiKey: asettings.mistralApiKey,
            baseURL: asettings.mistralBaseURL,
            model: asettings.mistralModel
        )
        self.mistralProvider = MistralProvider(config: mistralConfig)

        self.localLLMProvider = LocalModelProvider()

        // Initialize Anthropic
        let anthropicConfig = AnthropicConfig(
            apiKey: asettings.anthropicApiKey,
            model: asettings.anthropicModel
        )
        self.anthropicProvider = AnthropicProvider(config: anthropicConfig)

        // Initialize OllamaProvider with its settings.
        let ollamaConfig = OllamaConfig(
            baseURL: asettings.ollamaBaseURL,
            model: asettings.ollamaModel,
            keepAlive: asettings.ollamaKeepAlive
        )
        self.ollamaProvider = OllamaProvider(config: ollamaConfig)

        // Initialize OpenRouter
        let openRouterModelEnum = OpenRouterModel(rawValue: asettings.openRouterModel) ?? .gpt4o
        let openRouterModelName = (openRouterModelEnum == .custom)
            ? asettings.openRouterCustomModel
            : openRouterModelEnum.rawValue
        let openRouterConfig = OpenRouterConfig(
            apiKey: asettings.openRouterApiKey,
            model: openRouterModelName
        )
        self.openRouterProvider = OpenRouterProvider(config: openRouterConfig)

        if asettings.openAIApiKey.isEmpty &&
            asettings.geminiApiKey.isEmpty &&
            asettings.mistralApiKey.isEmpty &&
            asettings.openRouterApiKey.isEmpty &&
            asettings.anthropicApiKey.isEmpty {
            print("Warning: No API keys configured.")
        }

        // Perform migration from old system to new CommandManager if needed
        MigrationHelper.shared.migrateIfNeeded(
            commandManager: commandManager,
            customCommandsManager: customCommandsManager
        )
    }

    // For Gemini changes
    func saveGeminiConfig(apiKey: String, model: GeminiModel, customModelName: String? = nil) {
        AppSettings.shared.geminiApiKey = apiKey
        AppSettings.shared.geminiModel = model
        if model == .custom, let custom = customModelName {
            AppSettings.shared.geminiCustomModel = custom
        }

        let modelName = (model == .custom) ? (customModelName ?? "") : model.rawValue
        let config = GeminiConfig(apiKey: apiKey, modelName: modelName)
        geminiProvider = GeminiProvider(config: config)
    }

    // For OpenAI changes
    func saveOpenAIConfig(apiKey: String, baseURL: String, organization: String?, project: String?, model: String) {
        let asettings = AppSettings.shared
        asettings.openAIApiKey = apiKey
        asettings.openAIBaseURL = baseURL
        asettings.openAIOrganization = organization
        asettings.openAIProject = project
        asettings.openAIModel = model

        let config = OpenAIConfig(apiKey: apiKey, baseURL: baseURL, model: model)
        openAIProvider = OpenAIProvider(config: config)
    }

    // Update provider and persist to settings
    func setCurrentProvider(_ provider: String) {
        currentProvider = provider
        AppSettings.shared.currentProvider = provider
    }

    func saveMistralConfig(apiKey: String, baseURL: String, model: String) {
        let asettings = AppSettings.shared
        asettings.mistralApiKey = apiKey
        asettings.mistralBaseURL = baseURL
        asettings.mistralModel = model

        let config = MistralConfig(
            apiKey: apiKey,
            baseURL: baseURL,
            model: model
        )
        mistralProvider = MistralProvider(config: config)
    }

    // For Anthropic changes
    func saveAnthropicConfig(apiKey: String, model: String) {
        let asettings = AppSettings.shared
        asettings.anthropicApiKey = apiKey
        asettings.anthropicModel = model

        let config = AnthropicConfig(apiKey: apiKey, model: model)
        anthropicProvider = AnthropicProvider(config: config)
        print("AppState: Anthropic config saved and provider updated.")
    }

    // For updating Ollama settings
    func saveOllamaConfig(baseURL: String, model: String, keepAlive: String) {
        let asettings = AppSettings.shared
        asettings.ollamaBaseURL = baseURL
        asettings.ollamaModel = model
        asettings.ollamaKeepAlive = keepAlive

        let config = OllamaConfig(baseURL: baseURL, model: model, keepAlive: keepAlive)
        ollamaProvider = OllamaProvider(config: config)
    }

    // For updating OpenRouter settings
    func saveOpenRouterConfig(apiKey: String, model: OpenRouterModel, customModelName: String? = nil) {
        AppSettings.shared.openRouterApiKey = apiKey
        AppSettings.shared.openRouterModel = model.rawValue
        if model == .custom, let custom = customModelName {
            AppSettings.shared.openRouterCustomModel = custom
        }
        let modelName = (model == .custom) ? (customModelName ?? "") : model.rawValue
        let config = OpenRouterConfig(apiKey: apiKey, model: modelName)
        openRouterProvider = OpenRouterProvider(config: config)
    }


    // Process a command (unified method for all command types)
    func processCommand(_ command: CommandModel) {
        guard !selectedText.isEmpty else { return }

        isProcessing = true

        Task {
            do {
                let prompt = command.prompt

                // Get the appropriate provider for this command (respects per-command overrides)
                let provider = getProvider(for: command)

                var result = try await provider.processText(
                    systemPrompt: prompt,
                    userPrompt: selectedText,
                    images: [],
                    streaming: false
                )

                // Preserve trailing newlines from the original selection
                // This is important for triple-click selections which include the trailing newline
                if selectedText.hasSuffix("\n") && !result.hasSuffix("\n") {
                    result += "\n"
                    NSLog("Added trailing newline to match input")
                }

                if command.useResponseWindow {
                    let window = ResponseWindow(
                        title: "\(command.name) Result",
                        content: result,
                        selectedText: selectedText,
                        option: nil,
                        provider: provider
                    )

                    WindowManager.shared.addResponseWindow(window)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                } else {
                    if command.preserveFormatting, selectedAttributedText != nil {
                        replaceSelectedTextPreservingAttributes(with: result)
                    } else {
                        replaceSelectedText(with: result)
                    }
                }
            } catch {
                NSLog("Error processing command: \(error)")
            }

            isProcessing = false
        }
    }

    // MARK: - Fixed: Proper Window Activation Verification

    func replaceSelectedText(with newText: String) {
        // Take a snapshot of the current clipboard BEFORE we overwrite it
        let clipboardSnapshot = NSPasteboard.general.createSnapshot()

        // Set the new text on the clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)

        // Reactivate previous application
        if let previousApp = previousApplication {
            previousApp.activate()

            // Wait for window activation, paste, then restore clipboard
            activateWindowAndPaste(for: previousApp, clipboardSnapshot: clipboardSnapshot)
        }
    }

    private func activateWindowAndPaste(for app: NSRunningApplication, clipboardSnapshot: ClipboardSnapshot) {
        var attempts = 0
        let maxAttempts = 100 // ~1 second with 10ms intervals

        let timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] timer in
            attempts += 1

            // Check if target app is now frontmost or max attempts reached
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app.bundleIdentifier
                || attempts >= maxAttempts {
                timer.invalidate()
                Task { @MainActor in
                    // Perform the paste
                    self?.simulatePaste()

                    // Wait a moment for the paste to complete, then restore the clipboard
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                    // Restore the original clipboard content
                    NSPasteboard.general.restore(snapshot: clipboardSnapshot)
                    NSLog("Clipboard restored after paste")
                }
            }
        }

        // Safety: invalidate timer after 2 seconds regardless
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            timer.invalidate()
        }
    }

    func replaceSelectedTextPreservingAttributes(with corrected: String) {
        guard let original = selectedAttributedText else {
            replaceSelectedText(with: corrected)
            return
        }

        // Take a snapshot of the current clipboard BEFORE we overwrite it
        let clipboardSnapshot = NSPasteboard.general.createSnapshot()

        let mutable = NSMutableAttributedString(attributedString: original)
        mutable.applyCharacterDiff(from: original.string, to: corrected)

        let pb = NSPasteboard.general
        pb.clearContents()

        // Prefer HTML for web editors (e.g., Gmail in browsers), then RTF, always include plain text
        let fullRange = NSRange(location: 0, length: mutable.length)
        let htmlData = try? mutable.data(
            from: fullRange,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
            ]
        )
        let rtfData = try? mutable.data(
            from: fullRange,
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.rtf,
            ]
        )

        // Declare available types in priority order
        var types: [NSPasteboard.PasteboardType] = []
        if htmlData != nil { types.append(.html) }
        if rtfData != nil { types.append(.rtf) }
        types.append(.string)

        pb.declareTypes(types, owner: nil)

        if let htmlData {
            pb.setData(htmlData, forType: .html)
        }
        if let rtfData {
            pb.setData(rtfData, forType: .rtf)
        }
        pb.setString(corrected, forType: .string)

        if let previous = previousApplication {
            previous.activate()
            activateWindowAndPaste(for: previous, clipboardSnapshot: clipboardSnapshot)
        }
    }

    // MARK: - Fixed: Use cgSessionEventTap for Reliable Event Ordering

    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            NSLog("Failed to create CGEventSource")
            return
        }

        // Create Command + V key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) else {
            NSLog("Failed to create key down event")
            return
        }
        keyDown.flags = .maskCommand

        // Create Command + V key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            NSLog("Failed to create key up event")
            return
        }
        keyUp.flags = .maskCommand

        // Post to cgSessionEventTap for more predictable ordering
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}

extension NSMutableAttributedString {
    /// Transforms *self* so that `self.string == new`, preserving
    /// per-character attributes wherever possible.
    func applyCharacterDiff(from old: String, to new: String) {
        // Build the diff
        let diff = Array(new).difference(from: Array(old))

        // Collect removals & insertions with their offsets
        var removals: [Int] = []
        var insertions: [(offset: Int, char: Character)] = []

        for change in diff {
            switch change {
            case let .remove(offset, _, _):
                removals.append(offset)
            case let .insert(offset, element, _):
                insertions.append((offset, element))
            }
        }

        // Apply removals back-to-front
        for index in removals.sorted(by: >) {
            deleteCharacters(in: NSRange(location: index, length: 1))
        }

        // Apply insertions front-to-back
        for (index, ch) in insertions.sorted(by: { $0.offset < $1.offset }) {
            let inherited = index > 0
                ? attributes(at: index - 1, effectiveRange: nil)
                : [:]
            let piece = NSAttributedString(string: String(ch), attributes: inherited)
            insert(piece, at: index)
        }
    }
}
