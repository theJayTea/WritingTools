import Foundation

protocol AIProvider: ObservableObject {
    var isProcessing: Bool { get set }
    func processText(systemPrompt: String?, userPrompt: String) async throws -> String
    func cancel()
}
