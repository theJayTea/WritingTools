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
    @State private var isNameDuplicate = false
    @State private var showDuplicateAlert = false

    // Per-command AI provider configuration
    @State private var useCustomProvider: Bool
    @State private var selectedProvider: String
    @State private var customModel: String

    // Custom provider configuration
    @State private var customProviderBaseURL: String
    @State private var customProviderApiKey: String
    @State private var customProviderModel: String

    init(command: Binding<CommandModel>, onSave: @escaping () -> Void, onCancel: @escaping () -> Void, commandManager: CommandManager? = nil) {
        self._command = command
        self.onSave = onSave
        self.onCancel = onCancel
        self.isBuiltIn = command.wrappedValue.isBuiltIn

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
        _customProviderApiKey = State(initialValue: command.wrappedValue.customProviderApiKey ?? "")
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
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 6)
        }
        .frame(width: 900, height: 600)
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
                            Text("Leave empty to use the default model for the selected provider. Examples: gpt-4o-mini (OpenAI), claude-3-5-sonnet-20240620 (Anthropic), gemini-flash-latest (Gemini)")
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
        if !hasShortcut {
            KeyboardShortcuts.reset(.commandShortcut(for: command.id))
        }
        var updatedCommand = command
        updatedCommand.name = name
        updatedCommand.prompt = prompt
        updatedCommand.icon = selectedIcon
        updatedCommand.useResponseWindow = useResponseWindow
        updatedCommand.hasShortcut = hasShortcut

        // Save provider override settings
        if useCustomProvider {
            updatedCommand.providerOverride = selectedProvider

            logger.debug("CommandEditor: Saving with useCustomProvider=true, selectedProvider=\(selectedProvider)")

            if selectedProvider == "custom" {
                // Save custom provider configuration
                let trimmedBaseURL = customProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedApiKey = customProviderApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedModel = customProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)

                updatedCommand.customProviderBaseURL = trimmedBaseURL.isEmpty ? nil : trimmedBaseURL
                updatedCommand.customProviderApiKey = trimmedApiKey.isEmpty ? nil : trimmedApiKey
                updatedCommand.customProviderModel = trimmedModel.isEmpty ? nil : trimmedModel
                updatedCommand.modelOverride = nil

                logger.debug("CommandEditor: Saving custom provider - baseURL=\(trimmedBaseURL), apiKey=\(trimmedApiKey.isEmpty ? "empty" : "set"), model=\(trimmedModel)")
            } else {
                // Save model override for standard providers
                updatedCommand.modelOverride = customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                updatedCommand.customProviderBaseURL = nil
                updatedCommand.customProviderApiKey = nil
                updatedCommand.customProviderModel = nil
            }
        } else {
            updatedCommand.providerOverride = nil
            updatedCommand.modelOverride = nil
            updatedCommand.customProviderBaseURL = nil
            updatedCommand.customProviderApiKey = nil
            updatedCommand.customProviderModel = nil
        }

        command = updatedCommand
        onSave()
    }
}
