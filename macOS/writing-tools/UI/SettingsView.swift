import SwiftUI
import Carbon.HIToolbox
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showPopup = Self("showPopup")
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var shortcutText = UserDefaults.standard.string(forKey: "shortcut") ?? "⌥ Space"
    @State private var useGradientTheme = UserDefaults.standard.bool(forKey: "use_gradient_theme")
    @State private var selectedTheme = UserDefaults.standard.string(forKey: "theme_style") ?? "gradient"
    @State private var selectedProvider = UserDefaults.standard.string(forKey: "current_provider") ?? "gemini"
    
    // Gemini settings
    @State private var geminiApiKey = UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
    @State private var selectedGeminiModel = GeminiModel(rawValue: UserDefaults.standard.string(forKey: "gemini_model") ?? "gemini-1.5-flash-latest") ?? .oneflash
    
    // OpenAI settings
    @State private var openAIApiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    @State private var openAIBaseURL = UserDefaults.standard.string(forKey: "openai_base_url") ?? OpenAIConfig.defaultBaseURL
    @State private var openAIOrganization = UserDefaults.standard.string(forKey: "openai_organization") ?? ""
    @State private var openAIProject = UserDefaults.standard.string(forKey: "openai_project") ?? ""
    @State private var openAIModelName = UserDefaults.standard.string(forKey: "openai_model") ?? OpenAIConfig.defaultModel
    
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
                    Form {
                        
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
                            useGradientTheme = (newValue != "standard")
                        }
                    }
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
        UserDefaults.standard.set(selectedTheme, forKey: "theme_style")
        UserDefaults.standard.set(selectedTheme != "standard", forKey: "use_gradient_theme")
        
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
    // Converts stored Carbon modifier bits into SwiftUI’s `NSEvent.ModifierFlags`.
    private func decodeCarbonModifiers(_ rawModifiers: Int) -> NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        let carbonFlags = UInt32(rawModifiers)
        
        if (carbonFlags & UInt32(cmdKey))     != 0 { flags.insert(.command) }
        if (carbonFlags & UInt32(optionKey))  != 0 { flags.insert(.option) }
        if (carbonFlags & UInt32(controlKey)) != 0 { flags.insert(.control) }
        if (carbonFlags & UInt32(shiftKey))   != 0 { flags.insert(.shift) }
        
        return flags
    }
    
    // Returns a human-friendly string like "⌘ =" or "⌃ D".
    private func describeShortcut(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        
        if flags.contains(.command)  { parts.append("⌘") }
        if flags.contains(.option)   { parts.append("⌥") }
        if flags.contains(.control)  { parts.append("⌃") }
        if flags.contains(.shift)    { parts.append("⇧") }
        
        let keyCodeInt = Int(keyCode)
        
        switch keyCodeInt {
        case kVK_Space:
            parts.append("Space")
        case kVK_Return:
            parts.append("Return")
        case kVK_ANSI_Equal:
            parts.append("=")
        case kVK_ANSI_Minus:
            parts.append("-")
        case kVK_ANSI_LeftBracket:
            parts.append("[")
        case kVK_ANSI_RightBracket:
            parts.append("]")
            
        default:
            if let letter = keyCodeToLetter[keyCodeInt] {
                parts.append(letter)
            } else {
                parts.append("(\(keyCode))")
            }
        }
        
        return parts.joined(separator: " ")
    }
    
    // Maps the Carbon virtual key code (e.g. kVK_ANSI_D = 0x02) to the actual letter "D".
    private let keyCodeToLetter: [Int: String] = [
        kVK_ANSI_A: "A",
        kVK_ANSI_B: "B",
        kVK_ANSI_C: "C",
        kVK_ANSI_D: "D",
        kVK_ANSI_E: "E",
        kVK_ANSI_F: "F",
        kVK_ANSI_G: "G",
        kVK_ANSI_H: "H",
        kVK_ANSI_I: "I",
        kVK_ANSI_J: "J",
        kVK_ANSI_K: "K",
        kVK_ANSI_L: "L",
        kVK_ANSI_M: "M",
        kVK_ANSI_N: "N",
        kVK_ANSI_O: "O",
        kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q",
        kVK_ANSI_R: "R",
        kVK_ANSI_S: "S",
        kVK_ANSI_T: "T",
        kVK_ANSI_U: "U",
        kVK_ANSI_V: "V",
        kVK_ANSI_W: "W",
        kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z"
    ]
}
