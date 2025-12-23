import Foundation
import AIProxy

private let logger = AppLogger.logger("OpenAIProvider")

struct OpenAIConfig: Codable {
    var apiKey: String
    var baseURL: String
    var model: String
    
    static let defaultBaseURL = "https://api.openai.com"
    static let defaultModel = "gpt-4o"
}

enum OpenAIModel: String, CaseIterable {
    case gpt4 = "gpt-4.1"
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"
    
    var displayName: String {
        switch self {
        case .gpt4: return "GPT-4.1 (Most Capable)"
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
            
            // Check for custom Base URL
            if !config.baseURL.isEmpty && config.baseURL != OpenAIConfig.defaultBaseURL {
                return try await performCustomOpenAIRequest(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images, streaming: streaming)
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
                    ), secondsToWait: 60)
                    
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
                    ), secondsToWait: 60)
                    
                    return response.choices.first?.message.content ?? ""
                }
                
            } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
                logger.error("Received non-200 status code: \(statusCode) with response body: \(responseBody)")
                throw NSError(domain: "OpenAIAPI",
                              code: statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
            } catch {
                logger.error("Could not create OpenAI chat completion: \(error.localizedDescription)")
                throw error
            }
        }
    
    // MARK: - Custom Request Implementation
    
    private func performCustomOpenAIRequest(systemPrompt: String?, userPrompt: String, images: [Data], streaming: Bool) async throws -> String {
        // Construct URL
        var urlString = config.baseURL
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        // Append /chat/completions if not present (simple heuristic, can be improved)
        if !urlString.hasSuffix("/chat/completions") {
             urlString += "/chat/completions"
        }
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Base URL."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Construct Body
        var messages: [[String: Any]] = []
        
        if let systemPrompt = systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        
        if images.isEmpty {
            messages.append(["role": "user", "content": userPrompt])
        } else {
            var content: [[String: Any]] = [
                ["type": "text", "text": userPrompt]
            ]
            
            for imageData in images {
                let base64 = imageData.base64EncodedString()
                content.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/jpeg;base64,\(base64)"
                    ]
                ])
            }
            messages.append(["role": "user", "content": content])
        }
        
        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": false // Forcing non-streaming for custom providers for now to ensure compatibility
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type."])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Custom OpenAI Request Failed: \(httpResponse.statusCode) - \(errorBody)")
            throw NSError(domain: "OpenAIAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorBody)"])
        }
        
        // Parse Response
        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            return decoded.choices.first?.message.content ?? ""
        } catch {
            logger.error("Failed to decode response: \(error.localizedDescription)")
             throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse API response."])
        }
    }

    
    func cancel() {
        isProcessing = false
        currentTask = nil
    }
}
