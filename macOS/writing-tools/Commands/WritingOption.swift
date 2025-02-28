import SwiftUI

enum WritingOption: String, CaseIterable, Identifiable {
    case proofread = "Proofread"
    case rewrite = "Rewrite"
    case friendly = "Friendly"
    case professional = "Professional"
    case concise = "Concise"
    case summary = "Summary"
    case keyPoints = "Key Points"
    case table = "Table"
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .proofread:
            return String(localized:"Proofread", comment: "ID for proofreading")
        case .rewrite:
            return String(localized:"Rewrite", comment: "ID for rewriting")
        case .friendly:
            return String(localized:"Friendly", comment: "ID for friendly tone")
        case .professional:
            return String(localized:"Professional", comment: "ID for professional tone")
        case .concise:
            return String(localized:"Concise", comment: "ID for concise tone")
        case .summary:
            return String(localized:"Summary", comment: "ID for summarization")
        case .keyPoints:
            return String(localized:"Key Points", comment: "ID for key points extraction")
        case .table:
            return String(localized:"Table", comment: "ID for table conversion")
        }
    }
        
    var systemPrompt: String {
        switch self {
        case .proofread:
            return """
                You are a grammar proofreading assistant. Output ONLY the corrected text without any additional comments. Maintain the original text structure and writing style. Always respond in the same language as the input text. If the text is completely incompatible (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".
                """
        case .rewrite:
            return """
                You are a writing assistant. Rewrite the text provided by the user to improve phrasing. Output ONLY the rewritten text without additional comments. Always respond in the same language as the input text. If the text is completely incompatible (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".
                """
        case .friendly:
            return """
                You are a writing assistant. Rewrite the text provided by the user to make it more friendly. Output ONLY the friendly version without additional comments. Always respond in the same language as the input text. If the text is completely incompatible (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".
                """
        case .professional:
            return """
                You are a writing assistant. Rewrite the text provided by the user to make it sound more professional. Output ONLY the professional version without additional comments. Always respond in the same language as the input text. If the text is completely incompatible (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".
                """
        case .concise:
            return """
                You are a writing assistant. Rewrite the text provided by the user to make it slightly more concise, shortening it without losing key information. Output ONLY the concise version without additional comments. Always respond in the same language as the input text. If the text is completely incompatible (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".
                """
        case .summary:
            return """
                You are a summarization assistant. Provide a succinct summary of the text provided by the user. The summary should be concise, capturing all key points and using Markdown formatting (bold, italics, headings, etc.) for better readability. Always respond in the same language as the input text. If the text is completely incompatible (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".
                """
        case .keyPoints:
            return """
                You are an assistant that extracts key points from text provided by the user. Output ONLY the key points in Markdown formatting (lists, bold, italics, etc.). Always respond in the same language as the input text. If the text is completely incompatible (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".
                """
        case .table:
            return """
                You are an assistant that converts text provided by the user into a Markdown table. Output ONLY the table without additional comments. Always respond in the same language as the input text. If the text is completely incompatible (e.g., totally random gibberish), output "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST".
                """
        }
    }
    
    var icon: String {
        switch self {
        case .proofread: return "magnifyingglass"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .friendly: return "face.smiling"
        case .professional: return "briefcase"
        case .concise: return "scissors"
        case .summary: return "doc.text"
        case .keyPoints: return "list.bullet"
        case .table: return "tablecells"
        }
    }
}
