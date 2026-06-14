import SwiftUI
import KeyboardShortcuts

private let logger = AppLogger.logger("CommandEditor")

struct CommandEditor: View {
    @Binding var command: CommandModel
    @Bindable private var settings = AppSettings.shared
    @Environment(\.colorScheme) var colorScheme

    var onSave: () -> Void
    var onCancel: () -> Void
    var isBuiltIn: Bool

    @State private var name: String
    @State private var prompt: String
    @State private var selectedIcon: String
    @State private var useResponseWindow: Bool
    @State private var hasShortcut: Bool
    @State private var showingIconPicker = false
    @State private var showDuplicateAlert = false

    // Per-command AI provider configuration
    @State private var useCustomProvider: Bool
    @State private var selectedProvider: String
    @State private var customModel: String

    // Custom provider configuration
    @State private var customProviderBaseURL: String
    @State private var customProviderApiKey: String
    @State private var customProviderModel: String
    @State private var customProviderBaseURLError: String?
    @State private var customProviderApiKeyError: String?
    @State private var customProviderModelError: String?

    // Reference to command manager for duplicate checking
    private var commandManager: CommandManager?

    init(command: Binding<CommandModel>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void, commandManager: CommandManager? = nil) {
        self._command = command
        self.onSave = onSave
        self.onCancel = onCancel
        self.isBuiltIn = command.wrappedValue.isBuiltIn
        self.commandManager = commandManager

        _name = State(initialValue: command.wrappedValue.name)
        _prompt = State(initialValue: command.wrappedValue.prompt)
        _selectedIcon = State(initialValue: command.wrappedValue.icon)
        _useResponseWindow = State(initialValue: command.wrappedValue.useResponseWindow)
        _hasShortcut = State(initialValue: command.wrappedValue.hasShortcut)

        // Initialize provider override states
        _useCustomProvider = State(initialValue: command.wrappedValue.providerOverride != nil)
        _selectedProvider = State(initialValue: command.wrappedValue.providerOverride ?? AppSettings.shared.currentProvider)
        _customModel = State(initialValue: command.wrappedValue.modelOverride ?? "")

        // Initialize custom provider configuration
        _customProviderBaseURL = State(initialValue: command.wrappedValue.customProviderBaseURL ?? "")
        _customProviderApiKey = State(initialValue: KeychainManager.shared.retrieveCustomProviderApiKeySync(for: command.wrappedValue.id) ?? "")
        _customProviderModel = State(initialValue: command.wrappedValue.customProviderModel ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Enhanced Header
            HStack {
                Text(isBuiltIn ? "Edit Built-In Command" : "Edit Command")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(action: { onCancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .accessibilityLabel("Close editor")
                .accessibilityHint("Discard changes and close")
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Tab View
            TabView {
                mainTab
                    .tabItem {
                        Label("Main", systemImage: "gearshape")
                    }
                
                editorTab
                    .tabItem {
                        Label("Editor", systemImage: "pencil")
                    }
            }

            // Buttons (always at bottom, not inside scroll/content)
            HStack(spacing: 16) {
                Button(action: {
                    onCancel()
                }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: saveCommand) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || Self.isPromptEffectivelyEmpty(prompt)
                )
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 6)
        }
        .frame(minWidth: 720, idealWidth: 900, maxWidth: 1100, minHeight: 520, idealHeight: 600, maxHeight: 900)
        .windowBackground(useGradient: settings.useGradientTheme)
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $selectedIcon)
        }
        .alert("Duplicate Command Name", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A command with this name already exists. Please choose a different name.")
        }
    }
    
    // MARK: - Main Tab
    
    private var mainTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("General")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Name")
                            .frame(width: 80, alignment: .leading)
                        TextField("Command Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack(alignment: .center, spacing: 12) {
                        Text("Icon")
                            .frame(width: 80, alignment: .leading)
                        Button(action: { showingIconPicker = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: selectedIcon)
                                    .font(.title3)
                                    .frame(width: 24)
                                Text("Change Icon")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.controlBackgroundColor))
                            .clipShape(.rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }

                // Options Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Options")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Toggle("Display response in window", isOn: $useResponseWindow)

