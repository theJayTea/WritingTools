import Foundation
import AIProxy
import Observation

private let logger = AppLogger.logger("AnthropicProvider")

struct AnthropicConfig: Codable, Sendable {
    var apiKey: String
    var model: String
    
    static let defaultModel = "claude-sonnet-4-6"
}

enum AnthropicModel: String, CaseIterable {
    case claude45Haiku = "claude-haiku-4-5"
    case claude46Sonnet = "claude-sonnet-4-6"
    case claude46Opus = "claude-opus-4-6"
    case custom

    var displayName: String {
        switch self {
        case .claude45Haiku: return "Claude 4.5 Haiku (Fastest, Most Affordable)"
        case .claude46Sonnet: return "Claude 4.6 Sonnet (Best Coding Model)"
        case .claude46Opus: return "Claude 4.6 Opus (Most Capable, Expensive)"
        case .custom: return "Custom"
        }
    }
}

@MainActor
@Observable
final class AnthropicProvider: AIProvider {
    var isProcessing = false
    
    private var config: AnthropicConfig
    private var activeTask: Task<Void, any Error>?
    
    init(config: AnthropicConfig) {
        self.config = config
    }
    
    func processText(
        systemPrompt: String? = "You are a helpful writing assistant.",
        userPrompt: String,
        images: [Data] = []
    ) async throws -> String {
        isProcessing = true
        defer {
            isProcessing = false
        }

        guard !config.apiKey.isEmpty else {
            throw NSError(
                domain: "AnthropicAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "API key is missing."]
            )
        }

        let anthropicService = AIProxy.anthropicDirectService(unprotectedAPIKey: config.apiKey)
        let selectedModel = config.model.isEmpty ? AnthropicConfig.defaultModel : config.model

        var contentBlocks: [AnthropicContentBlockParam] = [
            .textBlock(.init(text: userPrompt))
        ]
        for imageData in images {
            let source = AnthropicImageBlockParamSource.base64(
                data: imageData.base64EncodedString(),
                mediaType: detectAnthropicMediaType(imageData)
            )
            contentBlocks.append(.imageBlock(.init(source: source)))
        }

        let messages: [AnthropicMessageParam] = [
            AnthropicMessageParam(
                content: .blocks(contentBlocks),
                role: .user
            )
        ]

        let requestBody = AnthropicMessageRequestBody(
            maxTokens: 10000,
            messages: messages,
            model: selectedModel,
            system: systemPrompt.map(AnthropicSystemPrompt.text)
        )

        do {
            try Task.checkCancellation()
            let response = try await withRetry {
                try await anthropicService.messageRequest(
                    body: requestBody,
                    secondsToWait: 60
                )
            }
            var compiledResponse = ""

            for content in response.content {
                switch content {
                case .textBlock(let textBlock):
                    compiledResponse += textBlock.text
                case .toolUseBlock(let toolUseBlock):
                    logger.debug("Anthropic tool use: \(toolUseBlock.name) input: \(toolUseBlock.input)")
                case .serverToolUseBlock(let serverToolUseBlock):
                    logger.debug("Anthropic server tool use: \(serverToolUseBlock.name) input: \(serverToolUseBlock.input)")
                case .thinkingBlock, .redactedThinkingBlock, .webSearchToolResultBlock, .futureProof:
                    continue
                }
            }

            if !compiledResponse.isEmpty {
                return compiledResponse
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
            throw NSError(domain: "AnthropicAPI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }

        let anthropicService = AIProxy.anthropicDirectService(unprotectedAPIKey: config.apiKey)
        let selectedModel = config.model.isEmpty ? AnthropicConfig.defaultModel : config.model

        var contentBlocks: [AnthropicContentBlockParam] = [
            .textBlock(.init(text: userPrompt))
        ]
        for imageData in images {
            let source = AnthropicImageBlockParamSource.base64(
                data: imageData.base64EncodedString(),
                mediaType: detectAnthropicMediaType(imageData)
            )
            contentBlocks.append(.imageBlock(.init(source: source)))
        }

        let requestBody = AnthropicMessageRequestBody(
            maxTokens: 10000,
            messages: [AnthropicMessageParam(content: .blocks(contentBlocks), role: .user)],
            model: selectedModel,
            system: systemPrompt.map(AnthropicSystemPrompt.text)
        )

        // Run the stream off the main actor (decode work stays off the UI
        // thread); hop to the main actor only to deliver each chunk.
        let service = anthropicService
        let body = requestBody
        let streamTask = Task.detached {
            let stream = try await service.streamingMessageRequest(
                body: body,
                secondsToWait: 60
            )
            for try await event in stream {
                try Task.checkCancellation()
                guard case let .contentBlockDelta(contentBlockDelta) = event else { continue }
                switch contentBlockDelta.delta {
                case .textDelta(let textDelta):
                    await onChunk(textDelta.text)
                case .inputJSONDelta, .citationsDelta, .thinkingDelta, .signatureDelta, .futureProof:
                    continue
                }
            }
        }
        activeTask = streamTask

        do {
            try await awaitForwardingCancellation(streamTask)
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            logger.error("Anthropic streaming error (\(statusCode)): \(responseBody)")
            throw NSError(domain: "AnthropicAPI", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
        } catch {
            logger.error("Anthropic streaming failed: \(error.localizedDescription)")
            throw error
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isProcessing = false
    }
}
