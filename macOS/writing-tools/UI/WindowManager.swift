
import SwiftUI

class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()
    
    private let windowQueue = DispatchQueue(label: "com.writingtools.windowmanager")
    
    private var onboardingWindow = NSMapTable<NSWindow, NSHostingView<OnboardingView>>.strongToWeakObjects()
    private var settingsWindow = NSMapTable<NSWindow, NSHostingView<SettingsView>>.strongToWeakObjects()
    private var popupWindow = NSMapTable<PopupWindow, NSHostingView<PopupView>>.strongToWeakObjects()
    private var responseWindows = NSHashTable<ResponseWindow>.weakObjects()
    
    private func performOnMainThread(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }
    
    private func performOnWindowQueue(_ operation: @escaping () -> Void) {
        windowQueue.async { [weak self] in
            guard self != nil else { return }
            operation()
        }
    }
    
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
    
    func removeResponseWindow(_ window: ResponseWindow) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            self.responseWindows.remove(window)
        }
    }
    
    func transitonFromOnboardingToSettings(appState: AppState) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            
            let currentOnboardingWindow = self.onboardingWindow.keyEnumerator().nextObject() as? NSWindow
            
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            
            settingsWindow.title = "Complete Setup"
            settingsWindow.center()
            settingsWindow.isReleasedWhenClosed = false
            
            let settingsView = SettingsView(appState: appState, showOnlyApiSetup: true)
            let hostingView = NSHostingView(rootView: settingsView)
            settingsWindow.contentView = hostingView
            settingsWindow.delegate = self
            
            self.settingsWindow.setObject(hostingView, forKey: settingsWindow)
            
            settingsWindow.makeKeyAndOrderFront(nil)
            currentOnboardingWindow?.close()
            self.onboardingWindow.removeAllObjects()
        }
    }
    
    func setOnboardingWindow(_ window: NSWindow, hostingView: NSHostingView<OnboardingView>) {
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            
            self.onboardingWindow.removeAllObjects()
            
            self.onboardingWindow.setObject(hostingView, forKey: window)
            window.delegate = self
            window.level = .floating
            window.center()
        }
    }
    
    
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        if !(window is PopupWindow) {
            performOnMainThread {
                window.level = .floating
            }
        }
    }
    
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
    
    private func getAllWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        
        if let onboardingWindow = onboardingWindow.keyEnumerator().nextObject() as? NSWindow {
            windows.append(onboardingWindow)
        }
        
        if let settingsWindow = settingsWindow.keyEnumerator().nextObject() as? NSWindow {
            windows.append(settingsWindow)
        }
        
        if let popupWindow = popupWindow.keyEnumerator().nextObject() as? PopupWindow {
            windows.append(popupWindow)
        }
        
        windows.append(contentsOf: responseWindows.allObjects)
        return windows
    }
    
    private func clearAllWindows() {
        performOnMainThread { [weak self] in
            self?.onboardingWindow.removeAllObjects()
            self?.settingsWindow.removeAllObjects()
            self?.popupWindow.removeAllObjects()
            self?.responseWindows.removeAllObjects()
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
    func cleanupPopupWindow(_ window: PopupWindow) {
        performOnMainThread {
            if self.popupWindow.object(forKey: window) != nil {
                window.cleanup()
                self.popupWindow.removeObject(forKey: window)
            }
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        performOnMainThread { [weak self] in
            guard let self = self else { return }
            
            if let popupWindow = window as? PopupWindow {
                popupWindow.cleanup()
                self.popupWindow.removeObject(forKey: popupWindow)
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
