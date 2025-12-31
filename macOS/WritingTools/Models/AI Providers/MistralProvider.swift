import Foundation
import AIProxy
import Observation

private let logger = AppLogger.logger("MistralProvider")

struct MistralConfig: Codable {
    var apiKey: String
    var baseURL: String
    var model: String
    
    static let defaultBaseURL = "https://api.mistral.ai/v1"
    static let defaultModel = "mistral-small-latest"
}
enum MistralModel: String, CaseIterable {
    case mistralSmall = "mistral-small-latest"
    case mistralMedium = "mistral-medium-latest"
    case mistralLarge = "mistral-large-latest"
    
    var displayName: String {
        switch self {
        case .mistralSmall: return "Mistral Small (Fast)"
        case .mistralMedium: return "Mistral Medium (Balanced)"
        case .mistralLarge: return "Mistral Large (Most Capable)"
        }
    }
}

@Observable
final class MistralProvider: AIProvider {
    var isProcessing = false
    private var config: MistralConfig
    private var aiProxyService: MistralService?
    private var currentTask: Task<Void, Never>?
    
    init(config: MistralConfig) {
        self.config = config
        setupAIProxyService()
    }
    
    private func setupAIProxyService() {
        guard !config.apiKey.isEmpty else { return }
        aiProxyService = AIProxy.mistralDirectService(unprotectedAPIKey: config.apiKey)
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = [], streaming: Bool = false) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "MistralAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }
        
        if aiProxyService == nil {
            setupAIProxyService()
        }
        
        guard let mistralService = aiProxyService else {
            throw NSError(domain: "MistralAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize AIProxy service."])
        }
        
        var messages: [MistralChatCompletionRequestBody.Message] = []
        
        if let systemPrompt = systemPrompt {
            messages.append(.system(content: systemPrompt))
        }
        
        // Extract OCR text from images (if any) and append to user prompt.
        var combinedPrompt = userPrompt
        if !images.isEmpty {
            let ocrText = await OCRManager.shared.extractText(from: images)
            if !ocrText.isEmpty {
                combinedPrompt += "\nExtracted Text: \(ocrText)"
            }
        }
        
        messages.append(.user(content: combinedPrompt))
        
        do {
            if streaming {
                var compiledResponse = ""
                let stream = try await mistralService.streamingChatCompletionRequest(body: .init(
                    messages: messages,
                    model: config.model
                ), secondsToWait: 60)
                
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if let content = chunk.choices.first?.delta.content {
                        compiledResponse += content
                    }
                    if let usage = chunk.usage {
                        logger.debug("Usage: prompt \(usage.promptTokens ?? 0), completion \(usage.completionTokens ?? 0), total \(usage.totalTokens ?? 0)")
                    }
                }
                return compiledResponse
                
            } else {
                let response = try await mistralService.chatCompletionRequest(body: .init(
                    messages: messages,
                    model: config.model
                ), secondsToWait: 60)
                
                /*if let usage = response.usage {
                    logger.debug("""
                            Used:
                             \(usage.promptTokens ?? 0) prompt tokens
                             \(usage.completionTokens ?? 0) completion tokens
                             \(usage.totalTokens ?? 0) total tokens
                            """)
                }*/
                
                return response.choices.first?.message.content ?? ""
            }
            
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            logger.error("Received non-200 status code: \(statusCode) with response body: \(responseBody)")
            throw NSError(domain: "MistralAPI",
                          code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
        } catch {
            logger.error("Could not create mistral chat completion: \(error.localizedDescription)")
            throw error
        }
    }
    
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
    }
}
