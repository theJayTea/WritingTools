import SwiftUI
import AppKit

private let logger = AppLogger.logger("WindowManager")

@MainActor
class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var onboardingWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?

    // Track a single PopupWindow
    private var popupWindow: PopupWindow?

    enum PopupDismissSuppressionReason: Hashable {
        case commandEditorSheet
        case commandsManagerSheet
    }

    private var popupDismissSuppressionReasons: Set<PopupDismissSuppressionReason> = []
    private var popupDismissSuppressionResetTask: Task<Void, Never>?
    private let popupDismissSuppressionFailsafeDelay: Duration = .seconds(2)

    var isPopupDismissSuppressed: Bool {
        !popupDismissSuppressionReasons.isEmpty
    }

    private var responseWindows = NSHashTable<ResponseWindow>.weakObjects()

    // MARK: - Response Windows

    func addResponseWindow(_ window: ResponseWindow) {
        guard !window.isReleasedWhenClosed else {
            logger.error("Attempted to add a released window.")
            return
        }
        if !responseWindows.contains(window) {
            responseWindows.add(window)
            window.delegate = self
        }
        bringWindowToFront(window)
    }

    /// Activates the app and brings the given window to the front.
    ///
    /// All callers here (About, Settings, Onboarding, response windows) are
    /// explicit, user-invoked `.normal`-level windows. For an accessory
    /// (menu-bar, no-Dock) app, `NSApp.activate()` + `makeKeyAndOrderFront`
    /// alone frequently leaves such a window *behind* the app the user was last
    /// in — so `orderFrontRegardless()` is required to actually surface it.
    ///
    /// This is NOT the focus-stealing anti-pattern: the popup deliberately does
    /// not use this method (it rides the high `.popUpMenu` window level instead),
    /// so restoring `orderFrontRegardless()` here cannot interfere with typing in
    /// another app during a capture.
    func bringWindowToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Brings the SwiftUI `Settings` scene window to the front after
    /// `openSettings()` has been invoked.
    ///
    /// `preexistingWindowNumbers` must be captured *before* calling
    /// `openSettings()`. The Settings window is then identified as the newly
    /// created titled window — locale-independent and without depending on the
    /// SwiftUI Settings window's private identifier, which varies across macOS
    /// versions. Once found it is cached so a later re-open can raise it directly.
    func raiseSettingsWindow(excluding preexistingWindowNumbers: Set<Int>) {
        Task { @MainActor in
            for _ in 0..<30 {
                // Reuse a previously-identified Settings window once it's visible.
                if let cached = settingsWindow, cached.isVisible {
                    bringWindowToFront(cached)
                    return
                }
                // Otherwise it's the titled window that wasn't open beforehand.
                if let newWindow = NSApp.windows.first(where: {
                    !preexistingWindowNumbers.contains($0.windowNumber)
                        && $0.isVisible
                        && $0.styleMask.contains(.titled)
                        && !($0 is PopupWindow)
                }) {
                    settingsWindow = newWindow
                    bringWindowToFront(newWindow)
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
            // Last resort: at least bring the app forward.
            NSApp.activate()
        }
    }

    func removeResponseWindow(_ window: ResponseWindow) {
        responseWindows.remove(window)
    }

    private func configureThemedChrome(for window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
    }

    // MARK: - Popup Window

    func registerPopupWindow(_ window: PopupWindow) {
        popupWindow = window
        window.delegate = self
    }

    func setPopupDismissSuppressed(
        _ isSuppressed: Bool,
        reason: PopupDismissSuppressionReason
    ) {
        if isSuppressed {
            popupDismissSuppressionReasons.insert(reason)
            schedulePopupDismissSuppressionFailsafe()
        } else {
            popupDismissSuppressionReasons.remove(reason)
            if popupDismissSuppressionReasons.isEmpty {
                popupDismissSuppressionResetTask?.cancel()
                popupDismissSuppressionResetTask = nil
            }
        }
    }

    func dismissPopup(clearImages: Bool = true) {
        clearPopupDismissSuppressionState()
        if let window = self.popupWindow {
            window.close()
            self.popupWindow = nil
        }

        if clearImages {
            AppState.shared.selectedImages = []
        }
    }

    // MARK: - Onboarding

    func setOnboardingWindow(
        _ window: NSWindow,
        hostingView: NSHostingView<OnboardingView>
    ) {
        onboardingWindow = window
        window.delegate = self
        window.level = .normal
        window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")
        
        window.center()
    }

    func showOnboarding(appState: AppState, title: String = "Welcome to Writing Tools") {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 600)
        configureThemedChrome(for: window)

        let onboardingView = OnboardingView(appState: appState)
        let hostingView = NSHostingView(rootView: onboardingView)
        window.contentView = hostingView
        window.level = .normal

        setOnboardingWindow(window, hostingView: hostingView)
        bringWindowToFront(window)
    }

    // MARK: - About Window

    func showAboutWindow() {
        // Reuse existing window if it's still open
        if let existing = aboutWindow, existing.isVisible {
            bringWindowToFront(existing)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("AboutWindow")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AboutView())
        window.title = "About Writing Tools"
        configureThemedChrome(for: window)
        window.delegate = self
        window.center()

        bringWindowToFront(window)
        aboutWindow = window
    }

    // MARK: - Window Delegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let preferredLevel: NSWindow.Level
        if window is PopupWindow {
            preferredLevel = .popUpMenu
        } else {
            preferredLevel = .normal
        }
        if window.level != preferredLevel {
            window.level = preferredLevel
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? PopupWindow else { return }
        // Auto-dismiss popup when it loses focus (e.g., user clicks elsewhere).
        // Skip if a sheet is attached OR if dismissal is temporarily suppressed
        // (e.g., a sheet is about to present but hasn't attached yet).
        if window.attachedSheet == nil && !isPopupDismissSuppressed {
            dismissPopup()
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        if let popup = window as? PopupWindow {
            popup.cleanup()
            clearPopupDismissSuppressionState()
            if popupWindow === popup {
                popupWindow = nil
            }
        } else if let responseWindow = window as? ResponseWindow {
            removeResponseWindow(responseWindow)
        } else if window === onboardingWindow {
            onboardingWindow = nil
        } else if window === aboutWindow {
            aboutWindow = nil
        }

        window.delegate = nil
    }

    // MARK: - Cleanup

    func cleanupWindows() {
        let windowsToClose = getAllWindows()

        windowsToClose.forEach { window in
            (window as? PopupWindow)?.cleanup()
            // Set delegate to nil to prevent callbacks during close
            window.delegate = nil
            window.close()
        }
        clearAllWindows()
    }

    private func getAllWindows() -> [NSWindow] {
        var windows: [NSWindow] = []

        if let onboardingWindow {
            windows.append(onboardingWindow)
        }

        if let aboutWindow {
            windows.append(aboutWindow)
        }

        if let popup = popupWindow {
            windows.append(popup)
        }

        windows.append(contentsOf: responseWindows.allObjects)
        return windows
    }

    private func clearAllWindows() {
        onboardingWindow = nil
        aboutWindow = nil
        responseWindows.removeAllObjects()
        clearPopupDismissSuppressionState()
        popupWindow = nil
    }

    deinit {}
}

extension WindowManager {
    private func schedulePopupDismissSuppressionFailsafe() {
        popupDismissSuppressionResetTask?.cancel()
        popupDismissSuppressionResetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: popupDismissSuppressionFailsafeDelay)
            guard !Task.isCancelled else { return }
            guard !popupDismissSuppressionReasons.isEmpty else { return }
            logger.warning("Resetting popup dismissal suppression via failsafe")
            popupDismissSuppressionReasons.removeAll()
            popupDismissSuppressionResetTask = nil
        }
    }

    private func clearPopupDismissSuppressionState() {
        popupDismissSuppressionResetTask?.cancel()
        popupDismissSuppressionResetTask = nil
        popupDismissSuppressionReasons.removeAll()
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
