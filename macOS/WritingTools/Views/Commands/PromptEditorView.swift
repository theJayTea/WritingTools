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
    @State private var advancedPreviewText: String

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

        let parsed = PromptStructure.from(jsonString: prompt.wrappedValue) ?? .default
        _promptStructure = State(initialValue: parsed)
        _advancedPreviewText = State(initialValue: parsed.toJSONString(pretty: true))
    }

    var body: some View {
        Group {
            if useHorizontalLayout {
                horizontalLayoutBody
            } else {
                verticalLayoutBody
            }
        }
        .confirmationDialog(
            "Convert to Advanced mode?",
            isPresented: $showModeChangeAlert,
            titleVisibility: .visible
        ) {
            Button("Convert") {
                if let target = pendingMode {
                    // Apply the content transform first, then flip the picker
                    // with the re-entrancy guard set so .onChange does not
                    // re-trigger the warning.
                    applyModeChange(to: target)
                    isApplyingConfirmedModeChange = true
                    selectedMode = target
                }
                pendingMode = nil
            }
            Button("Cancel", role: .cancel) {
                pendingMode = nil
            }
        } message: {
            Text("Your prompt text will be moved into the structured \"Task\" field. You can switch back to Simple mode to restore your original text.")
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
                            
                            Text(selectedMode == .simple ? simplePromptText : advancedPreviewText)
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
                    let updated = newValue.toJSONString(pretty: true)
                    // Update the binding when structure changes
                    prompt = updated
                    advancedPreviewText = updated
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

                    Text(selectedMode == .simple ? simplePromptText : advancedPreviewText)
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

    @State private var showModeChangeAlert = false
    /// The mode the user is trying to switch to while a confirmation is pending.
    @State private var pendingMode: EditorMode?
    /// Snapshot of the free-text prompt taken when we first leave Simple mode,
    /// so we can restore the user's original text if they switch back.
    @State private var cachedSimpleText: String?
    /// Set while programmatically applying a user-confirmed conversion so the
    /// resulting picker `.onChange` does not re-present the warning.
    @State private var isApplyingConfirmedModeChange = false

    /// True when switching to the given mode would lossily transform the user's
    /// content (free text stuffed into the structured `task` field).
    private func isLossyConversion(to newMode: EditorMode) -> Bool {
        guard newMode == .advanced else { return false }
        // Parsing as JSON is lossless; only non-JSON free text is at risk.
        if PromptStructure.from(jsonString: simplePromptText) != nil { return false }
        return !simplePromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleModeChange(to newMode: EditorMode) {
        // A confirmed conversion has already transformed the content; just clear
        // the guard and skip the warning + re-applying the transform.
        if isApplyingConfirmedModeChange {
            isApplyingConfirmedModeChange = false
            return
        }

        // Warn before a destructive/lossy Simple -> Advanced conversion. Revert
        // the picker to Simple until the user confirms.
        if isLossyConversion(to: newMode) {
            pendingMode = newMode
            selectedMode = .simple
            showModeChangeAlert = true
            return
        }
        applyModeChange(to: newMode)
    }

    private func applyModeChange(to newMode: EditorMode) {
        if newMode == .advanced {
            // Switching to advanced: try to parse simple text as JSON
            if let parsed = PromptStructure.from(jsonString: simplePromptText) {
                promptStructure = parsed
            } else if !simplePromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Cache the original free text so a later switch-back can restore it,
                // then preserve the user's text as the "task" field so nothing is lost.
                cachedSimpleText = simplePromptText
                var structure = PromptStructure.default
                structure.task = simplePromptText
                promptStructure = structure
            }
            let updated = promptStructure.toJSONString(pretty: true)
            prompt = updated
            advancedPreviewText = updated
        } else {
            // Switching to simple: restore the cached free text if we have one,
            // otherwise fall back to the current (serialized) prompt value.
            if let cached = cachedSimpleText {
                simplePromptText = cached
                prompt = cached
                cachedSimpleText = nil
            } else {
                simplePromptText = prompt
            }
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
