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
                VStack(spacing: 8) {
                    
                    
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
                        
                        // Progress indicators
                        HStack(spacing: 8) {
                            ForEach(0..<steps.count, id: \.self) { index in
                                Circle()
                                    .fill(currentStep >= index ? Color.accentColor : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
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
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.accentColor)

                Text(steps[0].title)
                    .font(.largeTitle)
                    .bold()
                    .multilineTextAlignment(.center)

                Text(steps[0].description)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Improves your writing with AI", systemImage: "brain.head.profile")
                    Label("Works in any application", systemImage: "app.badge")
                    Label("Helps you write with clarity and confidence", systemImage: "text.badge.checkmark")
                    Label("Supports Custom Commands", systemImage: "list.bullet.rectangle.portrait")
                }
                .font(.title3)
                .padding(.top)
            }
            .padding(.vertical, 40)
        }
    
    private var accessibilityStep: some View {
            VStack(spacing: 20) {
                Image(systemName: "figure.wave.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.blue)

                Text(steps[1].title)
                    .font(.title)
                    .bold()

                Text(steps[1].description)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                GroupBox {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("How to enable accessibility access:")
                            .font(.headline)

                        Label(
                            "Click the button below to open System Settings > Privacy & Security > Accessibility.",
                            systemImage: "1.circle"
                        )
                        Label(
                            "Click the '+' button (you may need to unlock first).",
                            systemImage: "2.circle"
                        )
                        Label(
                            "Navigate to your Applications folder and select 'WritingTools'.",
                            systemImage: "3.circle"
                        )
                        Label(
                            "Ensure the toggle switch next to 'WritingTools' is turned ON.",
                            systemImage: "4.circle"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }

                Button {
                    NSWorkspace.shared.open(
                        URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        )!
                    )
                } label: {
                    Label("Open Accessibility Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                //  Add a check status button
                /*
                 Button("Check Status") {
                     if isAccessibilityEnabled() {
                         // Show confirmation
                     } else {
                         // Show reminder
                     }
                 }
                 */
            }
            .padding(.vertical, 40)
        }
    
    private var customizationStep: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { // Increased spacing
                    Text("Customize Your Experience")
                        .font(.title)
                        .bold()
                        .padding(.bottom, 4)

                    // --- Shortcut Settings ---
                    GroupBox("Global Shortcut") {
                        VStack(alignment: .leading) {
                            Text("Set the keyboard shortcut to activate WritingTools from anywhere.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            KeyboardShortcuts.Recorder(
                                "Activate WritingTools:",
                                name: .showPopup
                            )
                        }
                        .padding(.vertical, 8)
                    }

                    // --- Theme Settings ---
                    GroupBox("Appearance Theme") {
                        VStack(alignment: .leading) {
                            Text("Choose how the popup window looks.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            Picker("Theme", selection: $settings.themeStyle) {
                                Text("Standard").tag("standard")
                                Text("Gradient").tag("gradient")
                                Text("Glass").tag("glass")
                                Text("OLED").tag("oled")
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 8)
                    }

                    // --- AI Provider Selection ---
                    GroupBox("AI Provider") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select the AI service you want to use.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)

                            Picker("Provider", selection: $settings.currentProvider) {
                                // Conditionally show Local LLM
                                if LocalModelProvider.isAppleSilicon {
                                    Text("Local LLM (On-Device)").tag("local")
                                }
                                Text("Gemini AI (Google)").tag("gemini")
                                Text("OpenAI (ChatGPT)").tag("openai")
                                Text("Mistral AI").tag("mistral")
                                Text("Ollama (Self-Hosted)").tag("ollama")
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: settings.currentProvider) { _, newValue in
                                // Fallback for Intel Macs selecting Local LLM
                                if newValue == "local" && !LocalModelProvider.isAppleSilicon {
                                    settings.currentProvider = "gemini"
                                }
                                // Reset API keys or specific settings if needed when provider changes?
                            }

                        }
                        .padding(.vertical, 8)
                    }

                    // --- Provider-specific settings ---
                    GroupBox("Provider Configuration") {
                         providerSpecificSettings
                            .padding(.vertical, 8)
                    }

                }
                .padding()
            }
        }

        // --- Provider Specific Settings View Builder ---
        @ViewBuilder
        private var providerSpecificSettings: some View {
            switch settings.currentProvider {
            case "gemini":
                geminiSettings
            case "mistral":
                mistralSettings
            case "openai":
                openAISettings
            case "ollama":
                ollamaSettings
            case "local":
                LocalLLMSettingsView(provider: appState.localLLMProvider)
            default:
                Text("Please select a provider.")
                    .foregroundColor(.secondary)
            }
        }

        // --- Settings Views for each provider ---
        private var geminiSettings: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configure Google Gemini AI")
                    .font(.headline)
                TextField("API Key", text: $settings.geminiApiKey)
                    .textFieldStyle(.roundedBorder)

                Picker("Model", selection: $settings.geminiModel) {
                    ForEach(GeminiModel.allCases, id: \.self) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Show custom model field if needed
                if settings.geminiModel == .custom {
                    TextField("Custom Model Name", text: $settings.geminiCustomModel)
                        .textFieldStyle(.roundedBorder)
                        .padding(.top, 4)
                }

                Button("Get Gemini API Key") {
                    if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        }

        private var mistralSettings: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configure Mistral AI")
                    .font(.headline)
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
                .buttonStyle(.link)
            }
        }

        private var openAISettings: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configure OpenAI (ChatGPT)")
                    .font(.headline)
                TextField("API Key", text: $settings.openAIApiKey)
                    .textFieldStyle(.roundedBorder)

                TextField("Base URL (Optional)", text: $settings.openAIBaseURL)
                    .textFieldStyle(.roundedBorder)

                TextField("Model Name", text: $settings.openAIModel)
                    .textFieldStyle(.roundedBorder)

                Text("Default models: \(OpenAIConfig.defaultModel), gpt-4o, gpt-4o-mini, etc.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Get OpenAI API Key") {
                    if let url = URL(string: "https://platform.openai.com/account/api-keys") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        }

        private var ollamaSettings: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configure Ollama (Self-Hosted)")
                    .font(.headline)
                TextField("Ollama Base URL", text: $settings.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)

                TextField("Ollama Model Name", text: $settings.ollamaModel)
                    .textFieldStyle(.roundedBorder)

                TextField("Keep Alive Time (e.g., 5m, 1h)", text: $settings.ollamaKeepAlive)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Image Recognition Mode")
                        .font(.subheadline) // Consistent font
                        .foregroundColor(.secondary)
                    Picker("Image Mode", selection: $settings.ollamaImageMode) {
                        ForEach(OllamaImageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Use local OCR or Ollama's vision model for images.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                SettingsView.LinkText()

                Button("Ollama Documentation") {
                    if let url = URL(string: "https://ollama.ai/download") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        }


        // --- Save Settings and Finish ---
        private func saveSettingsAndFinish() {
            if settings.currentProvider == "gemini" {
                appState.saveGeminiConfig(
                    apiKey: settings.geminiApiKey,
                    model: settings.geminiModel,
                    customModelName: settings.geminiCustomModel // Pass custom model name
                )
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
                UserDefaults.standard.set(settings.ollamaImageMode.rawValue, forKey: "ollama_image_mode")
            }

            // Set current provider in AppState (persists via AppSettings)
            appState.setCurrentProvider(settings.currentProvider)

            // Mark onboarding as complete
            settings.hasCompletedOnboarding = true // Use the AppSettings property

            print("Onboarding complete. Settings saved.")

            WindowManager.shared.cleanupWindows()
        }
    }

    // OnboardingStep struct
    struct OnboardingStep {
        let title: String
        let description: String
        let isPermissionStep: Bool
    }
