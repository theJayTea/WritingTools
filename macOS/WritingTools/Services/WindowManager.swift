import SwiftUI
import AppKit

class WindowManager: NSObject, NSWindowDelegate {
  static let shared = WindowManager()

  private let windowQueue =
    DispatchQueue(label: "com.writingtools.windowmanager")

  private var onboardingWindow =
    NSMapTable<NSWindow, NSHostingView<OnboardingView>>.strongToWeakObjects()
  private var settingsWindow =
    NSMapTable<NSWindow, NSHostingView<SettingsView>>.strongToWeakObjects()

  // Track a single PopupWindow
  private weak var popupWindow: PopupWindow?

  private var responseWindows = NSHashTable<ResponseWindow>.weakObjects()

  // Execute operation on main thread (runtime), not sufficient for @MainActor isolation.
  private func performOnMainThread(_ operation: @escaping () -> Void) {
    if Thread.isMainThread {
      operation()
    } else {
      DispatchQueue.main.async(execute: operation)
    }
  }

  // Execute operation on window queue
  private func performOnWindowQueue(_ operation: @escaping () -> Void) {
    windowQueue.async { [weak self] in
      guard self != nil else { return }
      operation()
    }
  }

  // Add a new response window
  func addResponseWindow(_ window: ResponseWindow) {
    performOnMainThread { [weak self] in
      guard let self = self, !window.isReleasedWhenClosed else {
        print("Error: Attempted to add a released window.")
        return
      }
      if !self.responseWindows.contains(window) {
        self.responseWindows.add(window)
        window.delegate = self
      }
      window.makeKeyAndOrderFront(nil)
    }
  }

  // Remove a response window
  func removeResponseWindow(_ window: ResponseWindow) {
    performOnMainThread { [weak self] in
      guard let self = self else { return }
      self.responseWindows.remove(window)
    }
  }

  // Register the popup with the manager so it can be cleaned up globally
  func registerPopupWindow(_ window: PopupWindow) {
    performOnMainThread { [weak self] in
      guard let self = self else { return }
      self.popupWindow = window
      window.delegate = self
    }
  }

  // Ensure this runs on the MainActor when touching AppState (which is @MainActor)
  @MainActor
  func dismissPopup() {
    // This method is now MainActor-isolated, so we can mutate AppState safely.
    if let window = self.popupWindow {
      window.close() // window.cleanup() is called inside close()
      self.popupWindow = nil
    }

    // Preserve previous behavior: clear selected images on popup close.
    AppState.shared.selectedImages = []
  }

  // Transition from onboarding to settings window
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
      settingsWindow.center()
      settingsWindow.isReleasedWhenClosed = false

      let settingsView =
        SettingsView(appState: appState, showOnlyApiSetup: true)
      let hostingView = NSHostingView(rootView: settingsView)
      settingsWindow.contentView = hostingView
      settingsWindow.delegate = self

      self.settingsWindow.setObject(hostingView, forKey: settingsWindow)

      settingsWindow.makeKeyAndOrderFront(nil)
      currentOnboardingWindow?.close()
      self.onboardingWindow.removeAllObjects()
    }
  }

  // Set up onboarding window
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
      window.center()
    }
  }

  // Handle window becoming key
  func windowDidBecomeKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    if !(window is PopupWindow) {
      performOnMainThread {
        window.level = .floating
      }
    }
  }

  // Clean up all windows
  func cleanupWindows() {
    performOnWindowQueue { [weak self] in
      guard let self = self else { return }

      let windowsToClose = self.getAllWindows()

      self.performOnMainThread {
        windowsToClose.forEach { $0.close() }
        self.clearAllWindows()
      }
    }
  }

  // Get all managed windows
  private func getAllWindows() -> [NSWindow] {
    var windows: [NSWindow] = []

    if let onboardingWindow =
      onboardingWindow.keyEnumerator().nextObject() as? NSWindow
    {
      windows.append(onboardingWindow)
    }

    if let settingsWindow =
      settingsWindow.keyEnumerator().nextObject() as? NSWindow
    {
      windows.append(settingsWindow)
    }

    if let popup = popupWindow {
      windows.append(popup)
    }

    windows.append(contentsOf: responseWindows.allObjects)
    return windows
  }

  // Clear all window references
  private func clearAllWindows() {
    performOnMainThread { [weak self] in
      guard let self = self else { return }
      self.onboardingWindow.removeAllObjects()
      self.settingsWindow.removeAllObjects()
      self.responseWindows.removeAllObjects()
      self.popupWindow = nil
    }
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

extension WindowManager {
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
}
