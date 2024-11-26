import Foundation

struct GeminiConfig: Codable {
    var apiKey: String
    var modelName: String
}

enum GeminiModel: String, CaseIterable {
    case flash8b = "gemini-1.5-flash-8b-latest"
    case flash = "gemini-1.5-flash-latest"
    case pro = "gemini-1.5-pro-latest"
    
    var displayName: String {
        switch self {
        case .flash8b: return "Gemini 1.5 Flash 8B (fast)"
        case .flash: return "Gemini 1.5 Flash (fast & more intelligent, recommended)"
        case .pro: return "Gemini 1.5 Pro (very intelligent, but slower & lower rate limit)"
        }
    }
}

class GeminiProvider: ObservableObject {
    @Published var isProcessing = false
    private var config: GeminiConfig
    private var currentTask: URLSessionDataTask?
    
    init(config: GeminiConfig) {
        self.config = config
    }
    
    func processText(userPrompt: String) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }
        
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(config.modelName):generateContent?key=\(config.apiKey)") else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL."])
        }
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": userPrompt]
                    ]
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: .fragmentsAllowed)
        
        do {
            isProcessing = true
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Check for valid HTTP response
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server returned an error."])
            }
            
            // Parse and handle JSON response
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response."])
            }
            
            // Extract candidates
            guard let candidates = json["candidates"] as? [[String: Any]], !candidates.isEmpty else {
                throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No candidates found in the response."])
            }
            
            // Navigate to content -> parts -> text
            if let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text
            }
            
            // Fallback if no useful data is found
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid content in response."])
        } catch {
            isProcessing = false
            print("Error processing JSON: \(error.localizedDescription)")
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error processing text: \(error.localizedDescription)"])
        }
    }
    
    func cancel() {
        currentTask?.cancel()
        isProcessing = false
    }
}
