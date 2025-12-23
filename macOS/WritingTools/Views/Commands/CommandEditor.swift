import SwiftUI
import KeyboardShortcuts

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
                    .foregroundColor(.primary)
                Spacer()
                Button(action: { onCancel() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cancel")
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 16) {
                // Command Info Card
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.headline)
                            .foregroundColor(.primary)
                        TextField("Command Name", text: $name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Button(action: { showingIconPicker = true }) {
                            HStack {
                                Image(systemName: selectedIcon)
                                    .font(.title2)
                                    .frame(width: 30)
                                Text("Change Icon")
                                    .font(.subheadline)
                            }
                            .padding(6)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Toggle("Display response in window", isOn: $useResponseWindow)

                // MARK: - AI Provider Configuration Section
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Use custom AI provider for this command", isOn: $useCustomProvider)
                        .help("Override the default AI provider for this specific command")

                    if useCustomProvider {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Provider:")
                                    .foregroundColor(.secondary)
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
                            }

                            if selectedProvider == "custom" {
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Base URL:")
                                                .foregroundColor(.secondary)
                                                .frame(width: 80, alignment: .leading)
                                            TextField("e.g., https://api.example.com/v1", text: $customProviderBaseURL)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                        Text("The base URL of your API endpoint (e.g., https://api.openai.com/v1)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 84)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("API Key:")
                                                .foregroundColor(.secondary)
                                                .frame(width: 80, alignment: .leading)
                                            SecureField("Your API key", text: $customProviderApiKey)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                        Text("Your API authentication key")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 84)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Model:")
                                                .foregroundColor(.secondary)
                                                .frame(width: 80, alignment: .leading)
                                            TextField("e.g., gpt-4o-mini", text: $customProviderModel)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                        Text("The model identifier to use")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 84)
                                    }
                                }
                                .padding(.top, 4)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Model (optional):")
                                            .foregroundColor(.secondary)
                                        TextField("e.g., gpt-4o-mini, claude-3-5-sonnet", text: $customModel)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    Text("Leave empty to use the default model for the selected provider. Examples: gpt-4o-mini (OpenAI), claude-3-5-sonnet-20240620 (Anthropic), gemini-flash-latest (Gemini)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.top, 4)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Keyboard Shortcut")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Toggle("Enable keyboard shortcut for this command", isOn: $hasShortcut)
                    if hasShortcut {
                        HStack {
                            Text("Command shortcut:")
                                .foregroundColor(.secondary)
                            KeyboardShortcuts.Recorder(
                                for: .commandShortcut(for: command.id),
                                onChange: { shortcut in
                                    if shortcut != nil {
                                        hasShortcut = true
                                    }
                                }
                            )
                        }
                        Text("Tip: This shortcut will execute the command directly without opening the popup window.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt")
                        .font(.headline)
                        .foregroundColor(.primary)
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.textBackgroundColor))
                            .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
                        TextEditor(text: $prompt)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(6)
                    }
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }

                if isBuiltIn {
                    Text("This is a built-in command. Your changes will be saved but you can reset to the original configuration later if needed.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxHeight: .infinity, alignment: .top) // Pushes buttons to bottom

            // Buttons (always at bottom, not inside scroll/content)
            HStack(spacing: 16) {
                Button(action: {
                    onCancel()
                }) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: {
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

                        NSLog("CommandEditor: Saving with useCustomProvider=true, selectedProvider=\(selectedProvider)")

                        if selectedProvider == "custom" {
                            // Save custom provider configuration
                            let trimmedBaseURL = customProviderBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedApiKey = customProviderApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedModel = customProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)

                            updatedCommand.customProviderBaseURL = trimmedBaseURL.isEmpty ? nil : trimmedBaseURL
                            updatedCommand.customProviderApiKey = trimmedApiKey.isEmpty ? nil : trimmedApiKey
                            updatedCommand.customProviderModel = trimmedModel.isEmpty ? nil : trimmedModel
                            updatedCommand.modelOverride = nil

                            NSLog("CommandEditor: Saving custom provider - baseURL=\(trimmedBaseURL), apiKey=\(trimmedApiKey.isEmpty ? "empty" : "set"), model=\(trimmedModel)")
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
                    NotificationCenter.default.post(name: NSNotification.Name("CommandsChanged"), object: nil)
                    onSave()
                }) {
                    Text("Save")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
            .padding(.top, 6)
        }
        .frame(width: 500, height: 800)
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
}
