import SwiftUI

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var geminiProvider: GeminiProvider
    @Published var openAIProvider: OpenAIProvider
    @Published var mistralProvider: MistralProvider
    @Published var anthropicProvider: AnthropicProvider
    @Published var ollamaProvider: OllamaProvider
    @Published var localLLMProvider: LocalModelProvider
    @Published var openRouterProvider: OpenRouterProvider
    
    @Published var customInstruction: String = ""
    @Published var selectedText: String = ""
    @Published var isPopupVisible: Bool = false
    @Published var isProcessing: Bool = false
    @Published var previousApplication: NSRunningApplication?
    @Published var selectedImages: [Data] = []  // Store selected image data
    
    // Command management
    @Published var commandManager = CommandManager()
    @Published var customCommandsManager = CustomCommandsManager()
    
    // Current provider with UI binding support
    @Published private(set) var currentProvider: String
    
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
        
        // Iniltialize Anthropic
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
            AppSettings.shared.geminiCustomModel = custom   // persist custom
        }
        
        // choose actual modelName
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
        objectWillChange.send()  // Explicitly notify observers
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
                let result = try await activeProvider.processText(
                    systemPrompt: prompt,
                    userPrompt: selectedText,
                    images: [],
                    streaming: false
                )
                
                // Determine what to do with the result based on command settings
                if command.useResponseWindow {
                    // Display in response window
                    let window = ResponseWindow(
                        title: "\(command.name) Result",
                        content: result,
                        selectedText: selectedText,
                        option: nil // Using nil since this is using the generic CommandModel
                    )
                    
                    WindowManager.shared.addResponseWindow(window)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                } else {
                    // Replace selected text by setting clipboard and pasting
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                    
                    // Reactivate previous application and paste
                    if let previousApp = previousApplication {
                        previousApp.activate()
                        
                        // Wait briefly for activation then paste once
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            self.simulatePaste()
                        }
                    }
                }
            } catch {
                // Handle error
                print("Error processing command: \(error)")
            }
            
            isProcessing = false
        }
    }
    
    // Helper method to replace selected text
    func replaceSelectedText(with newText: String) {
        // Store original selection for comparison
        let originalSelection = selectedText

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)

        // Reactivate previous application and paste
        if let previousApp = previousApplication {
            previousApp.activate()

            // Wait briefly for activation then paste once
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.simulatePaste()

                // Check if paste was successful after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.checkPasteSuccess(originalSelection: originalSelection, transformedText: newText)
                }
            }
        }
    }
    
    // Simulate paste command
    private func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        // Create a Command + V key down event
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand

        // Create a Command + V key up event
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand

        // Post the events to the HID event system
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    // Check if paste was successful by getting current selection
    private func checkPasteSuccess(originalSelection: String, transformedText: String) {
        // Get current selection to check if paste was successful
        getCurrentSelection { [weak self] currentSelection in
            guard let self = self else { return }

            // If selection is the same as original, paste failed (non-editable page)
            if currentSelection == originalSelection && !originalSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("Paste failed - showing modal window for non-editable page")
                self.showNonEditableModal(transformedText: transformedText, originalText: originalSelection)
            }
        }
    }

    // Get current selection by simulating copy
    private func getCurrentSelection(completion: @escaping (String) -> Void) {
        // Store current clipboard content
        let originalClipboard = NSPasteboard.general.string(forType: .string)

        // Clear clipboard and simulate copy
        NSPasteboard.general.clearContents()

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            completion("")
            return
        }

        // Create a Command + C key down event
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        keyDown?.flags = .maskCommand

        // Create a Command + C key up event
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand

        // Post the events
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Wait for copy operation to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let currentSelection = NSPasteboard.general.string(forType: .string) ?? ""

            // Restore original clipboard content
            NSPasteboard.general.clearContents()
            if let originalClipboard = originalClipboard {
                NSPasteboard.general.setString(originalClipboard, forType: .string)
            }

            completion(currentSelection)
        }
    }

    // Show non-editable modal window
    private func showNonEditableModal(transformedText: String, originalText: String) {
        DispatchQueue.main.async {
            let modal = NonEditableModalWindow(
                transformedText: transformedText,
                originalText: originalText
            )

            WindowManager.shared.addNonEditableModal(modal)
        }
    }
}
