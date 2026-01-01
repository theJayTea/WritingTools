import SwiftUI
import KeyboardShortcuts
import AppKit

extension KeyboardShortcuts.Name {
    static let showPopup = Self("showPopup")
    
    static func commandShortcut(for id: UUID) -> Self {
        return Self("command_\(id.uuidString)")
    }
}

struct SettingsView: View {
    @Bindable var appState: AppState
    @Bindable var settings = AppSettings.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var needsSaving: Bool = false
    @State private var showingCommandsManager = false
    
    var showOnlyApiSetup: Bool = false
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general     = "General"
        case appearance  = "Appearance"
        case aiProvider  = "AI Provider"
        
        var id: Self { self }
        
        var systemImage: String {
            switch self {
            case .general:
                return "gear"
            case .appearance:
                return "paintbrush"
            case .aiProvider:
                return "network"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                GeneralSettingsPane(
                    appState: appState,
                    needsSaving: $needsSaving,
                    showingCommandsManager: $showingCommandsManager,
                    showOnlyApiSetup: showOnlyApiSetup,
                    saveButton: saveButton
                )
                .tag(SettingsTab.general)
                .tabItem {
                    Label("General", systemImage: SettingsTab.general.systemImage)
                }
                
                AppearanceSettingsPane(
                    needsSaving: $needsSaving,
                    showOnlyApiSetup: showOnlyApiSetup,
                    saveButton: saveButton
                )
                .tag(SettingsTab.appearance)
                .tabItem {
                    Label("Appearance", systemImage: SettingsTab.appearance.systemImage)
                }
                
                AIProviderSettingsPane(
                    appState: appState,
                    needsSaving: $needsSaving,
                    showOnlyApiSetup: showOnlyApiSetup,
                    saveButton: saveButton,
                    completeSetupButton: completeSetupButton
                )
                .tag(SettingsTab.aiProvider)
                .tabItem {
                    Label("AI Provider", systemImage: SettingsTab.aiProvider.systemImage)
                }
            }
            .padding(20)
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
        Task { @MainActor in
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
                    .foregroundStyle(.secondary)
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
        
        UserDefaults.standard.set(settings.ollamaImageMode.rawValue, forKey: "ollama_image_mode")
        
        appState.setCurrentProvider(settings.currentProvider)
        
        if oldShortcut != settings.shortcutText {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }
        
        if showOnlyApiSetup {
            UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
        }
        
        needsSaving = false
        
        Task { @MainActor in
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
        settings.hasCompletedOnboarding = false

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

        WindowManager.shared.setOnboardingWindow(window, hostingView: hostingView)
        window.makeKeyAndOrderFront(nil)

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
