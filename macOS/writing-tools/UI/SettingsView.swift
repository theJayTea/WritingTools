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
                    .onChange(of: selectedTheme) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "theme_style")
                        settings.useGradientTheme = (newValue != "standard")
                    }
                }
                
                Section("AI Provider") {
                    Picker("Provider", selection: $settings.currentProvider) {
                        Text("Local LLM (LLama 3.2)").tag("local")
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
            } else if settings.currentProvider == "local" {
                LocalLLMSettingsView(evaluator: appState.localLLMProvider)
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


struct LocalLLMSettingsView: View {
    @ObservedObject private var llmEvaluator: LocalLLMProvider
    @State private var showingDeleteAlert = false
    @State private var showingErrorAlert = false
    
    init(evaluator: LocalLLMProvider) {
        self.llmEvaluator = evaluator
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !llmEvaluator.modelInfo.isEmpty {
                Text(llmEvaluator.modelInfo)
                    .textFieldStyle(.roundedBorder)
            }
            GroupBox("Model Information") {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Model", value: "LLama3.2 3b (4-bit Quantized)")
                    InfoRow(label: "Size", value: "~1.8GB")
                    InfoRow(label: "Optimized", value: "Apple Silicon")
                }
                .padding(.vertical, 4)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if llmEvaluator.isDownloading {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Downloading model...")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { llmEvaluator.cancelDownload() }) {
                                    Text("Cancel")
                                        .foregroundColor(.red)
                                }
                            }
                            ProgressView(value: llmEvaluator.downloadProgress) {
                                Text("\(Int(llmEvaluator.downloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if llmEvaluator.running {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading model...")
                                .foregroundColor(.secondary)
                        }
                    } else if case .idle = llmEvaluator.loadState {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model needs to be downloaded before first use")
                                .foregroundColor(.secondary)
                            HStack {
                                Button("Download Model") {
                                    llmEvaluator.startDownload()
                                }
                                .buttonStyle(.borderedProminent)
                                if llmEvaluator.lastError != nil {
                                    Button("Retry") {
                                        llmEvaluator.retryDownload()
                                    }
                                    .disabled(llmEvaluator.retryCount >= 3)
                                }
                            }
                            if let error = llmEvaluator.lastError {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Model ready")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("Delete Model") {
                                    showingDeleteAlert = true
                                }
                                .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Delete Model", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                do {
                    try llmEvaluator.deleteModel()
                } catch {
                    llmEvaluator.lastError = "Failed to delete model: \(error.localizedDescription)"
                    showingErrorAlert = true
                }
            }
        } message: {
            Text("Are you sure you want to delete the downloaded model? You'll need to download it again to use local processing.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = llmEvaluator.lastError {
                Text(error)
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}
