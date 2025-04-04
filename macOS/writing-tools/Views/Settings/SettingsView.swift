import SwiftUI
import Carbon.HIToolbox
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showPopup = Self("showPopup")
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings = AppSettings.shared
    
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
        ScrollView {
            VStack(spacing: 10) {
                if !showOnlyApiSetup {
                    generalSettingsSection
                    appearanceSection
                    aiProviderSection
                }
                
                providerSpecificSettings
                
                Button(showOnlyApiSetup ? "Complete Setup" : "Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500)
        .background(
            Rectangle()
                .fill(Color.clear)
                .windowBackground(useGradient: settings.useGradientTheme)
        )
    }
    
    private var generalSettingsSection: some View {
        GroupBox {
            KeyboardShortcuts.Recorder("Global Shortcut:", name: .showPopup)
                .padding(.vertical, 4)
        }
    }
    
    private var appearanceSection: some View {
        GroupBox {
            Picker("Theme", selection: $settings.themeStyle) {
                Text("Standard").tag("standard")
                Text("Gradient").tag("gradient")
                Text("Glass").tag("glass")
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
            // The onChange is handled by the property wrapper in AppSettings
        }
    }
    
    private var aiProviderSection: some View {
        GroupBox{
            VStack(alignment: .leading) {
                Picker("Provider", selection: $settings.currentProvider) {
                    if LocalLLMProvider.isAppleSilicon {
                        Text("Local LLM").tag("local")
                    }
                    Text("Gemini AI").tag("gemini")
                    Text("OpenAI").tag("openai")
                    Text("Mistral AI").tag("mistral")
                    Text("Ollama").tag("ollama")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: settings.currentProvider, initial: false) { oldValue, newValue in
                    if newValue == "local" && !LocalLLMProvider.isAppleSilicon {
                        settings.currentProvider = "gemini"
                    }
                }
                
                if settings.currentProvider == "local" {
                    Text("(Llama 3.2)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var providerSpecificSettings: some View {
        Group {
            if settings.currentProvider == "gemini" {
                geminiSettings
            } else if settings.currentProvider == "mistral" {
                mistralSettings
            } else if settings.currentProvider == "openai" {
                openAISettings
            } else if settings.currentProvider == "ollama" {
                ollamaSettings
            } else if settings.currentProvider == "local" {
                LocalLLMSettingsView(evaluator: appState.localLLMProvider)
            }
        }
    }
    
    private var geminiSettings: some View {
        GroupBox("Gemini AI Settings") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("API Key", text: $settings.geminiApiKey)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Model", selection: $settings.geminiModel) {
                    ForEach(GeminiModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button("Get API Key") {
                    if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var mistralSettings: some View {
        GroupBox("Mistral AI Settings") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("API Key", text: $settings.mistralApiKey)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Base URL", text: $settings.mistralBaseURL)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Model", selection: $settings.mistralModel) {
                    ForEach(MistralModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(model.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button("Get Mistral API Key") {
                    if let url = URL(string: "https://console.mistral.ai/api-keys/") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var openAISettings: some View {
        GroupBox("OpenAI Settings") {
            VStack(alignment: .leading, spacing: 12) {
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
                    set: { settings.openAIOrganization = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
                TextField("Project ID (Optional)", text: Binding(
                    get: { settings.openAIProject ?? "" },
                    set: { settings.openAIProject = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
                Button("Get OpenAI API Key") {
                    if let url = URL(string: "https://platform.openai.com/account/api-keys") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var ollamaSettings: some View {
        GroupBox("Ollama Provider Settings") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Ollama Base URL", text: $settings.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Ollama Model", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Keep Alive Time", text: $settings.ollamaKeepAlive)
                    .textFieldStyle(.roundedBorder)
                
                LinkText()
                
                Button("Ollama Documentation") {
                    if let url = URL(string: "https://ollama.ai/download") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func saveSettings() {
        let oldShortcut = UserDefaults.standard.string(forKey: "shortcut")
        
        UserDefaults.standard.set(settings.shortcutText, forKey: "shortcut")
        
        // No need to manually set theme_style as it's handled by the property wrapper
        
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
            if !llmEvaluator.isPlatformSupported {
                platformNotSupportedView
            } else {
                supportedPlatformView
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
    
    private var platformNotSupportedView: some View {
        VStack(alignment: .center, spacing: 20) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("Apple Silicon Required")
                .font(.title)
                .bold()
            
            Text("Local LLM is only available on Apple Silicon devices (M1/M2/M3 Macs).")
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            
            Text("Please use one of the online models instead:")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("OpenAI (GPT-4/3.5)", systemImage: "cloud")
                Label("Gemini", systemImage: "cloud")
                Label("Mistral", systemImage: "cloud")
                Label("Ollama (local, but requires separate installation)", systemImage: "desktopcomputer")
            }
            .padding(.vertical)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
    
    private var supportedPlatformView: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !llmEvaluator.modelInfo.isEmpty {
                Text(llmEvaluator.modelInfo)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Model", value: "Llama 3.2 3B (4-bit Quantized)")
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
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
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
