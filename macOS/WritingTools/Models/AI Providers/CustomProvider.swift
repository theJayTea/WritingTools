import Foundation
import Observation

private let logger = AppLogger.logger("CustomProvider")

struct CustomProviderConfig {
    let baseURL: String
    let apiKey: String
    let model: String
}

@Observable
final class CustomProvider: AIProvider {
    var isProcessing: Bool = false

    private let config: CustomProviderConfig
    private var currentTask: Task<Void, Never>?

    init(config: CustomProviderConfig) {
        self.config = config
    }

    func processText(systemPrompt: String?, userPrompt: String, images: [Data], streaming: Bool) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        logger.debug("CustomProvider: Starting request with baseURL=\(self.config.baseURL), model=\(self.config.model)")

        // Validate configuration
        guard !config.baseURL.isEmpty else {
            throw CustomProviderError.invalidConfiguration("Base URL is required")
        }

        guard !config.apiKey.isEmpty else {
            throw CustomProviderError.invalidConfiguration("API Key is required")
        }

        guard !config.model.isEmpty else {
            throw CustomProviderError.invalidConfiguration("Model is required")
        }

        // Prepare the URL
        guard var urlComponents = URLComponents(string: config.baseURL) else {
            throw CustomProviderError.invalidConfiguration("Invalid Base URL format")
        }

        // Ensure the path ends with /chat/completions if not already present
        if !urlComponents.path.hasSuffix("/chat/completions") {
            if urlComponents.path.isEmpty || urlComponents.path == "/" {
                urlComponents.path = "/v1/chat/completions"
            } else if !urlComponents.path.contains("/chat/completions") {
                urlComponents.path += "/chat/completions"
            }
        }

        guard let url = urlComponents.url else {
            throw CustomProviderError.invalidConfiguration("Could not construct valid URL")
        }

        logger.debug("CustomProvider: Using URL: \(url.absoluteString)")

        // Prepare the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        // Build messages array
        var messages: [[String: Any]] = []

        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            messages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        messages.append([
            "role": "user",
            "content": userPrompt
        ])

        // Prepare request body
        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 4096
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        logger.debug("CustomProvider: Sending request to \(url.absoluteString)")

        // Make the request
        let (data, response) = try await URLSession.shared.data(for: request)

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

        logger.debug("CustomProvider: Successfully extracted content (length: \(content.count))")
        return content
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isProcessing = false
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
