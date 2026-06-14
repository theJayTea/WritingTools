import Foundation
import AIProxy
import Observation

private let logger = AppLogger.logger("MistralProvider")

struct MistralConfig: Codable, Sendable {
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

@MainActor
@Observable
final class MistralProvider: AIProvider {
    var isProcessing = false
    private var config: MistralConfig
    private var activeTask: Task<Void, any Error>?
    
    init(config: MistralConfig) {
        self.config = config
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = []) async throws -> String {
        isProcessing = true
        defer {
            isProcessing = false
        }

        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "MistralAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }

        let mistralService = AIProxy.mistralDirectService(unprotectedAPIKey: config.apiKey)

        var messages: [MistralChatCompletionRequestBody.Message] = []

        if let systemPrompt = systemPrompt {
            messages.append(.system(content: systemPrompt))
        }

        // Extract OCR text from images (if any) and append to user prompt.
        var combinedPrompt = userPrompt
        if !images.isEmpty {
            let ocrText = try await OCRManager.shared.extractText(from: images)
            if !ocrText.isEmpty {
                combinedPrompt += "\nExtracted Text: \(ocrText)"
            }
        }

        messages.append(.user(content: combinedPrompt))

        do {
            try Task.checkCancellation()
            let requestMessages = messages
            let response = try await withRetry {
                try await mistralService.chatCompletionRequest(body: .init(
                    messages: requestMessages,
                    model: config.model
                ), secondsToWait: 60)
            }

            let content = response.choices.first?.message.content ?? ""
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "MistralAPI", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No text content in response."])
            }
            return content

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
    
    func processTextStreaming(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        onChunk: @escaping @Sendable @MainActor (String) -> Void
    ) async throws {
        isProcessing = true
        defer {
            isProcessing = false
            activeTask = nil
        }

        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "MistralAPI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }

        let mistralService = AIProxy.mistralDirectService(unprotectedAPIKey: config.apiKey)

        var messages: [MistralChatCompletionRequestBody.Message] = []
        if let systemPrompt = systemPrompt {
            messages.append(.system(content: systemPrompt))
        }

        var combinedPrompt = userPrompt
        if !images.isEmpty {
            let ocrText = try await OCRManager.shared.extractText(from: images)
            if !ocrText.isEmpty {
                combinedPrompt += "\nExtracted Text: \(ocrText)"
            }
        }
        messages.append(.user(content: combinedPrompt))

        // Run the stream off the main actor; hop to main only for onChunk.
        let service = mistralService
        let model = config.model
        let requestMessages = messages
        let streamTask = Task.detached {
            let stream = try await service.streamingChatCompletionRequest(body: .init(
                messages: requestMessages,
                model: model
            ), secondsToWait: 60)

            for try await chunk in stream {
                try Task.checkCancellation()
                if let content = chunk.choices.first?.delta.content {
                    await onChunk(content)
                }
            }
        }
        activeTask = streamTask

        do {
            try await awaitForwardingCancellation(streamTask)
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            logger.error("Mistral streaming error (\(statusCode)): \(responseBody)")
            throw NSError(domain: "MistralAPI", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
        } catch {
            logger.error("Mistral streaming failed: \(error.localizedDescription)")
            throw error
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isProcessing = false
    }
}
