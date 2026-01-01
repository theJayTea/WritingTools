import SwiftUI
import AppKit

private let logger = AppLogger.logger("WindowManager")

class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var onboardingWindow =
        NSMapTable<NSWindow, NSHostingView<OnboardingView>>.strongToWeakObjects()
    private var settingsWindow =
        NSMapTable<NSWindow, NSHostingView<SettingsView>>.strongToWeakObjects()

    // Track a single PopupWindow
    private weak var popupWindow: PopupWindow?

    private var responseWindows = NSHashTable<ResponseWindow>.weakObjects()
    
    private var cleanupTimer: Timer?

    // Execute operation on main thread
    private func performOnMainThread(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            Task { @MainActor in
                operation()
            }
        }
    }

    // Execute operation on window queue
    private func performOnWindowQueue(_ operation: @escaping () -> Void) {
        Task(priority: .userInitiated) { @MainActor [weak self] in
            guard self != nil else { return }
            operation()
        }
    }

    // MARK: - Response Windows

    func addResponseWindow(_ window: ResponseWindow) {
        performOnMainThread { [weak self] in
            guard let self = self, !window.isReleasedWhenClosed else {
                logger.error("Attempted to add a released window.")
                return
            }
            if !self.responseWindows.contains(window) {
                self.responseWindows.add(window)
                window.delegate = self
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    func removeResponseWindow(_ window: ResponseWindow) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            self.responseWindows.remove(window)
        }
    }

    // MARK: - Popup Window

    func registerPopupWindow(_ window: PopupWindow) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            self.popupWindow = window
            window.delegate = self
        }
    }

    @MainActor
    func dismissPopup() {
        if let window = self.popupWindow {
            window.close()
            self.popupWindow = nil
        }

        // Preserve previous behavior: clear selected images on popup close.
        AppState.shared.selectedImages = []
    }

    // MARK: - Onboarding & Settings

    func transitonFromOnboardingToSettings(appState: AppState) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }

            let currentOnboardingWindow =
                self.onboardingWindow.keyEnumerator().nextObject() as? NSWindow

            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )

            settingsWindow.title = "Complete Setup"
            settingsWindow.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
            settingsWindow.isReleasedWhenClosed = false

            let settingsView =
                SettingsView(appState: appState, showOnlyApiSetup: true)
            let hostingView = NSHostingView(rootView: settingsView)
            settingsWindow.contentView = hostingView
            settingsWindow.delegate = self

            self.settingsWindow.setObject(hostingView, forKey: settingsWindow)

            // ✓ Center window BEFORE display
            settingsWindow.level = .floating
            settingsWindow.center()
            
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            
            currentOnboardingWindow?.close()
            self.onboardingWindow.removeAllObjects()
        }
    }

    func setOnboardingWindow(
        _ window: NSWindow,
        hostingView: NSHostingView<OnboardingView>
    ) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }

            self.onboardingWindow.removeAllObjects()
            self.onboardingWindow.setObject(hostingView, forKey: window)
            window.delegate = self
            window.level = .floating
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")
            
            window.center()
        }
    }

    // MARK: - Window Delegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if !(window is PopupWindow) {
            performOnMainThread {
                window.level = .floating
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        performOnMainThread { [weak self] in
            guard let self = self else { return }

            if let popup = window as? PopupWindow {
                popup.cleanup()
                if self.popupWindow === popup {
                    self.popupWindow = nil
                }
            } else if let responseWindow = window as? ResponseWindow {
                self.removeResponseWindow(responseWindow)
            } else if self.onboardingWindow.object(forKey: window) != nil {
                self.onboardingWindow.removeObject(forKey: window)
            } else if self.settingsWindow.object(forKey: window) != nil {
                self.settingsWindow.removeObject(forKey: window)
            }

            window.delegate = nil
        }
    }

    // MARK: - Cleanup

    func cleanupWindows() {
        performOnWindowQueue { [weak self] in
            guard let self = self else { return }

            let windowsToClose = self.getAllWindows()

            self.performOnMainThread {
                windowsToClose.forEach { window in
                    // Set delegate to nil to prevent callbacks during close
                    window.delegate = nil
                    window.close()
                }
                self.clearAllWindows()
            }
        }
    }

    private func getAllWindows() -> [NSWindow] {
        var windows: [NSWindow] = []

        if let onboardingWindow =
            onboardingWindow.keyEnumerator().nextObject() as? NSWindow {
            windows.append(onboardingWindow)
        }

        if let settingsWindow =
            settingsWindow.keyEnumerator().nextObject() as? NSWindow {
            windows.append(settingsWindow)
        }

        if let popup = popupWindow {
            windows.append(popup)
        }

        windows.append(contentsOf: responseWindows.allObjects)
        return windows
    }

    private func clearAllWindows() {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            self.onboardingWindow.removeAllObjects()
            self.settingsWindow.removeAllObjects()
            self.responseWindows.removeAllObjects()
            self.popupWindow = nil
        }
    }

    deinit {
        cleanupTimer?.invalidate()
    }
}

extension WindowManager {
    enum WindowError: LocalizedError {
        case windowCreationFailed
        case invalidWindowType
        case windowNotFound

        var errorDescription: String? {
            switch self {
            case .windowCreationFailed:
                return "Failed to create window"
            case .invalidWindowType:
                return "Invalid window type"
            case .windowNotFound:
                return "Window not found"
            }
        }
    }
}
