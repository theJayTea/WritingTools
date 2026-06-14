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
    @State private var showingCommandsManager = false
    @State private var pendingProviderApplyTask: Task<Void, Never>?
    private let providerApplyDebounce: Duration = .milliseconds(800)
    private let credentialApplyDebounce: Duration = .milliseconds(1200)

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
        TabView(selection: $selectedTab) {
            GeneralSettingsPane(
                appState: appState,
                showingCommandsManager: $showingCommandsManager
            )
            .tag(SettingsTab.general)
            .tabItem {
                Label("General", systemImage: SettingsTab.general.systemImage)
            }

            AppearanceSettingsPane()
            .tag(SettingsTab.appearance)
            .tabItem {
                Label("Appearance", systemImage: SettingsTab.appearance.systemImage)
            }

            AIProviderSettingsPane(
                appState: appState
            )
            .tag(SettingsTab.aiProvider)
            .tabItem {
                Label("AI Provider", systemImage: SettingsTab.aiProvider.systemImage)
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, idealHeight: 560, maxHeight: 820)
        .windowBackground(useGradient: settings.useGradientTheme)
        .onAppear(perform: restoreLastTab)
        .onChange(of: selectedTab) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue,
                                      forKey: "lastSettingsTab")
        }
        .onChange(of: providerRuntimeApplySignature) { _, _ in
            scheduleProviderApply()
        }
        .onChange(of: providerCredentialSignature) { _, _ in
            scheduleProviderApply(debounce: credentialApplyDebounce)
        }
        .onDisappear {
            pendingProviderApplyTask?.cancel()
            appState.saveCurrentProviderSettings()
        }
    }

    private func restoreLastTab() {
        if let saved = UserDefaults.standard.string(forKey: "lastSettingsTab"),
           let savedTab = SettingsTab(rawValue: saved) {
            selectedTab = savedTab
        }
    }

    private func scheduleProviderApply(debounce: Duration? = nil) {
        let delay = debounce ?? providerApplyDebounce
        pendingProviderApplyTask?.cancel()
        pendingProviderApplyTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            appState.saveCurrentProviderSettings()
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
}

#Preview("SettingsView") {
    SettingsView(appState: AppState.shared)
}
