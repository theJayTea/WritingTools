import SwiftUI
import KeyboardShortcuts

struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @State private var currentStep = 0
    @State private var shortcutText = "⌃ Space"
    @State private var useGradientTheme = true
    @State private var selectedTheme = UserDefaults.standard.string(forKey: "theme_style") ?? "gradient"
    
    // Provider settings
    @State private var selectedProvider = UserDefaults.standard.string(forKey: "current_provider") ?? "gemini"
    @State private var geminiApiKey = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
    @State private var selectedGeminiModel = GeminiModel(rawValue: UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-1.5-flash-latest") ?? .oneflash
    @State private var openAIApiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    @State private var openAIBaseURL = UserDefaults.standard.string(forKey: "openai_base_url") ?? OpenAIConfig.defaultBaseURL
    @State private var openAIOrganization = UserDefaults.standard.string(forKey: "openai_organization") ?? ""
    @State private var openAIProject = UserDefaults.standard.string(forKey: "openai_project") ?? ""
    @State private var openAIModelName = UserDefaults.standard.string(forKey: "openai_model") ?? OpenAIConfig.defaultModel
    @State private var mistralApiKey = UserDefaults.standard.string(forKey: "mistral_api_key") ?? ""
    @State private var mistralBaseURL = UserDefaults.standard.string(forKey: "mistral_base_url") ?? MistralConfig.defaultBaseURL
    @State private var mistralModel = UserDefaults.standard.string(forKey: "mistral_model") ?? MistralConfig.defaultModel
    
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
                    Picker("Provider", selection: $selectedProvider) {
                        Text("Gemini AI").tag("gemini")
                        Text("OpenAI / Local LLM").tag("openai")
                        Text("Mistral AI").tag("mistral")
                    }
                    .pickerStyle(.segmented)
                    
                    // Provider-specific settings
                    if selectedProvider == "gemini" {
                        providerSettingsGemini
                    } else if selectedProvider == "mistral" {
                        providerSettingsMistral
                    } else {
                        providerSettingsOpenAI
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var providerSettingsGemini: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("API Key", text: $geminiApiKey)
                .textFieldStyle(.roundedBorder)
            
            Picker("Model", selection: $selectedGeminiModel) {
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
            TextField("API Key", text: $mistralApiKey)
                .textFieldStyle(.roundedBorder)
            
            TextField("Base URL", text: $mistralBaseURL)
                .textFieldStyle(.roundedBorder)
            
            Picker("Model", selection: $mistralModel) {
                ForEach(MistralModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model.rawValue)
                }
            }
            
            Button("Get Mistral API Key") {
                NSWorkspace.shared.open(URL(string: "https://console.mistral.ai/api-keys/")!)
            }
        }
    }
    
    private var providerSettingsOpenAI: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("API Key", text: $openAIApiKey)
                .textFieldStyle(.roundedBorder)
            
            TextField("Base URL", text: $openAIBaseURL)
                .textFieldStyle(.roundedBorder)
            
            TextField("Model Name", text: $openAIModelName)
                .textFieldStyle(.roundedBorder)
            
            Text("OpenAI models include: gpt-4o, gpt-3.5-turbo, etc.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LinkText()
            
            TextField("Organization ID (Optional)", text: $openAIOrganization)
                .textFieldStyle(.roundedBorder)
            
            TextField("Project ID (Optional)", text: $openAIProject)
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
        if selectedProvider == "gemini" {
            appState.saveGeminiConfig(apiKey: geminiApiKey, model: selectedGeminiModel)
        } else if selectedProvider == "mistral" {
            appState.saveMistralConfig(
                apiKey: mistralApiKey,
                baseURL: mistralBaseURL,
                model: mistralModel
            )
        } else {
            appState.saveOpenAIConfig(
                apiKey: openAIApiKey,
                baseURL: openAIBaseURL,
                organization: openAIOrganization,
                project: openAIProject,
                model: openAIModelName
            )
        }
        
        // Set current provider
        appState.setCurrentProvider(selectedProvider)
        
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
                    NSWorkspace.shared.open(URL(string: "https://github.com/theJayTea/WritingTools?tab=readme-ov-file#-optional-ollama-local-llm-instructions")!)
                }
            
            Text(".")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
