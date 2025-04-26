import Foundation
import AIProxy

struct OpenAIConfig: Codable {
    var apiKey: String
    var baseURL: String
    var model: String
    
    static let defaultBaseURL = "https://api.openai.com"
    static let defaultModel = "gpt-4o"
}

enum OpenAIModel: String, CaseIterable {
    case gpt4 = "gpt-4"
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"
    
    var displayName: String {
        switch self {
        case .gpt4: return "GPT-4 (Most Capable)"
        case .gpt4o: return "GPT-4o (Optimized)"
        case .gpt4oMini: return "GPT-4o Mini (Lightweight)"
        }
    }
}

@MainActor
class OpenAIProvider: ObservableObject, AIProvider {
    @Published var isProcessing = false
        private var config: OpenAIConfig
        private var aiProxyService: OpenAIService?
        private var currentTask: Task<Void, Never>?
        
        init(config: OpenAIConfig) {
            self.config = config
            setupAIProxyService()
        }
        
        private func setupAIProxyService() {
            guard !config.apiKey.isEmpty else { return }
            
            // Use custom base URL if provided, otherwise use default
            let baseURL = config.baseURL.isEmpty ? OpenAIConfig.defaultBaseURL : config.baseURL
            
            aiProxyService = AIProxy.openAIDirectService(
                unprotectedAPIKey: config.apiKey,
                baseURL: baseURL
            )
        }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = [], streaming: Bool = false) async throws -> String {
            isProcessing = true
            defer { isProcessing = false }
            
            guard !config.apiKey.isEmpty else {
                throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
            }
            
            if aiProxyService == nil {
                setupAIProxyService()
            }
            
            guard let openAIService = aiProxyService else {
                throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AIProxy service."])
            }
            
            var messages: [OpenAIChatCompletionRequestBody.Message] = []
            
            if let systemPrompt = systemPrompt {
                messages.append(.system(content: .text(systemPrompt)))
            }
            
            // Handle text and images
            if images.isEmpty {
                messages.append(.user(content: .text(userPrompt)))
            } else {
                var parts: [OpenAIChatCompletionRequestBody.Message.ContentPart] = [.text(userPrompt)]
                
                for imageData in images {
                    let dataString = "data:image/jpeg;base64," + imageData.base64EncodedString()
                    if let dataURL = URL(string: dataString) {
                        parts.append(.imageURL(dataURL, detail: .auto))
                    }
                }
                
                messages.append(.user(content: .parts(parts)))
            }
            
            do {
                if streaming {
                    var compiledResponse = ""
                    let stream = try await openAIService.streamingChatCompletionRequest(body: .init(
                        model: config.model,
                        messages: messages
                    ))
                    
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        if let content = chunk.choices.first?.delta.content {
                            compiledResponse += content
                        }
                    }
                    return compiledResponse
                    
                } else {
                    let response = try await openAIService.chatCompletionRequest(body: .init(
                        model: config.model,
                        messages: messages
                    ))
                    
                    return response.choices.first?.message.content ?? ""
                }
                
            } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
                print("Received non-200 status code: \(statusCode) with response body: \(responseBody)")
                throw NSError(domain: "OpenAIAPI",
                              code: statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
            } catch {
                print("Could not create OpenAI chat completion: \(error.localizedDescription)")
                throw error
            }
        }

    
    func cancel() {
        isProcessing = false
        currentTask = nil
    }
}
