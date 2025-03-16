import SwiftUI
import Carbon.HIToolbox
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showPopup = Self("showPopup")
    
    // Generate a shortcut name for a specific command
    static func commandShortcut(for id: UUID) -> Self {
        return Self("command_\(id.uuidString)")
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings = AppSettings.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var needsSaving: Bool = false
    @State private var showingCommandsManager = false
    
    var showOnlyApiSetup: Bool = false
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case appearance = "Appearance"
        case aiProvider = "AI Provider"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .appearance: return "paintpalette"
            case .aiProvider: return "brain.head.profile"
            }
        }
    }
    
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
        TabView(selection: $selectedTab) {
            generalPane
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)
            
            appearancePane
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }
                .tag(SettingsTab.appearance)
            
            aiProviderPane
                .tabItem {
                    Label("AI Provider", systemImage: "brain.head.profile")
                }
                .tag(SettingsTab.aiProvider)
        }
        .padding(20)
        .frame(width: 540, height: showOnlyApiSetup ? 400 : 460)
        .background(
            Rectangle()
                .fill(Color.clear)
                .windowBackground(useGradient: settings.useGradientTheme)
        )
        .onChange(of: selectedTab) { oldValue, newValue in 
            // Save selected tab for next time
            UserDefaults.standard.set(selectedTab.rawValue, forKey: "lastSettingsTab")
        }
        .onAppear {
            // Restore last selected tab
            if let savedTab = UserDefaults.standard.string(forKey: "lastSettingsTab"),
               let tab = SettingsTab(rawValue: savedTab) {
                selectedTab = tab
            }
            
            // Configure window properties
            DispatchQueue.main.async {
                if let window = NSApplication.shared.windows.first(where: {
                    $0.contentView?.subviews.contains(where: { $0 is NSHostingView<SettingsView> }) ?? false
                }) {
                    window.title = "\(selectedTab.rawValue) Settings"
                    
                    // Disable minimize and zoom buttons
                    window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
                    window.standardWindowButton(.zoomButton)?.isEnabled = false
                }
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            DispatchQueue.main.async {
                if let window = NSApplication.shared.windows.first(where: {
                    $0.contentView?.subviews.contains(where: { $0 is NSHostingView<SettingsView> }) ?? false
                }) {
                    window.title = "\(newValue.rawValue) Settings"
                }
            }
        }
    }
    
    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("General Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Global Keyboard Shortcut")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                KeyboardShortcuts.Recorder("Activate Writing Tools:", name: .showPopup)
                    .padding(.vertical, 2)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Commands")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Manage your writing tools and their keyboard shortcuts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    showingCommandsManager = true
                }) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Manage Commands")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            if !showOnlyApiSetup {
                saveButton
            }
        }
        .sheet(isPresented: $showingCommandsManager) {
            CommandsView(commandManager: appState.commandManager)
        }
    }
    
    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Appearance Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Window Style")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Choose how the app windows will appear")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Theme", selection: $settings.themeStyle) {
                    Text("Standard").tag("standard")
                    Text("Gradient").tag("gradient")
                    Text("Glass").tag("glass")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
                .onChange(of: settings.themeStyle) { oldValue, newValue in 
                    needsSaving = true 
                }
            }
            
            Spacer()
            
            if !showOnlyApiSetup {
                saveButton
            }
        }
    }
    
    private var aiProviderPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("AI Provider Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Select AI Service")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
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
                .onChange(of: settings.currentProvider) { oldValue, newValue in
                    if newValue == "local" && !LocalLLMProvider.isAppleSilicon {
                        settings.currentProvider = "gemini"
                    }
                    needsSaving = true
                }
                
                if settings.currentProvider == "local" {
                    Text("(Qwen2.5 3B 4-bit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
                .padding(.vertical, 4)
            
            ScrollView {
                providerSpecificSettings
                    .frame(maxWidth: .infinity)
            }
            
            if !showOnlyApiSetup {
                saveButton
            } else {
                completeSetupButton
            }
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
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("API Key", text: $settings.geminiApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.geminiApiKey) { oldValue, newValue in 
                            needsSaving = true 
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Selection")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Model", selection: $settings.geminiModel) {
                        ForEach(GeminiModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: settings.geminiModel) { oldValue, newValue in 
                        needsSaving = true 
                    }
                }
            }
            .padding(.bottom, 4)
                            
            Button("Get API Key") {
                if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
    }
    
    private var mistralSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("API Key", text: $settings.mistralApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.mistralApiKey) { oldValue, newValue in 
                            needsSaving = true 
                        }
                    
                    TextField("Base URL", text: $settings.mistralBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.mistralBaseURL) { oldValue, newValue in 
                            needsSaving = true 
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Selection")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Model", selection: $settings.mistralModel) {
                        ForEach(MistralModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: settings.mistralModel) { oldValue, newValue in 
                        needsSaving = true 
                    }
                }
            }
            .padding(.bottom, 4)
                            
            Button("Get Mistral API Key") {
                if let url = URL(string: "https://console.mistral.ai/api-keys/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
    }
    
    private var openAISettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("API Key", text: $settings.openAIApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.openAIApiKey) { oldValue, newValue in 
                            needsSaving = true 
                        }
                    
                    TextField("Base URL", text: $settings.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.openAIBaseURL) { oldValue, newValue in 
                            needsSaving = true 
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Model Name", text: $settings.openAIModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.openAIModel) { oldValue, newValue in 
                            needsSaving = true 
                        }
                    
                    Text("OpenAI models include: gpt-4o, gpt-4o-mini, etc.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Advanced Options")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Organization ID (Optional)", text: Binding(
                        get: { settings.openAIOrganization ?? "" },
                        set: { 
                            settings.openAIOrganization = $0.isEmpty ? nil : $0 
                            needsSaving = true
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    TextField("Project ID (Optional)", text: Binding(
                        get: { settings.openAIProject ?? "" },
                        set: { 
                            settings.openAIProject = $0.isEmpty ? nil : $0 
                            needsSaving = true
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
            .padding(.bottom, 4)
                            
            Button("Get OpenAI API Key") {
                if let url = URL(string: "https://platform.openai.com/account/api-keys") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
    }
    
    private var ollamaSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection Settings")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Ollama Base URL", text: $settings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.ollamaBaseURL) { oldValue, newValue in 
                            needsSaving = true 
                        }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("Ollama Model", text: $settings.ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.ollamaModel) { oldValue, newValue in 
                            needsSaving = true 
                        }
                    
                    TextField("Keep Alive Time", text: $settings.ollamaKeepAlive)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.ollamaKeepAlive) { oldValue, newValue in 
                            needsSaving = true 
                        }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Documentation")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    LinkText()
                }
            }
            .padding(.bottom, 4)
                            
            Button("Ollama Documentation") {
                if let url = URL(string: "https://ollama.ai/download") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
    }
    
    private var saveButton: some View {
        HStack {
            Spacer()
            Button("Save Changes") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!needsSaving)
        }
    }
    
    private var completeSetupButton: some View {
        HStack {
            Spacer()
            Button("Complete Setup") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
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
            
            Text("Local LLM is only available on Apple Silicon devices.")
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
                    InfoRow(label: "Model", value: "Qwen2.5 3B (4-bit Quantized)")
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
