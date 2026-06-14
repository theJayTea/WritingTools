import Foundation
import Observation

private let logger = AppLogger.logger("CustomProvider")

struct CustomProviderConfig: Sendable {
    let baseURL: String
    let apiKey: String
    let model: String
}

@Observable
@MainActor
final class CustomProvider: AIProvider {
    var isProcessing: Bool = false

    private let config: CustomProviderConfig
    private var activeTask: Task<Void, any Error>?

    init(config: CustomProviderConfig) {
        self.config = config
    }

    func processText(systemPrompt: String?, userPrompt: String, images: [Data]) async throws -> String {
        isProcessing = true
        defer {
            isProcessing = false
        }

        try Task.checkCancellation()
        return try await Self.performRequest(config: config, systemPrompt: systemPrompt, userPrompt: userPrompt, images: images)
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

        let config = self.config
        let url = try Self.buildEndpointURL(from: config)
        let messages = Self.buildMessages(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images)

        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 4096,
            "stream": true
        ]

        var requestBuilder = URLRequest(url: url)
        requestBuilder.httpMethod = "POST"
        requestBuilder.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requestBuilder.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        requestBuilder.timeoutInterval = 60
        requestBuilder.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        let request = requestBuilder

        // Run the stream off the main actor; hop to main only for onChunk.
        let streamTask = Task.detached {
            let (stream, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CustomProviderError.networkError("Invalid response from server")
            }
            guard (200...299).contains(http.statusCode) else {
                var data = Data()
                for try await byte in stream { data.append(byte) }
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    throw CustomProviderError.apiError("API Error (\(http.statusCode)): \(message)")
                }
                throw CustomProviderError.apiError("API Error: HTTP \(http.statusCode)")
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
                await onChunk(content)
            }
        }
        activeTask = streamTask

        try await awaitForwardingCancellation(streamTask)
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isProcessing = false
    }

    /// Validates the provider config and builds the chat completions endpoint URL.
    nonisolated private static func buildEndpointURL(from config: CustomProviderConfig) throws -> URL {
        guard !config.baseURL.isEmpty else {
            throw CustomProviderError.invalidConfiguration("Base URL is required")
        }
        guard !config.apiKey.isEmpty else {
            throw CustomProviderError.invalidConfiguration("API Key is required")
        }
        guard !config.model.isEmpty else {
            throw CustomProviderError.invalidConfiguration("Model is required")
        }

        guard var urlComponents = URLComponents(string: config.baseURL) else {
            throw CustomProviderError.invalidConfiguration("Invalid Base URL format")
        }
        if !urlComponents.path.hasSuffix("/chat/completions") {
            if urlComponents.path.isEmpty || urlComponents.path == "/" {
                urlComponents.path = "/v1/chat/completions"
            } else if !urlComponents.path.contains("/chat/completions") {
                // Strip trailing slash to avoid double-slash (e.g. "/v1/" + "/chat/completions")
                if urlComponents.path.hasSuffix("/") {
                    urlComponents.path = String(urlComponents.path.dropLast())
                }
                urlComponents.path += "/chat/completions"
            }
        }
        guard let url = urlComponents.url else {
            throw CustomProviderError.invalidConfiguration("Could not construct valid URL")
        }
        return url
    }

    /// Builds the messages array for an OpenAI-compatible chat request.
    nonisolated private static func buildMessages(
        systemPrompt: String?,
        userPrompt: String,
        images: [Data]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        if !images.isEmpty {
            var contentParts: [[String: Any]] = [
                ["type": "text", "text": userPrompt]
            ]
            for imageData in images {
                let base64 = imageData.base64EncodedString()
                let mimeType = detectImageMIMEType(imageData)
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(mimeType);base64,\(base64)"]
                ])
            }
            messages.append(["role": "user", "content": contentParts])
        } else {
            messages.append(["role": "user", "content": userPrompt])
        }
        return messages
    }

    nonisolated private static func performRequest(
        config: CustomProviderConfig,
        systemPrompt: String?,
        userPrompt: String,
        images: [Data] = []
    ) async throws -> String {
        logger.debug("CustomProvider: Starting request with baseURL=\(config.baseURL), model=\(config.model)")

        let url = try buildEndpointURL(from: config)
        logger.debug("CustomProvider: Using URL: \(url.absoluteString)")

        var requestBuilder = URLRequest(url: url)
        requestBuilder.httpMethod = "POST"
        requestBuilder.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requestBuilder.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        requestBuilder.timeoutInterval = 60

        let messages = buildMessages(systemPrompt: systemPrompt, userPrompt: userPrompt, images: images)
        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 4096
        ]

        requestBuilder.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Capture as immutable value for Swift 6 concurrency
        let request = requestBuilder

        logger.debug("CustomProvider: Sending request to \(url.absoluteString)")

        // Make the request with retry for transient failures
        let (data, response) = try await withRetry(config: .default) {
            try await URLSession.shared.data(for: request)
        }

        try Task.checkCancellation()
        logger.debug("CustomProvider: Received response")

        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CustomProviderError.networkError("Invalid response from server")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to parse error message from response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw CustomProviderError.apiError("API Error (\(httpResponse.statusCode)): \(message)")
            }
            throw CustomProviderError.apiError("API Error: HTTP \(httpResponse.statusCode)")
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            logger.error("CustomProvider: Failed to parse JSON. Response: \(responseString)")
            throw CustomProviderError.invalidResponse("Could not parse JSON response from API")
        }

        guard let choices = json["choices"] as? [[String: Any]] else {
            logger.error("CustomProvider: No 'choices' array in response")
            throw CustomProviderError.invalidResponse("Response missing 'choices' array")
        }

        guard let firstChoice = choices.first else {
            logger.error("CustomProvider: 'choices' array is empty")
            throw CustomProviderError.invalidResponse("'choices' array is empty")
        }

        guard let message = firstChoice["message"] as? [String: Any] else {
            logger.error("CustomProvider: No 'message' object in first choice")
            throw CustomProviderError.invalidResponse("First choice missing 'message' object")
        }

        guard let content = message["content"] as? String else {
            logger.error("CustomProvider: No 'content' string in message")
            throw CustomProviderError.invalidResponse("Message missing 'content' string")
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.error("CustomProvider: 'content' string is empty")
            throw CustomProviderError.invalidResponse("Response contained no text content")
        }

        logger.debug("CustomProvider: Successfully extracted content (length: \(content.count))")
        return content
    }
}

enum CustomProviderError: LocalizedError {
    case invalidConfiguration(String)
    case networkError(String)
    case apiError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Configuration Error: \(message)"
        case .networkError(let message):
            return "Network Error: \(message)"
        case .apiError(let message):
            return message
        case .invalidResponse(let message):
            return "Response Error: \(message)"
        }
    }
}
