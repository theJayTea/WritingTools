import Foundation

/// A utility class to help migrate from the old WritingOption/CustomCommand system
/// to the new unified CommandModel system
class MigrationHelper {
    static let shared = MigrationHelper()
    
    private let migrationCompletedKey = "command_migration_completed"
    
    private init() {}
    
    /// Checks if migration has been completed
    var isMigrationCompleted: Bool {
        return UserDefaults.standard.bool(forKey: migrationCompletedKey)
    }
    
    /// Performs migration from the old system to the new CommandManager system
    func migrateIfNeeded(commandManager: CommandManager, customCommandsManager: CustomCommandsManager) {
        // Skip if already migrated
        if isMigrationCompleted {
            return
        }
        
        // Migrate custom commands
        commandManager.migrateFromLegacySystems(customCommands: customCommandsManager.commands)
        
        // Mark migration as complete
        UserDefaults.standard.set(true, forKey: migrationCompletedKey)
    }
    
    /// Forces a re-migration (for testing or if needed)
    func forceMigration(commandManager: CommandManager, customCommandsManager: CustomCommandsManager) {
        // Reset migration flag
        UserDefaults.standard.set(false, forKey: migrationCompletedKey)
        
        // Perform migration
        migrateIfNeeded(commandManager: commandManager, customCommandsManager: customCommandsManager)
    }
} 