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
                case .general:
                    GeneralSettingsPane(
                        appState: appState,
                        needsSaving: $needsSaving,
                        showingCommandsManager: $showingCommandsManager,
                        showOnlyApiSetup: showOnlyApiSetup,
                        saveButton: AnyView(saveButton)
                    )
                case .appearance:
                    AppearanceSettingsPane(
                        needsSaving: $needsSaving,
                        showOnlyApiSetup: showOnlyApiSetup,
                        saveButton: AnyView(saveButton)
                    )
                case .aiProvider:
                    AIProviderSettingsPane(
                        appState: appState,
                        needsSaving: $needsSaving,
                        showOnlyApiSetup: showOnlyApiSetup,
                        saveButton: AnyView(saveButton),
                        completeSetupButton: AnyView(completeSetupButton)
                    )
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
                
        // Save provider-specific settings
        if settings.currentProvider == "gemini" {
            appState.saveGeminiConfig(
                apiKey: settings.geminiApiKey,
                model: settings.geminiModel,
                customModelName: settings.geminiCustomModel
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


#Preview("SettingsView") {
    SettingsView(appState: AppState.shared)
}
