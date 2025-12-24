import SwiftUI

/// Tabbed view for editing prompts with Simple (text) and Advanced (structured) modes
struct PromptEditorView: View {
    @Binding var prompt: String
    let isBuiltIn: Bool
    var useHorizontalLayout: Bool = false

    @State private var selectedMode: EditorMode
    @State private var promptStructure: PromptStructure
    @State private var simplePromptText: String
    @State private var showPreview: Bool = true

    enum EditorMode: String, CaseIterable {
        case simple = "Simple"
        case advanced = "Advanced"
    }

    init(prompt: Binding<String>, isBuiltIn: Bool, useHorizontalLayout: Bool = false) {
        self._prompt = prompt
        self.isBuiltIn = isBuiltIn
        self.useHorizontalLayout = useHorizontalLayout

        // Determine initial mode based on whether it's built-in and if prompt is structured
        let isStructured = PromptStructure.isStructuredPrompt(prompt.wrappedValue)
        let initialMode: EditorMode = isBuiltIn && isStructured ? .advanced : .simple

        _selectedMode = State(initialValue: initialMode)
        _simplePromptText = State(initialValue: prompt.wrappedValue)

        // Try to parse as structured prompt, or use default
        if let parsed = PromptStructure.from(jsonString: prompt.wrappedValue) {
            _promptStructure = State(initialValue: parsed)
        } else {
            _promptStructure = State(initialValue: .default)
        }
    }

    var body: some View {
        if useHorizontalLayout {
            horizontalLayoutBody
        } else {
            verticalLayoutBody
        }
    }
    
    // MARK: - Horizontal Layout (for Editor tab with side-by-side preview)
    
    private var horizontalLayoutBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode selector (always show preview in horizontal mode)
            HStack {
                Picker("Editor Mode", selection: $selectedMode) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedMode) { _, newMode in
                    handleModeChange(to: newMode)
                }
                
                Spacer()
            }
            
            // Editor and preview side by side
            HSplitView {
                // Left: Editor
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if selectedMode == .simple {
                            simpleEditorView
                        } else {
                            advancedEditorView
                        }
                    }
                    .padding(12)
                }
                .frame(minWidth: 400)
                
                // Right: Preview
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "eye")
                            .foregroundStyle(.secondary)
                        Text("Preview")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.textBackgroundColor))
                            
                            Text(selectedMode == .simple ? simplePromptText : promptStructure.toJSONString(pretty: true))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
                .frame(minWidth: 300)
            }
        }
    }

    // MARK: - Vertical Layout (for inline use in Form Section)

    private var verticalLayoutBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mode selector and preview toggle
            HStack {
                Picker("Editor Mode", selection: $selectedMode) {
                    ForEach(EditorMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                Toggle("Show Preview", isOn: $showPreview)
                    .toggleStyle(.switch)
            }
            .onChange(of: selectedMode) { _, newMode in
                handleModeChange(to: newMode)
            }

            // Editor content with optional preview
            if showPreview {
                VStack(alignment: .leading, spacing: 8) {
                    // Editor content in a scroll view
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if selectedMode == .simple {
                                simpleEditorView
                            } else {
                                advancedEditorView
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 300)

                    Divider()

                    // Preview section
                    previewSection
                }
            } else {
                // Editor content without preview - takes full available height
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if selectedMode == .simple {
                            simpleEditorView
                        } else {
                            advancedEditorView
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(minHeight: 200)
            }
        }
    }

    // MARK: - Simple Editor

    private var simpleEditorView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.textBackgroundColor))
                    .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)

                TextEditor(text: $simplePromptText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(8)
                    .onChange(of: simplePromptText) { _, newValue in
                        prompt = newValue
                    }
            }
            .frame(minHeight: 150)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            Text("Enter your prompt as plain text")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Advanced Editor

    private var advancedEditorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdvancedPromptEditor(promptStructure: $promptStructure)
                .onChange(of: promptStructure) { _, newValue in
                    // Update the binding when structure changes
                    prompt = newValue.toJSONString(pretty: true)
                }

            Text("Configure your prompt using structured fields")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Preview Section (Vertical)

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                Text("Prompt Preview")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
            }

            ScrollView {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.textBackgroundColor))

                    Text(selectedMode == .simple ? simplePromptText : promptStructure.toJSONString(pretty: true))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            }
            .frame(maxHeight: 120)
        }
        .padding(.top, 4)
    }

    // MARK: - Mode Change Handler

    private func handleModeChange(to newMode: EditorMode) {
        if newMode == .advanced {
            // Switching to advanced: try to parse simple text as JSON
            if let parsed = PromptStructure.from(jsonString: simplePromptText) {
                promptStructure = parsed
            } else {
                // If not valid JSON, keep current structure or use default
                // User can start building from scratch
            }
            prompt = promptStructure.toJSONString(pretty: true)
        } else {
            // Switching to simple: use current prompt value
            simplePromptText = prompt
        }
    }
}

#Preview {
    @Previewable @State var samplePrompt = """
    {
      "role": "proofreading assistant",
      "task": "correct grammar, spelling, and punctuation errors",
      "rules": {
        "acknowledge_content": false,
        "add_explanations": false,
        "output": "only corrected text",
        "preserve": {
          "language": "input"
        }
      }
    }
    """

    return VStack {
        PromptEditorView(prompt: $samplePrompt, isBuiltIn: true)
    }
    .frame(width: 600, height: 700)
    .padding()
}
