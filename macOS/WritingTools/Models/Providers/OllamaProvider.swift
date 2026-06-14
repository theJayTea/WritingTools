import Foundation
import Observation

private let logger = AppLogger.logger("OllamaProvider")

struct OllamaConfig: Codable, Sendable {
    var baseURL: String         // Accepts either "http://host:11434" or ".../api"
    var model: String
    var keepAlive: String?      // e.g. "5m", "0", "-1"

    // Keep your existing defaults; we normalize below
    static let defaultBaseURL = "http://localhost:11434/api"
    static let defaultModel = "llama3.2"
    static let defaultKeepAlive = "5m"
}

enum OllamaImageMode: String, CaseIterable, Identifiable {
    case ocr
    case ollama

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ocr: return "OCR (Apple Vision)"
        case .ollama: return "Ollama Image Recognition"
        }
    }
}

/// Response chunk from the Ollama `/api/chat` endpoint.
private struct ChatChunk: Decodable {
    struct Message: Decodable {
        let role: String?
        let content: String?
    }
    let message: Message?
    let done: Bool?
    let error: String?
}

/// Legacy `/api/generate` chunk kept only for `decodeServerError`.
private struct GenerateChunk: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

@MainActor
@Observable
final class OllamaProvider: AIProvider {
    var isProcessing = false
    private var config: OllamaConfig
    private var activeTask: Task<Void, any Error>?

    init(config: OllamaConfig) {
        self.config = config
    }

    // MARK: - Public

    func processText(
        systemPrompt: String? = "You are a helpful writing assistant.",
        userPrompt: String,
        images: [Data] = []
    ) async throws -> String {
        isProcessing = true
        defer {
            isProcessing = false
        }

        let imageMode = AppSettings.shared.ollamaImageMode

        // 1) Build the messages array for the chat endpoint
        var messages: [[String: Any]] = []

        // System message
        if let system = systemPrompt, !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(["role": "system", "content": system])
        }

        // User message
        var userContent = userPrompt
        var imagesForOllama: [String] = []

        if !images.isEmpty {
            switch imageMode {
            case .ocr:
                let ocrText = try await OCRManager.shared.extractText(from: images)
                if !ocrText.isEmpty {
                    userContent += "\n\nExtracted Text: \(ocrText)"
                }
            case .ollama:
                imagesForOllama = images.map { $0.base64EncodedString() }
            }
        }

        var userMessage: [String: Any] = ["role": "user", "content": userContent]
        if !imagesForOllama.isEmpty {
            userMessage["images"] = imagesForOllama
        }
        messages.append(userMessage)

        // 2) Construct URL
        guard let url = Self.makeEndpointURL(config.baseURL, path: "/chat") else {
            throw Self.makeClientError("Invalid base URL '\(config.baseURL)'. Expected like http://localhost:11434 or http://localhost:11434/api")
        }

