import SwiftUI
import KeyboardShortcuts
import Carbon.HIToolbox

private let logger = AppLogger.logger("AppDelegate")

/// AppDelegate handles keyboard shortcuts, services, and popup window management.
/// Menu bar UI is handled by SwiftUI's MenuBarExtra in writing_toolsApp.swift.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var iCloudSyncObserver: NSObjectProtocol?
    private var iCloudQuotaObserver: NSObjectProtocol?
    private var clipboardRestoreObserver: NSObjectProtocol?
    private var commandsChangedObserver: NSObjectProtocol?
    private var commandShortcutNamesById: [UUID: KeyboardShortcuts.Name] = [:]
    
    let appState = AppState.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = self

        if CommandLine.arguments.contains("--reset") {
            Task { @MainActor [weak self] in
                self?.performRecoveryReset()
            }
            return
        }

        Task { @MainActor in
            if !AppSettings.shared.hasCompletedOnboarding {
                self.showOnboarding()
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
        commandsChangedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CommandsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupCommandShortcuts()
            }
        }

        configureCloudCommandSync(enabled: AppSettings.shared.enableICloudCommandSync)
        iCloudSyncObserver = NotificationCenter.default.addObserver(
            forName: .iCloudCommandSyncPreferenceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configureCloudCommandSync(enabled: AppSettings.shared.enableICloudCommandSync)
            }
        }

        iCloudQuotaObserver = NotificationCenter.default.addObserver(
            forName: .iCloudCommandSyncQuotaExceeded,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                let payloadBytes = note.userInfo?[CloudCommandsSyncUserInfoKey.payloadBytes] as? Int
                let totalBytes = note.userInfo?[CloudCommandsSyncUserInfoKey.totalBytes] as? Int
                let reason = note.userInfo?[CloudCommandsSyncUserInfoKey.reason] as? String
                self.showICloudQuotaWarningAlert(
                    payloadBytes: payloadBytes,
                    totalBytes: totalBytes,
                    reason: reason
                )
            }
        }

        clipboardRestoreObserver = NotificationCenter.default.addObserver(
            forName: .clipboardRestoreSkipped,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                let expected = note.userInfo?[ClipboardNotificationUserInfoKey.expectedChangeCount] as? Int ?? -1
                let actual = note.userInfo?[ClipboardNotificationUserInfoKey.actualChangeCount] as? Int ?? -1
                self.showClipboardRestoreSkippedWarningAlert(
                    expectedChangeCount: expected,
                    actualChangeCount: actual
                )
            }
        }
    }

    private func setupCommandShortcuts() {
        let commandsWithShortcuts = appState.commandManager.commands.filter(\.hasShortcut)
        let desiredIds = Set(commandsWithShortcuts.map(\.id))
        let registeredIds = Set(commandShortcutNamesById.keys)

        guard desiredIds != registeredIds else { return }

        let removedIds = registeredIds.subtracting(desiredIds)
        for id in removedIds {
            guard let shortcutName = commandShortcutNamesById[id] else { continue }
            KeyboardShortcuts.removeHandler(for: shortcutName)
            KeyboardShortcuts.reset(shortcutName)
            commandShortcutNamesById[id] = nil
        }

        let addedIds = desiredIds.subtracting(registeredIds)
        for commandId in addedIds {
            let shortcutName = KeyboardShortcuts.Name.commandShortcut(for: commandId)
            KeyboardShortcuts.removeHandler(for: shortcutName)
            KeyboardShortcuts.onKeyUp(for: shortcutName) { [weak self] in
                guard let self, !AppSettings.shared.hotkeysPaused else { return }
                guard let command = self.appState.commandManager.commands.first(where: { $0.id == commandId }) else {
                    logger.warning("Shortcut fired for missing command ID: \(commandId.uuidString)")
                    return
                }
                self.executeCommandDirectly(command)
            }
            commandShortcutNamesById[commandId] = shortcutName
        }
    }

    private func executeCommandDirectly(_ command: CommandModel) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                _ = try await CommandExecutionEngine.shared.executeCommand(
                    command,
                    source: .hotkey
                )
            } catch let error as CommandExecutionEngineError {
                self.handleCommandExecutionError(error)
            } catch {
                logger.error("Error processing command \(command.name): \(error.localizedDescription)")
                await self.presentCommandErrorAlert(commandName: command.name, error: error)
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any debounced keychain writes before exit
        AppSettings.shared.flushPendingKeychainWrites()

        // Flush cloud sync: cancel debounce, push immediately, and synchronize
        CloudCommandsSync.shared.flushAndSynchronize()

        if let commandsChangedObserver {
            NotificationCenter.default.removeObserver(commandsChangedObserver)
            self.commandsChangedObserver = nil
        }
        if let iCloudSyncObserver {
            NotificationCenter.default.removeObserver(iCloudSyncObserver)
            self.iCloudSyncObserver = nil
        }
        if let iCloudQuotaObserver {
            NotificationCenter.default.removeObserver(iCloudQuotaObserver)
            self.iCloudQuotaObserver = nil
        }
        if let clipboardRestoreObserver {
            NotificationCenter.default.removeObserver(clipboardRestoreObserver)
            self.clipboardRestoreObserver = nil
        }
        for shortcutName in commandShortcutNamesById.values {
            KeyboardShortcuts.removeHandler(for: shortcutName)
        }
        commandShortcutNamesById.removeAll()
        CloudCommandsSync.shared.stop()
        WindowManager.shared.cleanupWindows()
    }

    private func performRecoveryReset() {
        // Stop sync first so an in-flight pull can't fight the reset.
        CloudCommandsSync.shared.stop()

        // resetAll() clears the Keychain API keys and resets in-memory settings,
        // and also removes the UserDefaults persistent domain. Without this, the
        // next launch's keychain migration would find no source and lose API keys.
        AppSettings.shared.resetAll()

        WindowManager.shared.cleanupWindows()

        let alert = NSAlert()
        alert.messageText = "Recovery Complete"
        alert.informativeText =
            "The app has been reset to its default state."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        NSApp.activate()
        if let keyWindow = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWindow)
        } else {
            alert.runModal()
        }
    }

    private func showOnboarding() {
        WindowManager.shared.showOnboarding(appState: appState)
    }

    @MainActor
    private func showPopup() {
        Task { @MainActor in
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                self.appState.previousApplication = frontApp
            }

            self.closePopupWindow()

            guard let capture = await ClipboardCoordinator.shared.captureSelection() else {
                logger.debug("Clipboard capture skipped because another operation is in progress")
                return
            }

            if !capture.didChange {
                logger.warning("Pasteboard did not change after copy; clearing selection to avoid stale context")
            }

            self.appState.selectedAttributedText = capture.attributedText
            self.appState.selectedText = capture.text
            self.appState.selectedImages = capture.images

            let window = PopupWindow(appState: self.appState)
            if !capture.text.isEmpty || !capture.images.isEmpty {
                window.setContentSize(NSSize(width: 400, height: 400))
            } else {
                window.setContentSize(NSSize(width: 400, height: 100))
            }

            window.positionNearMouse()
            // Activate cooperatively and make the popup key. We deliberately do
            // NOT call orderFrontRegardless(): it bypasses the window server's
            // normal activation handshake and can yank focus away from the app
            // the user is actively typing in, dropping keystrokes (see the note
            // in WindowManager.bringWindowToFront).
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func handleCommandExecutionError(_ error: CommandExecutionEngineError) {
        switch error {
        case .captureInProgress:
            logger.debug("Clipboard capture skipped because another operation is in progress")
        case .noNewCopiedContent(let commandName):
            logger.warning("No new content was copied for command: \(commandName)")
        case .emptySelection(let commandName):
            logger.info("No text or images selected for command: \(commandName)")
        case .emptyInstruction:
            logger.warning("Custom instruction execution failed due to empty instruction")
        case .customProviderConfigurationIncomplete(let commandName, let missingFields):
            logger.warning(
                """
                Custom provider configuration incomplete for command \(commandName). \
                Missing fields: \(missingFields.joined(separator: ", "))
                """
            )
        }
    }

    private func presentCommandErrorAlert(commandName: String, error: Error) async {
        let alert = NSAlert()
        alert.messageText = "Command Error"
        alert.informativeText = "Failed to process '\(commandName)': \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        NSApp.activate()
        if let keyWindow = NSApp.keyWindow {
            await alert.beginSheetModal(for: keyWindow)
        } else {
            alert.runModal()
        }
    }

    private func closePopupWindow() {
        WindowManager.shared.dismissPopup()
    }

    private func configureCloudCommandSync(enabled: Bool) {
        CloudCommandsSync.shared.setEnabled(enabled)
        logger.info("iCloud command sync \(enabled ? "enabled" : "disabled")")
    }

    private func showICloudQuotaWarningAlert(payloadBytes: Int?, totalBytes: Int?, reason: String?) {
        let alert = NSAlert()
        alert.messageText = "iCloud Sync Storage Limit Reached"
        switch reason {
        case "preflight_payload_too_large":
            if let payloadBytes {
                alert.informativeText =
                    """
                    Writing Tools couldn't sync commands because the command payload is too large (\(payloadBytes) bytes).
                    Try deleting some commands or shortening large prompts, then sync again.
                    """
            } else {
                alert.informativeText =
                    """
                    Writing Tools couldn't sync commands because the command payload is too large.
                    Try deleting some commands or shortening large prompts, then sync again.
                    """
            }
        case "preflight_total_store_too_large":
            if let totalBytes {
                alert.informativeText =
                    """
                    Writing Tools couldn't sync commands because estimated iCloud key-value storage usage reached \(totalBytes) bytes.
                    Try deleting some commands, shortening large prompts, or clearing old deleted-command history.
                    """
            } else {
                alert.informativeText =
                    """
                    Writing Tools couldn't sync commands because iCloud key-value storage quota was exceeded.
                    Try deleting some commands, shortening large prompts, or clearing old deleted-command history.
                    """
            }
        default:
            alert.informativeText =
                """
                Writing Tools couldn't sync commands because iCloud key-value storage quota was exceeded.
                Try deleting some commands or shortening large prompts, then sync again.
                """
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")

        NSApp.activate()
        if let keyWindow = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWindow)
        } else {
            alert.runModal()
        }
    }

    private func showClipboardRestoreSkippedWarningAlert(
        expectedChangeCount: Int,
        actualChangeCount: Int
    ) {
        let alert = NSAlert()
        alert.messageText = "Clipboard Was Updated by Another App"
        alert.informativeText =
            """
            Writing Tools captured your selection, but your clipboard changed before it could be restored.
            Your latest clipboard content was preserved.
            (Expected change count: \(expectedChangeCount), actual: \(actualChangeCount))
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        NSApp.activate()
        if let keyWindow = NSApp.keyWindow {
            alert.beginSheetModal(for: keyWindow)
        } else {
            alert.runModal()
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
