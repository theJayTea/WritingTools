import Foundation
import Observation
import SwiftUI

private let logger = AppLogger.logger("CommandManager")

@MainActor
@Observable
final class CommandManager {
    private(set) var commands: [CommandModel] = []

    private let saveKey = "unified_commands"
    private let backupKey = "unified_commands_backup"
    private let hasInitializedKey = "has_initialized_commands"
    private let deletedDefaultsKey = "deleted_default_commands"
    
    // Track which default command IDs have been deleted
    private var deletedDefaultIds: Set<UUID> = []
    
    init() {
        loadDeletedDefaultIds()
        loadCommands()
    }
    
    // MARK: - Command Management
    
    func addCommand(_ command: CommandModel) {
        // Stamp the edit time so timestamp-based merge treats this as a fresh edit.
        var command = command
        command.updatedAt = Date()
        commands.append(command)
        saveCommands()
        notifyCommandsChanged()
    }

    func updateCommand(_ command: CommandModel) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            // Stamp the edit time so timestamp-based merge treats this as a fresh edit.
            var command = command
            command.updatedAt = Date()
            commands[index] = command
            saveCommands()

            notifyCommandsChanged()
        }
    }
    
    func deleteCommand(_ command: CommandModel) {
        commands.removeAll { $0.id == command.id }

        // If it's a built-in command, track its ID as deleted
        if command.isBuiltIn {
            deletedDefaultIds.insert(command.id)
            saveDeletedDefaultIds()
        }

        KeychainManager.shared.deleteCustomProviderApiKeySync(for: command.id)

        saveCommands()
        notifyCommandsChanged()
    }
    
    func moveCommand(fromOffsets source: IndexSet, toOffset destination: Int) {
        commands.move(fromOffsets: source, toOffset: destination)
        saveCommands()
        notifyCommandsChanged()
    }

    /// Reorder custom commands without disturbing built-in command positions.
    /// `source`/`destination` are expressed in the coordinate space of the
    /// `customCommands` filtered array (i.e. what the SwiftUI `.onMove` hands
    /// us). Rather than mapping offsets into the full `commands` array (which
    /// breaks when built-ins and customs are interleaved after a sync merge or
    /// lenient-decode recovery), we operate directly on a mutable copy of the
    /// custom sublist, apply the move there, then reassemble as
    /// builtInCommands + reorderedCustom. This is correct regardless of prior
    /// interleaving and does not bump any command's `updatedAt` timestamp.
    func moveCustomCommand(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = customCommands
        guard !reordered.isEmpty else { return }

        reordered.move(fromOffsets: source, toOffset: destination)
        commands = builtInCommands + reordered
        saveCommands()
        notifyCommandsChanged()
    }
    
    // Public method to replace all commands
    func replaceAllCommands(with newCommands: [CommandModel]) {
        let removedIds = Set(commands.map(\.id)).subtracting(newCommands.map(\.id))
        for id in removedIds {
            KeychainManager.shared.deleteCustomProviderApiKeySync(for: id)
        }
        commands = newCommands
        saveCommands()
        notifyCommandsChanged()
    }
    
    // MARK: - Getters with filtering
    
    var builtInCommands: [CommandModel] {
        commands.filter { $0.isBuiltIn }
    }
    
    var customCommands: [CommandModel] {
        commands.filter { !$0.isBuiltIn }
    }
    
    // MARK: - Data Persistence
    
    private func loadCommands() {
        // Check if we've initialized commands before
        let hasInitialized = UserDefaults.standard.bool(forKey: hasInitializedKey)
        
        if !hasInitialized {
            // First run, set up default commands
            initializeDefaultCommands()
            return
        }
        
        // Normal load
        if let data = UserDefaults.standard.data(forKey: saveKey) {
            do {
                let decoded = try JSONDecoder().decode([CommandModel].self, from: data)
                self.commands = decoded
                if containsLegacyCustomProviderKey(in: data) {
                    saveCommands()
                    notifyCommandsChanged()
                }
            } catch {
                // The whole-array decode failed. Rather than nuking everything,
                // attempt a lenient element-wise decode that skips only the
                // individual commands that fail to decode, keeping the rest.
                let recovered = lenientDecode(from: data)

                if recovered.isEmpty {
                    // Nothing could be recovered — treat as genuine corruption.
                    logger.error("Failed to decode saved commands and recovered zero valid commands: \(error.localizedDescription). Backing up corrupted data and resetting to defaults.")
                    // Preserve corrupted data for potential recovery
                    UserDefaults.standard.set(data, forKey: backupKey)
                    initializeDefaultCommands()
                    // Post a notification so the UI can alert the user
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CommandsLoadFailed"),
                        object: nil
                    )
                } else {
                    // Salvaged at least one command. Keep the recovered set and
                    // rewrite storage so the corrupt element is dropped going forward.
                    logger.error("Failed to decode saved commands as a whole (\(error.localizedDescription)); recovered \(recovered.count) valid command(s) via lenient decode.")
                    self.commands = recovered
                    saveCommands()
                    notifyCommandsChanged()
                }
            }
        } else {
            // No saved data at all — initialize defaults
            initializeDefaultCommands()
        }
    }
    
    /// A wrapper that decodes its element if possible and otherwise stores `nil`
    /// instead of throwing. This lets us decode a JSON array of commands while
    /// skipping only the individual elements that are malformed.
    private struct Failable: Decodable {
        let value: CommandModel?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            // Swallow per-element decode failures so one bad command does not
            // abort decoding of the entire array.
            value = try? container.decode(CommandModel.self)
        }
    }

    /// Lenient element-wise decode: decode the JSON array, keeping every command
    /// that decodes successfully and silently dropping any that fail.
    /// Returns an empty array if the data isn't even a decodable array.
    private func lenientDecode(from data: Data) -> [CommandModel] {
        guard let wrapped = try? JSONDecoder().decode([Failable].self, from: data) else {
            return []
        }
        return wrapped.compactMap(\.value)
    }

    private func saveCommands() {
        do {
            let encoded = try JSONEncoder().encode(commands)
            UserDefaults.standard.set(encoded, forKey: saveKey)
        } catch {
            logger.error("Failed to encode commands for saving: \(error.localizedDescription)")
        }
    }
    
    private func loadDeletedDefaultIds() {
        if let data = UserDefaults.standard.data(forKey: deletedDefaultsKey),
           let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            self.deletedDefaultIds = decoded
        }
    }
    
    private func saveDeletedDefaultIds() {
        if let encoded = try? JSONEncoder().encode(deletedDefaultIds) {
            UserDefaults.standard.set(encoded, forKey: deletedDefaultsKey)
        }
    }

    private func containsLegacyCustomProviderKey(in data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        return json.contains { $0["customProviderApiKey"] != nil }
    }
    
    // MARK: - Default Commands
    
    private func initializeDefaultCommands() {
        // Get the default commands and filter out any that are in the deleted list
        var defaultCmds = CommandModel.defaultCommands
        defaultCmds = defaultCmds.filter { !deletedDefaultIds.contains($0.id) }
        
        // Set up commands (if any custom commands, they will be added later)
        self.commands = defaultCmds
        saveCommands()
        notifyCommandsChanged()
        
        // Mark as initialized
        UserDefaults.standard.set(true, forKey: hasInitializedKey)
    }
    
    // MARK: - Reset to Defaults
    
    func resetToDefaults() {
        // Get only the custom commands (not built-in)
        let customCommands = self.commands.filter { !$0.isBuiltIn }
        
        // Get all the default commands (including previously deleted ones)
        let defaultCommands = CommandModel.defaultCommands
        
        // Clear the deleted defaults tracking
        deletedDefaultIds.removeAll()
        saveDeletedDefaultIds()
        
        // Reset to factory defaults and keep custom commands
        self.commands = defaultCommands + customCommands
        
        // Save the changes
        saveCommands()
        notifyCommandsChanged()
    }
    
    // MARK: - Migration Helpers
    
    func migrateFromLegacySystems(customCommands: [CustomCommand]) {
        // Get existing commands but filter out built-in ones (which we'll be replacing)
        let existingCustom = self.commands.filter { !$0.isBuiltIn }
        
        // Convert legacy custom commands
        let convertedCustom = customCommands.map { CommandModel.fromCustomCommand($0) }
        
        // Get default commands but filter out deleted ones
        var defaultCmds = CommandModel.defaultCommands
        defaultCmds = defaultCmds.filter { !deletedDefaultIds.contains($0.id) }
        
        // Set commands to be:
        // 1. Default built-in commands (except deleted ones)
        // 2. Any existing custom commands we already have in the new system
        // 3. Newly converted custom commands from the legacy system
        self.commands = defaultCmds + existingCustom + convertedCustom
        
        // Remove duplicates (by ID) while preserving insertion order
        var seenIds = Set<UUID>()
        self.commands = self.commands.filter { command in
            seenIds.insert(command.id).inserted
        }
        saveCommands()
        notifyCommandsChanged()
    }

    private func notifyCommandsChanged() {
        NotificationCenter.default.post(
            name: NSNotification.Name("CommandsChanged"),
            object: nil
        )
    }
}
