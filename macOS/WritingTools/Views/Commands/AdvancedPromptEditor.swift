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

                    Divider()

                    // Style section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Style Guidelines")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Tone:")
                                .frame(width: 60, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { promptStructure.style?.tone ?? "neutral" },
                                set: { newValue in
                                    if promptStructure.style == nil {
                                        promptStructure.style = PromptStructure.Style()
                                    }
                                    promptStructure.style?.tone = newValue == "neutral" ? nil : newValue
                                }
                            )) {
                                Text("Neutral").tag("neutral")
                                Text("Formal").tag("formal")
                                Text("Casual").tag("casual")
                                Text("Friendly").tag("friendly")
                                Text("Professional").tag("professional")
                                Text("Academic").tag("academic")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }

                        HStack {
                            Text("Voice:")
                                .frame(width: 60, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { promptStructure.style?.voice ?? "neutral" },
                                set: { newValue in
                                    if promptStructure.style == nil {
                                        promptStructure.style = PromptStructure.Style()
                                    }
                                    promptStructure.style?.voice = newValue == "neutral" ? nil : newValue
                                }
                            )) {
                                Text("Neutral").tag("neutral")
                                Text("First Person").tag("first person")
                                Text("Third Person").tag("third person")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }

                        HStack {
                            Text("Personality:")
                                .frame(width: 60, alignment: .leading)
                            TextField("e.g., helpful, authoritative", text: Binding(
                                get: { promptStructure.style?.personality ?? "" },
                                set: { newValue in
                                    if promptStructure.style == nil {
                                        promptStructure.style = PromptStructure.Style()
                                    }
                                    promptStructure.style?.personality = newValue.isEmpty ? nil : newValue
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Register:")
                                .frame(width: 60, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { promptStructure.style?.register ?? "neutral" },
                                set: { newValue in
                                    if promptStructure.style == nil {
                                        promptStructure.style = PromptStructure.Style()
                                    }
                                    promptStructure.style?.register = newValue == "neutral" ? nil : newValue
                                }
                            )) {
                                Text("Neutral").tag("neutral")
                                Text("Academic").tag("academic")
                                Text("Business").tag("business")
                                Text("Conversational").tag("conversational")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }
                    }

                    Divider()

                    // Constraints section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Constraints")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Max Length:")
                                .frame(width: 80, alignment: .leading)
                            TextField("e.g., 500", text: Binding(
                                get: {
                                    guard let maxLength = promptStructure.constraints?.maxLength else { return "" }
                                    return String(maxLength)
                                },
                                set: { newValue in
                                    if promptStructure.constraints == nil {
                                        promptStructure.constraints = PromptStructure.Constraints()
                                    }
                                    promptStructure.constraints?.maxLength = Int(newValue)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Min Length:")
                                .frame(width: 80, alignment: .leading)
                            TextField("e.g., 50", text: Binding(
                                get: {
                                    guard let minLength = promptStructure.constraints?.minLength else { return "" }
                                    return String(minLength)
                                },
                                set: { newValue in
                                    if promptStructure.constraints == nil {
                                        promptStructure.constraints = PromptStructure.Constraints()
                                    }
                                    promptStructure.constraints?.minLength = Int(newValue)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Avoid Words:")
                                .frame(width: 80, alignment: .leading)
                            TextField("e.g., very, really", text: Binding(
                                get: {
                                    guard let avoidWords = promptStructure.constraints?.avoidWords else { return "" }
                                    return avoidWords.joined(separator: ", ")
                                },
                                set: { newValue in
                                    if promptStructure.constraints == nil {
                                        promptStructure.constraints = PromptStructure.Constraints()
                                    }
                                    let words = newValue.components(separatedBy: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
                                    promptStructure.constraints?.avoidWords = words.isEmpty ? nil : words
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    Divider()

                    // Formatting rules section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Formatting Rules")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Toggle("Use Markdown", isOn: Binding(
                            get: { promptStructure.formattingRules?.useMarkdown ?? false },
                            set: { newValue in
                                if promptStructure.formattingRules == nil {
                                    promptStructure.formattingRules = PromptStructure.FormattingRules()
                                }
                                promptStructure.formattingRules?.useMarkdown = newValue
                            }
                        ))

                        Toggle("Use Headers", isOn: Binding(
                            get: { promptStructure.formattingRules?.useHeaders ?? false },
                            set: { newValue in
                                if promptStructure.formattingRules == nil {
                                    promptStructure.formattingRules = PromptStructure.FormattingRules()
                                }
                                promptStructure.formattingRules?.useHeaders = newValue
                            }
                        ))

                        Toggle("Use Lists", isOn: Binding(
                            get: { promptStructure.formattingRules?.useLists ?? false },
                            set: { newValue in
                                if promptStructure.formattingRules == nil {
                                    promptStructure.formattingRules = PromptStructure.FormattingRules()
                                }
                                promptStructure.formattingRules?.useLists = newValue
                            }
                        ))

                        Toggle("Use Code Blocks", isOn: Binding(
                            get: { promptStructure.formattingRules?.useCodeBlocks ?? false },
                            set: { newValue in
                                if promptStructure.formattingRules == nil {
                                    promptStructure.formattingRules = PromptStructure.FormattingRules()
                                }
                                promptStructure.formattingRules?.useCodeBlocks = newValue
                            }
                        ))

                        Toggle("Use Tables", isOn: Binding(
                            get: { promptStructure.formattingRules?.useTables ?? false },
                            set: { newValue in
                                if promptStructure.formattingRules == nil {
                                    promptStructure.formattingRules = PromptStructure.FormattingRules()
                                }
                                promptStructure.formattingRules?.useTables = newValue
                            }
                        ))
                    }

                    Divider()

                    // Steps section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Process Steps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Define step-by-step instructions for complex tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: Binding(
                            get: {
                                guard let steps = promptStructure.steps else { return "" }
                                return steps.joined(separator: "\n")
                            },
                            set: { newValue in
                                let stepList = newValue.components(separatedBy: "\n").map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
                                promptStructure.steps = stepList.isEmpty ? nil : stepList
                            }
                        ))
                        .frame(height: 80)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}
