import Foundation
import AIProxy

private let logger = AppLogger.logger("AnthropicProvider")

struct AnthropicConfig: Codable {
    var apiKey: String
    var model: String
    
    static let defaultModel = "claude-3-5-sonnet-20240620"
}

enum AnthropicModel: String, CaseIterable {
    case claude45Haiku = "claude-haiku-4-5"
    case claude45Sonnet = "claude-sonnet-4-5"
    case claude41Opus = "claude-opus-4-1"
    case custom
    
    var displayName: String {
        switch self {
        case .claude45Haiku: return "Claude 4.5 Haiku (Fastest, Most Affordable)"
        case .claude45Sonnet: return "Claude 4.5 Sonnet (Best Coding Model)"
        case .claude41Opus: return "Claude 4.1 Opus (Most Capable, Expensive)"
        case .custom: return "Custom"
        }
    }
}

@MainActor
class AnthropicProvider: ObservableObject, AIProvider {
    @Published var isProcessing = false
    
    private var config: AnthropicConfig
    private var aiProxyService: AnthropicService?
    private var currentTask: Task<Void, Never>?
    
    init(config: AnthropicConfig) {
        self.config = config
        setupAIProxyService()
    }
    
    private func setupAIProxyService() {
        guard !config.apiKey.isEmpty else { return }
        aiProxyService = AIProxy.anthropicDirectService(unprotectedAPIKey: config.apiKey)
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
                domain: "AnthropicAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "API key is missing."]
            )
        }
        
        if aiProxyService == nil {
            setupAIProxyService()
        }
        
        guard let anthropicService = aiProxyService else {
            throw NSError(
                domain: "AnthropicAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AIProxy service."]
            )
        }
        
        // Compose messages array
        var messages: [AnthropicInputMessage] = []
        
        var userContent: [AnthropicInputContent] = [.text(userPrompt)]
        for imageData in images {
            userContent.append(
                .image(mediaType: AnthropicImageMediaType.jpeg, data: imageData.base64EncodedString())
            )
        }
        messages.append(
            AnthropicInputMessage(content: userContent, role: .user)
        )
        
        let requestBody = AnthropicMessageRequestBody(
            maxTokens: 1024,
            messages: messages,
            model: config.model.isEmpty ? AnthropicConfig.defaultModel : config.model,
            system: systemPrompt
        )
        
        do {
            let response = try await anthropicService.messageRequest(body: requestBody)
            
            for content in response.content {
                switch content {
                case .text(let message):
                    return message
                case .toolUse(id: _, name: let toolName, input: let toolInput):
                    logger.debug("Anthropic tool use: \(toolName) input: \(toolInput)")
                }
            }
            throw NSError(
                domain: "AnthropicAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No text content in response."]
            )
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            logger.error("Anthropic error (\(statusCode)): \(responseBody)")
            throw NSError(
                domain: "AnthropicAPI",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"]
            )
        } catch {
            logger.error("Anthropic request failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }
}
