import Foundation

/// Represents the structured format of a prompt with role, task, rules, and error handling
struct PromptStructure: Codable, Equatable {
    var role: String
    var task: String
    var rules: Rules
    var errorHandling: ErrorHandling?

    // New fields for improved prompt engineering
    var style: Style?
    var constraints: Constraints?
    var qualityCriteria: QualityCriteria?
    var steps: [String]?
    var formattingRules: FormattingRules?
    var examples: [Example]?

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

    // MARK: - New Structures for Enhanced Prompt Engineering

    /// Style guidelines for the output (tone, voice, personality)
    struct Style: Codable, Equatable {
        var tone: String?           // e.g., "formal", "casual", "friendly", "professional"
        var voice: String?           // e.g., "first person", "third person", "neutral"
        var personality: String?       // e.g., "helpful", "authoritative", "empathetic"
        var register: String?          // e.g., "academic", "business", "conversational"

        enum CodingKeys: String, CodingKey {
            case tone, voice, personality, register
        }

        init(
            tone: String? = nil,
            voice: String? = nil,
            personality: String? = nil,
            register: String? = nil
        ) {
            self.tone = tone
            self.voice = voice
            self.personality = personality
            self.register = register
        }
    }

    /// Constraints and negative constraints (what to avoid)
    struct Constraints: Codable, Equatable {
        var maxLength: Int?           // Maximum character count
        var minLength: Int?           // Minimum character count
        var avoidWords: [String]?      // Words/phrases to avoid
        var avoidPhrases: [String]?    // Phrases to avoid
        var mustInclude: [String]?     // Required keywords/phrases
        var forbiddenTopics: [String]?  // Topics to avoid

        enum CodingKeys: String, CodingKey {
            case maxLength = "max_length"
            case minLength = "min_length"
            case avoidWords = "avoid_words"
            case avoidPhrases = "avoid_phrases"
            case mustInclude = "must_include"
            case forbiddenTopics = "forbidden_topics"
        }

        init(
            maxLength: Int? = nil,
            minLength: Int? = nil,
            avoidWords: [String]? = nil,
            avoidPhrases: [String]? = nil,
            mustInclude: [String]? = nil,
            forbiddenTopics: [String]? = nil
        ) {
            self.maxLength = maxLength
            self.minLength = minLength
            self.avoidWords = avoidWords
            self.avoidPhrases = avoidPhrases
            self.mustInclude = mustInclude
            self.forbiddenTopics = forbiddenTopics
        }
    }

    /// Quality criteria for model to evaluate its output
    struct QualityCriteria: Codable, Equatable {
        var checklist: [String]?        // List of criteria to verify
        var selfEvaluate: Bool?         // Should model self-evaluate before output
        var minAccuracy: String?        // e.g., "high", "very high"
        var completeness: String?       // e.g., "full", "comprehensive"

        enum CodingKeys: String, CodingKey {
            case checklist
            case selfEvaluate = "self_evaluate"
            case minAccuracy = "min_accuracy"
            case completeness
        }

        init(
            checklist: [String]? = nil,
            selfEvaluate: Bool? = nil,
            minAccuracy: String? = nil,
            completeness: String? = nil
        ) {
            self.checklist = checklist
            self.selfEvaluate = selfEvaluate
            self.minAccuracy = minAccuracy
            self.completeness = completeness
        }
    }

    /// Formatting rules for output structure
    struct FormattingRules: Codable, Equatable {
        var useMarkdown: Bool?         // Use Markdown formatting
        var useHeaders: Bool?           // Include headers
        var useLists: Bool?             // Use bulleted/numbered lists
        var useCodeBlocks: Bool?         // Use code blocks for code
        var useTables: Bool?            // Use tables
        var useLinks: Bool?              // Include hyperlinks
        var lineLength: Int?            // Max characters per line (for text wrapping)

        enum CodingKeys: String, CodingKey {
            case useMarkdown = "use_markdown"
            case useHeaders = "use_headers"
            case useLists = "use_lists"
            case useCodeBlocks = "use_code_blocks"
            case useTables = "use_tables"
            case useLinks = "use_links"
            case lineLength = "line_length"
        }

        init(
            useMarkdown: Bool? = nil,
            useHeaders: Bool? = nil,
            useLists: Bool? = nil,
            useCodeBlocks: Bool? = nil,
            useTables: Bool? = nil,
            useLinks: Bool? = nil,
            lineLength: Int? = nil
        ) {
            self.useMarkdown = useMarkdown
            self.useHeaders = useHeaders
            self.useLists = useLists
            self.useCodeBlocks = useCodeBlocks
            self.useTables = useTables
            self.useLinks = useLinks
            self.lineLength = lineLength
        }
    }

    /// Few-shot learning examples
    struct Example: Codable, Equatable {
        var input: String               // Example input text
        var output: String              // Expected output
        var explanation: String?         // Optional explanation of why

        init(
            input: String,
            output: String,
            explanation: String? = nil
        ) {
            self.input = input
            self.output = output
            self.explanation = explanation
        }
    }

    enum CodingKeys: String, CodingKey {
        case role, task, rules
        case errorHandling = "error_handling"
        case style, constraints
        case qualityCriteria = "quality_criteria"
        case steps
        case formattingRules = "formatting_rules"
        case examples
    }

    /// Initialize from a JSON string with backward compatibility
    static func from(jsonString: String) -> PromptStructure? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        // The decoder will automatically handle optional fields with defaults
        return try? decoder.decode(PromptStructure.self, from: data)
    }

    /// Initialize with backward compatibility for old prompts
    init(
        role: String,
        task: String,
        rules: Rules,
        errorHandling: ErrorHandling? = nil,
        style: Style? = nil,
        constraints: Constraints? = nil,
        qualityCriteria: QualityCriteria? = nil,
        steps: [String]? = nil,
        formattingRules: FormattingRules? = nil,
        examples: [Example]? = nil
    ) {
        self.role = role
        self.task = task
        self.rules = rules
        self.errorHandling = errorHandling
        self.style = style
        self.constraints = constraints
        self.qualityCriteria = qualityCriteria
        self.steps = steps
        self.formattingRules = formattingRules
        self.examples = examples
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
            ),
            style: Style(
                tone: "neutral",
                voice: "third person",
                personality: "helpful"
            ),
            constraints: nil,
            qualityCriteria: nil,
            steps: nil,
            formattingRules: FormattingRules(
                useMarkdown: true
            ),
            examples: nil
        )
    }

    /// Check if a prompt string appears to be structured (JSON-like)
    static func isStructuredPrompt(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }
}
