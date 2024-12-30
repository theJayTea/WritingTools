import Foundation

protocol AIProvider: ObservableObject {
    
    // Indicates if provider is processing a request
    var isProcessing: Bool { get set }
    
    // Process text with optional system prompt
    func processText(systemPrompt: String?, userPrompt: String) async throws -> String
    
    // Cancel ongoing requests
    func cancel()
}
