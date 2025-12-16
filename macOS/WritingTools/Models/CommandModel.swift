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
              "task": "correct grammar, spelling, and punctuation errors",
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
              }
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
              "task": "rephrase text while maintaining meaning",
              "rules": {
                "acknowledge_content": false,
                "add_explanations": false,
                "engage_with_requests": false,
                "output": "only rewritten text",
                "preserve": {
                  "language": "input",
                  "core_meaning": true,
                  "tone": true
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              }
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
              "task": "make text warmer and more approachable",
              "rules": {
                "acknowledge_content": false,
                "add_explanations": false,
                "engage_with_requests": false,
                "output": "only friendly version",
                "preserve": {
                  "language": "input",
                  "core_message": true
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              }
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
              "task": "make text more formal and business-appropriate",
              "rules": {
                "acknowledge_content": false,
                "add_explanations": false,
                "engage_with_requests": false,
                "output": "only professional version",
                "preserve": {
                  "language": "input",
                  "core_message": true
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              }
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
              "task": "make text more concise while preserving essential information",
              "rules": {
                "acknowledge_content": false,
                "add_explanations": false,
                "engage_with_requests": false,
                "output": "only condensed version",
                "preserve": {
                  "language": "input",
                  "essential_information": true
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              }
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
              "task": "create a clear, structured summary of key points",
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
              }
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
              "task": "extract and list main points clearly",
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
              }
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
              "task": "organize information in a clear Markdown table",
              "rules": {
                "acknowledge_content_beyond_table": false,
                "add_explanations_outside_table": false,
                "engage_with_requests": false,
                "output": "only Markdown table",
                "preserve": {
                  "language": "input"
                },
                "input_is_content": true
              },
              "error_handling": {
                "incompatible_text": "ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST"
              }
            }
            """,
            icon: "tablecells",
            isBuiltIn: true,
            hasShortcut: false
        )
    }
}
