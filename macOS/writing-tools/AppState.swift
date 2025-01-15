import SwiftUI

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var geminiProvider: GeminiProvider
    @Published var openAIProvider: OpenAIProvider
    
    @Published var customInstruction: String = ""
    @Published var selectedText: String = ""
    @Published var isPopupVisible: Bool = false
    @Published var isProcessing: Bool = false
    @Published var previousApplication: NSRunningApplication?

    // Derived from AppSettings
    var currentProvider: String {
        get { AppSettings.shared.currentProvider }
        set { AppSettings.shared.currentProvider = newValue }
    }
    
    var activeProvider: any AIProvider {
        currentProvider == "openai" ? openAIProvider : geminiProvider
    }
    
    private init() {
        // Read from AppSettings
        let asettings = AppSettings.shared
        
        // Initialize Gemini
        let geminiConfig = GeminiConfig(apiKey: asettings.geminiApiKey,
                                        modelName: asettings.geminiModel.rawValue)
        self.geminiProvider = GeminiProvider(config: geminiConfig)
        
        // Initialize OpenAI
        let openAIConfig = OpenAIConfig(
            apiKey: asettings.openAIApiKey,
            baseURL: asettings.openAIBaseURL,
            organization: asettings.openAIOrganization,
            project: asettings.openAIProject,
            model: asettings.openAIModel
        )
        self.openAIProvider = OpenAIProvider(config: openAIConfig)
        
        if asettings.openAIApiKey.isEmpty && asettings.geminiApiKey.isEmpty {
            print("Warning: No API keys configured.")
        }
    }
    
    // For Gemini changes
    func saveGeminiConfig(apiKey: String, model: GeminiModel) {
        AppSettings.shared.geminiApiKey = apiKey
        AppSettings.shared.geminiModel = model
        
        let config = GeminiConfig(apiKey: apiKey, modelName: model.rawValue)
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
        
        let config = OpenAIConfig(apiKey: apiKey, baseURL: baseURL,
                                  organization: organization, project: project,
                                  model: model)
        openAIProvider = OpenAIProvider(config: config)
    }
    
    // Switch AI provider
    func setCurrentProvider(_ provider: String) {
        AppSettings.shared.currentProvider = provider
    }
}
