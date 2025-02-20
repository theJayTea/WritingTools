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

class OllamaProvider: ObservableObject, AIProvider {
    @Published var isProcessing = false
    private var config: OllamaConfig
    
    init(config: OllamaConfig) {
        self.config = config
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String, images: [Data] = []) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        // Construct the endpoint URL.
        guard let url = URL(string: "\(config.baseURL)/generate") else {
            throw NSError(domain: "OllamaAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL."])
        }
        
        // Build the request payload.
        var requestBody: [String: Any] = [
            "model": config.model,
            "prompt": userPrompt,
            "stream": false
        ]
        if let system = systemPrompt {
            requestBody["system"] = system
        }
        if let keepAlive = config.keepAlive, !keepAlive.isEmpty {
            requestBody["keep_alive"] = keepAlive
        }
        if !images.isEmpty {
            let base64Images = images.map { $0.base64EncodedString() }
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
