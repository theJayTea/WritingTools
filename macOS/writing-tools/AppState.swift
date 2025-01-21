import SwiftUI

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var geminiProvider: GeminiProvider
    @Published var openAIProvider: OpenAIProvider
    @Published var mistralProvider: MistralProvider
    
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
        
        // Initialize Mistral
        let mistralConfig = MistralConfig(
            apiKey: asettings.mistralApiKey,
            baseURL: asettings.mistralBaseURL,
            model: asettings.mistralModel
        )
        self.mistralProvider = MistralProvider(config: mistralConfig)
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
}