                    Toggle("Enable keyboard shortcut for this command", isOn: $hasShortcut)
                    
                    if hasShortcut {
                        HStack(spacing: 12) {
                            Text("Shortcut:")
                                .frame(width: 80, alignment: .leading)
                            KeyboardShortcuts.Recorder(
                                for: .commandShortcut(for: command.id),
                                onChange: { shortcut in
                                    if shortcut != nil {
                                        hasShortcut = true
                                    }
                                }
                            )
                            Spacer()
                        }
                        
                        Text("Tip: This shortcut will execute the command directly without opening the popup window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // AI Provider Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Provider")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Toggle("Use custom AI provider for this command", isOn: $useCustomProvider)
                        .help("Override the default AI provider for this specific command")

                    if useCustomProvider {
                        HStack(spacing: 12) {
                            Text("Provider:")
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $selectedProvider) {
                                if LocalModelProvider.isAppleSilicon {
                                    Text("Local LLM").tag("local")
                                }
                                Text("Gemini AI").tag("gemini")
                                Text("OpenAI").tag("openai")
                                Text("Anthropic").tag("anthropic")
                                Text("Mistral AI").tag("mistral")
                                Text("Ollama").tag("ollama")
                                Text("OpenRouter").tag("openrouter")
                                Text("Custom Provider").tag("custom")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                            Spacer()
                        }

                        if selectedProvider == "custom" {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Text("Base URL:")
                                        .frame(width: 80, alignment: .leading)
                                    TextField("e.g., https://api.example.com/v1", text: $customProviderBaseURL)
                                        .textFieldStyle(.roundedBorder)
                                }
                                if let customProviderBaseURLError {
                                    Text(customProviderBaseURLError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .padding(.leading, 92)
                                }
                                Text("The base URL of your API endpoint (e.g., https://api.openai.com/v1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 92)

                                HStack(spacing: 12) {
                                    Text("API Key:")
                                        .frame(width: 80, alignment: .leading)
                                    SecureField("Your API key", text: $customProviderApiKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                                if let customProviderApiKeyError {
                                    Text(customProviderApiKeyError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .padding(.leading, 92)
                                }
                                Text("Your API authentication key")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 92)

                                HStack(spacing: 12) {
                                    Text("Model:")
                                        .frame(width: 80, alignment: .leading)
                                    TextField("e.g., gpt-4o-mini", text: $customProviderModel)
                                        .textFieldStyle(.roundedBorder)
                                }
                                if let customProviderModelError {
                                    Text(customProviderModelError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .padding(.leading, 92)
                                }
                                Text("The model identifier to use")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 92)
                            }
                            .padding(.top, 8)
                        } else {
                            HStack(spacing: 12) {
                                Text("Model:")
                                    .frame(width: 80, alignment: .leading)
                                TextField("e.g., gpt-4o-mini, claude-3-5-sonnet", text: $customModel)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Text("Leave empty to use the default model for the selected provider. Examples: gpt-5-mini (OpenAI), claude-sonnet-4-5 (Anthropic), gemini-flash-latest (Gemini)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 92)
                        }
                    }
                }

                if isBuiltIn {
                    Text("This is a built-in command. Your changes will be saved but you can reset to the original configuration later if needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }
    
    // MARK: - Editor Tab
    
    private var editorTab: some View {
        PromptEditorView(prompt: $prompt, isBuiltIn: isBuiltIn, useHorizontalLayout: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    // MARK: - Save Command

    private func saveCommand() {
        let trimmedName = Self.trimmedNameForSave(name)
        guard !trimmedName.isEmpty else { return }

        // Require a non-empty (effective) prompt so we never persist a command
        // that would run with no instructions.
        guard !Self.isPromptEffectivelyEmpty(prompt) else { return }

        clearCustomProviderValidationErrors()
        guard validateCustomProviderFieldsIfNeeded() else { return }
        let normalizedTrimmedName = Self.normalizedCommandName(trimmedName)

        // Check for duplicate command names (excluding the current command)
        if let manager = commandManager,
           Self.hasDuplicateName(
            normalizedCandidateName: normalizedTrimmedName,
            currentCommandID: command.id,
            existingCommands: manager.commands
           ) {
                showDuplicateAlert = true
                return
        }

        if !hasShortcut {
            KeyboardShortcuts.reset(.commandShortcut(for: command.id))
        }
        var updatedCommand = command
        updatedCommand.name = trimmedName
        updatedCommand.prompt = prompt
        updatedCommand.icon = selectedIcon
        updatedCommand.useResponseWindow = useResponseWindow

        // The persisted `hasShortcut` must reflect whether a key was actually
        // recorded. Toggling the switch ON without recording a shortcut would
        // otherwise leave a dead handler registered in AppDelegate.
        updatedCommand.hasShortcut = KeyboardShortcuts.getShortcut(for: .commandShortcut(for: command.id)) != nil

        // Keep the stored top-level formatting flag in sync with the prompt's
        // effective value so `preserveFormatting` and `effectivePreserveFormatting`
        // never diverge (the advanced editor writes rules.preserve_formatting
        // into the JSON but does not touch this stored bool directly).
        updatedCommand.preserveFormatting = updatedCommand.effectivePreserveFormatting

        // Save provider override settings
        if useCustomProvider {
            updatedCommand.providerOverride = selectedProvider

            logger.debug("CommandEditor: Saving with useCustomProvider=true, selectedProvider=\(selectedProvider)")

            if selectedProvider == "custom" {
                // Save custom provider configuration
                let trimmedBaseURL = customProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedApiKey = customProviderApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedModel = customProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)

                updatedCommand.customProviderBaseURL = trimmedBaseURL
                updatedCommand.customProviderModel = trimmedModel
                updatedCommand.modelOverride = nil

                logger.debug("CommandEditor: Saving custom provider - baseURL=\(trimmedBaseURL), apiKey=\(trimmedApiKey.isEmpty ? "empty" : "set"), model=\(trimmedModel)")
                KeychainManager.shared.saveCustomProviderApiKeySync(trimmedApiKey, for: updatedCommand.id)
            } else {
                // Save model override for standard providers
                updatedCommand.modelOverride = customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                updatedCommand.customProviderBaseURL = nil
                updatedCommand.customProviderModel = nil
                KeychainManager.shared.deleteCustomProviderApiKeySync(for: updatedCommand.id)
            }
        } else {
            updatedCommand.providerOverride = nil
            updatedCommand.modelOverride = nil
            updatedCommand.customProviderBaseURL = nil
            updatedCommand.customProviderModel = nil
            KeychainManager.shared.deleteCustomProviderApiKeySync(for: updatedCommand.id)
        }

        command = updatedCommand
        onSave()
    }

    static func normalizedCommandName(_ value: String) -> String {
        trimmedNameForSave(value)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    static func trimmedNameForSave(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the prompt is effectively blank and therefore not savable.
    /// A raw prompt that is empty after trimming is rejected. For a structured
    /// (JSON) prompt we additionally reject one whose effective `task` is blank,
    /// since that would run with no actual instruction.
    static func isPromptEffectivelyEmpty(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        if let structure = PromptStructure.from(jsonString: trimmed) {
            return structure.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return false
    }

    static func hasDuplicateName(
        normalizedCandidateName: String,
        currentCommandID: UUID,
        existingCommands: [CommandModel]
    ) -> Bool {
        existingCommands.contains { existingCommand in
            existingCommand.id != currentCommandID
            && normalizedCommandName(existingCommand.name) == normalizedCandidateName
        }
    }

    private func clearCustomProviderValidationErrors() {
        customProviderBaseURLError = nil
        customProviderApiKeyError = nil
        customProviderModelError = nil
    }

    private func validateCustomProviderFieldsIfNeeded() -> Bool {
        guard useCustomProvider, selectedProvider == "custom" else { return true }

        let trimmedBaseURL = customProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedApiKey = customProviderApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = customProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)

        var hasValidationError = false
        if trimmedBaseURL.isEmpty {
            customProviderBaseURLError = "Base URL is required."
            hasValidationError = true
        }
        if trimmedApiKey.isEmpty {
            customProviderApiKeyError = "API key is required."
            hasValidationError = true
        }
        if trimmedModel.isEmpty {
            customProviderModelError = "Model is required."
            hasValidationError = true
        }

        return !hasValidationError
    }
}
