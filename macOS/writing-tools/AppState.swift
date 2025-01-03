import SwiftUI

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var geminiProvider: GeminiProvider
    @Published var openAIProvider: OpenAIProvider
    @Published var currentProvider: String // "gemini" or "openai"
    @Published var customInstruction: String = ""
    @Published var selectedText: String = ""
    @Published var isPopupVisible: Bool = false
    @Published var isProcessing: Bool = false
    @Published var previousApplication: NSRunningApplication?
    
    var activeProvider: (any AIProvider) {
        currentProvider == "openai" ? openAIProvider as any AIProvider : geminiProvider as any AIProvider
    }
    
    private init() {
        // Initialize Gemini
        let geminiApiKey = UserDefaults.standard.string(forKey: "gemini_api_key")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let geminiModelName = UserDefaults.standard.string(forKey: "gemini_model") ?? GeminiModel.oneflash.rawValue
        let geminiConfig = GeminiConfig(apiKey: geminiApiKey, modelName: geminiModelName)
        self.geminiProvider = GeminiProvider(config: geminiConfig)
        
        // Initialize OpenAI
        let openAIApiKey = UserDefaults.standard.string(forKey: "openai_api_key")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let openAIBaseURL = UserDefaults.standard.string(forKey: "openai_base_url") ?? OpenAIConfig.defaultBaseURL
        let openAIOrg = UserDefaults.standard.string(forKey: "openai_organization")
        let openAIProject = UserDefaults.standard.string(forKey: "openai_project")
        let openAIModel = UserDefaults.standard.string(forKey: "openai_model") ?? OpenAIModel.gpt4.rawValue
        
        let openAIConfig = OpenAIConfig(
            apiKey: openAIApiKey,
            baseURL: openAIBaseURL,
            organization: openAIOrg,
            project: openAIProject,
            model: openAIModel
        )
        self.openAIProvider = OpenAIProvider(config: openAIConfig)
        
        // Set current provider
        self.currentProvider = UserDefaults.standard.string(forKey: "current_provider") ?? "gemini"
        
        if openAIApiKey.isEmpty && geminiApiKey.isEmpty {
            print("Warning: No API keys configured.")
        }
    }
    
    // Save Gemini API configuration
    func saveGeminiConfig(apiKey: String, model: GeminiModel) {
        UserDefaults.standard.setValue(apiKey, forKey: "gemini_api_key")
        UserDefaults.standard.setValue(model.rawValue, forKey: "gemini_model")
        
        let config = GeminiConfig(apiKey: apiKey, modelName: model.rawValue)
        geminiProvider = GeminiProvider(config: config)
    }
    
    // Save OpenAI API configuration
    func saveOpenAIConfig(apiKey: String, baseURL: String, organization: String?, project: String?, model: String) {
        UserDefaults.standard.setValue(apiKey, forKey: "openai_api_key")
        UserDefaults.standard.setValue(baseURL, forKey: "openai_base_url")
        UserDefaults.standard.setValue(organization, forKey: "openai_organization")
        UserDefaults.standard.setValue(project, forKey: "openai_project")
        UserDefaults.standard.setValue(model, forKey: "openai_model")
        
        let config = OpenAIConfig(
            apiKey: apiKey,
            baseURL: baseURL,
            organization: organization,
            project: project,
            model: model
        )
        openAIProvider = OpenAIProvider(config: config)
    }
    
    // Update the current AI provider
    func setCurrentProvider(_ provider: String) {
        currentProvider = provider
        UserDefaults.standard.setValue(provider, forKey: "current_provider")
    }
}
