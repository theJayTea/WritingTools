//
//  Untitled.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import Foundation
import Security

private let logger = AppLogger.logger("KeychainMigrationManager")

class KeychainMigrationManager {
    static let shared = KeychainMigrationManager()
    
    private let keychain = KeychainManager.shared
    private let userDefaults = UserDefaults.standard
    
    // Migration tracking
    private let migrationCompleteKey = "keychain_migration_complete_v1"
    private let migrationLogKey = "keychain_migration_log"
    
    private init() {}
    
    // MARK: - Public API
    
    func migrateIfNeeded() {
        // Skip if already migrated
        guard !hasMigrationCompleted() else {
            logger.info("Keychain migration already completed")
            return
        }
        
        logger.info("Starting Keychain migration for API keys...")
        
        let keysToMigrate = [
            ("gemini_api_key", "gemini_api_key"),
            ("openai_api_key", "openai_api_key"),
            ("mistral_api_key", "mistral_api_key"),
            ("anthropic_api_key", "anthropic_api_key"),
            ("openrouter_api_key", "openrouter_api_key"),
        ]
        
        var migratedKeys: [String] = []
        var failedKeys: [String] = []
        
        for (oldKey, newKey) in keysToMigrate {
            if let value = userDefaults.string(forKey: oldKey), !value.isEmpty {
                do {
                    try keychain.save(value, forKey: newKey)
                    migratedKeys.append(oldKey)
                    logger.debug("Migrated: \(oldKey)")
                    
                    // Remove from UserDefaults after successful migration
                    userDefaults.removeObject(forKey: oldKey)
                } catch {
                    failedKeys.append(oldKey)
                    logger.error("Failed to migrate \(oldKey): \(error.localizedDescription)")
                }
            }
        }
        
        // Log migration results
        logMigration(migratedKeys: migratedKeys, failedKeys: failedKeys)
        
        // Mark migration as complete
        markMigrationComplete()
        
        logger.info("Keychain migration complete. Migrated: \(migratedKeys.count), Failed: \(failedKeys.count)")
    }
    
    // MARK: - Private Methods
    
    private func hasMigrationCompleted() -> Bool {
        return userDefaults.bool(forKey: migrationCompleteKey)
    }
    
    private func markMigrationComplete() {
        userDefaults.set(true, forKey: migrationCompleteKey)
    }
    
    private func logMigration(migratedKeys: [String], failedKeys: [String]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = """
        [Migration Log - \(timestamp)]
        Migrated keys: \(migratedKeys.isEmpty ? "none" : migratedKeys.joined(separator: ", "))
        Failed keys: \(failedKeys.isEmpty ? "none" : failedKeys.joined(separator: ", "))
        """
        
        var existingLog = userDefaults.string(forKey: migrationLogKey) ?? ""
        existingLog += "\n" + logEntry
        userDefaults.set(existingLog, forKey: migrationLogKey)
    }
    
    // MARK: - Debug/Admin Methods
    
    func getMigrationLog() -> String {
        return userDefaults.string(forKey: migrationLogKey) ?? "No migration log available"
    }
    
    func resetMigration() {
        userDefaults.removeObject(forKey: migrationCompleteKey)
        userDefaults.removeObject(forKey: migrationLogKey)
        logger.info("Migration reset flag cleared")
    }
    
    func forceMigration() {
        resetMigration()
        migrateIfNeeded()
    }
}
