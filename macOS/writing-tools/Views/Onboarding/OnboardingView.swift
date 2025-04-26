import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings = AppSettings.shared
    @State private var currentStep = 0
    
    private let steps = [
        OnboardingStep(
            title: "Welcome to WritingTools!",
            description: "Let's get you set up with just a few quick steps.",
            isPermissionStep: false
        ),
        OnboardingStep(
            title: "Enable Accessibility Access",
            description: "WritingTools needs accessibility access to detect text selection and enhance your writing experience.",
            isPermissionStep: true
        ),
        OnboardingStep(
            title: "Customize Your Experience",
            description: "Set up your preferred shortcut, theme, and AI provider.",
            isPermissionStep: false
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    switch currentStep {
                    case 0:
                        welcomeStep
                    case 1:
                        accessibilityStep
                    case 2:
                        customizationStep
                    default:
                        EmptyView()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
            }
            
            // Bottom navigation area
            VStack(spacing: 16) {
                // Progress indicators
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Circle()
                            .fill(currentStep >= index ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Navigation buttons
                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Spacer()
                    
                    Button(currentStep == steps.count - 1 ? "Finish" : "Next") {
                        if currentStep == steps.count - 1 {
                            saveSettingsAndFinish()
                        } else {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 600, height: 600)
        .background(
            Rectangle()
                .fill(Color.clear)
                .windowBackground(useGradient: settings.useGradientTheme)
        )
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.accentColor)
            
            Text(steps[0].title)
                .font(.largeTitle)
                .bold()
            
            VStack(alignment: .center, spacing: 10) {
                Text("• Improves your writing with AI")
                Text("• Works in any application")
                Text("• Helps you write with clarity and confidence")
                Text("• Support Custom Commands for anything you want")
            }
            .font(.title3)
        }
    }
    
    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Text(steps[1].title)
                .font(.title)
                .bold()
            
            Text(steps[1].description)
                .multilineTextAlignment(.center)
            
            GroupBox {
                VStack(alignment: .leading, spacing: 15) {
                    Text("How to enable accessibility access:")
                        .font(.headline)
                    
                    Text("1. Click the button below to open System Settings")
                    Text("2. Click the '+' button in the accessibility section")
                    Text("3. Navigate to Applications and select writing-tools")
                    Text("4. Enable the checkbox next to writing-tools")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var customizationStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Customize Your Experience")
                    .font(.title)
                    .bold()
                
                // Shortcut Settings
                GroupBox {
                    KeyboardShortcuts.Recorder("Global Shortcut:", name: .showPopup)
                        .padding(.vertical, 4)
                }
                
                // Theme Settings
                GroupBox {
                    Picker("Theme", selection: $settings.themeStyle) {
                        Text("Standard").tag("standard")
                        Text("Gradient").tag("gradient")
                        Text("Glass").tag("glass")
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)
                }
                
                // AI Provider Selection
                GroupBox {
                    VStack(alignment: .leading) {
                        Picker("Provider", selection: $settings.currentProvider) {
                            // Remove Local LLM option for Intel Macs
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
                        }
                        
                        if settings.currentProvider == "local" {
                            Text("(Llama 3.2 3B 4-bit)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Provider-specific settings
                providerSpecificSettings
            }
            .padding()
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
                if LocalLLMProvider.isAppleSilicon {
                    LocalLLMSettingsView(evaluator: appState.localLLMProvider)
                } else {
                    localLLMNotSupportedView
                }
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
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Image Recognition Mode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("Image Mode", selection: $settings.ollamaImageMode) {
                        ForEach(OllamaImageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Choose between local OCR or Ollama's built-in vision capabilities.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
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
    
    private var localLLMNotSupportedView: some View {
        GroupBox {
            VStack(alignment: .center, spacing: 16) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
                
                Text("Apple Silicon Required")
                    .font(.title3)
                    .bold()
                
                Text("Local LLM is only available on Apple Silicon devices (M1/M2/M3 Macs).")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text("Please select a different AI provider.")
                    .font(.headline)
                    .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
    
    private func saveSettingsAndFinish() {
        // Save provider-specific settings based on the selected provider
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
        
        // Save shortcut settings (handled by KeyboardShortcuts.Recorder)
        
        // Mark onboarding as complete
        UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
        
        // Clean up windows
        WindowManager.shared.cleanupWindows()
    }
}

struct OnboardingStep {
    let title: String
    let description: String
    let isPermissionStep: Bool
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
