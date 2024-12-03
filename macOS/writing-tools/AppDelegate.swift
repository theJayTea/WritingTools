import SwiftUI
import HotKey
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static var sharedStatusItem: NSStatusItem?
    var statusBarItem: NSStatusItem! {
        get {
            if AppDelegate.sharedStatusItem == nil {
                AppDelegate.sharedStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                configureStatusBarItem()
            }
            return AppDelegate.sharedStatusItem
        }
        set {
            AppDelegate.sharedStatusItem = newValue
        }
    }
    var hotKey: HotKey?
    let appState = AppState.shared
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private(set) var popupWindow: NSWindow?
    private var settingsHostingView: NSHostingView<SettingsView>?
    private var aboutHostingView: NSHostingView<AboutView>?
    private let windowAccessQueue = DispatchQueue(label: "com.example.writingtools.windowQueue")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBar()
            self?.setupHotKey()
            
            if self?.statusBarItem == nil {
                self?.recreateStatusBarItem()
            }
            
            if !UserDefaults.standard.bool(forKey: "has_completed_onboarding") {
                self?.showOnboarding()
            }
            
            self?.requestAccessibilityPermissions()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.cleanupWindows()
    }
    
    private func recreateStatusBarItem() {
        AppDelegate.sharedStatusItem = nil
        _ = self.statusBarItem
    }
    
    private func configureStatusBarItem() {
        guard let button = statusBarItem?.button else { return }
        button.image = NSImage(systemSymbolName: "pencil.circle", accessibilityDescription: "Writing Tools")
    }
    
    private func setupMenuBar() {
        guard let statusBarItem = self.statusBarItem else {
            print("Failed to create status bar item")
            return
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "Reset App", action: #selector(resetApp), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusBarItem.menu = menu
    }
    
    @objc private func resetApp() {
        hotKey = nil
        WindowManager.shared.cleanupWindows()
        
        recreateStatusBarItem()
        setupMenuBar()
        
        setupHotKey()
        
        let alert = NSAlert()
        alert.messageText = "App Reset Complete"
        alert.informativeText = "The app has been reset. If you're still experiencing issues, try restarting the app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func requestAccessibilityPermissions() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = "Writing Tools needs accessibility access to detect text selection and simulate keyboard shortcuts. Please grant access in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
    
    private func setupHotKey() {
        updateHotKey()
        
        NotificationCenter.default.removeObserver(self, name: UserDefaults.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }
    
    @objc private func shortcutChanged() {
        DispatchQueue.main.async { [weak self] in
            if UserDefaults.standard.string(forKey: "shortcut") != nil {
                self?.updateHotKey()
            }
        }
    }
    
    private func updateHotKey() {
        // Remove existing hotkey first
        hotKey = nil
        
        let shortcutText = UserDefaults.standard.string(forKey: "shortcut") ?? "⌥ Space"
        
        var modifiers: NSEvent.ModifierFlags = []
        var keyCode: UInt32 = 0
        
        let components = shortcutText.components(separatedBy: " ")
        for component in components {
            switch component {
            case "⌘": modifiers.insert(.command)
            case "⌥": modifiers.insert(.option)
            case "⌃": modifiers.insert(.control)
            case "⇧": modifiers.insert(.shift)
            case "Space": keyCode = UInt32(kVK_Space)
            case "Return": keyCode = UInt32(kVK_Return)
            case "D": keyCode = UInt32(kVK_ANSI_D)
            default:
                if let firstChar = component.first,
                   let asciiValue = firstChar.uppercased().first?.asciiValue {
                    keyCode = UInt32(asciiValue) - UInt32(0x41) + UInt32(kVK_ANSI_A)
                }
            }
        }
        
        guard keyCode != 0 else {
            print("Invalid key code, resetting to default shortcut")
            UserDefaults.standard.set("⌥ Space", forKey: "shortcut")
            updateHotKey()
            return
        }
        
        hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: keyCode, carbonModifiers: modifiers.carbonFlags))
        hotKey?.keyDownHandler = { [weak self] in
            DispatchQueue.main.async {
                if let frontmostApp = NSWorkspace.shared.frontmostApplication {
                    self?.appState.previousApplication = frontmostApp
                }
                
                self?.showPopup()
            }
        }
    }
    
    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Writing Tools"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        let onboardingView = OnboardingView(appState: appState)
        let hostingView = NSHostingView(rootView: onboardingView)
        window.contentView = hostingView
        window.level = .floating
        
        WindowManager.shared.setOnboardingWindow(window, hostingView: hostingView)
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc private func showSettings() {
        settingsWindow?.close()
        settingsWindow = nil
        settingsHostingView = nil
        
        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        settingsWindow?.title = "Settings"
        settingsWindow?.center()
        settingsWindow?.isReleasedWhenClosed = false
        
        let settingsView = SettingsView(appState: appState, showOnlyApiSetup: false)
        settingsHostingView = NSHostingView(rootView: settingsView)
        settingsWindow?.contentView = settingsHostingView
        settingsWindow?.delegate = self
        
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func showAbout() {
        aboutWindow?.close()
        aboutWindow = nil
        aboutHostingView = nil
        
        aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        aboutWindow?.title = "About Writing Tools"
        aboutWindow?.center()
        aboutWindow?.isReleasedWhenClosed = false
        
        let aboutView = AboutView()
        aboutHostingView = NSHostingView(rootView: aboutView)
        aboutWindow?.contentView = aboutHostingView
        aboutWindow?.delegate = self
        
        aboutWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func showPopup() {
        appState.activeProvider.cancel()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.closePopupWindow()
            
            let pasteboard = NSPasteboard.general
            let oldContents = pasteboard.string(forType: .string)
            pasteboard.clearContents()
            
            // Simulate copy command
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                let selectedText = pasteboard.string(forType: .string) ?? ""
                
                pasteboard.clearContents()
                if let oldContents = oldContents {
                    pasteboard.setString(oldContents, forType: .string)
                }
                
                // Create window even if no text is selected
                let window = PopupWindow(appState: self.appState)
                window.delegate = self
                
                self.appState.selectedText = selectedText
                self.popupWindow = window
                
                if selectedText.isEmpty {
                    window.setContentSize(NSSize(width: 400, height: 100))
                }
                
                window.positionNearMouse()
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
    
    private func closePopupWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let existingWindow = self.popupWindow as? PopupWindow {
                existingWindow.delegate = nil
                existingWindow.cleanup()
                existingWindow.close()
                
                self.popupWindow = nil
            }
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { [weak self] in
            if window == self?.settingsWindow {
                self?.settingsHostingView = nil
                self?.settingsWindow = nil
            } else if window == self?.aboutWindow {
                self?.aboutHostingView = nil
                self?.aboutWindow = nil
            } else if window == self?.popupWindow {
                self?.popupWindow?.delegate = nil
                self?.popupWindow = nil
            }
        }
    }
}

// Extension to convert ModifierFlags to Carbon flags
extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var carbon: UInt32 = 0
        if contains(.command) { carbon |= UInt32(cmdKey) }
        if contains(.option) { carbon |= UInt32(optionKey) }
        if contains(.control) { carbon |= UInt32(controlKey) }
        if contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
