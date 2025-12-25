import Foundation
import SwiftUI

struct CommandModel: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var icon: String
    var useResponseWindow: Bool
    var isBuiltIn: Bool
    var hasShortcut: Bool
    var preserveFormatting: Bool

    // MARK: - Per-Command AI Provider Configuration

    /// Optional provider override (e.g., "openai", "gemini", "anthropic", "ollama", "mistral", "openrouter", "local", "custom")
    /// If nil, uses the default provider from AppSettings
    var providerOverride: String?

    /// Optional model override for the specified provider
    /// If nil, uses the default model for the provider
    var modelOverride: String?

    /// Custom provider configuration (only used when providerOverride == "custom")
    var customProviderBaseURL: String?
    var customProviderApiKey: String?
    var customProviderModel: String?

    // MARK: – CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id, name, prompt, icon
        case useResponseWindow
        case isBuiltIn
        case hasShortcut
        case preserveFormatting
        case providerOverride
        case modelOverride
        case customProviderBaseURL
        case customProviderApiKey
        case customProviderModel
    }

    // MARK: – Decoding (old data OK)

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        prompt = try c.decode(String.self, forKey: .prompt)
        icon = try c.decode(String.self, forKey: .icon)
        useResponseWindow = try c.decodeIfPresent(Bool.self, forKey: .useResponseWindow) ?? false
        isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        hasShortcut = try c.decodeIfPresent(Bool.self, forKey: .hasShortcut) ?? false
        preserveFormatting = try c.decodeIfPresent(Bool.self,
                                                   forKey: .preserveFormatting) ?? false
        providerOverride = try c.decodeIfPresent(String.self, forKey: .providerOverride)
        modelOverride = try c.decodeIfPresent(String.self, forKey: .modelOverride)
        customProviderBaseURL = try c.decodeIfPresent(String.self, forKey: .customProviderBaseURL)
        customProviderApiKey = try c.decodeIfPresent(String.self, forKey: .customProviderApiKey)
        customProviderModel = try c.decodeIfPresent(String.self, forKey: .customProviderModel)
    }

    // MARK: – Encoding (store compactly)

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(icon, forKey: .icon)
        if useResponseWindow { try c.encode(useResponseWindow, forKey: .useResponseWindow) }
        if isBuiltIn { try c.encode(isBuiltIn, forKey: .isBuiltIn) }
        if hasShortcut { try c.encode(hasShortcut, forKey: .hasShortcut) }
        if preserveFormatting {
            try c.encode(preserveFormatting, forKey: .preserveFormatting)
        }
        if let providerOverride = providerOverride {
            try c.encode(providerOverride, forKey: .providerOverride)
        }
        if let modelOverride = modelOverride {
            try c.encode(modelOverride, forKey: .modelOverride)
        }
        if let customProviderBaseURL = customProviderBaseURL {
            try c.encode(customProviderBaseURL, forKey: .customProviderBaseURL)
        }
        if let customProviderApiKey = customProviderApiKey {
            try c.encode(customProviderApiKey, forKey: .customProviderApiKey)
        }
        if let customProviderModel = customProviderModel {
            try c.encode(customProviderModel, forKey: .customProviderModel)
        }
    }

    // MARK: – Convenience initialiser (unchanged)

    init(id: UUID = UUID(),
         name: String,
         prompt: String,
         icon: String,
         useResponseWindow: Bool = false,
         isBuiltIn: Bool = false,
         hasShortcut: Bool = false,
         preserveFormatting: Bool = false,
         providerOverride: String? = nil,
         modelOverride: String? = nil,
         customProviderBaseURL: String? = nil,
         customProviderApiKey: String? = nil,
         customProviderModel: String? = nil) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.icon = icon
        self.useResponseWindow = useResponseWindow
        self.isBuiltIn = isBuiltIn
        self.hasShortcut = hasShortcut
        self.preserveFormatting = preserveFormatting
        self.providerOverride = providerOverride
        self.modelOverride = modelOverride
        self.customProviderBaseURL = customProviderBaseURL
        self.customProviderApiKey = customProviderApiKey
        self.customProviderModel = customProviderModel
    }

    // Helper to create from WritingOption for migration
    static func fromWritingOption(_ option: WritingOption) -> CommandModel {
        CommandModel(
            id: UUID(),
            name: option.localizedName,
            prompt: option.systemPrompt,
            icon: option.icon,
            useResponseWindow: false,
            isBuiltIn: true,
            hasShortcut: false
        )
    }

    // Helper to create from CustomCommand for migration
    static func fromCustomCommand(_ command: CustomCommand) -> CommandModel {
        CommandModel(
            id: command.id,
            name: command.name,
            prompt: command.prompt,
            icon: command.icon,
            useResponseWindow: command.useResponseWindow,
            isBuiltIn: false,
            hasShortcut: false
        )
    }

    static var defaultCommands: [CommandModel] {
        return [
            proofread,
            rewrite,
            friendly,
            professional,
            concise,
            summary,
            keyPoints,
            table,
        ]
    }

    static var proofread: CommandModel {
        CommandModel(
            name: String(localized: "Proofread", comment: "ID for proofreading"),
            prompt: """
            {
              "role": "proofreading assistant",
              "task": "correct grammar, spelling, and punctuation errors while preserving the original meaning and formatting",
              "rules": {
                "acknowledge_content": false,
                "add_explanations": false,
                "engage_with_requests": false,
                "output": "only corrected text",
                "preserve": {
                  "tone": true,
                  "style": true,
                  "format": true,
                  "language": "input"
                },
                "input_is_content": true,
                "preserve_formatting": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              },
              "style": {
                "tone": "neutral",
                "personality": "precise",
                "register": "conversational"
              },
              "constraints": {
                "avoid_words": ["very", "really", "basically"],
                "must_include": []
              },
              "quality_criteria": {
                "checklist": [
                  "All grammar errors corrected",
                  "All spelling errors corrected",
                  "All punctuation errors corrected",
                  "Original meaning preserved",
                  "Original tone preserved"
                ],
                "self_evaluate": true,
                "min_accuracy": "high",
                "completeness": "full"
              },
              "formatting_rules": {
                "use_markdown": false,
                "use_headers": false,
                "use_lists": false,
                "use_code_blocks": false,
                "use_tables": false,
                "use_links": false
              },
              "examples": [
                {
                  "input": "The quick brown fox jumps over the lazy dog. Their was five apples on the table.",
                  "output": "The quick brown fox jumps over the lazy dog. There were five apples on the table.",
                  "explanation": "Corrected 'Their' to 'There' and 'was' to 'were' for proper subject-verb agreement."
                },
                {
                  "input": "Me and him went to the store yesterday.",
                  "output": "He and I went to the store yesterday.",
                  "explanation": "Changed to proper subject case 'He and I' for clarity and grammatical correctness."
                }
              ]
            }
            """,
            icon: "magnifyingglass",
            isBuiltIn: true,
            hasShortcut: false,
            preserveFormatting: true
        )
    }

    static var rewrite: CommandModel {
        CommandModel(
            name: String(localized: "Rewrite", comment: "ID for rewriting"),
            prompt: """
            {
              "role": "rewriting assistant",
              "task": "rephrase text to improve clarity, flow, and readability while maintaining the original meaning and intent",
              "rules": {
                "acknowledge_content": false,
                "add_explanations": false,
                "engage_with_requests": false,
                "output": "only rewritten text",
                "preserve": {
                  "language": "input",
                  "core_meaning": true,
                  "tone": true,
                  "essential_information": true
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              },
              "style": {
                "tone": "neutral",
                "personality": "clear",
                "register": "conversational"
              },
              "constraints": {
                "avoid_words": ["utilize", "leverage", "synergy", "paradigm"],
                "avoid_phrases": ["at the end of the day", "think outside the box"]
              },
              "quality_criteria": {
                "checklist": [
                  "Original meaning preserved",
                  "Improved clarity and flow",
                  "Better readability",
                  "Appropriate word choice",
                  "Natural phrasing"
                ],
                "self_evaluate": true,
                "min_accuracy": "high",
                "completeness": "full"
              },
              "formatting_rules": {
                "use_markdown": false,
                "use_headers": false,
                "use_lists": false,
                "use_code_blocks": false,
                "use_tables": false,
                "use_links": false
              },
              "steps": [
                  "Analyze the original text to understand its meaning and intent",
                  "Identify areas for improvement in clarity, flow, and readability",
                  "Rewrite the text using better word choice and phrasing",
                  "Verify that the original meaning is preserved",
                  "Ensure the rewrite feels natural and appropriate for the context"
              ],
              "examples": [
                  {
                      "input": "I would like to take this opportunity to say that I am very happy with the results that were achieved.",
                      "output": "I'm very pleased with the results achieved.",
                      "explanation": "Condensed wordy phrasing and removed redundancy while maintaining the positive sentiment."
                  },
                  {
                      "input": "The implementation of the new system was completed in a timely manner.",
                      "output": "The new system was implemented on time.",
                      "explanation": "Removed passive voice and wordy construction for direct, active phrasing."
                  }
              ]
            }
            """,
            icon: "arrow.triangle.2.circlepath",
            isBuiltIn: true,
            hasShortcut: false
        )
    }

    static var friendly: CommandModel {
        CommandModel(
            name: String(localized: "Friendly", comment: "ID for friendly tone"),
            prompt: """
            {
              "role": "tone adjustment assistant",
              "task": "make text warmer, more approachable, and conversational while maintaining original meaning",
              "rules": {
                "acknowledge_content": false,
                "add_explanations": false,
                "engage_with_requests": false,
                "output": "only friendly version",
                "preserve": {
                  "language": "input",
                  "core_message": true,
                  "essential_information": true
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              },
              "style": {
                "tone": "casual",
                "voice": "neutral",
                "personality": "warm",
                "register": "conversational"
              },
              "constraints": {
                "avoid_words": ["formal", "hereby", "pursuant", "therefore"],
                "must_include": []
              },
              "quality_criteria": {
                "checklist": [
                  "Tone is warm and approachable",
                  "Original meaning preserved",
                  "Feels natural and conversational",
                  "Appropriate for friendly communication"
                ],
                "self_evaluate": true,
                "min_accuracy": "high",
                "completeness": "full"
              },
              "formatting_rules": {
                "use_markdown": false,
                "use_headers": false,
                "use_lists": false,
                "use_code_blocks": false,
                "use_tables": false,
                "use_links": false
              },
              "examples": [
                  {
                      "input": "Please be advised that your request has been processed.",
                      "output": "Good news! Your request has been processed.",
                      "explanation": "Changed formal language to warm, positive phrasing while conveying the same information."
                  },
                  {
                      "input": "I am writing to inform you that the meeting has been rescheduled.",
                      "output": "Just wanted to let you know that the meeting has been rescheduled.",
                      "explanation": "Replaced formal statement with conversational phrasing while keeping the message intact."
                  }
              ]
            }
            """,
            icon: "face.smiling",
            isBuiltIn: true,
            hasShortcut: false
        )
    }

    static var professional: CommandModel {
        CommandModel(
            name: String(localized: "Professional", comment: "ID for professional tone"),
            prompt: """
            {
              "role": "professional tone assistant",
              "task": "make text more formal, polished, and business-appropriate while maintaining original meaning",
              "rules": {
                "acknowledge_content": false,
                "add_explanations": false,
                "engage_with_requests": false,
                "output": "only professional version",
                "preserve": {
                  "language": "input",
                  "core_message": true,
                  "essential_information": true
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              },
              "style": {
                "tone": "formal",
                "voice": "third person",
                "personality": "professional",
                "register": "business"
              },
              "constraints": {
                "avoid_words": ["awesome", "super", "gonna", "wanna"],
                "must_include": []
              },
              "quality_criteria": {
                "checklist": [
                  "Tone is formal and professional",
                  "Appropriate for business context",
                  "Original meaning preserved",
                  "Polished and articulate"
                ],
                "self_evaluate": true,
                "min_accuracy": "high",
                "completeness": "full"
              },
              "formatting_rules": {
                "use_markdown": false,
                "use_headers": false,
                "use_lists": false,
                "use_code_blocks": false,
                "use_tables": false,
                "use_links": false
              },
              "examples": [
                  {
                      "input": "Hey, thanks for reaching out! We'll get back to you soon.",
                      "output": "Thank you for your inquiry. We will respond to you shortly.",
                      "explanation": "Elevated casual language to formal business correspondence while maintaining the helpful intent."
                  },
                  {
                      "input": "I think we should do the project together.",
                      "output": "I propose we collaborate on this project.",
                      "explanation": "Replaced tentative phrasing with more decisive, professional language."
                  }
              ]
            }
            """,
            icon: "briefcase",
            isBuiltIn: true,
            hasShortcut: false
        )
    }

    static var concise: CommandModel {
        CommandModel(
            name: String(localized: "Concise", comment: "ID for concise tone"),
            prompt: """
            {
              "role": "text condensing assistant",
              "task": "make text more concise by removing redundancy and unnecessary words while preserving essential information and meaning",
              "rules": {
                "acknowledge_content": false,
                "add_explanations": false,
                "engage_with_requests": false,
                "output": "only condensed version",
                "preserve": {
                  "language": "input",
                  "essential_information": true,
                  "core_message": true
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              },
              "style": {
                "tone": "neutral",
                "personality": "efficient",
                "register": "conversational"
              },
              "constraints": {
                "avoid_words": ["very", "really", "basically", "essentially", "actually"],
                "must_include": [],
                "min_length": 10
              },
              "quality_criteria": {
                "checklist": [
                  "All essential information preserved",
                  "Redundancy removed",
                  "Text is shorter than original",
                  "Meaning remains intact",
                  "No information loss"
                ],
                "self_evaluate": true,
                "min_accuracy": "high",
                "completeness": "full"
              },
              "formatting_rules": {
                "use_markdown": false,
                "use_headers": false,
                "use_lists": false,
                "use_code_blocks": false,
                "use_tables": false,
                "use_links": false
              },
              "steps": [
                  "Analyze the original text to identify all essential information",
                  "Remove unnecessary words, redundancies, and wordy phrasing",
                  "Condense repetitive phrases into single, clear statements",
                  "Verify that all key information is preserved",
                  "Ensure the condensed text flows naturally"
              ],
              "examples": [
                  {
                      "input": "Due to the fact that we have a lot of different options available for you to choose from, we are able to provide you with exactly what it is that you need.",
                      "output": "We have many options available and can provide exactly what you need.",
                      "explanation": "Removed wordy phrases and redundancies while preserving the core message."
                  },
                  {
                      "input": "The results of the study that we conducted showed that there was a significant improvement in all areas.",
                      "output": "Our study showed significant improvement in all areas.",
                      "explanation": "Condensed passive construction and removed unnecessary words."
                  }
              ]
            }
            """,
            icon: "scissors",
            isBuiltIn: true,
            hasShortcut: false
        )
    }

    static var summary: CommandModel {
        CommandModel(
            name: String(localized: "Summary", comment: "ID for summarization"),
            prompt: """
            {
              "role": "summarization assistant",
              "task": "create a clear, structured summary that captures the main ideas and key information from the input text",
              "rules": {
                "acknowledge_content_beyond_summary": false,
                "add_explanations_outside_summary": false,
                "engage_with_requests": false,
                "output": "only summary with basic Markdown formatting",
                "preserve": {
                  "language": "input"
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              },
              "style": {
                "tone": "neutral",
                "personality": "clear",
                "register": "academic"
              },
              "quality_criteria": {
                "checklist": [
                  "Main ideas captured",
                  "Key information preserved",
                  "Summary is concise",
                  "Structure is logical",
                  "No critical information omitted"
                ],
                "self_evaluate": true,
                "min_accuracy": "high",
                "completeness": "comprehensive"
              },
              "formatting_rules": {
                "use_markdown": true,
                "use_headers": true,
                "use_lists": true,
                "use_code_blocks": false,
                "use_tables": false,
                "use_links": false
              },
              "steps": [
                  "Analyze the input text to identify the main ideas and themes",
                  "Extract key information, facts, and supporting details",
                  "Organize the information in a logical structure",
                  "Draft the summary focusing on clarity and conciseness",
                  "Review to ensure all critical information is included"
              ],
              "examples": [
                  {
                      "input": "The company announced a new product launch scheduled for next quarter. The product features advanced AI capabilities and will be priced competitively in the market. Analysts predict strong sales.",
                      "output": "## Summary\n\nThe company will launch a new AI-powered product next quarter with competitive pricing, and analysts project strong sales.",
                      "explanation": "Condensed information into a single, clear sentence with structured formatting."
                  }
              ]
            }
            """,
            icon: "doc.text",
            isBuiltIn: true,
            hasShortcut: false
        )
    }

    static var keyPoints: CommandModel {
        CommandModel(
            name: String(localized: "Key Points", comment: "ID for key points extraction"),
            prompt: """
            {
              "role": "key points extraction assistant",
              "task": "extract and clearly list the most important points and takeaways from the input text",
              "rules": {
                "acknowledge_content_beyond_key_points": false,
                "add_explanations_outside_key_points": false,
                "engage_with_requests": false,
                "output": "only key points in Markdown list format",
                "preserve": {
                  "language": "input"
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              },
              "style": {
                "tone": "neutral",
                "personality": "analytical",
                "register": "academic"
              },
              "constraints": {
                "min_length": 20,
                "must_include": []
              },
              "quality_criteria": {
                "checklist": [
                  "All key points extracted",
                  "Points are clear and concise",
                  "No critical information omitted",
                  "List format is organized"
                ],
                "self_evaluate": true,
                "min_accuracy": "high",
                "completeness": "comprehensive"
              },
              "formatting_rules": {
                "use_markdown": true,
                "use_headers": false,
                "use_lists": true,
                "use_code_blocks": false,
                "use_tables": false,
                "use_links": false
              },
              "steps": [
                  "Read and analyze the input text thoroughly",
                  "Identify the main ideas and important information",
                  "Extract key points, avoiding minor details",
                  "Organize points in a logical order",
                  "Format as clear, bulleted list"
              ],
              "examples": [
                  {
                      "input": "The meeting covered three main topics: budget allocation, timeline adjustments, and team expansion. Budget will be increased by 15%. Timeline moved to Q2. Team will grow by 5 people.",
                      "output": "## Key Points\n\n- Budget allocation: Increased by 15%\n- Timeline: Adjusted to Q2\n- Team expansion: Adding 5 new members",
                      "explanation": "Extracted the three main points with specific details in a clear, bulleted format."
                  }
              ]
            }
            """,
            icon: "list.bullet",
            isBuiltIn: true,
            hasShortcut: false
        )
    }

    static var table: CommandModel {
        CommandModel(
            name: String(localized: "Table", comment: "ID for table conversion"),
            prompt: """
            {
              "role": "table conversion assistant",
              "task": "organize information from input text into a clear, well-structured Markdown table",
              "rules": {
                "acknowledge_content_beyond_table": false,
                "add_explanations_outside_table": false,
                "engage_with_requests": false,
                "output": "only Markdown table",
                "preserve": {
                  "language": "input",
                  "essential_information": true
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              },
              "style": {
                "tone": "neutral",
                "personality": "organized",
                "register": "academic"
              },
              "quality_criteria": {
                "checklist": [
                  "All relevant data included in table",
                  "Table structure is logical",
                  "Headers are clear",
                  "Data is accurate",
                  "No information loss"
                ],
                "self_evaluate": true,
                "min_accuracy": "high",
                "completeness": "full"
              },
              "formatting_rules": {
                "use_markdown": true,
                "use_headers": false,
                "use_lists": false,
                "use_code_blocks": false,
                "use_tables": true,
                "use_links": false
              },
              "steps": [
                  "Analyze input text to identify data points and relationships",
                  "Determine appropriate table structure (rows and columns)",
                  "Extract all relevant information for each cell",
                  "Create table with clear headers",
                  "Organize data logically within table"
              ],
              "examples": [
                  {
                      "input": "John Smith is a developer from New York who earns $95,000. Jane Doe is a designer from San Francisco earning $88,000.",
                      "output": "| Name | Role | Location | Salary |\n|------|------|----------|--------|\n| John Smith | Developer | New York | $95,000 |\n| Jane Doe | Designer | San Francisco | $88,000 |",
                      "explanation": "Organized structured data into a clean Markdown table with appropriate headers."
                  }
              ]
            }
            """,
            icon: "tablecells",
            isBuiltIn: true,
            hasShortcut: false
        )
    }
}
