import Foundation
import AIProxy

struct GeminiConfig: Codable {
    var apiKey: String
    var modelName: String
}

enum GeminiModel: String, CaseIterable {
    case twofashlite = "gemini-2.0-flash-lite"
    case twoflash = "gemini-2.0-flash"
    case twofiveflash = "gemini-2.5-flash-preview-04-17"
    case twofivepro = "gemini-2.5-pro-preview-03-25"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .twofashlite: return "Gemini 2.0 Flash Lite (Agile Intelligence | Blazing Fast | ~30 uses/min)"
        case .twoflash: return "Gemini 2.0 Flash (Balanced Intelligence | Swift | ~15 uses/min)"
        case .twofiveflash: return "Gemini 2.5 Flash (Enhanced Intelligence | Measured Pace | ~10 uses/min)"
        case .twofivepro: return "Gemini 2.5 Pro (Peak Intelligence | Deliberate Speed | ~5 uses/min)"
        case .custom: return "Custom"
        }
    }
}

@MainActor
class GeminiProvider: ObservableObject, AIProvider {
    @Published var isProcessing = false
    private var config: GeminiConfig
    private var aiProxyService: GeminiService?
    private var currentTask: Task<Void, Never>?
    
    init(config: GeminiConfig) {
        self.config = config
        setupAIProxyService()
    }
    
    private func setupAIProxyService() {
        guard !config.apiKey.isEmpty else { return }
        aiProxyService = AIProxy.geminiDirectService(unprotectedAPIKey: config.apiKey)
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = [], streaming: Bool = false) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }
        
        if aiProxyService == nil {
            setupAIProxyService()
        }
        
        guard let geminiService = aiProxyService else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AIProxy service."])
        }
        
        let finalPrompt = systemPrompt.map { "\($0)\n\n\(userPrompt)" } ?? userPrompt
        
        var parts: [GeminiGenerateContentRequestBody.Content.Part] = [.text(finalPrompt)]
        
        for imageData in images {
            parts.append(.inline(data: imageData, mimeType: "image/jpeg"))
        }
        
        let requestBody = GeminiGenerateContentRequestBody(
            contents: [.init(parts: parts)],
            safetySettings: [
                .init(category: .dangerousContent, threshold: .none),
                .init(category: .harassment, threshold: .none),
                .init(category: .hateSpeech, threshold: .none),
                .init(category: .sexuallyExplicit, threshold: .none),
                .init(category: .civicIntegrity, threshold: .none)
            ]
        )
        
        do {
            let response = try await geminiService.generateContentRequest(body: requestBody, model: config.modelName, secondsToWait: 60)
            
            /*if let usage = response.usageMetadata {
                print("""
                     Gemini API Usage:
                     
                      \(usage.promptTokenCount ?? 0) prompt tokens
                      \(usage.candidatesTokenCount ?? 0) candidate tokens
                      \(usage.totalTokenCount ?? 0) total tokens
                     """)
            }*/
            
            for part in response.candidates?.first?.content?.parts ?? [] {
                switch part {
                case .text(let text):
                    return text
                case .functionCall(name: let functionName, args: let arguments):
                    print("Function call received: \(functionName) with args: \(arguments ?? [:])")
                case .inlineData(mimeType: _, base64Data: _):
                    print("Image generation?")
                }
            }
            
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No text content in response."])
            
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            print("AIProxy error (\(statusCode)): \(responseBody)")
            throw NSError(domain: "GeminiAPI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
        } catch {
            print("Gemini request failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }
}
