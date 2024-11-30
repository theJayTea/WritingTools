import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    @Binding var shortcutText: String
    @State private var isRecording = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack {
            Text(shortcutText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .onTapGesture {
                    isFocused = true
                    isRecording = true
                }
            
            if isRecording {
                Text("Recording...")
                    .foregroundColor(.secondary)
            }
        }
        .focusable()
        .focused($isFocused)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                if isRecording {
                    handleKeyEvent(event)
                    return nil
                }
                return event
            }
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        var components: [String] = []
        
        let flags = event.modifierFlags
        
        if flags.contains(.command) { components.append("⌘") }
        if flags.contains(.option) { components.append("⌥") }
        if flags.contains(.control) { components.append("⌃") }
        if flags.contains(.shift) { components.append("⇧") }
        
        // Add key character if it's a key down event
        if event.type == .keyDown {
            if let specialKey = specialKeyMapping[event.keyCode] {
                components.append(specialKey)
            } else if let character = event.charactersIgnoringModifiers?.uppercased(),
                      !character.isEmpty {
                components.append(character)
            }
            
            shortcutText = components.joined(separator: " ")
            isRecording = false
            isFocused = false
        }
    }
    
    private let specialKeyMapping: [UInt16: String] = [
        0x31: "Space",
        0x35: "Esc",
        0x33: "Delete",
        0x30: "Tab",
        0x24: "Return",
        0x7E: "↑",
        0x7D: "↓",
        0x7B: "←",
        0x7C: "→"
    ]
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var shortcutText = UserDefaults.standard.string(forKey: "shortcut") ?? "⌥ Space"
    @State private var useGradientTheme = UserDefaults.standard.bool(forKey: "use_gradient_theme")
    @State private var selectedProvider = UserDefaults.standard.string(forKey: "current_provider") ?? "gemini"
    
    // Gemini settings
    @State private var geminiApiKey = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
    @State private var selectedGeminiModel = GeminiModel(rawValue: UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-1.5-flash-latest") ?? .flash
    
    // OpenAI settings
    @State private var openAIApiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    @State private var openAIBaseURL = UserDefaults.standard.string(forKey: "openai_base_url") ?? OpenAIConfig.defaultBaseURL
    @State private var openAIOrganization = UserDefaults.standard.string(forKey: "openai_organization") ?? ""
    @State private var openAIProject = UserDefaults.standard.string(forKey: "openai_project") ?? ""
    @State private var openAIModelName = UserDefaults.standard.string(forKey: "openai_model") ?? OpenAIConfig.defaultModel
    
    
    var showOnlyApiSetup: Bool = false
    
    struct LinkText: View {
        var body: some View {
            HStack(spacing: 4) {
                Text("Local LLMs: use instructions at")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("GitHub Guide")
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

    
    var body: some View {
        Form {
            if !showOnlyApiSetup {
                Section("General Settings") {
                    ShortcutRecorderView(shortcutText: $shortcutText)
                    Toggle("Use Gradient Theme", isOn: $useGradientTheme)
                }
                
                Section("AI Provider") {
                    Picker("Provider", selection: $selectedProvider) {
                        Text("Gemini AI").tag("gemini")
                        Text("OpenAI / Local LLM").tag("openai")
                    }
                }
            }
            
            if selectedProvider == "gemini" {
                Section("Gemini AI Settings") {
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
            } else {
                Section("OpenAI / Local LLM Settings") {
                    TextField("API Key", text: $openAIApiKey)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Base URL", text: $openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Model Name", text: $openAIModelName)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("OpenAI models include: gpt-4o, gpt-3.5-turbo")
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
            
            Button(showOnlyApiSetup ? "Complete Setup" : "Save") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 500)
        .windowBackground(useGradient: useGradientTheme)
    }
    
    private func saveSettings() {
        let oldShortcut = UserDefaults.standard.string(forKey: "shortcut")
        
        UserDefaults.standard.set(shortcutText, forKey: "shortcut")
        UserDefaults.standard.set(useGradientTheme, forKey: "use_gradient_theme")
        
        // Save provider-specific settings
        if selectedProvider == "gemini" {
            appState.saveGeminiConfig(apiKey: geminiApiKey, model: selectedGeminiModel)
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
        
        // If shortcut changed, post notification
        if oldShortcut != shortcutText {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }
        
        // If this is the onboarding API setup, mark onboarding as complete
        if showOnlyApiSetup {
            UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
        }
        
        // Close windows safely
        DispatchQueue.main.async {
            if self.showOnlyApiSetup {
                WindowManager.shared.cleanupWindows()
            } else {
                if let window = NSApplication.shared.windows.first(where: { $0.contentView?.subviews.contains(where: { $0 is NSHostingView<SettingsView> }) ?? false }) {
                    window.close()
                }
            }
        }
    }
}
