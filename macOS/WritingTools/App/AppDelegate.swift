import SwiftUI
import KeyboardShortcuts
import Carbon.HIToolbox
import UniformTypeIdentifiers
import ImageIO

private let logger = AppLogger.logger("AppDelegate")

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
    @objc private func toggleHotkeys() {
        AppSettings.shared.hotkeysPaused.toggle()
        setupMenuBar()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self

        if CommandLine.arguments.contains("--reset") {
            Task { @MainActor [weak self] in
                self?.performRecoveryReset()
            }
            return
        }

        Task { @MainActor [weak self] in
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
                logger.info("Hotkeys are paused")
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
            let oldChangeCount = pb.changeCount

            // IMPORTANT: Capture the ENTIRE clipboard state before copying
            let clipboardSnapshot = pb.createSnapshot()
            logger.debug("Captured clipboard snapshot with \(clipboardSnapshot.itemCount) items")

            // Create and post Cmd+C event
            let src = CGEventSource(stateID: .hidSystemState)
            let kd = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
            let ku = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
            kd?.flags = .maskCommand
            ku?.flags = .maskCommand

            kd?.post(tap: .cgSessionEventTap)
            ku?.post(tap: .cgSessionEventTap)

            // Give the system a tiny moment to process the copy event
            try? await Task.sleep(for: .milliseconds(50)) // 50ms - increased for reliability

            // Wait for the pasteboard to actually change
            await waitForPasteboardChange(pb, initialChangeCount: oldChangeCount)

            // Only proceed if the pasteboard actually changed (new content was copied)
            guard pb.changeCount > oldChangeCount else {
                logger.warning("No new content was copied for command: \(command.name) - change count didn't increase (old: \(oldChangeCount), new: \(pb.changeCount))")
                return
            }

            // Read the newly copied content IMMEDIATELY after detecting the change
            var foundImages: [Data] = []

            let classes = [NSURL.self]
            let imageTypeIdentifiers = [
                UTType.image,
                UTType.png,
                UTType.jpeg,
                UTType.tiff,
                UTType.gif,
            ].map(\.identifier)

            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: imageTypeIdentifiers,
            ]

            if let urls = pb.readObjects(forClasses: classes, options: options) as? [URL] {
                let loadedImages = await loadImageData(from: urls)
                if !loadedImages.isEmpty {
                    foundImages.append(contentsOf: loadedImages)
                }
            }

            if foundImages.isEmpty {
                let supportedImageTypes: [NSPasteboard.PasteboardType] = [
                    NSPasteboard.PasteboardType(UTType.png.identifier),
                    NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                    NSPasteboard.PasteboardType(UTType.tiff.identifier),
                    NSPasteboard.PasteboardType(UTType.gif.identifier),
                    NSPasteboard.PasteboardType(UTType.image.identifier),
                ]

                for type in supportedImageTypes {
                    if let data = pb.data(forType: type) {
                        foundImages.append(data)
                        logger.debug("Found direct image data of type: \(type.rawValue)")
                        break
                    }
                }
            }

            // Read rich text BEFORE clearing
            let rich = pb.readAttributedSelection()
            let selectedText = rich?.string ?? pb.string(forType: .string) ?? ""

            guard !selectedText.isEmpty else {
                logger.info("No text selected for command: \(command.name) - pasteboard contained no text")
                // Restore original clipboard using snapshot
                pb.restore(snapshot: clipboardSnapshot)
                return
            }

            logger.debug("Successfully captured text for command \(command.name): \(selectedText.prefix(50))...")

            // Store data in appState BEFORE restoring clipboard
            self.appState.selectedImages = foundImages
            self.appState.selectedAttributedText = rich
            self.appState.selectedText = selectedText

            // Set previous app AFTER we've successfully copied
            if let previousApp = previousApp {
                self.appState.previousApplication = previousApp
            }

            // NOW restore original clipboard using the snapshot
            pb.restore(snapshot: clipboardSnapshot)
            logger.debug("Restored original clipboard after capturing selection")

            // Process the command with the captured data
            await self.processCommandWithUI(command)
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
            // Get the appropriate provider for this command (respects per-command overrides)
            let provider = appState.getProvider(for: command)

            var result = try await provider.processText(
                systemPrompt: command.prompt,
                userPrompt: appState.selectedText,
                images: appState.selectedImages,
                streaming: false
            )

            // Preserve trailing newlines from the original selection
            // This is important for triple-click selections which include the trailing newline
            let originalText = appState.selectedText
            if originalText.hasSuffix("\n") && !result.hasSuffix("\n") {
                result += "\n"
                logger.debug("Added trailing newline to match input")
            }

            await MainActor.run {
                if command.useResponseWindow {
                    let window = ResponseWindow(
                        title: command.name,
                        content: result,
                        selectedText: appState.selectedText,
                        option: nil,
                        provider: provider
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
            logger.error("Error processing command \(command.name): \(error.localizedDescription)")

            // Show error alert
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Command Error"
                alert.informativeText = "Failed to process '\(command.name)': \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    // MARK: - Fixed: Clipboard Monitoring (Replace polling)

    private func waitForPasteboardChange(_ pb: NSPasteboard, initialChangeCount: Int) async {
        let startTime = Date()
        let timeout: TimeInterval = 2.0 // Increased timeout
        let pollInterval: Duration = .milliseconds(5)

        while pb.changeCount == initialChangeCount && Date().timeIntervalSince(startTime) < timeout {
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                // Task was cancelled
                logger.debug("Clipboard monitoring cancelled: \(error.localizedDescription)")
                return
            }
        }

        if pb.changeCount == initialChangeCount {
            logger.warning("Clipboard update timeout after \(timeout)s - no change detected")
        } else {
            let elapsed = Date().timeIntervalSince(startTime)
            let formattedElapsed = elapsed.formatted(.number.precision(.fractionLength(3)))
            logger.debug("Clipboard changed after \(formattedElapsed)s")
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
            logger.error("Failed to create status bar item")
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
            let oldChangeCount = pb.changeCount

            // Capture the ENTIRE clipboard state before copying
            let clipboardSnapshot = pb.createSnapshot()
            logger.debug("Captured clipboard snapshot with \(clipboardSnapshot.itemCount) items")

            // Create and post Cmd+C event
            let src = CGEventSource(stateID: .hidSystemState)
            let kd = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
            let ku = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
            kd?.flags = .maskCommand
            ku?.flags = .maskCommand

            kd?.post(tap: .cgSessionEventTap)
            ku?.post(tap: .cgSessionEventTap)

            // Give the system a tiny moment to process the copy event
            try? await Task.sleep(for: .milliseconds(50)) // 50ms - increased for reliability

            await waitForPasteboardChange(pb, initialChangeCount: oldChangeCount)

            var foundImages: [Data] = []

            let classes = [NSURL.self]
            let imageTypeIdentifiers = [
                UTType.image,
                UTType.png,
                UTType.jpeg,
                UTType.tiff,
                UTType.gif,
            ].map(\.identifier)

            let options: [NSPasteboard.ReadingOptionKey: Any] = [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: imageTypeIdentifiers,
            ]

            if let urls = pb.readObjects(forClasses: classes, options: options) as? [URL] {
                let loadedImages = await loadImageData(from: urls)
                if !loadedImages.isEmpty {
                    foundImages.append(contentsOf: loadedImages)
                }
            }

            if foundImages.isEmpty {
                let supportedImageTypes: [NSPasteboard.PasteboardType] = [
                    NSPasteboard.PasteboardType(UTType.png.identifier),
                    NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                    NSPasteboard.PasteboardType(UTType.tiff.identifier),
                    NSPasteboard.PasteboardType(UTType.gif.identifier),
                    NSPasteboard.PasteboardType(UTType.image.identifier),
                ]

                for type in supportedImageTypes {
                    if let data = pb.data(forType: type) {
                        foundImages.append(data)
                        logger.debug("Found direct image data of type: \(type.rawValue)")
                        break
                    }
                }
            }

            // Read rich text and plain text BEFORE restoring clipboard
            let rich = pb.readAttributedSelection()
            let plainText = rich?.string ?? pb.string(forType: .string) ?? ""

            // Store data in appState BEFORE restoring clipboard
            self.appState.selectedAttributedText = rich
            self.appState.selectedText = plainText
            self.appState.selectedImages = foundImages

            // Restore original clipboard using the snapshot
            pb.restore(snapshot: clipboardSnapshot)
            logger.debug("Restored original clipboard after capturing selection")

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
        Task { @MainActor [weak self] in
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

// MARK: - Image Loading

private extension AppDelegate {
    func loadImageData(from urls: [URL]) async -> [Data] {
        await Task.detached(priority: .userInitiated) {
            var images: [Data] = []
            images.reserveCapacity(urls.count)

            for url in urls {
                if let imageData = try? Data(contentsOf: url),
                   await Self.isValidImageData(imageData) {
                    images.append(imageData)
                    logger.debug("Loaded image data from file: \(url.lastPathComponent)")
                }
            }
            return images
        }.value
    }

    static func isValidImageData(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }
}

extension AppDelegate {
    override func awakeFromNib() {
        super.awakeFromNib()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }
}
