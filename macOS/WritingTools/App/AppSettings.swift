import Foundation

// A singleton for app-wide settings that wraps UserDefaults access
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    private let keychain = KeychainManager.shared
    
    // MARK: - Published Settings
    @Published var themeStyle: String {
        didSet {
            defaults.set(themeStyle, forKey: "theme_style")
            useGradientTheme = (themeStyle != "standard")
        }
    }
    
    // API Keys now use computed properties backed by Keychain
    @Published var geminiApiKey: String = "" {
        didSet {
            try? keychain.save(geminiApiKey, forKey: "gemini_api_key")
        }
    }
    
    @Published var geminiModel: GeminiModel {
        didSet { defaults.set(geminiModel.rawValue, forKey: "gemini_model") }
    }
    
    @Published var geminiCustomModel: String {
        didSet { defaults.set(geminiCustomModel, forKey: "gemini_custom_model") }
    }
    
    @Published var openAIApiKey: String = "" {
        didSet {
            try? keychain.save(openAIApiKey, forKey: "openai_api_key")
        }
    }
    
    @Published var openAIBaseURL: String {
        didSet { defaults.set(openAIBaseURL, forKey: "openai_base_url") }
    }
    
    @Published var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: "openai_model") }
    }
    
    @Published var openAIOrganization: String? {
        didSet { defaults.set(openAIOrganization, forKey: "openai_organization") }
    }
    
    @Published var openAIProject: String? {
        didSet { defaults.set(openAIProject, forKey: "openai_project") }
    }
    
    @Published var currentProvider: String {
        didSet { defaults.set(currentProvider, forKey: "current_provider") }
    }
    
    @Published var shortcutText: String {
        didSet { defaults.set(shortcutText, forKey: "shortcut") }
    }
    
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "has_completed_onboarding") }
    }
    
    @Published var useGradientTheme: Bool {
        didSet { defaults.set(useGradientTheme, forKey: "use_gradient_theme") }
    }
    
    // MARK: - HotKey data
    @Published var hotKeyCode: Int {
        didSet { defaults.set(hotKeyCode, forKey: "hotKey_keyCode") }
    }
    @Published var hotKeyModifiers: Int {
        didSet { defaults.set(hotKeyModifiers, forKey: "hotKey_modifiers") }
    }
    @Published var hotkeysPaused: Bool {
        didSet { defaults.set(hotkeysPaused, forKey: "hotkeys_paused") }
    }
    
    @Published var mistralApiKey: String = "" {
        didSet {
            try? keychain.save(mistralApiKey, forKey: "mistral_api_key")
        }
    }
    
    @Published var mistralBaseURL: String {
        didSet { defaults.set(mistralBaseURL, forKey: "mistral_base_url") }
    }
    
    @Published var mistralModel: String {
        didSet { defaults.set(mistralModel, forKey: "mistral_model") }
    }
    
    // Ollama settings:
    @Published var ollamaBaseURL: String {
        didSet { defaults.set(ollamaBaseURL, forKey: "ollama_base_url") }
    }
    
    @Published var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: "ollama_model") }
    }
    
    @Published var ollamaKeepAlive: String {
        didSet { defaults.set(ollamaKeepAlive, forKey: "ollama_keep_alive") }
    }
    
    @Published var ollamaImageMode: OllamaImageMode {
        didSet { defaults.set(ollamaImageMode.rawValue, forKey: "ollama_image_mode") }
    }
    
    @Published var anthropicApiKey: String = "" {
        didSet {
            try? keychain.save(anthropicApiKey, forKey: "anthropic_api_key")
        }
    }
    
    @Published var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: "anthropic_model") }
    }
    
    @Published var openRouterApiKey: String = "" {
        didSet {
            try? keychain.save(openRouterApiKey, forKey: "openrouter_api_key")
        }
    }
    @Published var openRouterModel: String {
        didSet { defaults.set(openRouterModel, forKey: "openrouter_model") }
    }
    @Published var openRouterCustomModel: String {
        didSet { defaults.set(openRouterCustomModel, forKey: "openrouter_custom_model") }
    }
    
    // Store the ID (rawValue) of the selected local LLM model type
    @Published var selectedLocalLLMId: String? {
        didSet { defaults.set(selectedLocalLLMId, forKey: "selected_local_llm_id") }
    }
    
    // MARK: - Custom Commands Settings
    @Published var openCustomCommandsInResponseWindow: Bool {
        didSet { defaults.set(openCustomCommandsInResponseWindow, forKey: "open_custom_commands_in_response_window") }
    }
    
    // MARK: - Init
    private init() {
        let defaults = UserDefaults.standard
        
        // MARK: - Perform Keychain Migration (One-time on first launch after update)
        KeychainMigrationManager.shared.migrateIfNeeded()
        
        // Initialize the theme style first
        self.themeStyle = defaults.string(forKey: "theme_style") ?? "gradient"
        
        // Load API Keys from Keychain (post-migration)
        self.geminiApiKey = (try? keychain.retrieve(forKey: "gemini_api_key")) ?? ""
        let geminiModelStr = defaults.string(forKey: "gemini_model") ?? GeminiModel.twoflash.rawValue
        self.geminiModel = GeminiModel(rawValue: geminiModelStr) ?? .twoflash
        
        self.geminiCustomModel = defaults.string(forKey: "gemini_custom_model") ?? ""
        
        self.openAIApiKey = (try? keychain.retrieve(forKey: "openai_api_key")) ?? ""
        self.openAIBaseURL = defaults.string(forKey: "openai_base_url") ?? OpenAIConfig.defaultBaseURL
        self.openAIModel = defaults.string(forKey: "openai_model") ?? OpenAIConfig.defaultModel
        self.openAIOrganization = defaults.string(forKey: "openai_organization")
        self.openAIProject = defaults.string(forKey: "openai_project")
        
        self.mistralApiKey = (try? keychain.retrieve(forKey: "mistral_api_key")) ?? ""
        self.mistralBaseURL = defaults.string(forKey: "mistral_base_url") ?? MistralConfig.defaultBaseURL
        self.mistralModel = defaults.string(forKey: "mistral_model") ?? MistralConfig.defaultModel
        
        self.ollamaBaseURL = defaults.string(forKey: "ollama_base_url") ?? OllamaConfig.defaultBaseURL
        self.ollamaModel = defaults.string(forKey: "ollama_model") ?? OllamaConfig.defaultModel
        self.ollamaKeepAlive = defaults.string(forKey: "ollama_keep_alive") ?? OllamaConfig.defaultKeepAlive
        
        self.currentProvider = defaults.string(forKey: "current_provider") ?? "gemini"
        self.shortcutText = defaults.string(forKey: "shortcut") ?? "⌥ Space"
        self.hasCompletedOnboarding = defaults.bool(forKey: "has_completed_onboarding")
        self.useGradientTheme = defaults.bool(forKey: "use_gradient_theme")
        
        // HotKey
        self.hotKeyCode = defaults.integer(forKey: "hotKey_keyCode")
        self.hotKeyModifiers = defaults.integer(forKey: "hotKey_modifiers")
        self.hotkeysPaused = defaults.bool(forKey: "hotkeys_paused")
        
        let ollamaImageModeRaw = defaults.string(forKey: "ollama_image_mode") ?? OllamaImageMode.ocr.rawValue
        self.ollamaImageMode = OllamaImageMode(rawValue: ollamaImageModeRaw) ?? .ocr
        
        self.anthropicApiKey = (try? keychain.retrieve(forKey: "anthropic_api_key")) ?? ""
        self.anthropicModel = defaults.string(forKey: "anthropic_model") ?? AnthropicConfig.defaultModel
        
        self.selectedLocalLLMId = defaults.string(forKey: "selected_local_llm_id")
        
        self.openRouterApiKey = (try? keychain.retrieve(forKey: "openrouter_api_key")) ?? ""
        self.openRouterModel = defaults.string(forKey: "openrouter_model") ?? OpenRouterConfig.defaultModel
        self.openRouterCustomModel = defaults.string(forKey: "openrouter_custom_model") ?? ""
        
        // Custom commands setting - default to true (open in response window)
        self.openCustomCommandsInResponseWindow = defaults.object(forKey: "open_custom_commands_in_response_window") as? Bool ?? true
    }
    
    // MARK: - Convenience
    func resetAll() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        
        // Clear Keychain API keys
        try? keychain.clearAllApiKeys()
    }
}
