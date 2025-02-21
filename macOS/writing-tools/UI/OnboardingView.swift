import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings = AppSettings.shared
    @State private var currentStep = 0
    @State private var shortcutText = "⌃ Space"
    @State private var selectedTheme = UserDefaults.standard.string(forKey: "theme_style") ?? "gradient"
    
    
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
        .frame(width: 600, height: 700)
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
            
            VStack(alignment: .leading, spacing: 15) {
                Text("How to enable accessibility access:")
                    .font(.headline)
                
                Text("1. Click the button below to open System Settings")
                Text("2. Click the '+' button in the accessibility section")
                Text("3. Navigate to Applications and select writing-tools")
                Text("4. Enable the checkbox next to writing-tools")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var customizationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Customize Your Experience")
                .font(.title)
                .bold()
            
            // Shortcut and Theme
            Group {
                Text("Basic Settings")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 15) {
                    Text("Set your keyboard shortcut:")
                    KeyboardShortcuts.Recorder("Shortcut:", name: .showPopup)
                    
                    Divider()
                    
                    Text("Choose your theme:")
                    Picker("Theme", selection: $selectedTheme) {
                        Text("Standard").tag("standard")
                        Text("Gradient").tag("gradient")
                        Text("Glass").tag("glass")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)
            }
            
            // AI Provider Selection
            Group {
                Text("AI Provider Settings")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 15) {
                    Picker("Provider", selection: $settings.currentProvider) {
                        Text("Local LLM (LLama 3.2 3b)").tag("local")
                        Text("Gemini AI").tag("gemini")
                        Text("OpenAI").tag("openai")
                        Text("Mistral AI").tag("mistral")
                        Text("Ollama").tag("ollama")
                    }
                    .pickerStyle(.segmented)
                    
                    // Provider-specific settings
                    if appState.currentProvider == "gemini" {
                        providerSettingsGemini
                    } else if appState.currentProvider == "mistral" {
                        providerSettingsMistral
                    } else if appState.currentProvider == "openai" {
                        providerSettingsOpenAI
                    }else if appState.currentProvider == "ollama" {
                        providerSettingsOllama
                    }
                    else if appState.currentProvider == "local" {
                        LocalLLMSettingsView(evaluator: appState.localLLMProvider)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var providerSettingsGemini: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("API Key", text: $settings.geminiApiKey)
                .textFieldStyle(.roundedBorder)
            
            Picker("Model", selection: $settings.geminiModel) {
                ForEach(GeminiModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model)
                }
            }
            
            Button("Get API Key") {
                NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
            }
        }
    }
    
    private var providerSettingsMistral: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                NSWorkspace.shared.open(URL(string: "https://console.mistral.ai/api-keys/")!)
            }
        }
    }
    

    private var providerSettingsOllama: some View {
        VStack(alignment: .leading, spacing: 10) {
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
    
    private var providerSettingsOpenAI: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            HStack {
                Button("Get OpenAI API Key") {
                    NSWorkspace.shared.open(URL(string: "https://platform.openai.com/account/api-keys")!)
                }
                
                Button("Ollama Documentation") {
                    NSWorkspace.shared.open(URL(string: "https://ollama.ai/download")!)
                }
            }
        }
    }
    
    private func saveSettingsAndFinish() {
        // Save theme settings
        UserDefaults.standard.set(selectedTheme, forKey: "theme_style")
        UserDefaults.standard.set(selectedTheme != "standard", forKey: "use_gradient_theme")
        
        // Save provider-specific settings
        if appState.currentProvider == "gemini" {
            appState.saveGeminiConfig(apiKey: settings.geminiApiKey, model: settings.geminiModel)
        } else if appState.currentProvider == "mistral" {
            appState.saveMistralConfig(
                apiKey: settings.mistralApiKey,
                baseURL: settings.mistralBaseURL,
                model: settings.mistralModel
            )
        } else if appState.currentProvider == "openai" {
            appState.saveOpenAIConfig(
                apiKey: settings.openAIApiKey,
                baseURL: settings.openAIBaseURL,
                organization: settings.openAIOrganization,
                project: settings.openAIProject,
                model: settings.openAIModel
            )
        } else if appState.currentProvider == "ollama" {
            appState.saveOllamaConfig(
                baseURL: settings.ollamaBaseURL,
                model: settings.ollamaModel,
                keepAlive: settings.ollamaKeepAlive
            )
        }
        
        // Set current provider
        appState.setCurrentProvider(appState.currentProvider)
        
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
