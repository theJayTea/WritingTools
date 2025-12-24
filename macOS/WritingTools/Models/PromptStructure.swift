import Foundation

/// Represents the structured format of a prompt with role, task, rules, and error handling
struct PromptStructure: Codable, Equatable {
    var role: String
    var task: String
    var rules: Rules
    var errorHandling: ErrorHandling?

    struct Rules: Codable, Equatable {
        var acknowledgeContent: Bool?
        var addExplanations: Bool?
        var engageWithRequests: Bool?
        var output: String
        var preserve: Preserve
        var inputIsContent: Bool?
        var preserveFormatting: Bool?

        // Support for alternative field names in legacy prompts
        var acknowledgeContentBeyondSummary: Bool?
        var addExplanationsBeyondSummary: Bool?
        var acknowledgeContentBeyondKeyPoints: Bool?
        var addExplanationsOutsideKeyPoints: Bool?
        var acknowledgeContentBeyondTable: Bool?
        var addExplanationsOutsideTable: Bool?

        enum CodingKeys: String, CodingKey {
            case acknowledgeContent = "acknowledge_content"
            case addExplanations = "add_explanations"
            case engageWithRequests = "engage_with_requests"
            case output
            case preserve
            case inputIsContent = "input_is_content"
            case preserveFormatting = "preserve_formatting"
            case acknowledgeContentBeyondSummary = "acknowledge_content_beyond_summary"
            case addExplanationsBeyondSummary = "add_explanations_outside_summary"
            case acknowledgeContentBeyondKeyPoints = "acknowledge_content_beyond_key_points"
            case addExplanationsOutsideKeyPoints = "add_explanations_outside_key_points"
            case acknowledgeContentBeyondTable = "acknowledge_content_beyond_table"
            case addExplanationsOutsideTable = "add_explanations_outside_table"
        }

        // Computed property to get the effective acknowledge content value
        var effectiveAcknowledgeContent: Bool {
            acknowledgeContent
            ?? acknowledgeContentBeyondSummary
            ?? acknowledgeContentBeyondKeyPoints
            ?? acknowledgeContentBeyondTable
            ?? false
        }

        // Computed property to get the effective add explanations value
        var effectiveAddExplanations: Bool {
            addExplanations
            ?? addExplanationsBeyondSummary
            ?? addExplanationsOutsideKeyPoints
            ?? addExplanationsOutsideTable
            ?? false
        }
    }

    struct Preserve: Codable, Equatable {
        var tone: Bool?
        var style: Bool?
        var format: Bool?
        var language: String?
        var coreMessage: Bool?
        var coreMeaning: Bool?
        var essentialInformation: Bool?

        enum CodingKeys: String, CodingKey {
            case tone, style, format, language
            case coreMessage = "core_message"
            case coreMeaning = "core_meaning"
            case essentialInformation = "essential_information"
        }
    }

    struct ErrorHandling: Codable, Equatable {
        var incompatibleText: String?

        enum CodingKeys: String, CodingKey {
            case incompatibleText = "incompatible_text"
        }
    }

    enum CodingKeys: String, CodingKey {
        case role, task, rules
        case errorHandling = "error_handling"
    }

    /// Initialize from a JSON string
    static func from(jsonString: String) -> PromptStructure? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(PromptStructure.self, from: data)
    }

    /// Convert to a formatted JSON string
    func toJSONString(pretty: Bool = true) -> String {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }

        guard let data = try? encoder.encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return ""
        }
        return jsonString
    }

    /// Create a default structure for new prompts
    static var `default`: PromptStructure {
        PromptStructure(
            role: "assistant",
            task: "process the selected text",
            rules: Rules(
                acknowledgeContent: false,
                addExplanations: false,
                engageWithRequests: false,
                output: "only processed text",
                preserve: Preserve(
                    language: "input"
                ),
                inputIsContent: true
            ),
            errorHandling: ErrorHandling(
                incompatibleText: "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
            )
        )
    }

    /// Check if a prompt string appears to be structured (JSON-like)
    static func isStructuredPrompt(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }
}
