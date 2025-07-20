import SwiftUI
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
        case general     = "General"
        case appearance  = "Appearance"
        case aiProvider  = "AI Provider"
        
        var id: Self { self }
    }
    
    struct LinkText: View {
        var body: some View {
            HStack(spacing: 4) {
                Text("Local LLMs: use the instructions on")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("GitHub Page.")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .underline()
                    .onTapGesture {
                        if let url = URL(string: "https://github.com/theJayTea/WritingTools?tab=readme-ov-file#-optional-ollama-local-llm-instructions") {
                            NSWorkspace.shared.open(url)
                        }
                    }
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                WindowControlButtons()
                Spacer()
            }
            .contentShape(Rectangle())          // draggable
            
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            Group {
                switch selectedTab {
                case .general:     generalPane
                case .appearance:  appearancePane
                case .aiProvider:  aiProviderPane
                }
            }
            .padding(20)
        }
        .frame(width: 540, height: showOnlyApiSetup ? 400 : 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .windowBackground(useGradient: settings.useGradientTheme)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .onAppear(perform: restoreLastTab)
        .onChange(of: selectedTab) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue,
                                      forKey: "lastSettingsTab")
            updateWindowTitle(to: newValue)
        }
        
    }
    
    private func restoreLastTab() {
        if let saved = UserDefaults.standard.string(forKey: "lastSettingsTab"),
           let savedTab = SettingsTab(rawValue: saved) {
            selectedTab = savedTab
        }
        updateWindowTitle(to: selectedTab)
    }
    
    private func updateWindowTitle(to tab: SettingsTab) {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: {
                $0.contentView?
                    .subviews
                    .contains(where: { $0 is NSHostingView<SettingsView> })
                ?? false
            }) {
                window.title = "\(tab.rawValue) Settings"
                
                // disable unused buttons
                window.standardWindowButton(.miniaturizeButton)?
                    .isEnabled = false
                window.standardWindowButton(.zoomButton)?
                    .isEnabled = false
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
                
                Text("Choose how the popup window looks.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Theme", selection: $settings.themeStyle) {
                    Text("Standard").tag("standard")
                    Text("Gradient").tag("gradient")
                    Text("Glass").tag("glass")
                    Text("OLED").tag("oled")
                    Text("LiquidGlass").tag("liquidGlass")
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
                    if LocalModelProvider.isAppleSilicon {
                        Text("Local LLM").tag("local")
                    }
                    Text("Gemini AI").tag("gemini")
                    Text("OpenAI").tag("openai")
                    Text("Anthropic").tag("anthropic")
                    Text("Mistral AI").tag("mistral")
                    Text("Ollama").tag("ollama")
                    Text("OpenRouter").tag("openrouter")
                }
                
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: settings.currentProvider) { oldValue, newValue in
                    if newValue == "local" && !LocalModelProvider.isAppleSilicon {
                        settings.currentProvider = "gemini"
                    }
                    needsSaving = true
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
            } else if settings.currentProvider == "anthropic" {
                anthropicSettings
            } else if settings.currentProvider == "openai" {
                openAISettings
            } else if settings.currentProvider == "ollama" {
                ollamaSettings
            } else if settings.currentProvider == "openrouter" {
                openRouterSettings
            } else if settings.currentProvider == "local" {
                LocalLLMSettingsView(provider: appState.localLLMProvider)
            }
        }
    }
    
    private var openRouterSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configure OpenRouter")
                .font(.headline)
            TextField("API Key", text: $settings.openRouterApiKey)
                .textFieldStyle(.roundedBorder)
                .onChange(of: settings.openRouterApiKey) { _, _ in needsSaving = true }
            
            Picker("Model", selection: $settings.openRouterModel) {
                ForEach(OpenRouterModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: settings.openRouterModel) { _, _ in needsSaving = true }
            
            if settings.openRouterModel == OpenRouterModel.custom.rawValue {
                TextField("Custom Model Name", text: $settings.openRouterCustomModel)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settings.openRouterCustomModel) { _, _ in needsSaving = true }
                    .padding(.top, 4)
            }
            
            Button("Get OpenRouter API Key") {
                if let url = URL(string: "https://openrouter.ai/keys") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
        }
    }
    
    private var anthropicSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Configuration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("API Key", text: $settings.anthropicApiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.anthropicApiKey) { _, _ in needsSaving = true }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Selection")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Model", selection: $settings.anthropicModel) {
                        ForEach(AnthropicModel.allCases, id: \.self) { model in
                            Text(model.displayName).tag(model.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: settings.anthropicModel) { _, _ in needsSaving = true }
                    
                    TextField("Or Custom Model Name", text: $settings.anthropicModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onChange(of: settings.anthropicModel) { _, _ in needsSaving = true }
                    Text("E.g., \(AnthropicModel.claude3Haiku.rawValue), \(AnthropicModel.claude3Sonnet.rawValue), etc.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 4)
            
            Button("Get Anthropic API Key") {
                if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
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
                        .onChange(of: settings.geminiApiKey) { _, _ in
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
                    .onChange(of: settings.geminiModel) { _, _ in
                        needsSaving = true
                    }
                    
                    if settings.geminiModel == .custom {         // ADD: show field for custom
                        TextField("Custom Model Name", text: $settings.geminiCustomModel)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.geminiCustomModel) { _, _ in
                                needsSaving = true
                            }
                            .padding(.top, 4)
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
                    
                    /*TextField("Base URL", text: $settings.mistralBaseURL)
                     .textFieldStyle(.roundedBorder)
                     .onChange(of: settings.mistralBaseURL) { oldValue, newValue in
                     needsSaving = true
                     }*/
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
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image Recognition")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Image Mode", selection: $settings.ollamaImageMode) {
                        ForEach(OllamaImageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.ollamaImageMode) { oldValue, newValue in
                        needsSaving = true
                    }
                    
                    Text("Choose between performing OCR locally or using an Ollama vision-enabled model for image input.")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            appState.saveGeminiConfig(
                apiKey: settings.geminiApiKey,
                model: settings.geminiModel,
                customModelName: settings.geminiCustomModel   // ADD: pass custom
            )
        } else if settings.currentProvider == "mistral" {
            appState.saveMistralConfig(
                apiKey: settings.mistralApiKey,
                baseURL: settings.mistralBaseURL,
                model: settings.mistralModel
            )
        } else if settings.currentProvider == "anthropic" {
            appState.saveAnthropicConfig(
                apiKey: settings.anthropicApiKey,
                model: settings.anthropicModel
            )
        }
        else if settings.currentProvider == "openrouter" {
            appState.saveOpenRouterConfig(
                apiKey: settings.openRouterApiKey,
                model: OpenRouterModel(rawValue: settings.openRouterModel) ?? .gpt4o,
                customModelName: settings.openRouterCustomModel
            )
        }
        else if settings.currentProvider == "openai" {
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
        
        // Save ollama image mode
        UserDefaults.standard.set(settings.ollamaImageMode.rawValue, forKey: "ollama_image_mode")
        
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
    @ObservedObject private var llmProvider: LocalModelProvider
    @ObservedObject private var settings = AppSettings.shared
    
    @State private var showingDeleteAlert = false
    @State private var showingErrorAlert = false
    @State private var selectedModelCategory: ModelCategory = .all
    
    enum ModelCategory: String, CaseIterable, Identifiable {
        case all = "All Models"
        case text = "Text Models"
        case vision = "Vision Models"
        
        var id: String { self.rawValue }
    }
    
    init(provider: LocalModelProvider) {
        self.llmProvider = provider
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !llmProvider.isPlatformSupported {
                platformNotSupportedView
            } else {
                supportedPlatformView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // --- Delete Alert ---
        .alert("Delete Model", isPresented: $showingDeleteAlert, presenting: llmProvider.selectedModelType) { modelType in
            Button("Cancel", role: .cancel) { }
            Button("Delete \(modelType.displayName)") {
                Task {
                    do {
                        try llmProvider.deleteModel()
                    } catch {
                        llmProvider.lastError = "Failed to delete \(modelType.displayName): \(error.localizedDescription)"
                    }
                }
            }
        } message: { modelType in
            Text("Are you sure you want to delete the downloaded model \(modelType.displayName)? You'll need to download it again to use it.")
        }
        // --- General Error Alert ---
        .alert("Local LLM Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { llmProvider.lastError = nil }
        } message: {
            Text(llmProvider.lastError ?? "An unknown error occurred.")
        }
        .onChange(of: llmProvider.lastError) { _, newValue in
            // Show the alert if a new error is set by the provider
            if newValue != nil {
                showingErrorAlert = true
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
            
            Text("Local LLM processing is only available on Apple Silicon (M1/M2/M3/M4 etc.) devices.")
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            
            Text("Please select a different AI Provider in the settings if you are on an Intel Mac.")
                .font(.headline)
                .multilineTextAlignment(.center)
            
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
    
    // Filter models based on the selected category
    private var filteredModels: [LocalModelType] {
        switch selectedModelCategory {
        case .all:
            return LocalModelType.allCases
        case .text:
            return LocalModelType.allCases.filter { !$0.isVisionModel }
        case .vision:
            return LocalModelType.allCases.filter { $0.isVisionModel }
        }
    }
    
    private var supportedPlatformView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // --- Category Filter ---
            Picker("Filter", selection: $selectedModelCategory) {
                ForEach(ModelCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)
            
            // --- Model Selection Picker ---
            VStack(alignment: .leading, spacing: 4) {
                Text("Select Local Model")
                    .font(.headline)
                Picker("Model", selection: $settings.selectedLocalLLMId) {
                    Text("None Selected").tag(String?.none)
                    
                    // Filter models based on selected category
                    ForEach(filteredModels) { modelType in
                        HStack {
                            Text(modelType.displayName)
                            // Optional: Add a camera icon to indicate vision models
                            if modelType.isVisionModel {
                                Image(systemName: "camera.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .tag(String?.some(modelType.id))
                    }
                }
                .pickerStyle(.menu)
                
                Text("Choose a model to download and use for local processing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let selectedModel = llmProvider.selectedModelType {
                    HStack {
                        if selectedModel.isVisionModel {
                            Label("Vision-capable model", systemImage: "camera.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text("Can process images directly")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Label("Text-only model", systemImage: "text.justifyleft")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, 10)
            
            
            // --- Status/Action Section (only if a model is selected) ---
            if let selectedModelType = llmProvider.selectedModelType {
                GroupBox("Status: \(selectedModelType.displayName)") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Display current status info from provider
                        if !llmProvider.modelInfo.isEmpty {
                            Text(llmProvider.modelInfo)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // --- Action Buttons / Progress ---
                        modelActionView(for: selectedModelType)
                        
                        // Display last error specific to this model
                        if let error = llmProvider.lastError {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                // Prompt to select a model
                Text("Please select a model from the dropdown above to see its status and download options.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
    
    // --- Extracted View for Model Actions ---
    @ViewBuilder
    private func modelActionView(for modelType: LocalModelType) -> some View {
        // Show relevant controls based on the provider's state for the selected model
        switch llmProvider.loadState {
        case .idle, .checking:
            ProgressView().controlSize(.small) // Show activity indicator while checking
            Text("Checking status...")
                .foregroundColor(.secondary)
        case .needsDownload:
            HStack {
                Button("Download \(modelType.displayName)") {
                    llmProvider.startDownload()
                }
                .buttonStyle(.borderedProminent)
                .disabled(llmProvider.isDownloading) // Disable while download starts
                
                // Show retry button only if there was a previous error
                if llmProvider.lastError != nil && llmProvider.retryCount < 3 {
                    Button("Retry Download") {
                        llmProvider.retryDownload()
                    }
                    .disabled(llmProvider.isDownloading)
                }
            }
            
        case .downloaded, .loaded: // Model is ready or loaded
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("\(modelType.displayName) Ready")
                    .foregroundColor(.secondary)
                Spacer()
                Button("Delete Model") {
                    showingDeleteAlert = true // Trigger the alert
                }
                .foregroundColor(.red)
                .disabled(llmProvider.isDownloading || llmProvider.running) // Disable if busy
            }
            if case .loading = llmProvider.loadState {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading model into memory...")
                        .foregroundColor(.secondary)
                }
            }
            
            
        case .loading:
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading \(modelType.displayName)...")
                    .foregroundColor(.secondary)
            }
            
        case .error:
            // Error shown separately, provide retry for download errors
            if llmProvider.lastError?.contains("download") == true && llmProvider.retryCount < 3 {
                Button("Retry Download") {
                    llmProvider.retryDownload()
                }
                .disabled(llmProvider.isDownloading)
            } else {
                Text("Cannot proceed due to error.")
                    .foregroundColor(.red)
            }
            
            
        }
        
        // --- Download Progress (shown only when downloading) ---
        if llmProvider.isDownloading {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading \(modelType.displayName)...")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { llmProvider.cancelDownload() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                ProgressView(value: llmProvider.downloadProgress) {
                    Text("\(Int(llmProvider.downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .animation(.linear, value: llmProvider.downloadProgress)
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
