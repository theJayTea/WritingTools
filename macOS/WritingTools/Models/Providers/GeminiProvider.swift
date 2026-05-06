import Foundation
import AIProxy
import Observation

private let logger = AppLogger.logger("GeminiProvider")

struct GeminiConfig: Codable, Sendable {
    var apiKey: String
    var modelName: String
}

enum GeminiModel: String, CaseIterable {
    case gemmabig = "gemma-4-27b-it"
    case gemmasmall = "gemma-4-9b-it"
    case flashlite = "gemini-flash-lite-latest"
    case flash = "gemini-3-flash-preview"
    case pro = "gemini-3.1-pro-preview"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .gemmabig: return "Gemma 4 27B (Very Intelligent | unlimited)"
        case .gemmasmall: return "Gemma 4 9B (Intelligent | unlimited)"
        case .flashlite: return "Gemini Flash Lite Latest (Intelligent | ~20 uses/min)"
        case .flash: return "Gemini Flash 3 (Very Intelligent | ~20 uses/min)"
        case .pro: return "Gemini Pro 3.1 (Peak Intelligence | ~5 uses/min)"
        case .custom: return "Custom"
        }
    }
}

@MainActor
@Observable
final class GeminiProvider: AIProvider {
    var isProcessing = false
    private var config: GeminiConfig
    private var activeTask: Task<Void, any Error>?
    
    init(config: GeminiConfig) {
        self.config = config
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = [], streaming: Bool = false) async throws -> String {
        isProcessing = true
        defer {
            isProcessing = false
        }

        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }

        let geminiService = AIProxy.geminiDirectService(unprotectedAPIKey: config.apiKey)
        let finalPrompt = systemPrompt.map { "\($0)\n\n\(userPrompt)" } ?? userPrompt

        var parts: [GeminiGenerateContentRequestBody.Content.Part] = [.text(finalPrompt)]
        for imageData in images {
            parts.append(.inline(data: imageData, mimeType: detectImageMIMEType(imageData)))
        }

        let requestBody = GeminiGenerateContentRequestBody(
            contents: [.init(parts: parts)],
            safetySettings: [
                .init(category: .dangerousContent, threshold: .high),
                .init(category: .harassment, threshold: .high),
                .init(category: .hateSpeech, threshold: .high),
                .init(category: .sexuallyExplicit, threshold: .high),
                .init(category: .civicIntegrity, threshold: .high)
            ]
        )

        do {
            try Task.checkCancellation()
            let response = try await geminiService.generateContentRequest(body: requestBody, model: config.modelName, secondsToWait: 60)

            for part in response.candidates?.first?.content?.parts ?? [] {
                switch part {
                case .text(let text):
                    return text
                case .functionCall(name: let functionName, args: let arguments):
                    logger.debug("Function call received: \(functionName) with args: \(arguments ?? [:])")
                case .inlineData(mimeType: _, base64Data: _):
                    logger.debug("Image generation response part received")
                }
            }

            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No text content in response."])

        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            logger.error("AIProxy error (\(statusCode)): \(responseBody)")
            throw NSError(domain: "GeminiAPI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
        } catch {
            logger.error("Gemini request failed: \(error.localizedDescription)")
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
            throw NSError(domain: "GeminiAPI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }

        let geminiService = AIProxy.geminiDirectService(unprotectedAPIKey: config.apiKey)
        let finalPrompt = systemPrompt.map { "\($0)\n\n\(userPrompt)" } ?? userPrompt

        var parts: [GeminiGenerateContentRequestBody.Content.Part] = [.text(finalPrompt)]
        for imageData in images {
            parts.append(.inline(data: imageData, mimeType: detectImageMIMEType(imageData)))
        }

        let requestBody = GeminiGenerateContentRequestBody(
            contents: [.init(parts: parts)],
            safetySettings: [
                .init(category: .dangerousContent, threshold: .high),
                .init(category: .harassment, threshold: .high),
                .init(category: .hateSpeech, threshold: .high),
                .init(category: .sexuallyExplicit, threshold: .high),
                .init(category: .civicIntegrity, threshold: .high)
            ]
        )

        // Wrap work in a stored task so cancel() can interrupt it
        let streamTask = Task { @MainActor in
            let stream = try await geminiService.generateStreamingContentRequest(
                body: requestBody,
                model: config.modelName,
                secondsToWait: 60
            )
            for try await chunk in stream {
                try Task.checkCancellation()
                for part in chunk.candidates?.first?.content?.parts ?? [] {
                    if case .text(let text) = part {
                        onChunk(text)
                    }
                }
            }
        }
        activeTask = streamTask

        do {
            try await streamTask.value
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            logger.error("Gemini streaming error (\(statusCode)): \(responseBody)")
            throw NSError(domain: "GeminiAPI", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
        } catch {
            logger.error("Gemini streaming failed: \(error.localizedDescription)")
            throw error
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isProcessing = false
    }

    private func runWithCancellationRelay<T>(
        _ operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let operationTask = Task { @MainActor in
            try await operation()
        }
        activeTask = Task { [operationTask] in
            await withTaskCancellationHandler {
                _ = try? await operationTask.value
            } onCancel: {
                operationTask.cancel()
            }
        }

        do {
            let value = try await operationTask.value
            activeTask = nil
            return value
        } catch {
            activeTask = nil
            throw error
        }
    }
}
