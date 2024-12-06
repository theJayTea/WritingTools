import Foundation

struct OpenAIConfig: Codable {
    var apiKey: String
    var baseURL: String
    var organization: String?
    var project: String?
    var model: String
    
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o"
}

enum OpenAIModel: String, CaseIterable {
    case gpt4 = "gpt-4"
    case gpt35Turbo = "gpt-3.5-turbo"
    case gpt4o = "gpt-4o"
    case gpt4oMini = "gpt-4o-mini"
    
    var displayName: String {
        switch self {
        case .gpt4: return "GPT-4 (Most Capable)"
        case .gpt35Turbo: return "GPT-3.5 Turbo (Faster)"
        case .gpt4o: return "GPT-4o (Optimized)"
        case .gpt4oMini: return "GPT-4o Mini (Lightweight)"
        }
    }
}

class OpenAIProvider: ObservableObject, AIProvider {
    @Published var isProcessing = false
    private var config: OpenAIConfig
    private var currentTask: URLSessionDataTask?
    
    init(config: OpenAIConfig) {
        self.config = config
    }
    
    func processText(systemPrompt: String? = "You are a helpful writing assistant.", userPrompt: String) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key is missing."])
        }
        
        let baseURL = config.baseURL.isEmpty ? OpenAIConfig.defaultBaseURL : config.baseURL
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL."])
        }
        
        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt ?? "You are a helpful writing assistant."],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.5
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        if let organization = config.organization, !organization.isEmpty {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            isProcessing = true
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server returned an error."])
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response."])
            }
            
            return content
            
        } catch {
            isProcessing = false
            throw NSError(domain: "OpenAIAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error processing text: \(error.localizedDescription)"])
        }
    }
    
    func cancel() {
        currentTask?.cancel()
        isProcessing = false
    }
}
