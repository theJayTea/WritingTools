import Foundation
import AppKit
import AIProxy

private let logger = AppLogger.logger("OpenRouterProvider")

struct OpenRouterConfig: Codable {
    var apiKey: String
    var model: String
    static let defaultModel = "openai/gpt-4o"
}

enum OpenRouterModel: String, CaseIterable {
    case gpt4o = "openai/gpt-4o"
    case deepseekR1 = "deepseek/deepseek-r1"
    case deepseekChat = "deepseek/deepseek-chat"
    case grok2Vision = "x-ai/grok-2-vision-1212"
    case custom
    
    var displayName: String {
        switch self {
        case .gpt4o: return "OpenAI GPT-4o"
        case .deepseekR1: return "DeepSeek R1"
        case .deepseekChat: return "DeepSeek Chat"
        case .grok2Vision: return "Grok 2 Vision"
        case .custom: return "Custom"
        }
    }
}

@MainActor
class OpenRouterProvider: ObservableObject, AIProvider {
    @Published var isProcessing = false
    
    private var config: OpenRouterConfig
    private var aiProxyService: OpenRouterService?
    private var currentTask: Task<Void, Never>?
    
    init(config: OpenRouterConfig) {
        self.config = config
        setupAIProxyService()
    }
    
    private func setupAIProxyService() {
        guard !config.apiKey.isEmpty else { return }
        aiProxyService = AIProxy.openRouterDirectService(unprotectedAPIKey: config.apiKey)
    }
    
    func processText(
        systemPrompt: String? = "You are a helpful writing assistant.",
        userPrompt: String,
        images: [Data] = [],
        streaming: Bool = false
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        guard !config.apiKey.isEmpty else {
            throw NSError(
                domain: "OpenRouterAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "API key is missing."]
            )
        }
        
        if aiProxyService == nil {
            setupAIProxyService()
        }
        
        guard let openRouterService = aiProxyService else {
            throw NSError(
                domain: "OpenRouterAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AIProxy service."]
            )
        }
        
        // Compose messages
        var messages: [OpenRouterChatCompletionRequestBody.Message] = []
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            messages.append(.system(content: .text(systemPrompt)))
        }
        
        if images.isEmpty {
            messages.append(.user(content: .text(userPrompt)))
        } else {
            var parts: [OpenRouterChatCompletionRequestBody.Message.UserContent.Part] = [.text(userPrompt)]
            for imageData in images {
                if let nsImage = NSImage(data: imageData),
                   let imageURL = AIProxy.encodeImageAsURL(image: nsImage, compressionQuality: 0.8) {
                    parts.append(.imageURL(imageURL))
                }
            }
            messages.append(.user(content: .parts(parts)))
        }
        
        let modelName = config.model.isEmpty ? OpenRouterConfig.defaultModel : config.model
        
        let requestBody = OpenRouterChatCompletionRequestBody(
            messages: messages,
            models: [modelName],
            route: .fallback
        )
        
        do {
            if streaming {
                var compiledResponse = ""
                let stream = try await openRouterService.streamingChatCompletionRequest(body: requestBody)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if let content = chunk.choices.first?.delta.content {
                        compiledResponse += content
                    }
                }
                return compiledResponse
            } else {
                let response = try await openRouterService.chatCompletionRequest(body: requestBody)
                return response.choices.first?.message.content ?? ""
            }
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            logger.error("OpenRouter error (\(statusCode)): \(responseBody)")
            throw NSError(
                domain: "OpenRouterAPI",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"]
            )
        } catch {
            logger.error("OpenRouter request failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }
}
