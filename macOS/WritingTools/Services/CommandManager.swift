import Foundation
import SwiftUI

class CommandManager: ObservableObject {
    @Published private(set) var commands: [CommandModel] = []
    
    private let saveKey = "unified_commands"
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
        commands.append(command)
        saveCommands()
    }
    
    func updateCommand(_ command: CommandModel) {
        if let index = commands.firstIndex(where: { $0.id == command.id }) {
            commands[index] = command
            saveCommands()
            
            // Notify that commands have changed to update shortcuts
            NotificationCenter.default.post(name: NSNotification.Name("CommandsChanged"), object: nil)
        }
    }
    
    func deleteCommand(_ command: CommandModel) {
        commands.removeAll { $0.id == command.id }
        
        // If it's a built-in command, track its ID as deleted
        if command.isBuiltIn {
            deletedDefaultIds.insert(command.id)
            saveDeletedDefaultIds()
        }
        
        saveCommands()
    }
    
    func moveCommand(fromOffsets source: IndexSet, toOffset destination: Int) {
        commands.move(fromOffsets: source, toOffset: destination)
        saveCommands()
    }
    
    // Public method to replace all commands
    func replaceAllCommands(with newCommands: [CommandModel]) {
        commands = newCommands
        saveCommands()
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
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([CommandModel].self, from: data) {
            self.commands = decoded
        } else {
            // Fallback if something went wrong with loading
            initializeDefaultCommands()
        }
    }
    
    private func saveCommands() {
        if let encoded = try? JSONEncoder().encode(commands) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
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
    
    // MARK: - Default Commands
    
    private func initializeDefaultCommands() {
        // Get the default commands and filter out any that are in the deleted list
        var defaultCmds = CommandModel.defaultCommands
        defaultCmds = defaultCmds.filter { !deletedDefaultIds.contains($0.id) }
        
        // Set up commands (if any custom commands, they will be added later)
        self.commands = defaultCmds
        saveCommands()
        
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
        
        // Remove any duplicates (by name)
        let uniqueCommands = Dictionary(grouping: self.commands, by: { $0.name })
            .compactMap { $1.first }
        
        self.commands = uniqueCommands
        saveCommands()
    }
} 