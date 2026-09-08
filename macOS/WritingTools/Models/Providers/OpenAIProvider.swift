import Foundation
import AIProxy
import Observation

private let logger = AppLogger.logger("OpenAIProvider")

struct OpenAIConfig: Codable, Sendable {
    var apiKey: String
    var baseURL: String
    var model: String
    
    static let defaultBaseURL = "https://api.openai.com"
    static let defaultModel = "gpt-5.2"
}

enum OpenAIModel: String, CaseIterable {
    case gpt4_1 = "gpt-4.1"
    case gpt5 = "gpt-5.2"
    case gpt5Mini = "gpt-5-mini"
    
    var displayName: String {
        switch self {
        case .gpt4_1: return "GPT-4.1 (Older Model)"
        case .gpt5: return "GPT-5.2 (Most Capable)"
        case .gpt5Mini: return "GPT-5 Mini (Lightweight)"
        }
    }
}

@MainActor
@Observable
final class OpenAIProvider: AIProvider {
    var isProcessing = false
    private var config: OpenAIConfig
    private var activeTask: Task<Void, any Error>?
    
    init(config: OpenAIConfig) {
        self.config = config
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = [], streaming: Bool = false) async throws -> String {
        isProcessing = true
        defer {
            isProcessing = false
        }

        // Check for custom Base URL
        if !config.baseURL.isEmpty && config.baseURL != OpenAIConfig.defaultBaseURL {
            return try await Self.performCustomOpenAIRequest(config: config, systemPrompt: systemPrompt, userPrompt: userPrompt, images: images)
        }

        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }

        let baseURL = config.baseURL.isEmpty ? OpenAIConfig.defaultBaseURL : config.baseURL
        let openAIService = AIProxy.openAIDirectService(
            unprotectedAPIKey: config.apiKey,
            baseURL: baseURL
        )

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
                let mimeType = detectImageMIMEType(imageData)
                let dataString = "data:\(mimeType);base64," + imageData.base64EncodedString()
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
                    try Task.checkCancellation()
                    if let content = chunk.choices.first?.delta.content {
                        compiledResponse += content
                    }
                }
                return compiledResponse

            } else {
                try Task.checkCancellation()
                let requestMessages = messages
                let response = try await withRetry {
                    try await openAIService.chatCompletionRequest(body: .init(
                        model: config.model,
                        messages: requestMessages
                    ), secondsToWait: 60)
                }

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
    
    private static func performCustomOpenAIRequest(config: OpenAIConfig, systemPrompt: String?, userPrompt: String, images: [Data]) async throws -> String {
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
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
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
                let mimeType = detectImageMIMEType(imageData)
                content.append([
                    "type": "image_url",
                    "image_url": [
                        "url": "data:\(mimeType);base64,\(base64)"
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

    
    // MARK: - Custom Streaming Request Implementation
    
    private static func performCustomOpenAIStreamingRequest(
        config: OpenAIConfig,
        systemPrompt: String?,
        userPrompt: String,
        images: [Data],
        onChunk: @escaping @Sendable @MainActor (String) -> Void
    ) async throws {
        var urlString = config.baseURL
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        if !urlString.hasSuffix("/chat/completions") {
            urlString += "/chat/completions"
        }
        
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Base URL."])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        
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
                let mimeType = detectImageMIMEType(imageData)
                content.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(mimeType);base64,\(base64)"]
                ])
            }
            messages.append(["role": "user", "content": content])
        }
        
        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": true
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (stream, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type."])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            var data = Data()
            for try await byte in stream { data.append(byte) }
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Custom OpenAI Streaming Request Failed: \(httpResponse.statusCode) - \(errorBody)")
            throw NSError(domain: "OpenAIAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error: \(errorBody)"])
        }
        
        for try await line in stream.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            if jsonStr.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            onChunk(content)
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isProcessing = false
    }
    
    // MARK: - Streaming Implementation
    
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
        
        // For custom base URLs, use manual SSE streaming
        if !config.baseURL.isEmpty && config.baseURL != OpenAIConfig.defaultBaseURL {
            let config = self.config
            let streamTask = Task { @MainActor in
                try await Self.performCustomOpenAIStreamingRequest(
                    config: config,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    images: images,
                    onChunk: onChunk
                )
            }
            activeTask = streamTask
            try await streamTask.value
            return
        }

        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }
        
        let baseURL = config.baseURL.isEmpty ? OpenAIConfig.defaultBaseURL : config.baseURL
        let openAIService = AIProxy.openAIDirectService(
            unprotectedAPIKey: config.apiKey,
            baseURL: baseURL
        )
        
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
                let mimeType = detectImageMIMEType(imageData)
                let dataString = "data:\(mimeType);base64," + imageData.base64EncodedString()
                if let dataURL = URL(string: dataString) {
                    parts.append(.imageURL(dataURL, detail: .auto))
                }
            }
            
            messages.append(.user(content: .parts(parts)))
        }
        
        // Wrap work in a stored task so cancel() can interrupt it
        let streamTask = Task { @MainActor in
            let stream = try await openAIService.streamingChatCompletionRequest(body: .init(
                model: config.model,
                messages: messages
            ), secondsToWait: 60)
            
            for try await chunk in stream {
                try Task.checkCancellation()
                if let content = chunk.choices.first?.delta.content {
                    onChunk(content)
                }
            }
        }
        activeTask = streamTask
        
        do {
            try await streamTask.value
        } catch AIProxyError.unsuccessfulRequest(let statusCode, let responseBody) {
            logger.error("Received non-200 status code: \(statusCode) with response body: \(responseBody)")
            throw NSError(domain: "OpenAIAPI",
                          code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "API error: \(responseBody)"])
        } catch {
            logger.error("Could not create OpenAI streaming chat completion: \(error.localizedDescription)")
            throw error
        }
    }
}
