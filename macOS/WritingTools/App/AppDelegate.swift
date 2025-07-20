import SwiftUI
import KeyboardShortcuts
import Carbon.HIToolbox

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    
    // Static status item to prevent deallocation
    private static var sharedStatusItem: NSStatusItem?
    
    // Property to track service-triggered popups
    private var isServiceTriggered: Bool = false
    
    // Computed property to manage the menu bar status item
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
    let appState = AppState.shared
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private(set) var popupWindow: NSWindow?
    private var settingsHostingView: NSHostingView<SettingsView>?
    private var aboutHostingView: NSHostingView<AboutView>?
    @objc private func toggleHotkeys() {
        AppSettings.shared.hotkeysPaused.toggle()
        // Refresh the menu so the title changes.
        setupMenuBar()
    }
    // Called when app launches - initializes core functionality
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        NSApp.servicesProvider = self
        
        if CommandLine.arguments.contains("--reset") {
            DispatchQueue.main.async { [weak self] in
                self?.performRecoveryReset()
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBar()
            
            if self?.statusBarItem == nil {
                self?.recreateStatusBarItem()
            }
            
            if !UserDefaults.standard.bool(forKey: "has_completed_onboarding") {
                self?.showOnboarding()
            }
            
        }
        
        // Register the main popup shortcut
        KeyboardShortcuts.onKeyUp(for: .showPopup) { [weak self] in
            if !AppSettings.shared.hotkeysPaused {
                self?.showPopup()
            } else {
                NSLog("Hotkeys are paused")
            }
        }
        
        // Set up command-specific shortcuts
        setupCommandShortcuts()
        
        // Register for command changes to update shortcuts
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(setupCommandShortcuts),
            name: NSNotification.Name("CommandsChanged"),
            object: nil
        )
    }
    
    // Setup and register all command shortcuts
    @objc private func setupCommandShortcuts() {
        // Only reset shortcuts for commands that should not have shortcuts
        for command in appState.commandManager.commands.filter({ !$0.hasShortcut }) {
            KeyboardShortcuts.reset(.commandShortcut(for: command.id))
        }
        
        // Register handlers for commands with shortcuts enabled
        for command in appState.commandManager.commands.filter({ $0.hasShortcut }) {
            KeyboardShortcuts.onKeyUp(for: .commandShortcut(for: command.id)) { [weak self] in
                guard let self = self, !AppSettings.shared.hotkeysPaused else { return }
                
                // Execute the command directly
                self.executeCommandDirectly(command)
            }
        }
    }
    
    // Executes a command without showing the popup
    private func executeCommandDirectly(_ command: CommandModel) {
        // Cancel any ongoing processing first
        appState.activeProvider.cancel()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Save the current app so we can return to it
            if let currentFrontmostApp = NSWorkspace.shared.frontmostApplication {
                self.appState.previousApplication = currentFrontmostApp
            }
            
            let generalPasteboard = NSPasteboard.general
            
            // Get initial pasteboard content to restore later
            let oldContents = generalPasteboard.string(forType: .string)
            
            // Clear and perform copy command to get selected text
            generalPasteboard.clearContents()
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            
            // Wait for copy operation to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                
                // Get the selected text
                let selectedText = generalPasteboard.string(forType: .string) ?? ""
                
                // Restore original clipboard contents
                generalPasteboard.clearContents()
                if let oldContents = oldContents {
                    generalPasteboard.setString(oldContents, forType: .string)
                }
                
                // Skip if no text is selected
                guard !selectedText.isEmpty else {
                    NSLog("No text selected for command: \(command.name)")
                    return
                }
                
                // Store the selected text in app state
                self.appState.selectedText = selectedText
                
                // Process the command
                Task {
                    await self.processCommandWithUI(command)
                }
            }
        }
    }
    
    // Process a command with appropriate UI feedback
    private func processCommandWithUI(_ command: CommandModel) async {
        // Set processing flag to prevent duplicate operations
        if appState.isProcessing {
            return
        }
        
        appState.isProcessing = true
        
        do {
            // Process the text with the AI provider
            let result = try await appState.activeProvider.processText(
                systemPrompt: command.prompt,
                userPrompt: appState.selectedText,
                images: [],
                streaming: false
            )
            
            // Handle the result
            await MainActor.run {
                if command.useResponseWindow {
                    // Show in response window
                    let window = ResponseWindow(
                        title: command.name,
                        content: result,
                        selectedText: appState.selectedText,
                        option: nil
                    )
                    
                    NSApp.activate(ignoringOtherApps: true)
                    WindowManager.shared.addResponseWindow(window)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                } else {
                    // Replace text directly
                    appState.replaceSelectedText(with: result)
                }
            }
        } catch {
            print("Error processing command \(command.name): \(error.localizedDescription)")
        }
        
        await MainActor.run {
            appState.isProcessing = false
        }
    }
    
    // Called when app is about to close - performs cleanup
    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.cleanupWindows()
    }
    
    // Recreates the menu bar item if it was lost
    private func recreateStatusBarItem() {
        AppDelegate.sharedStatusItem = nil
        _ = self.statusBarItem
    }
    
    // Sets up the status bar item's icon
    private func configureStatusBarItem() {
        guard let button = statusBarItem?.button else { return }
        button.image = NSImage(systemSymbolName: "pencil.circle", accessibilityDescription: "Writing Tools")
    }
    
    // Creates the menu that appears when clicking the status bar icon
    private func setupMenuBar() {
        guard let statusBarItem = self.statusBarItem else {
            print("Failed to create status bar item")
            return
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "i"))
        // New Pause/Resume item:
        let hotkeyTitle = AppSettings.shared.hotkeysPaused ? "Resume" : "Pause"
        menu.addItem(NSMenuItem(title: hotkeyTitle, action: #selector(toggleHotkeys), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Reset App", action: #selector(resetApp), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusBarItem.menu = menu
    }
    
    // Resets app to default state when triggered from menu
    @objc private func resetApp() {
        WindowManager.shared.cleanupWindows()
        
        recreateStatusBarItem()
        setupMenuBar()
        
        
        let alert = NSAlert()
        alert.messageText = "App Reset Complete"
        alert.informativeText = "The app has been reset. If you're still experiencing issues, try restarting the app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // Full app reset when launched with --reset flag
    private func performRecoveryReset() {
        // Reset all app defaults
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()
        
        // Reset the app state
        WindowManager.shared.cleanupWindows()
        
        // Recreate status bar and setup
        recreateStatusBarItem()
        setupMenuBar()
        
        // Show confirmation
        let alert = NSAlert()
        alert.messageText = "Recovery Complete"
        alert.informativeText = "The app has been reset to its default state."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // Shows the first-time setup/onboarding window
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
    
    // Opens the settings window
    @objc private func showSettings() {
        settingsWindow?.close()
        closePopupWindow()
        settingsWindow = nil
        settingsHostingView = nil
        
        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        settingsWindow?.titleVisibility = .hidden
        settingsWindow?.titlebarAppearsTransparent = true
        settingsWindow?.isMovableByWindowBackground = true
        settingsWindow?.isReleasedWhenClosed = false
        
        for type in [.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType] {
            settingsWindow?.standardWindowButton(type)?.isHidden = true
        }
        
        let settingsView = SettingsView(appState: appState, showOnlyApiSetup: false)
        settingsHostingView = NSHostingView(rootView: settingsView)
        settingsWindow?.contentView = settingsHostingView
        settingsWindow?.delegate = self
        
        // Ensure window appears in front
        if let window = settingsWindow {
            window.level = .floating
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
    
    // Opens the about window
    @objc private func showAbout() {
        aboutWindow?.close()
        aboutWindow = nil
        aboutHostingView = nil
        
        aboutWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        aboutWindow?.titleVisibility = .hidden
        aboutWindow?.titlebarAppearsTransparent = true
        aboutWindow?.isMovableByWindowBackground = true
        aboutWindow?.isReleasedWhenClosed = false
        
        for type in [.closeButton, .miniaturizeButton, .zoomButton] as [NSWindow.ButtonType] {
            aboutWindow?.standardWindowButton(type)?.isHidden = true
        }
        
        let aboutView = AboutView()
        aboutHostingView = NSHostingView(rootView: aboutView)
        aboutWindow?.contentView = aboutHostingView
        aboutWindow?.delegate = self
        
        // Ensure window appears in front
        if let window = aboutWindow {
            window.level = .floating
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
    
    @MainActor private func showPopup() {
        appState.activeProvider.cancel()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let currentFrontmostApp = NSWorkspace.shared.frontmostApplication {
                self.appState.previousApplication = currentFrontmostApp
            }
            
            self.closePopupWindow()
            
            let generalPasteboard = NSPasteboard.general
            let oldContents = generalPasteboard.string(forType: .string)
            
            // Clear and perform copy command to get current selection
            generalPasteboard.clearContents()
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            
            // Wait for the copy operation to complete, then process the pasteboard
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                
                var foundImages: [Data] = []
                var selectedText = ""
                
                // First check for file URLs (for Finder selections)
                let classes = [NSURL.self]
                let options: [NSPasteboard.ReadingOptionKey: Any] = [
                    .urlReadingFileURLsOnly: true,
                    .urlReadingContentsConformToTypes: [
                        "public.image",
                        "public.png",
                        "public.jpeg",
                        "public.tiff",
                        "com.compuserve.gif"
                    ]
                ]
                
                if let urls = generalPasteboard.readObjects(forClasses: classes, options: options) as? [URL] {
                    for url in urls {
                        if let imageData = try? Data(contentsOf: url) {
                            if NSImage(data: imageData) != nil {
                                foundImages.append(imageData)
                                NSLog("Loaded image data from file: \(url.lastPathComponent)")
                            }
                        }
                    }
                }
                
                // If no file URLs found, check for direct image data
                if foundImages.isEmpty {
                    let supportedImageTypes = [
                        NSPasteboard.PasteboardType("public.png"),
                        NSPasteboard.PasteboardType("public.jpeg"),
                        NSPasteboard.PasteboardType("public.tiff"),
                        NSPasteboard.PasteboardType("com.compuserve.gif"),
                        NSPasteboard.PasteboardType("public.image")
                    ]
                    
                    for type in supportedImageTypes {
                        if let data = generalPasteboard.data(forType: type) {
                            foundImages.append(data)
                            NSLog("Found direct image data of type: \(type)")
                            break
                        }
                    }
                }
                
                // Get any text content
                selectedText = generalPasteboard.string(forType: .string) ?? ""
                
                // Restore original pasteboard contents
                generalPasteboard.clearContents()
                if let oldContents = oldContents {
                    generalPasteboard.setString(oldContents, forType: .string)
                }
                
                // Update app state and show popup
                self.appState.selectedImages = foundImages
                self.appState.selectedText = selectedText
                
                let window = PopupWindow(appState: self.appState)
                window.delegate = self
                self.popupWindow = window
                
                // Set window size based on content
                if !selectedText.isEmpty || !foundImages.isEmpty {
                    window.setContentSize(NSSize(width: 400, height: 400))
                } else {
                    window.setContentSize(NSSize(width: 400, height: 100))
                }
                
                window.positionNearMouse()
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
    
    // Closes and cleans up the popup window
    private func closePopupWindow() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let existingWindow = self.popupWindow as? PopupWindow {
                existingWindow.delegate = nil
                existingWindow.cleanup()
                existingWindow.close()
                
                self.appState.selectedImages = []
                self.popupWindow = nil
            }
        }
    }
    
    // Handles window cleanup when any window is closed
    func windowWillClose(_ notification: Notification) {
        guard !isServiceTriggered else { return }
        
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

// extension to support service registration
extension AppDelegate {
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // Register services provider
        NSApp.servicesProvider = self
        
        // Register the service
        NSUpdateDynamicServices()
    }
}
