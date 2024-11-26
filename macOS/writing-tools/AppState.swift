import SwiftUI

class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var geminiProvider: GeminiProvider
    @Published var customInstruction: String = ""
    @Published var selectedText: String = ""
    @Published var isPopupVisible: Bool = false
    @Published var isProcessing: Bool = false
    @Published var previousApplication: NSRunningApplication?
    
    private init() {
        let apiKey = UserDefaults.standard.string(forKey: "gemini_api_key")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let modelName = UserDefaults.standard.string(forKey: "gemini_model") ?? GeminiModel.flash.rawValue

        if apiKey.isEmpty {
            print("Warning: Gemini API key is not configured.")
        }

        let config = GeminiConfig(apiKey: apiKey, modelName: modelName)
        self.geminiProvider = GeminiProvider(config: config)
    }
    
    func saveConfig(apiKey: String, model: GeminiModel) {
        UserDefaults.standard.setValue(apiKey, forKey: "gemini_api_key")
        UserDefaults.standard.setValue(model.rawValue, forKey: "gemini_model")
        
        let config = GeminiConfig(apiKey: apiKey, modelName: model.rawValue)
        geminiProvider = GeminiProvider(config: config)
    }
}
