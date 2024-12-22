import SwiftUI
import Carbon.HIToolbox

struct ShortcutRecorderView: View {
    @State private var displayText = ""
    
    @FocusState private var isFocused: Bool
    @State private var isRecording = false
    
    var body: some View {
        HStack {
            Text(displayText.isEmpty ? "Click to record" : displayText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .onTapGesture {
                    isFocused = true
                    isRecording = true
                    displayText = "Recording..."
                }
            
            if isRecording {
                Text("Press desired shortcut…")
                    .foregroundColor(.secondary)
            }
        }
        .focusable()
        .focused($isFocused)
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                if isRecording {
                    handleKeyEvent(event)
                    // Return nil to indicate the event is handled
                    return nil
                }
                // Otherwise, pass it on
                return event
            }
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Modifiers
            let carbonModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).carbonFlags
            
            // The physical key code from the system
            let rawKeyCode = UInt32(event.keyCode)
            
            // Save them in UserDefaults
            UserDefaults.standard.set(Int(rawKeyCode), forKey: "hotKey_keyCode")
            UserDefaults.standard.set(Int(carbonModifiers), forKey: "hotKey_modifiers")
            
            displayText = describeShortcut(keyCode: event.keyCode,
                                           flags: event.modifierFlags)
            
            // Done recording
            isRecording = false
            isFocused = false
        }
    }
    
    //  helper to produce a “Ctrl + D” style string.
    private func describeShortcut(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        
        // 1) Collect modifier flags
        if flags.contains(.command)  { parts.append("⌘") }
        if flags.contains(.option)   { parts.append("⌥") }
        if flags.contains(.control)  { parts.append("⌃") }
        if flags.contains(.shift)    { parts.append("⇧") }
        
        // 2) Convert keyCode -> Int
        let keyCodeInt = Int(keyCode)
        
        // 3) Check if it matches certain special/symbol keys
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
        // Add more symbol keys if needed (e.g., kVK_ANSI_Semicolon, etc.)
            
        default:
            // 4) If we find a letter in our dictionary, use it; else show the numeric code.
            if let letter = keyCodeToLetter[keyCodeInt] {
                parts.append(letter)
            } else {
                parts.append("(\(keyCode))") // Fallback for anything unrecognized
            }
        }
        
        // 5) Combine with spaces, e.g. "⌃ D", "⌘ ="
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
                            Text(displayShortcut.isEmpty ? "Not set" : displayShortcut)
                            
                            ShortcutRecorderView()
                        
                    }
                    .onAppear {
                        // Load the raw keyCode & modifiers from UserDefaults
                        let rawKeyCode   = UserDefaults.standard.integer(forKey: "hotKey_keyCode")
                        let rawModifiers = UserDefaults.standard.integer(forKey: "hotKey_modifiers")
                        
                        // Convert to proper Swift types
                        let keyCode = UInt16(rawKeyCode)
                        let flags   = decodeCarbonModifiers(rawModifiers)
                        
                        displayShortcut = describeShortcut(keyCode: keyCode, flags: flags)
                    }
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
