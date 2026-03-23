import SwiftUI
import Observation
import UniformTypeIdentifiers
import CryptoKit

private let logger = AppLogger.logger("AppState")

enum CommandInputMode: Sendable, Equatable {
    case textOnly
    case textOrImagesWithOCRFallback
}

struct CommandExecutionInput: Sendable {
    enum Source: Sendable, Equatable {
        case selectedText
        case imageOCRFallback
    }

    let userPrompt: String
    let images: [Data]
    let source: Source
}

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

    // Cache for providers with model overrides to prevent memory leaks
    // Key: "providerName:model" -> Provider instance
    @ObservationIgnored
    private var modelOverrideProviderCache: [String: any AIProvider] = [:]
    @ObservationIgnored
    private var cacheInsertionOrder: [String] = []
    private let maxCacheSize = 10
    @ObservationIgnored
    private var apiKeyChangeObserver: NSObjectProtocol?

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

        logger.debug("AppState.getProvider: command=\(command.name), providerOverride=\(command.providerOverride ?? "nil"), providerName=\(providerName)")

        // Handle custom provider
        if providerName == "custom" {
            logger.debug("AppState.getProvider: Custom provider selected")
            let baseURL = command.customProviderBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let apiKey =
                KeychainManager.shared.retrieveCustomProviderApiKeySync(for: command.id)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let model = command.customProviderModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if baseURL.isEmpty || apiKey.isEmpty || model.isEmpty {
                logger.warning(
                    """
                    AppState.getProvider: Custom provider config incomplete - baseURL=\(baseURL.isEmpty ? "empty" : "set"), \
                    apiKey=\(apiKey.isEmpty ? "empty" : "set"), model=\(model.isEmpty ? "empty" : "set")
                    """
                )
            }

            let config = CustomProviderConfig(
                baseURL: baseURL,
                apiKey: apiKey,
                model: model
            )
            return CustomProvider(config: config)
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

    /// Create or retrieve a cached provider instance with a specific model override
    private func createProviderWithModel(providerName: String, model: String) -> any AIProvider {
        let apiKey = Self.currentAPIKey(for: providerName)
        let baseURL = Self.currentBaseURL(for: providerName)
        let keyHash = apiKey.isEmpty ? "" : String(SHA256.hash(data: Data(apiKey.utf8)).description.prefix(8))
        let urlHash = baseURL.isEmpty ? "" : String(SHA256.hash(data: Data(baseURL.utf8)).description.prefix(8))
        let cacheKey = "\(providerName):\(model):\(keyHash):\(urlHash)"

        // Return cached provider if available and mark it as recently used.
        if let cached = modelOverrideProviderCache[cacheKey] {
            touchProviderCacheKey(cacheKey)
            return cached
        }

        let asettings = AppSettings.shared
        let provider: any AIProvider

        switch providerName {
        case "openai":
            let config = OpenAIConfig(
                apiKey: asettings.openAIApiKey,
                baseURL: asettings.openAIBaseURL,
                model: model,
                forceStreaming: asettings.openAIForceStreaming
            )
            provider = OpenAIProvider(config: config)

        case "gemini":
            let config = GeminiConfig(
                apiKey: asettings.geminiApiKey,
                modelName: model
            )
            provider = GeminiProvider(config: config)

        case "anthropic":
            let config = AnthropicConfig(
                apiKey: asettings.anthropicApiKey,
                model: model
            )
            provider = AnthropicProvider(config: config)

        case "ollama":
            let config = OllamaConfig(
                baseURL: asettings.ollamaBaseURL,
                model: model,
                keepAlive: asettings.ollamaKeepAlive
            )
            provider = OllamaProvider(config: config)

        case "mistral":
            let config = MistralConfig(
                apiKey: asettings.mistralApiKey,
                baseURL: asettings.mistralBaseURL,
                model: model
            )
            provider = MistralProvider(config: config)

        case "openrouter":
            let config = OpenRouterConfig(
                apiKey: asettings.openRouterApiKey,
                model: model
            )
            provider = OpenRouterProvider(config: config)

        case "local":
            return localLLMProvider

        default:
            return activeProvider
        }

        // Evict least recently used entry if cache is full.
        if modelOverrideProviderCache.count >= maxCacheSize,
           !cacheInsertionOrder.isEmpty {
            let oldest = cacheInsertionOrder.removeFirst()
            if let evicted = modelOverrideProviderCache.removeValue(forKey: oldest) {
                evicted.cancel()
            }
        }

        // Cache the new provider
        modelOverrideProviderCache[cacheKey] = provider
        touchProviderCacheKey(cacheKey)
        return provider
    }

    private func touchProviderCacheKey(_ key: String) {
        if let existingIndex = cacheInsertionOrder.firstIndex(of: key) {
            cacheInsertionOrder.remove(at: existingIndex)
        }
        cacheInsertionOrder.append(key)
    }

    /// Clear the model override provider cache (call when settings change)
    func clearProviderCache() {
        modelOverrideProviderCache.removeAll()
        cacheInsertionOrder.removeAll()
    }

    /// Returns the current API key for the given provider name (used for cache key hashing).
    private static func currentAPIKey(for providerName: String) -> String {
        let s = AppSettings.shared
        switch providerName {
        case "openai":    return s.openAIApiKey
        case "gemini":    return s.geminiApiKey
        case "anthropic": return s.anthropicApiKey
        case "mistral":   return s.mistralApiKey
        case "openrouter": return s.openRouterApiKey
        default:          return ""
        }
    }

    /// Returns the current base URL for providers that support custom endpoints (used for cache key hashing).
    private static func currentBaseURL(for providerName: String) -> String {
        let s = AppSettings.shared
        switch providerName {
        case "openai":  return s.openAIBaseURL
        case "mistral": return s.mistralBaseURL
        case "ollama":  return s.ollamaBaseURL
        default:        return ""
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
            model: asettings.openAIModel,
            forceStreaming: asettings.openAIForceStreaming
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
        let openRouterModelEnum = OpenRouterModel(rawValue: asettings.openRouterModel)
        let openRouterModelName = (openRouterModelEnum == .custom)
            ? asettings.openRouterCustomModel
            : openRouterModelEnum?.rawValue ?? asettings.openRouterModel
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
            logger.warning("No API keys configured.")
        }

        // Perform migration from old system to new CommandManager if needed
        MigrationHelper.shared.migrateIfNeeded(
            commandManager: commandManager,
            customCommandsManager: customCommandsManager
        )

        // Invalidate cached providers when API keys change so stale keys aren't reused
        apiKeyChangeObserver = NotificationCenter.default.addObserver(
            forName: .apiKeyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearProviderCache()
            }
        }
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
        clearProviderCache()
    }

    // For OpenAI changes
    func saveOpenAIConfig(apiKey: String, baseURL: String, organization: String?, project: String?, model: String) {
        let asettings = AppSettings.shared
        asettings.openAIApiKey = apiKey
        asettings.openAIBaseURL = baseURL
        asettings.openAIOrganization = organization
        asettings.openAIProject = project
        asettings.openAIModel = model

        let config = OpenAIConfig(apiKey: apiKey, baseURL: baseURL, model: model, forceStreaming: asettings.openAIForceStreaming)
        openAIProvider = OpenAIProvider(config: config)
        clearProviderCache()
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
        clearProviderCache()
    }

    // For Anthropic changes
    func saveAnthropicConfig(apiKey: String, model: String) {
        let asettings = AppSettings.shared
        asettings.anthropicApiKey = apiKey
        asettings.anthropicModel = model

        let config = AnthropicConfig(apiKey: apiKey, model: model)
        anthropicProvider = AnthropicProvider(config: config)
        clearProviderCache()
        logger.debug("Anthropic config saved and provider updated.")
    }

    // For updating Ollama settings
    func saveOllamaConfig(baseURL: String, model: String, keepAlive: String) {
        let asettings = AppSettings.shared
        asettings.ollamaBaseURL = baseURL
        asettings.ollamaModel = model
        asettings.ollamaKeepAlive = keepAlive

        let config = OllamaConfig(baseURL: baseURL, model: model, keepAlive: keepAlive)
        ollamaProvider = OllamaProvider(config: config)
        clearProviderCache()
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
        clearProviderCache()
    }

    /// Saves provider settings based on the currently selected provider
    /// This is a unified method to reduce code duplication between OnboardingView and SettingsView
    func saveCurrentProviderSettings() {
        let settings = AppSettings.shared

        switch settings.currentProvider {
        case "gemini":
            saveGeminiConfig(
                apiKey: settings.geminiApiKey,
                model: settings.geminiModel,
                customModelName: settings.geminiCustomModel
            )
        case "mistral":
            saveMistralConfig(
                apiKey: settings.mistralApiKey,
                baseURL: settings.mistralBaseURL,
                model: settings.mistralModel
            )
        case "openai":
            saveOpenAIConfig(
                apiKey: settings.openAIApiKey,
                baseURL: settings.openAIBaseURL,
                organization: settings.openAIOrganization,
                project: settings.openAIProject,
                model: settings.openAIModel
            )
        case "anthropic":
            saveAnthropicConfig(
                apiKey: settings.anthropicApiKey,
                model: settings.anthropicModel
            )
        case "openrouter":
            saveOpenRouterConfig(
                apiKey: settings.openRouterApiKey,
                model: OpenRouterModel(rawValue: settings.openRouterModel) ?? .kimi,
                customModelName: settings.openRouterCustomModel
            )
        case "ollama":
            saveOllamaConfig(
                baseURL: settings.ollamaBaseURL,
                model: settings.ollamaModel,
                keepAlive: settings.ollamaKeepAlive
            )
            UserDefaults.standard.set(settings.ollamaImageMode.rawValue, forKey: "ollama_image_mode")
        default:
            break
        }

        setCurrentProvider(settings.currentProvider)
    }

    func resolveCommandInput(
        mode: CommandInputMode = .textOrImagesWithOCRFallback
    ) async throws -> CommandExecutionInput {
        let trimmedSelectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSelectedText.isEmpty {
            return CommandExecutionInput(
                userPrompt: selectedText,
                images: selectedImages,
                source: .selectedText
            )
        }

        guard !selectedImages.isEmpty else {
            throw NSError(
                domain: "CommandInput",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Select text or images before running a command."]
            )
        }

        guard mode == .textOrImagesWithOCRFallback else {
            throw NSError(
                domain: "CommandInput",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "This command requires selected text."]
            )
        }

        let ocrText = try await OCRManager.shared
            .extractText(from: selectedImages)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !ocrText.isEmpty else {
            throw NSError(
                domain: "CommandInput",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Image-only selection is not supported without readable OCR text. Select text, or use images that contain readable text."]
            )
        }

        let ocrPrompt = """
        The user selected image content without selectable text.
        Use the extracted OCR text below to complete the request.

        \(ocrText)
        """

        return CommandExecutionInput(
            userPrompt: ocrPrompt,
            images: [],
            source: .imageOCRFallback
        )
    }

    // MARK: - Fixed: Proper Window Activation Verification

    func replaceSelectedText(with newText: String) {
        // Take a snapshot of the current clipboard BEFORE we overwrite it
        let clipboardSnapshot = NSPasteboard.general.createSnapshot()

        // Set the new text on the clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: [])
        pasteboard.writeObjects([newText as NSString])

        // Reactivate previous application using cooperative activation
        if let previousApp = previousApplication {
            NSApp.yieldActivation(to: previousApp)
            let didActivate = previousApp.activate(from: .current, options: [.activateAllWindows])
            if !didActivate {
                logger.warning("Failed to activate previous app: \(previousApp.bundleIdentifier ?? "unknown")")
            }

            // Wait for window activation, paste, then restore clipboard
            // Capture the changeCount after we wrote text so we can detect external changes
            let changeCountAfterWrite = NSPasteboard.general.changeCount
            activateWindowAndPaste(for: previousApp, clipboardSnapshot: clipboardSnapshot, expectedChangeCount: changeCountAfterWrite)
        }
    }

    private func activateWindowAndPaste(for app: NSRunningApplication, clipboardSnapshot: ClipboardSnapshot, expectedChangeCount: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            // If the target app is already frontmost, paste immediately.
            // Otherwise, wait for NSWorkspace activation notification with a timeout.
            let alreadyFrontmost =
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app.bundleIdentifier

            if !alreadyFrontmost {
                let activated = await self.waitForAppActivation(app, timeout: .seconds(2))
                if !activated {
                    logger.warning("Timeout reached without target app becoming frontmost. Text left on clipboard for manual paste.")
                    self.showPasteTimeoutAlert(targetApp: app)
                    return  // Don't restore clipboard — user needs text for manual paste
                }
            }

            // Perform the paste
            self.simulatePaste()

            // Wait for the paste to complete before restoring the clipboard.
            // There is no cross-process API to detect when a paste finishes, so we
            // use a conservative fixed delay. 500ms accommodates slower apps
            // (e.g. Electron, heavy IDEs) better than the previous 250ms while
            // still feeling responsive.  If this task is cancelled (e.g. the user
            // triggers another action) we skip the restore entirely so we don't
            // clobber the new clipboard content.
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                logger.debug("Paste delay interrupted: \(error.localizedDescription)")
                return  // Don't restore — cancellation means the flow was superseded
            }

            // Restore the original clipboard content, but only if no external
            // app has modified the clipboard since we wrote our text to it
            let restoreOutcome = NSPasteboard.general.restoreIfUnchanged(
                snapshot: clipboardSnapshot,
                expectedChangeCount: expectedChangeCount
            )
            switch restoreOutcome {
            case .restored:
                logger.debug("Clipboard restored after paste")
            case .skippedExternalChange(let expected, let actual):
                logger.warning("Clipboard restore skipped after paste due to external change (expected \(expected), actual \(actual))")
                self.showClipboardRestoreSkippedAlert(
                    targetApp: app,
                    expectedChangeCount: expected,
                    actualChangeCount: actual
                )
            case .failedWrite:
                logger.error("Clipboard restore failed after paste")
                self.showClipboardRestoreFailedAlert(targetApp: app)
            }
        }
    }

    /// Waits for the given application to become frontmost using
    /// `NSWorkspace.didActivateApplicationNotification`, with a timeout fallback.
    /// Returns `true` if the app became frontmost, `false` on timeout.
    private func waitForAppActivation(_ app: NSRunningApplication, timeout: Duration) async -> Bool {
        // Check immediately in case it already activated between our yield and this call
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == app.bundleIdentifier {
            return true
        }

        // Both closures below run on the main queue/actor, so shared
        // mutable state is safe. Use a small class box to satisfy Sendable.
        final class ActivationState: @unchecked Sendable {
            var observer: NSObjectProtocol?
            var timeoutTask: Task<Void, Never>?
            var resumed = false
        }
        let state = ActivationState()

        return await withCheckedContinuation { continuation in
            state.observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { note in
                guard let activatedApp = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      activatedApp.bundleIdentifier == app.bundleIdentifier else {
                    return
                }
                guard !state.resumed else { return }
                state.resumed = true
                state.timeoutTask?.cancel()
                if let obs = state.observer { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
                continuation.resume(returning: true)
            }

            state.timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !state.resumed else { return }
                state.resumed = true
                if let obs = state.observer { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
                continuation.resume(returning: false)
            }
        }
    }

    func replaceSelectedTextPreservingAttributes(with corrected: String) {
        guard let original = selectedAttributedText else {
            replaceSelectedText(with: corrected)
            return
        }

        if original.containsTextAttachments {
            logger.warning("Attributed selection contains attachments; falling back to plain-text replacement")
            replaceSelectedText(with: corrected)
            return
        }

        // Take a snapshot of the current clipboard BEFORE we overwrite it
        let clipboardSnapshot = NSPasteboard.general.createSnapshot()

        let mutable = NSMutableAttributedString(attributedString: original)
        let didApplyDiff = mutable.applyCharacterDiff(from: original.string, to: corrected)
        if !didApplyDiff {
            logger.warning("Failed to apply UTF-16-safe diff; falling back to plain-text replacement")
            replaceSelectedText(with: corrected)
            return
        }

        let pb = NSPasteboard.general
        pb.prepareForNewContents(with: [])

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

        let item = NSPasteboardItem()

        if let htmlData {
            let htmlType = NSPasteboard.PasteboardType(UTType.html.identifier)
            item.setData(htmlData, forType: htmlType)
        }
        if let rtfData {
            let rtfType = NSPasteboard.PasteboardType(UTType.rtf.identifier)
            item.setData(rtfData, forType: rtfType)
        }
        item.setString(corrected, forType: .string)

        pb.writeObjects([item])

        if let previous = previousApplication {
            NSApp.yieldActivation(to: previous)
            let didActivate = previous.activate(from: .current, options: [.activateAllWindows])
            if !didActivate {
                logger.warning("Failed to activate previous app: \(previous.bundleIdentifier ?? "unknown")")
            }
            let changeCountAfterWrite = NSPasteboard.general.changeCount
            activateWindowAndPaste(for: previous, clipboardSnapshot: clipboardSnapshot, expectedChangeCount: changeCountAfterWrite)
        }
    }

    // MARK: - Fixed: Use cgSessionEventTap for Reliable Event Ordering

    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("Failed to create CGEventSource")
            return
        }

        // Create Command + V key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) else {
            logger.error("Failed to create key down event")
            return
        }
        keyDown.flags = .maskCommand

        // Create Command + V key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            logger.error("Failed to create key up event")
            return
        }
        keyUp.flags = .maskCommand

        // Post to cgSessionEventTap for more predictable ordering
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    private func showPasteTimeoutAlert(targetApp: NSRunningApplication) {
        let alert = NSAlert()
        alert.messageText = "Paste Could Not Complete"
        let appName = targetApp.localizedName ?? targetApp.bundleIdentifier ?? "the target app"
        alert.informativeText =
            "Writing Tools couldn't paste into \(appName) because it didn't become active in time. The processed text is still on your clipboard — you can paste it manually with ⌘V."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        NSApp.activate()
        if let keyWindow = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWindow)
        } else {
            alert.runModal()
        }
    }

    private func showClipboardRestoreFailedAlert(targetApp: NSRunningApplication) {
        let alert = NSAlert()
        alert.messageText = "Clipboard Restore Failed"
        let bundleId = targetApp.bundleIdentifier ?? "unknown app"
        alert.informativeText =
            "Writing Tools couldn't restore your clipboard after pasting into \(bundleId). You may need to re-copy your previous clipboard contents."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        NSApp.activate()
        if let keyWindow = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWindow)
        } else {
            alert.runModal()
        }
    }

    private func showClipboardRestoreSkippedAlert(
        targetApp: NSRunningApplication,
        expectedChangeCount: Int,
        actualChangeCount: Int
    ) {
        let alert = NSAlert()
        alert.messageText = "Clipboard Was Updated by Another App"
        let appName = targetApp.localizedName ?? targetApp.bundleIdentifier ?? "the target app"
        logger.info("Clipboard restore skipped: expected change count \(expectedChangeCount), actual \(actualChangeCount)")
        alert.informativeText =
            """
            Writing Tools pasted into \(appName), but your clipboard changed before restoration.
            Your clipboard was intentionally left unchanged to avoid overwriting newer content.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        NSApp.activate()
        if let keyWindow = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWindow)
        } else {
            alert.runModal()
        }
    }
}

extension NSMutableAttributedString {
    /// Transforms *self* so that `self.string == new`, preserving
    /// attributes around the changed span wherever possible.
    @discardableResult
    func applyCharacterDiff(from old: String, to new: String) -> Bool {
        guard old == self.string else {
            logger.error("applyCharacterDiff precondition failed: receiver content does not match source text")
            return false
        }

        if old == new {
            return true
        }

        let oldChars = Array(old)
        let newChars = Array(new)

        // Find longest common prefix.
        var prefix = 0
        while prefix < oldChars.count &&
              prefix < newChars.count &&
              oldChars[prefix] == newChars[prefix] {
            prefix += 1
        }

        // Find longest common suffix after the shared prefix.
        var oldSuffix = oldChars.count
        var newSuffix = newChars.count
        while oldSuffix > prefix &&
              newSuffix > prefix &&
              oldChars[oldSuffix - 1] == newChars[newSuffix - 1] {
            oldSuffix -= 1
            newSuffix -= 1
        }

        let oldStartIndex = old.index(old.startIndex, offsetBy: prefix)
        let oldEndIndex = old.index(old.startIndex, offsetBy: oldSuffix)

        guard let utf16Start = oldStartIndex.samePosition(in: old.utf16),
              let utf16End = oldEndIndex.samePosition(in: old.utf16) else {
            logger.error("Failed to map Swift string indices to UTF-16 for attributed replacement")
            return false
        }

        let location = old.utf16.distance(from: old.utf16.startIndex, to: utf16Start)
        let length = old.utf16.distance(from: utf16Start, to: utf16End)
        let range = NSRange(location: location, length: length)

        let replacementText = String(newChars[prefix..<newSuffix])
        let replacementAttributes: [NSAttributedString.Key: Any]
        if location > 0 && location - 1 < self.length {
            replacementAttributes = attributes(at: location - 1, effectiveRange: nil)
        } else if location < self.length {
            replacementAttributes = attributes(at: location, effectiveRange: nil)
        } else {
            replacementAttributes = [:]
        }

        replaceCharacters(
            in: range,
            with: NSAttributedString(string: replacementText, attributes: replacementAttributes)
        )

        let succeeded = (self.string == new)
        if !succeeded {
            logger.error("UTF-16-safe attributed diff produced mismatched result")
        }
        return succeeded
    }
}

extension NSAttributedString {
    var containsTextAttachments: Bool {
        var hasAttachment = false
        let fullRange = NSRange(location: 0, length: length)
        enumerateAttribute(.attachment, in: fullRange, options: []) { value, _, stop in
            if value is NSTextAttachment {
                hasAttachment = true
                stop.pointee = true
            }
        }
        return hasAttachment
    }
}
