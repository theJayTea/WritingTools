import SwiftUI

@main
struct writing_toolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState.shared
    @State private var settings = AppSettings.shared
    
    var body: some Scene {
        // Menu bar extra provides the status item and dropdown menu
        MenuBarExtra("Writing Tools", systemImage: "pencil.circle") {
            MenuBarMenu(appState: appState, settings: settings)
        }
        .menuBarExtraStyle(.menu)
        
        // Settings scene for the preferences window
        Settings {
            SettingsView(appState: appState)
        }
    }
}

// MARK: - Menu Bar Menu Content

struct MenuBarMenu: View {
    @Bindable var appState: AppState
    @Bindable var settings: AppSettings
    @Environment(\.openSettings) private var openSettings
    
    @State private var showResetConfirmation = false
    @State private var showResetComplete = false
    
    var body: some View {
        // Settings - use Button with openSettings to ensure proper activation
        Button("Settings") {
            openSettings()
            // For accessory apps, activate after opening so the window
            // comes to front above other applications.
            Task { @MainActor in
                await Task.yield()
                if let settingsWindow = NSApp.windows.first(where: {
                    $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window"
                        || $0.title.contains("Settings")
                }), settingsWindow.isVisible {
                    WindowManager.shared.bringWindowToFront(settingsWindow)
                }
            }
        }
        .keyboardShortcut(",", modifiers: .command)
        
        Button("About Writing Tools") {
            showAboutWindow()
        }
        
        Button(settings.hotkeysPaused ? "Resume Hotkeys" : "Pause Hotkeys") {
            settings.hotkeysPaused.toggle()
        }
        
        Divider()
        
        Button("Reset App") {
            showResetConfirmation = true
        }
        .dialogSeverity(.critical)
        .confirmationDialog(
            "Reset Writing Tools?",
            isPresented: $showResetConfirmation
        ) {
            Button("Reset", role: .destructive) {
                WindowManager.shared.cleanupWindows()
                showResetComplete = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset windows and UI state. Your commands and settings will remain.")
        }
        .alert(
            "App Reset Complete",
            isPresented: $showResetComplete
        ) {
            Button("OK") {}
        } message: {
            Text("The app has been reset. If you're still experiencing issues, try restarting the app.")
        }
        
        Divider()
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
    
    private func showAboutWindow() {
        WindowManager.shared.showAboutWindow()
    }
}
