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
                AppDelegate.sharedStatusItem =
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
    private var settingsHostingView: NSHostingView<SettingsView>?
    private var aboutHostingView: NSHostingView<AboutView>?

    // Pasteboard monitoring
    private var pasteboardObserver: NSObjectProtocol?
    private let pasteboardQueue = DispatchQueue(label: "com.writingtools.pasteboard", qos: .userInitiated)

    @objc private func toggleHotkeys() {
        AppSettings.shared.hotkeysPaused.toggle()
        setupMenuBar()
    }

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

    @objc private func setupCommandShortcuts() {
        for command in appState.commandManager.commands.filter({ !$0.hasShortcut }) {
            KeyboardShortcuts.reset(.commandShortcut(for: command.id))
        }

        for command in appState.commandManager.commands.filter({ $0.hasShortcut }) {
            KeyboardShortcuts.onKeyUp(for: .commandShortcut(for: command.id)) {
                [weak self] in
                guard let self = self, !AppSettings.shared.hotkeysPaused else {
                    return
                }
                self.executeCommandDirectly(command)
            }
        }
    }

    private func executeCommandDirectly(_ command: CommandModel) {
        appState.activeProvider.cancel()

        Task { @MainActor in
            // Store the previous app BEFORE any operations
            let previousApp = NSWorkspace.shared.frontmostApplication

            let pb = NSPasteboard.general
            let oldPlain = pb.string(forType: .string)
            let oldChangeCount = pb.changeCount

            // Create and post Cmd+C event
            let src = CGEventSource(stateID: .hidSystemState)
            let kd = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
            let ku = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
            kd?.flags = .maskCommand
            ku?.flags = .maskCommand

            kd?.post(tap: .cgSessionEventTap)
            ku?.post(tap: .cgSessionEventTap)

            // Give the system a tiny moment to process the copy event
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

            // Wait for the pasteboard to actually change
            await waitForPasteboardChange(pb, initialChangeCount: oldChangeCount)

            // Only proceed if the pasteboard actually changed (new content was copied)
            guard pb.changeCount > oldChangeCount else {
                NSLog("No new content was copied for command: \(command.name) - change count didn't increase (old: \(oldChangeCount), new: \(pb.changeCount))")
                return
            }

            // Read the newly copied content
            var foundImages: [Data] = []

            let classes = [NSURL.self]
            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [
                    "public.image",
                    "public.png",
                    "public.jpeg",
                    "public.tiff",
                    "com.compuserve.gif",
                ],
            ]

            if let urls = pb.readObjects(forClasses: classes, options: options) as? [URL] {
                for url in urls {
                    if let imageData = try? Data(contentsOf: url),
                       NSImage(data: imageData) != nil {
                        foundImages.append(imageData)
                        NSLog("Loaded image data from file: \(url.lastPathComponent)")
                    }
                }
            }

            if foundImages.isEmpty {
                let supportedImageTypes: [NSPasteboard.PasteboardType] = [
                    NSPasteboard.PasteboardType("public.png"),
                    NSPasteboard.PasteboardType("public.jpeg"),
                    NSPasteboard.PasteboardType("public.tiff"),
                    NSPasteboard.PasteboardType("com.compuserve.gif"),
                    NSPasteboard.PasteboardType("public.image"),
                ]

                for type in supportedImageTypes {
                    if let data = pb.data(forType: type) {
                        foundImages.append(data)
                        NSLog("Found direct image data of type: \(type)")
                        break
                    }
                }
            }

            let rich = pb.readAttributedSelection()
            let selectedText = rich?.string ?? pb.string(forType: .string) ?? ""

            guard !selectedText.isEmpty else {
                NSLog("No text selected for command: \(command.name) - pasteboard contained no text")
                // Restore old clipboard
                pb.clearContents()
                if let oldPlain {
                    pb.setString(oldPlain, forType: .string)
                }
                return
            }

            NSLog("Successfully captured text for command \(command.name): \(selectedText.prefix(50))...")

            // Set previous app AFTER we've successfully copied
            if let previousApp = previousApp {
                self.appState.previousApplication = previousApp
            }

            self.appState.selectedImages = foundImages
            self.appState.selectedAttributedText = rich
            self.appState.selectedText = selectedText

            // Restore old clipboard content AFTER we've stored the new selection
            pb.clearContents()
            if let oldPlain {
                pb.setString(oldPlain, forType: .string)
            }

            Task { await self.processCommandWithUI(command) }
        }
    }

    private func processCommandWithUI(_ command: CommandModel) async {
        if appState.isProcessing {
            return
        }

        appState.isProcessing = true

        defer {
            appState.isProcessing = false
        }

        do {
            let result = try await appState.activeProvider.processText(
                systemPrompt: command.prompt,
                userPrompt: appState.selectedText,
                images: appState.selectedImages,
                streaming: false
            )

            await MainActor.run {
                if command.useResponseWindow {
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
                    if command.preserveFormatting, appState.selectedAttributedText != nil {
                        appState.replaceSelectedTextPreservingAttributes(with: result)
                    } else {
                        appState.replaceSelectedText(with: result)
                    }
                }
            }
        } catch {
            NSLog("Error processing command \(command.name): \(error.localizedDescription)")
        }
    }

    // MARK: - Fixed: Clipboard Monitoring (Replace polling)

    private func waitForPasteboardChange(_ pb: NSPasteboard, initialChangeCount: Int) async {
        let startTime = Date()
        let timeout: TimeInterval = 2.0 // Increased timeout
        let pollInterval: UInt64 = 5_000_000 // 5 milliseconds in nanoseconds (more responsive)

        while pb.changeCount == initialChangeCount && Date().timeIntervalSince(startTime) < timeout {
            do {
                try await Task.sleep(nanoseconds: pollInterval)
            } catch {
                // Task was cancelled
                NSLog("Clipboard monitoring cancelled: \(error)")
                return
            }
        }
        
        if pb.changeCount == initialChangeCount {
            NSLog("Warning: Clipboard update timeout after \(timeout)s - no change detected")
        } else {
            let elapsed = Date().timeIntervalSince(startTime)
            NSLog("Clipboard changed after \(String(format: "%.3f", elapsed))s")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = pasteboardObserver {
            NotificationCenter.default.removeObserver(observer)
            pasteboardObserver = nil
        }
        WindowManager.shared.cleanupWindows()
    }

    private func recreateStatusBarItem() {
        AppDelegate.sharedStatusItem = nil
        _ = self.statusBarItem
    }

    private func configureStatusBarItem() {
        guard let button = statusBarItem?.button else { return }
        button.image = NSImage(
            systemSymbolName: "pencil.circle",
            accessibilityDescription: "Writing Tools"
        )
    }

    private func setupMenuBar() {
        guard let statusBarItem = self.statusBarItem else {
            print("Failed to create status bar item")
            return
        }

        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        )
        menu.addItem(
            NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "i")
        )
        let hotkeyTitle = AppSettings.shared.hotkeysPaused ? "Resume" : "Pause"
        menu.addItem(
            NSMenuItem(title: hotkeyTitle, action: #selector(toggleHotkeys), keyEquivalent: "p")
        )
        menu.addItem(
            NSMenuItem(title: "Reset App", action: #selector(resetApp), keyEquivalent: "r")
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        statusBarItem.menu = menu
    }

    @objc private func resetApp() {
        WindowManager.shared.cleanupWindows()

        recreateStatusBarItem()
        setupMenuBar()

        let alert = NSAlert()
        alert.messageText = "App Reset Complete"
        alert.informativeText =
            "The app has been reset. If you're still experiencing issues, try restarting the app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func performRecoveryReset() {
        let domain = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.synchronize()

        WindowManager.shared.cleanupWindows()

        recreateStatusBarItem()
        setupMenuBar()

        let alert = NSAlert()
        alert.messageText = "Recovery Complete"
        alert.informativeText =
            "The app has been reset to its default state."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showSettings() {
        settingsWindow?.close()
        closePopupWindow()
        settingsWindow = nil
        settingsHostingView = nil

        settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow?.isReleasedWhenClosed = false

        let settingsView =
            SettingsView(appState: appState, showOnlyApiSetup: false)
        settingsHostingView = NSHostingView(rootView: settingsView)
        settingsWindow?.contentView = settingsHostingView
        settingsWindow?.delegate = self

        if let window = settingsWindow {
            window.title = "Settings"
            window.level = .floating
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
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
        aboutWindow?.isReleasedWhenClosed = false

        let aboutView = AboutView()
        aboutHostingView = NSHostingView(rootView: aboutView)
        aboutWindow?.contentView = aboutHostingView
        aboutWindow?.delegate = self

        if let window = aboutWindow {
            window.title = "About Writing Tools"
            window.level = .floating
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Writing Tools"
        window.isReleasedWhenClosed = false
        
        window.center()

        let onboardingView = OnboardingView(appState: appState)
        let hostingView = NSHostingView(rootView: onboardingView)
        window.contentView = hostingView
        window.level = .floating

        WindowManager.shared.setOnboardingWindow(
            window,
            hostingView: hostingView
        )
        window.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func showPopup() {
        appState.activeProvider.cancel()

        Task { @MainActor in
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                self.appState.previousApplication = frontApp
            }

            self.closePopupWindow()

            let pb = NSPasteboard.general
            let oldPlain = pb.string(forType: .string)
            let oldChangeCount = pb.changeCount

            // Create and post Cmd+C event
            let src = CGEventSource(stateID: .hidSystemState)
            let kd = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
            let ku = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
            kd?.flags = .maskCommand
            ku?.flags = .maskCommand

            kd?.post(tap: .cgSessionEventTap)
            ku?.post(tap: .cgSessionEventTap)

            // Give the system a tiny moment to process the copy event
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms

            await waitForPasteboardChange(pb, initialChangeCount: oldChangeCount)

            var foundImages: [Data] = []

            let classes = [NSURL.self]
            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [
                    "public.image",
                    "public.png",
                    "public.jpeg",
                    "public.tiff",
                    "com.compuserve.gif",
                ],
            ]

            if let urls = pb.readObjects(forClasses: classes, options: options) as? [URL] {
                for url in urls {
                    if let imageData = try? Data(contentsOf: url),
                       NSImage(data: imageData) != nil {
                        foundImages.append(imageData)
                        NSLog("Loaded image data from file: \(url.lastPathComponent)")
                    }
                }
            }

            if foundImages.isEmpty {
                let supportedImageTypes: [NSPasteboard.PasteboardType] = [
                    NSPasteboard.PasteboardType("public.png"),
                    NSPasteboard.PasteboardType("public.jpeg"),
                    NSPasteboard.PasteboardType("public.tiff"),
                    NSPasteboard.PasteboardType("com.compuserve.gif"),
                    NSPasteboard.PasteboardType("public.image"),
                ]

                for type in supportedImageTypes {
                    if let data = pb.data(forType: type) {
                        foundImages.append(data)
                        NSLog("Found direct image data of type: \(type)")
                        break
                    }
                }
            }

            let rich = pb.readAttributedSelection()
            let plainText = rich?.string ?? pb.string(forType: .string) ?? ""

            self.appState.selectedAttributedText = rich
            self.appState.selectedText = plainText
            self.appState.selectedImages = foundImages

            // Restore old clipboard content AFTER we've stored the new selection
            pb.clearContents()
            if let oldPlain {
                pb.setString(oldPlain, forType: .string)
            }

            let window = PopupWindow(appState: self.appState)
            if !plainText.isEmpty || !foundImages.isEmpty {
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

    private func closePopupWindow() {
        WindowManager.shared.dismissPopup()
    }

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
            }
        }
    }
}

extension AppDelegate {
    override func awakeFromNib() {
        super.awakeFromNib()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }
}
