import Foundation
import Combine

struct OllamaConfig: Codable {
    var baseURL: String
    var model: String
    var keepAlive: String? // e.g. "5m", "0" (immediate unload), "-1" (always loaded)
    
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

@MainActor
class OllamaProvider: ObservableObject, AIProvider {
    @Published var isProcessing = false
    private var config: OllamaConfig
    
    // ADD: Image mode settings reference
    private var imageMode: OllamaImageMode { AppSettings.shared.ollamaImageMode }

    init(config: OllamaConfig) {
        self.config = config
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = [], streaming: Bool = false) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        // Determine if we are using OCR or Ollama's own image-recognition
        var combinedPrompt = userPrompt
        var imagesForOllama: [Data] = []

        if !images.isEmpty {
            switch imageMode {
            case .ocr:
                let ocrText = await OCRManager.shared.extractText(from: images)
                if !ocrText.isEmpty {
                    combinedPrompt += "\nExtracted Text: \(ocrText)"
                }
                // Do NOT send images to Ollama
            case .ollama:
                imagesForOllama = images // Pass images as base64 to Ollama API
            }
        }
        
        // Construct the endpoint URL.
        guard let url = URL(string: "\(config.baseURL)/generate") else {
            throw NSError(domain: "OllamaAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL."])
        }
        
        // Build the request payload.
        var requestBody: [String: Any] = [
            "model": config.model,
            "prompt": combinedPrompt,
            "stream": false
        ]
        if let system = systemPrompt {
            requestBody["system"] = system
        }
        if let keepAlive = config.keepAlive, !keepAlive.isEmpty {
            requestBody["keep_alive"] = keepAlive
        }
        
        // Only add images to payload if in .ollama image mode
        if !imagesForOllama.isEmpty {
            let base64Images = imagesForOllama.map { $0.base64EncodedString() }
            requestBody["images"] = base64Images
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Perform the network call.
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OllamaAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server."])
        }
        
        guard httpResponse.statusCode == 200 else {
            // Capture server error message from the response body (if any)
            let serverMessage = String(data: data, encoding: .utf8) ?? "No additional error info."
            throw NSError(domain: "OllamaAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned an error: \(serverMessage)"])
        }
        
        // Parse the JSON response.
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw NSError(domain: "OllamaAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response."])
        }
        
        return responseText
    }
    
    func cancel() {
        // For a more advanced implementation you might store a URLSessionTask to cancel.
        isProcessing = false
    }
}
