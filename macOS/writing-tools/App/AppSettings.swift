import Foundation

// A singleton for app-wide settings that wraps UserDefaults access
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Published Settings
    @Published var themeStyle: String {
        didSet {
            defaults.set(themeStyle, forKey: "theme_style")
            useGradientTheme = (themeStyle != "standard")
        }
    }
    
    @Published var geminiApiKey: String {
        didSet { defaults.set(geminiApiKey, forKey: "gemini_api_key") }
    }
    
    @Published var geminiModel: GeminiModel {
        didSet { defaults.set(geminiModel.rawValue, forKey: "gemini_model") }
    }
    
    @Published var geminiCustomModel: String {
        didSet { defaults.set(geminiCustomModel, forKey: "gemini_custom_model") }
    }
    
    @Published var openAIApiKey: String {
        didSet { defaults.set(openAIApiKey, forKey: "openai_api_key") }
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
    
    
    @Published var mistralApiKey: String {
        didSet { defaults.set(mistralApiKey, forKey: "mistral_api_key") }
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
    
    // Store the ID (rawValue) of the selected local LLM model type
    @Published var selectedLocalLLMId: String? {
        didSet { defaults.set(selectedLocalLLMId, forKey: "selected_local_llm_id") }
    }
    
    // MARK: - Init
    private init() {
        let defaults = UserDefaults.standard
        
        // Initialize the theme style first
        self.themeStyle = defaults.string(forKey: "theme_style") ?? "gradient"
        
        // Load or set defaults
        self.geminiApiKey = defaults.string(forKey: "gemini_api_key") ?? ""
        let geminiModelStr = defaults.string(forKey: "gemini_model") ?? GeminiModel.twoflash.rawValue
        self.geminiModel = GeminiModel(rawValue: geminiModelStr) ?? .twoflash
        
        self.geminiCustomModel = defaults.string(forKey: "gemini_custom_model") ?? ""
        
        self.openAIApiKey = defaults.string(forKey: "openai_api_key") ?? ""
        self.openAIBaseURL = defaults.string(forKey: "openai_base_url") ?? OpenAIConfig.defaultBaseURL
        self.openAIModel = defaults.string(forKey: "openai_model") ?? OpenAIConfig.defaultModel
        self.openAIOrganization = defaults.string(forKey: "openai_organization") ?? nil
        self.openAIProject = defaults.string(forKey: "openai_project") ?? nil
        
        self.mistralApiKey = defaults.string(forKey: "mistral_api_key") ?? ""
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
        
        self.selectedLocalLLMId = defaults.string(forKey: "selected_local_llm_id")
    }
    
    // MARK: - Convenience
    func resetAll() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
    }
}
