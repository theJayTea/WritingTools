//
//  Untitled.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import Foundation

private let logger = AppLogger.logger("KeychainMigrationManager")

@MainActor
final class KeychainMigrationManager {
    static let shared = KeychainMigrationManager()
    
    private let keychain = KeychainManager.shared
    private let userDefaults = UserDefaults.standard
    
    // Migration tracking
    private let migrationCompleteKey = "keychain_migration_complete_v1"
    private let migrationLogKey = "keychain_migration_log"

    enum MigrationResult: Equatable {
        case skipped
        case success(migratedKeys: [String])
        case failed(migratedKeys: [String], failedKeys: [String])
    }
    
    private init() {}
    
    // MARK: - Public API
    
    @discardableResult
    func migrateIfNeeded() -> MigrationResult {
        // Skip if already migrated
        guard !hasMigrationCompleted() else {
            logger.info("Keychain migration already completed")
            return .skipped
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
            guard let value = userDefaults.string(forKey: oldKey), !value.isEmpty else {
                continue
            }

            // Use nonisolated bootstrap save/read because migration runs at startup
            // before async contexts are available.
            let saveSucceeded = keychain.bootstrapSave(value, forKey: newKey, synchronizable: true)
            guard saveSucceeded else {
                failedKeys.append(oldKey)
                logger.error("Failed to migrate \(oldKey): keychain write failed")
                continue
            }

            let readBack = keychain.bootstrapRetrieve(forKey: newKey, scope: .any)
            guard readBack == value else {
                failedKeys.append(oldKey)
                logger.error("Failed to migrate \(oldKey): keychain read-back verification failed")
                continue
            }

            migratedKeys.append(oldKey)
            logger.debug("Migrated: \(oldKey)")
        }

        // Log migration results
        logMigration(migratedKeys: migratedKeys, failedKeys: failedKeys)

        if failedKeys.isEmpty {
            // Only now that EVERY key migrated and verified do we delete the
            // originals from UserDefaults. Deleting per-key inside the loop was a
            // data-loss hazard: if a later key's keychain write failed, migration
            // was never marked complete, yet the already-deleted originals were
            // gone — so the next launch's re-run found empty values and silently
            // lost those keys forever.
            for oldKey in migratedKeys {
                userDefaults.removeObject(forKey: oldKey)
            }
            markMigrationComplete()
            logger.info("Keychain migration complete. Migrated: \(migratedKeys.count)")
            return .success(migratedKeys: migratedKeys)
        }

        // Partial failure: leave ALL originals (including the ones that migrated
        // this pass) in UserDefaults so the next launch can safely retry. The
        // keychain bootstrapSave is an upsert, so re-migrating an already-written
        // key is harmless.
        logger.error("Keychain migration incomplete. Migrated: \(migratedKeys.count), Failed: \(failedKeys.count). Originals retained for retry.")
        return .failed(migratedKeys: migratedKeys, failedKeys: failedKeys)
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
