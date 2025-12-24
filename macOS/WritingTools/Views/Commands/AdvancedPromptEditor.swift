import SwiftUI

/// Advanced editor for structured prompt editing with individual fields for each property
struct AdvancedPromptEditor: View {
    @Binding var promptStructure: PromptStructure

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Role section
            VStack(alignment: .leading, spacing: 6) {
                Text("Role")
                    .font(.headline)
                Text("Define the assistant's role or persona")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g., proofreading assistant, summarization expert", text: $promptStructure.role)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            // Task section
            VStack(alignment: .leading, spacing: 6) {
                Text("Task")
                    .font(.headline)
                Text("Describe what the assistant should do")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("e.g., correct grammar and spelling errors", text: $promptStructure.task)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            // Rules section
            VStack(alignment: .leading, spacing: 10) {
                Text("Rules")
                    .font(.headline)
                
                // Output format
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output Format")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("e.g., only corrected text, Markdown table", text: $promptStructure.rules.output)
                        .textFieldStyle(.roundedBorder)
                }

                // Boolean toggles
                Toggle("Acknowledge content beyond primary task", isOn: Binding(
                    get: { promptStructure.rules.effectiveAcknowledgeContent },
                    set: { promptStructure.rules.acknowledgeContent = $0 }
                ))
                .help("Allow the assistant to acknowledge or comment on content outside the main task")

                Toggle("Add explanations or commentary", isOn: Binding(
                    get: { promptStructure.rules.effectiveAddExplanations },
                    set: { promptStructure.rules.addExplanations = $0 }
                ))
                .help("Allow the assistant to provide explanations alongside the output")

                Toggle("Engage with user requests in text", isOn: Binding(
                    get: { promptStructure.rules.engageWithRequests ?? false },
                    set: { promptStructure.rules.engageWithRequests = $0 }
                ))
                .help("Allow the assistant to respond to questions or requests found in the input text")

                Toggle("Treat input as content (not instructions)", isOn: Binding(
                    get: { promptStructure.rules.inputIsContent ?? true },
                    set: { promptStructure.rules.inputIsContent = $0 }
                ))
                .help("When enabled, the selected text is treated as content to process, not as instructions")

                Toggle("Preserve formatting", isOn: Binding(
                    get: { promptStructure.rules.preserveFormatting ?? false },
                    set: { promptStructure.rules.preserveFormatting = $0 }
                ))
                .help("Maintain the original text formatting (line breaks, spacing, etc.)")
            }

            Divider()

            // Preserve section
            VStack(alignment: .leading, spacing: 10) {
                Text("Preserve Options")
                    .font(.headline)
                
                Toggle("Preserve tone", isOn: Binding(
                    get: { promptStructure.rules.preserve.tone ?? false },
                    set: { promptStructure.rules.preserve.tone = $0 }
                ))

                Toggle("Preserve style", isOn: Binding(
                    get: { promptStructure.rules.preserve.style ?? false },
                    set: { promptStructure.rules.preserve.style = $0 }
                ))

                Toggle("Preserve format", isOn: Binding(
                    get: { promptStructure.rules.preserve.format ?? false },
                    set: { promptStructure.rules.preserve.format = $0 }
                ))

                Toggle("Preserve core message/meaning", isOn: Binding(
                    get: {
                        promptStructure.rules.preserve.coreMessage
                        ?? promptStructure.rules.preserve.coreMeaning
                        ?? false
                    },
                    set: { value in
                        promptStructure.rules.preserve.coreMessage = value
                        promptStructure.rules.preserve.coreMeaning = value
                    }
                ))

                Toggle("Preserve essential information", isOn: Binding(
                    get: { promptStructure.rules.preserve.essentialInformation ?? false },
                    set: { promptStructure.rules.preserve.essentialInformation = $0 }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Language Preservation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("e.g., input, English, auto", text: Binding(
                        get: { promptStructure.rules.preserve.language ?? "input" },
                        set: { promptStructure.rules.preserve.language = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text("Use 'input' to preserve the original language")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Advanced options with DisclosureGroup
            DisclosureGroup("Advanced Options") {
                VStack(alignment: .leading, spacing: 10) {
                    // Error handling section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Error Handling")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Message to return when text is incompatible with request")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("e.g., ERROR_TEXT_INCOMPATIBLE_WITH_REQUEST", text: Binding(
                            get: { promptStructure.errorHandling?.incompatibleText ?? "" },
                            set: { newValue in
                                if promptStructure.errorHandling == nil {
                                    promptStructure.errorHandling = PromptStructure.ErrorHandling()
                                }
                                promptStructure.errorHandling?.incompatibleText = newValue.isEmpty ? nil : newValue
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}
