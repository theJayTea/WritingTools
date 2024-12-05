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
        
        if event.type == .keyDown {
            var components: [String] = []
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            
            if flags.contains(.control) { components.append("⌃") }
            if flags.contains(.option) { components.append("⌥") }
            if flags.contains(.shift) { components.append("⇧") }
            if flags.contains(.command) { components.append("⌘") }
            
            if let specialKey = specialKeyMapping[event.keyCode] {
                components.append(specialKey)
            } else {
                if let keyChar = virtualKeyCodeToChar[event.keyCode] {
                    components.append(keyChar)
                }
            }
            
            if !components.isEmpty {
                print("Final components: \(components)")
                shortcutText = components.joined(separator: " ")
                isRecording = false
                isFocused = false
            }
        }
    }
    
    private let specialKeyMapping: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Escape): "Esc",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→"
    ]
    
    private let virtualKeyCodeToChar: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A",
        UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E",
        UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G",
        UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K",
        UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M",
        UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q",
        UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S",
        UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W",
        UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y",
        UInt16(kVK_ANSI_Z): "Z"
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
}