        // 3) Build request body using the chat messages format
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": false
        ]
        if let keepAlive = config.keepAlive, !keepAlive.isEmpty {
            body["keep_alive"] = keepAlive
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var requestBuilder = URLRequest(url: url)
        requestBuilder.httpMethod = "POST"
        requestBuilder.httpBody = jsonData
        requestBuilder.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requestBuilder.setValue("application/json", forHTTPHeaderField: "Accept")
        requestBuilder.timeoutInterval = 60

        // Capture as immutable value for Swift 6 concurrency
        let request = requestBuilder

        // 4) Execute request with retry for transient failures
        return try await withRetry(config: .default) {
            try Task.checkCancellation()
            return try await Self.performOneShot(request)
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

        let imageMode = AppSettings.shared.ollamaImageMode

        var messages: [[String: Any]] = []

        if let system = systemPrompt, !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(["role": "system", "content": system])
        }

        var userContent = userPrompt
        var imagesForOllama: [String] = []
        if !images.isEmpty {
            switch imageMode {
            case .ocr:
                let ocrText = try await OCRManager.shared.extractText(from: images)
                if !ocrText.isEmpty {
                    userContent += "\n\nExtracted Text: \(ocrText)"
                }
            case .ollama:
                imagesForOllama = images.map { $0.base64EncodedString() }
            }
        }

        var userMessage: [String: Any] = ["role": "user", "content": userContent]
        if !imagesForOllama.isEmpty {
            userMessage["images"] = imagesForOllama
        }
        messages.append(userMessage)

        guard let url = Self.makeEndpointURL(config.baseURL, path: "/chat") else {
            throw Self.makeClientError("Invalid base URL '\(config.baseURL)'.")
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "stream": true
        ]
        if let keepAlive = config.keepAlive, !keepAlive.isEmpty {
            body["keep_alive"] = keepAlive
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var requestBuilder = URLRequest(url: url)
        requestBuilder.httpMethod = "POST"
        requestBuilder.httpBody = jsonData
        requestBuilder.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requestBuilder.setValue("application/json", forHTTPHeaderField: "Accept")
        requestBuilder.timeoutInterval = 60
        let request = requestBuilder

        // Run the stream off the main actor; hop to main only for onChunk.
        let streamTask = Task.detached {
            let (stream, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw Self.makeClientError("Invalid response from server.")
            }

            if http.statusCode != 200 {
                var data = Data()
                for try await byte in stream { data.append(byte) }
                let message = Self.decodeServerError(from: data)
                throw Self.makeServerError(http.statusCode, message)
            }

            for try await line in stream.lines {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8) else { continue }
                if let chunk = try? JSONDecoder().decode(ChatChunk.self, from: data) {
                    if let t = chunk.message?.content {
                        await onChunk(t)
                    }
                    if chunk.done == true { break }
                    if let err = chunk.error, !err.isEmpty {
                        throw Self.makeServerError(500, err)
                    }
                }
            }
        }
        activeTask = streamTask

        // Mirror the error handling of the other providers: surface a clean,
        // logged error rather than letting a raw transport NSError escape.
        do {
            try await awaitForwardingCancellation(streamTask)
        } catch is CancellationError {
            // User cancelled; not an error worth surfacing.
            throw CancellationError()
        } catch {
            logger.error("Ollama streaming request failed: \(error.localizedDescription)")
            throw error
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isProcessing = false
    }

    // MARK: - Networking

    nonisolated private static func performOneShot(_ request: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw makeClientError("Invalid response from server.")
        }

        guard http.statusCode == 200 else {
            let message = decodeServerError(from: data)
            throw makeServerError(http.statusCode, message)
        }

        let obj = try JSONDecoder().decode(ChatChunk.self, from: data)
        if let err = obj.error, !err.isEmpty {
            throw makeServerError(http.statusCode, err)
        }
        guard let text = obj.message?.content else {
            throw makeClientError("Failed to parse response.")
        }
        return text
    }

    // MARK: - Utilities

    nonisolated private static func makeEndpointURL(_ baseURL: String, path: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed) else { return nil }

        // Normalize the path: strip trailing slashes, strip "/api" suffix if present,
        // then append "/api" + the requested path consistently.
        var basePath = components.path
        while basePath.hasSuffix("/") {
            basePath = String(basePath.dropLast())
        }
        // Only strip "/api" when it's a complete path segment (preceded by "/" or is the entire path)
        if basePath.lowercased().hasSuffix("/api") {
            basePath = String(basePath.dropLast(4))
        } else if basePath.lowercased() == "api" {
            basePath = ""
        }
        while basePath.hasSuffix("/") {
            basePath = String(basePath.dropLast())
        }

        components.path = basePath + "/api" + path
        return components.url
    }

    nonisolated private static func decodeServerError(from data: Data) -> String {
        if let obj = try? JSONDecoder().decode(ChatChunk.self, from: data),
           let err = obj.error, !err.isEmpty {
            return err
        }
        if let obj = try? JSONDecoder().decode(GenerateChunk.self, from: data),
           let err = obj.error, !err.isEmpty {
            return err
        }
        return String(data: data, encoding: .utf8) ?? "Unknown server error."
    }

    nonisolated private static func makeClientError(_ message: String) -> NSError {
        NSError(domain: "OllamaClient", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    nonisolated private static func makeServerError(_ code: Int, _ message: String) -> NSError {
        let hint: String
        if message.localizedCaseInsensitiveContains("image") && !message.localizedCaseInsensitiveContains("tool") {
            hint = "\nHint: The selected model may not support images. Try OCR mode or a vision model like 'llava'."
        } else {
            hint = ""
        }
        return NSError(domain: "OllamaAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "\(message)\(hint)"])
    }
}
