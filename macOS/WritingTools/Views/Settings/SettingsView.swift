import SwiftUI
import KeyboardShortcuts
import AppKit

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
            .controlSize(.regular)
        }
        .frame(width: 540, height: showOnlyApiSetup ? 470 : 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .windowBackground(useGradient: settings.useGradientTheme)
        .onAppear(perform: restoreLastTab)
        .onChange(of: selectedTab) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue,
                                      forKey: "lastSettingsTab")
            updateWindowTitle(to: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CommandsChanged"))) { _ in
            needsSaving = true
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
            }
        }
    }
    
    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General Settings")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            GroupBox("Keyboard Shortcuts") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Set a global shortcut to quickly activate Writing Tools.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    HStack(alignment: .center, spacing: 12) {
                        Text("Activate Writing Tools:")
                            .frame(width: 180, alignment: .leading)
                            .foregroundColor(.primary)
                        KeyboardShortcuts.Recorder(
                            for: .showPopup,
                            onChange: { _ in
                                needsSaving = true
                            }
                        )
                        .help("Choose a convenient key combination to bring up Writing Tools from anywhere.")
                    }
                    .padding(.vertical, 2)
                }
            }

            GroupBox("Commands") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Manage your writing tools and assign keyboard shortcuts.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button(action: {
                        showingCommandsManager = true
                    }) {
                        HStack(spacing: 8) {
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
                    .help("Open the Commands Manager to add, edit, or remove commands.")

                    Toggle(isOn: $settings.openCustomCommandsInResponseWindow) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open custom prompts in response window")
                            Text("When unchecked, custom prompts will replace selected text inline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.top, 4)
                    .onChange(of: settings.openCustomCommandsInResponseWindow) { _, _ in
                        needsSaving = true
                    }
                    .help("Choose whether custom prompts open in a separate response window or replace text inline.")
                }
            }
            
            GroupBox("Onboarding") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You can rerun the onboarding flow to review permissions and quickly configure the app.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    HStack {
                        Button {
                            restartOnboarding()
                        } label: {
                            Label("Restart Onboarding", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Open the onboarding window to set up WritingTools again.")

                        Spacer()
                    }
                }
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
                
                Text("Choose a window appearance that matches your preferences and context.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Theme", selection: $settings.themeStyle) {
                    Text("Standard").tag("standard")
                    Text("Gradient").tag("gradient")
                    Text("Glass").tag("glass")
                    Text("OLED").tag("oled")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
                .onChange(of: settings.themeStyle) { oldValue, newValue in
                    needsSaving = true
                }
                .help("Standard uses system backgrounds. Glass respects transparency preferences. OLED uses deep blacks.")
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
                .help("Select which AI service to use for processing.")
                
            }
            
            Divider()
                .padding(.vertical, 2)
            
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
            .help("Open OpenRouter to retrieve your API key.")
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
            .help("Open Anthropic console to create or view your API key.")
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
            .help("Open Google AI Studio to generate an API key.")
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
            .help("Open Mistral console to create an API key.")
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
            .help("Open OpenAI dashboard to create an API key.")
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
            .help("Open Ollama download and documentation page in your browser.")
        }
    }
    
    private var saveButton: some View {
        HStack(spacing: 8) {
            if !needsSaving {
                Text("All changes saved")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Save Changes") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .help("Save your changes and close settings.")
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
        
        // Mark changes as saved
        needsSaving = false
        
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
    
    private func restartOnboarding() {
        // Mark onboarding as not completed
        settings.hasCompletedOnboarding = false

        // Create the onboarding window the same way AppDelegate does
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Onboarding"
        window.isReleasedWhenClosed = false
        
        let onboardingView = OnboardingView(appState: appState)
        let hostingView = NSHostingView(rootView: onboardingView)
        window.contentView = hostingView
        window.level = .floating

        // Register with WindowManager properly
        WindowManager.shared.setOnboardingWindow(window, hostingView: hostingView)
        window.makeKeyAndOrderFront(nil)

        // Optionally close Settings to reduce window clutter
        if let settingsWindow = NSApplication.shared.windows.first(where: {
            $0.contentView?.subviews.contains(where: { $0 is NSHostingView<SettingsView> }) ?? false
        }) {
            settingsWindow.close()
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
