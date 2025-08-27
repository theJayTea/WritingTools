import Foundation
import Combine

struct OllamaConfig: Codable {
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

private struct GenerateChunk: Decodable {
    let response: String?
    let done: Bool?
    let error: String?
}

@MainActor
final class OllamaProvider: ObservableObject, AIProvider {
    @Published var isProcessing = false
    private var config: OllamaConfig
    private var imageMode: OllamaImageMode { AppSettings.shared.ollamaImageMode }

    init(config: OllamaConfig) {
        self.config = config
    }

    // MARK: - Public

    func processText(
        systemPrompt: String? = "You are a helpful writing assistant.",
        userPrompt: String,
        images: [Data] = [],
        streaming: Bool = false
    ) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }

        // 1) Build prompt + image policy (OCR vs Ollama)
        var combinedPrompt = userPrompt
        var imagesForOllama: [String] = []

        if !images.isEmpty {
            switch imageMode {
            case .ocr:
                let ocrText = await OCRManager.shared.extractText(from: images)
                if !ocrText.isEmpty {
                    combinedPrompt += "\nExtracted Text: \(ocrText)"
                }
            case .ollama:
                imagesForOllama = images.map { $0.base64EncodedString() }
            }
        }

        // 2) Construct URL against normalized /api base
        guard let url = makeEndpointURL("/generate") else {
            throw makeClientError("Invalid base URL '\(config.baseURL)'. Expected like http://localhost:11434 or http://localhost:11434/api")
        }

        // 3) Encode request
        var body: [String: Any] = [
            "model": config.model,
            "prompt": combinedPrompt,
            "stream": streaming  // honor caller
        ]
        if let system = systemPrompt { body["system"] = system }
        if let keepAlive = config.keepAlive, !keepAlive.isEmpty { body["keep_alive"] = keepAlive }
        if !imagesForOllama.isEmpty { body["images"] = imagesForOllama }

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // 4) Call API (streaming vs non-streaming per Ollama docs)
        if streaming {
            return try await performStreaming(request)
        } else {
            return try await performOneShot(request)
        }
    }

    func cancel() {
        // No in-flight task handle stored yet; keep UI flag correct.
        isProcessing = false
    }

    // MARK: - Networking

    private func performOneShot(_ request: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw makeClientError("Invalid response from server.")
        }

        // Surface server-side errors with payload if present
        guard http.statusCode == 200 else {
            let message = decodeServerError(from: data)
            throw makeServerError(http.statusCode, message)
        }

        // Non-stream: one JSON object containing the full `response`
        // per /api/generate "Request (No streaming)" docs.
        // https://ollama.readthedocs.io → API → Generate (stream=false)
        let obj = try JSONDecoder().decode(GenerateChunk.self, from: data)
        if let err = obj.error, !err.isEmpty {
            throw makeServerError(http.statusCode, err)
        }
        guard let text = obj.response else {
            throw makeClientError("Failed to parse response.")
        }
        return text
    }

    private func performStreaming(_ request: URLRequest) async throws -> String {
        var aggregate = ""
        let (stream, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw makeClientError("Invalid response from server.")
        }

        if http.statusCode != 200 {
            var data = Data()
            for try await byte in stream {
                data.append(byte)              // <-- FIX: append single UInt8
                // or: data.append(contentsOf: [byte])
            }
            let message = decodeServerError(from: data)
            throw makeServerError(http.statusCode, message)
        }

        for try await line in stream.lines {
            guard let data = line.data(using: .utf8) else { continue }
            if let chunk = try? JSONDecoder().decode(GenerateChunk.self, from: data) {
                if let t = chunk.response { aggregate += t }
                if chunk.done == true { break }
                if let err = chunk.error, !err.isEmpty {
                    throw makeServerError(500, err)
                }
            }
        }
        return aggregate
    }


    // MARK: - Utilities

    /// Accepts either "...:11434" or "...:11434/api" and returns a URL for "/api{path}".
    private func makeEndpointURL(_ path: String) -> URL? {
        let trimmed = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let noSlash = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let root: String = noSlash.hasSuffix("api") ? String(noSlash.dropLast(3)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : noSlash
        let full = root + "/api" + path
        return URL(string: full)
    }

    private func decodeServerError(from data: Data) -> String {
        if let obj = try? JSONDecoder().decode(GenerateChunk.self, from: data), let err = obj.error, !err.isEmpty {
            return err
        }
        return String(data: data, encoding: .utf8) ?? "Unknown server error."
    }

    private func makeClientError(_ message: String) -> NSError {
        NSError(domain: "OllamaClient", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func makeServerError(_ code: Int, _ message: String) -> NSError {
        let hint: String
        if message.localizedCaseInsensitiveContains("image") && !message.localizedCaseInsensitiveContains("tool") {
            hint = "\nHint: The selected model may not support images. Try OCR mode or a vision model like 'llava'."
        } else {
            hint = ""
        }
        return NSError(domain: "OllamaAPI", code: code, userInfo: [NSLocalizedDescriptionKey: "\(message)\(hint)"])
    }
}
