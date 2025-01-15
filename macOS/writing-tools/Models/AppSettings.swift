import Foundation

// A singleton for app-wide settings that wraps UserDefaults access
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard

    // MARK: - Published Settings
    @Published var geminiApiKey: String {
        didSet { defaults.set(geminiApiKey, forKey: "gemini_api_key") }
    }
    
    @Published var geminiModel: GeminiModel {
        didSet { defaults.set(geminiModel.rawValue, forKey: "gemini_model") }
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

    // MARK: - Init
    private init() {
        let defaults = UserDefaults.standard
        
        // Load or set defaults
        self.geminiApiKey = defaults.string(forKey: "gemini_api_key") ?? ""
        let geminiModelStr = defaults.string(forKey: "gemini_model") ?? GeminiModel.oneflash.rawValue
        self.geminiModel = GeminiModel(rawValue: geminiModelStr) ?? .oneflash
        
        self.openAIApiKey = defaults.string(forKey: "openai_api_key") ?? ""
        self.openAIBaseURL = defaults.string(forKey: "openai_base_url") ?? OpenAIConfig.defaultBaseURL
        self.openAIModel = defaults.string(forKey: "openai_model") ?? OpenAIConfig.defaultModel
        self.openAIOrganization = defaults.string(forKey: "openai_organization") ?? nil
        self.openAIProject = defaults.string(forKey: "openai_project") ?? nil
        
        self.currentProvider = defaults.string(forKey: "current_provider") ?? "gemini"
        self.shortcutText = defaults.string(forKey: "shortcut") ?? "⌥ Space"
        self.hasCompletedOnboarding = defaults.bool(forKey: "has_completed_onboarding")
        self.useGradientTheme = defaults.bool(forKey: "use_gradient_theme")

        // HotKey
        self.hotKeyCode = defaults.integer(forKey: "hotKey_keyCode")
        self.hotKeyModifiers = defaults.integer(forKey: "hotKey_modifiers")
    }
    
    // MARK: - Convenience
    func resetAll() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
    }
}
