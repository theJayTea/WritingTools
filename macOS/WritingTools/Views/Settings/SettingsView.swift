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
    @State private var hostingWindow: NSWindow?
    @State private var pendingProviderApplyTask: Task<Void, Never>?
    private let providerApplyDebounce: Duration = .milliseconds(800)

    // Validation alert state
    @State private var showingValidationAlert = false
    @State private var validationAlertMessage = ""

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
            .padding(16)
        }
        .frame(minWidth: 520, idealWidth: 540, maxWidth: 720, minHeight: 470, idealHeight: showOnlyApiSetup ? 470 : 540, maxHeight: 820)
        .background(WindowAccessor { window in
            hostingWindow = window
            updateWindowTitle(to: selectedTab)
        })
        .windowBackground(useGradient: settings.useGradientTheme)
        .onAppear(perform: restoreLastTab)
        .onChange(of: selectedTab) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue,
                                      forKey: "lastSettingsTab")
            updateWindowTitle(to: newValue)
        }
        .onChange(of: providerRuntimeApplySignature) { _, _ in
            scheduleProviderApply()
        }
        .onChange(of: providerCredentialSignature) { _, _ in
            pendingProviderApplyTask?.cancel()
        }
        .onDisappear {
            pendingProviderApplyTask?.cancel()
            appState.saveCurrentProviderSettings()
        }
        .alert("Settings Incomplete", isPresented: $showingValidationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationAlertMessage)
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
            hostingWindow?.title = "\(tab.rawValue) Settings"
        }
    }
    
    private var saveButton: some View {
        HStack(spacing: 8) {
            Text("Most changes apply automatically. Click Done to apply API key updates.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return)
            .help("Close settings.")
            .accessibilityLabel("Done")
            .accessibilityHint("Closes the settings window")
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
        if let validationError = validateProviderSettings() {
            showValidationAlert(message: validationError)
            return
        }

        pendingProviderApplyTask?.cancel()
        appState.saveCurrentProviderSettings()

        let oldShortcut = UserDefaults.standard.string(forKey: "shortcut")

        UserDefaults.standard.set(settings.shortcutText, forKey: "shortcut")

        if oldShortcut != settings.shortcutText {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }

        if showOnlyApiSetup {
            UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
        }

        needsSaving = false

        Task { @MainActor in
            if let hostingWindow {
                hostingWindow.close()
            } else {
                WindowManager.shared.closeSettingsWindow()
            }
        }
    }

    private func scheduleProviderApply() {
        pendingProviderApplyTask?.cancel()
        pendingProviderApplyTask = Task { @MainActor in
            try? await Task.sleep(for: providerApplyDebounce)
            guard !Task.isCancelled else { return }
            appState.saveCurrentProviderSettings()
            needsSaving = false
        }
    }

    private var providerRuntimeApplySignature: String {
        [
            settings.currentProvider,
            settings.geminiModel.rawValue,
            settings.geminiCustomModel,
            settings.openAIBaseURL,
            settings.openAIModel,
            settings.openAIOrganization ?? "",
            settings.openAIProject ?? "",
            settings.mistralBaseURL,
            settings.mistralModel,
            settings.anthropicModel,
            settings.openRouterModel,
            settings.openRouterCustomModel,
            settings.ollamaBaseURL,
            settings.ollamaModel,
            settings.ollamaKeepAlive,
            settings.ollamaImageMode.rawValue,
        ].joined(separator: "|")
    }

    private var providerCredentialSignature: String {
        [
            settings.geminiApiKey,
            settings.openAIApiKey,
            settings.mistralApiKey,
            settings.anthropicApiKey,
            settings.openRouterApiKey,
        ].joined(separator: "|")
    }

    private func validateProviderSettings() -> String? {
        switch settings.currentProvider {
        case "gemini":
            if settings.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Gemini API key is required."
            }
            if settings.geminiModel == .custom &&
                settings.geminiCustomModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Custom Gemini model name is required."
            }
        case "mistral":
            if settings.mistralApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Mistral API key is required."
            }
            if settings.mistralModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Mistral model is required."
            }
        case "anthropic":
            if settings.anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Anthropic API key is required."
            }
            if settings.anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Anthropic model is required."
            }
        case "openrouter":
            if settings.openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "OpenRouter API key is required."
            }
            if OpenRouterModel(rawValue: settings.openRouterModel) == .custom &&
                settings.openRouterCustomModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Custom OpenRouter model name is required."
            }
        case "openai":
            let trimmedOpenAIBaseURL = settings.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let isUsingDefaultOpenAIEndpoint = trimmedOpenAIBaseURL.isEmpty || trimmedOpenAIBaseURL == OpenAIConfig.defaultBaseURL
            if isUsingDefaultOpenAIEndpoint &&
                settings.openAIApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "OpenAI API key is required."
            }
            if settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "OpenAI model is required."
            }
        case "ollama":
            if settings.ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Ollama base URL is required."
            }
            if settings.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Ollama model is required."
            }
        default:
            break
        }
        return nil
    }

    private func showValidationAlert(message: String) {
        validationAlertMessage = message
        showingValidationAlert = true
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowAccessorView(callback: callback)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowAccessorView else { return }
        view.callback = callback
    }
}

private final class WindowAccessorView: NSView {
    var callback: (NSWindow?) -> Void

    init(callback: @escaping (NSWindow?) -> Void) {
        self.callback = callback
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        callback(window)
    }
}

#Preview("SettingsView") {
    SettingsView(appState: AppState.shared)
}
