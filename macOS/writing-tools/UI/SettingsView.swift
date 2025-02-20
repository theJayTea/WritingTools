import SwiftUI
import Carbon.HIToolbox
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showPopup = Self("showPopup")
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings = AppSettings.shared
    @State private var selectedTheme: String = UserDefaults.standard.string(forKey: "theme_style") ?? "gradient"
    @State private var displayShortcut = ""
    
    var showOnlyApiSetup: Bool = false
    
    struct LinkText: View {
        var body: some View {
            HStack(spacing: 4) {
                Text("Local LLMs: use the instructions on")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("GitHub Page")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .underline()
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/theJayTea/WritingTools?tab=readme-ov-file#-optional-ollama-local-llm-instructions") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                Text(".")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    var body: some View {
        Form {
            if !showOnlyApiSetup {
                Section("General Settings") {
                    KeyboardShortcuts.Recorder("Global Shortcut:", name: .showPopup)
                }
                
                Section("Appearance") {
                    Picker("Theme", selection: $selectedTheme) {
                        Text("Standard").tag("standard")
                        Text("Gradient").tag("gradient")
                        Text("Glass").tag("glass")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedTheme) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "theme_style")
                        settings.useGradientTheme = (newValue != "standard")
                    }
                }
                
                Section("AI Provider") {
                    Picker("Provider", selection: $settings.currentProvider) {
                        Text("Gemini AI").tag("gemini")
                        Text("OpenAI").tag("openai")
                        Text("Mistral AI").tag("mistral")
                        Text("Ollama").tag("ollama")
                    }
                }
            }
            
            if settings.currentProvider == "gemini" {
                Section("Gemini AI Settings") {
                    TextField("API Key", text: $settings.geminiApiKey)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("Model", selection: $settings.geminiModel) {
                        ForEach(GeminiModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    
                    Button("Get API Key") {
                        if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else if settings.currentProvider == "mistral" {
                Section("Mistral AI Settings") {
                    TextField("API Key", text: $settings.mistralApiKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Base URL", text: $settings.mistralBaseURL)
                        .textFieldStyle(.roundedBorder)
                    Picker("Model", selection: $settings.mistralModel) {
                        ForEach(MistralModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    Button("Get Mistral API Key") {
                        if let url = URL(string: "https://console.mistral.ai/api-keys/") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else if settings.currentProvider == "openai" {
                Section("OpenAI Settings") {
                    TextField("API Key", text: $settings.openAIApiKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Base URL", text: $settings.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model Name", text: $settings.openAIModel)
                        .textFieldStyle(.roundedBorder)
                    Text("OpenAI models include: gpt-4o, gpt-4o-mini, etc.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    LinkText()
                    TextField("Organization ID (Optional)", text: Binding(
                        get: { settings.openAIOrganization ?? "" },
                        set: { settings.openAIOrganization = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    TextField("Project ID (Optional)", text: Binding(
                        get: { settings.openAIProject ?? "" },
                        set: { settings.openAIProject = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Get OpenAI API Key") {
                            if let url = URL(string: "https://platform.openai.com/account/api-keys") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } else if settings.currentProvider == "ollama" {
                Section(header: Text("Ollama Provider Settings")) {
                    TextField("Ollama Base URL", text: $settings.ollamaBaseURL)
                    TextField("Ollama Model", text: $settings.ollamaModel)
                    TextField("Keep Alive Time", text: $settings.ollamaKeepAlive)
                    LinkText()
                    HStack {
                        Button("Ollama Documentation") {
                            if let url = URL(string: "https://ollama.ai/download") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            
            Button(showOnlyApiSetup ? "Complete Setup" : "Save") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 500)
        .windowBackground(useGradient: settings.useGradientTheme)
    }
    
    private func saveSettings() {
        let oldShortcut = UserDefaults.standard.string(forKey: "shortcut")
        
        UserDefaults.standard.set(settings.shortcutText, forKey: "shortcut")
        UserDefaults.standard.set(selectedTheme, forKey: "theme_style")
        UserDefaults.standard.set(selectedTheme != "standard", forKey: "use_gradient_theme")
        
        // Save provider-specific settings
        if settings.currentProvider == "gemini" {
            appState.saveGeminiConfig(apiKey: settings.geminiApiKey, model: settings.geminiModel)
        } else if settings.currentProvider == "mistral" {
            appState.saveMistralConfig(
                apiKey: settings.mistralApiKey,
                baseURL: settings.mistralBaseURL,
                model: settings.mistralModel
            )
        } else if settings.currentProvider == "openai" {
            appState.saveOpenAIConfig(
                apiKey: settings.openAIApiKey,
                baseURL: settings.openAIBaseURL,
                organization: settings.openAIOrganization,
                project: settings.openAIProject,
                model: settings.openAIModel
            )
        } else if settings.currentProvider == "ollama" {
            appState.saveOllamaConfig(
                baseURL: settings.ollamaBaseURL,
                model: settings.ollamaModel,
                keepAlive: settings.ollamaKeepAlive
            )
        }
        
        // Set current provider
        appState.setCurrentProvider(settings.currentProvider)
        
        // If shortcut changed, post notification
        if oldShortcut != settings.shortcutText {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }
        
        // If this is the onboarding API setup, mark onboarding as complete
        if showOnlyApiSetup {
            UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
        }
        
        // Close window
        DispatchQueue.main.async {
            if self.showOnlyApiSetup {
                WindowManager.shared.cleanupWindows()
            } else if let window = NSApplication.shared.windows.first(where: {
                $0.contentView?.subviews.contains(where: { $0 is NSHostingView<SettingsView> }) ?? false
            }) {
                window.close()
            }
        }
    }
}
