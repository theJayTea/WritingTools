//
//  KeychainManager.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import Foundation
import Security

actor KeychainManager {
    static let shared = KeychainManager()
    private static let serviceName = "com.aryamirsepasi.writing-tools"
    private let customProviderKeyPrefix = "custom_provider_api_key_"

    private init() {}

    enum ItemScope {
        case any
        case synchronizableOnly
        case localOnly
    }
    
    enum KeychainError: LocalizedError {
        case failedToSave(OSStatus)
        case failedToRead(OSStatus)
        case failedToDelete(OSStatus)
        case noDataFound
        
        var errorDescription: String? {
            switch self {
            case .failedToSave(let status):
                return "Failed to save to Keychain: \(status)"
            case .failedToRead(let status):
                return "Failed to read from Keychain: \(status)"
            case .failedToDelete(let status):
                return "Failed to delete from Keychain: \(status)"
            case .noDataFound:
                return "No data found in Keychain"
            }
        }
    }
    
    // MARK: - Save
    
    func save(_ value: String, forKey key: String, synchronizable: Bool = true) throws {
        guard !value.isEmpty else {
            try delete(forKey: key, scope: .any)
            return
        }
        
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.failedToSave(-1)
        }

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        addQuery[kSecAttrSynchronizable as String] =
            synchronizable ? (kCFBooleanTrue as Any) : (kCFBooleanFalse as Any)

        // Delete existing synchronizable and non-synchronizable values before saving.
        try delete(forKey: key, scope: .any)

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.failedToSave(status)
        }
    }
    
    // MARK: - Read
    
    func retrieve(forKey key: String, scope: ItemScope = .any) throws -> String? {
        switch scope {
        case .any:
            if let syncValue = try retrieveSingle(forKey: key, scope: .synchronizableOnly) {
                return syncValue
            }
            return try retrieveSingle(forKey: key, scope: .localOnly)
        case .synchronizableOnly, .localOnly:
            return try retrieveSingle(forKey: key, scope: scope)
        }
    }

    private func retrieveSingle(forKey key: String, scope: ItemScope) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: synchronizableQueryValue(for: scope)
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.failedToRead(status)
        }
        
        guard let data = result as? Data else {
            throw KeychainError.noDataFound
        }
        
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - Delete
    
    func delete(forKey key: String, scope: ItemScope = .any) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName,
            kSecAttrSynchronizable as String: synchronizableQueryValue(for: scope)
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.failedToDelete(status)
        }
    }
    
    // MARK: - Clear All
    
    /// Removes every API key this app stores under its Keychain service.
    ///
    /// This covers both the named provider keys and the per-command custom
    /// provider keys (whose account names are UUID-suffixed and can't be
    /// enumerated individually). Matching on the service alone with
    /// `kSecAttrSynchronizableAny` deletes the local and iCloud-synced copies
    /// in a single pass. Unlike the previous implementation, failures are
    /// surfaced to the caller instead of being silently swallowed.
    func clearAllApiKeys() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.failedToDelete(status)
        }
    }
    
    func hasMigratedKey(forKey key: String) -> Bool {
        do {
            let value = try retrieve(forKey: key, scope: .any)
            return value != nil
        } catch {
            return false
        }
    }

    func verifyMigration() -> [String: Bool] {
        let keysToCheck = [
            "gemini_api_key",
            "openai_api_key",
            "mistral_api_key",
            "anthropic_api_key",
            "openrouter_api_key"
        ]
        
        var results: [String: Bool] = [:]
        for key in keysToCheck {
            results[key] = hasMigratedKey(forKey: key)
        }
        return results
    }

    // MARK: - Synchronizable Keychain (iCloud Keychain)

    func saveSynchronizable(_ value: String, forKey key: String) throws {
        try save(value, forKey: key, synchronizable: true)
    }

    func retrieveSynchronizable(forKey key: String) throws -> String? {
        try retrieve(forKey: key, scope: .synchronizableOnly)
    }

    func deleteSynchronizable(forKey key: String) throws {
        try delete(forKey: key, scope: .any)
    }

    // MARK: - Custom Provider API Keys (Synchronizable)

    func saveCustomProviderApiKey(_ value: String?, for commandId: UUID) {
        let key = customProviderKeyPrefix + commandId.uuidString
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            try? deleteSynchronizable(forKey: key)
        } else {
            try? saveSynchronizable(trimmed, forKey: key)
        }
    }

    func retrieveCustomProviderApiKey(for commandId: UUID) -> String? {
        let key = customProviderKeyPrefix + commandId.uuidString
        return try? retrieveSynchronizable(forKey: key)
    }

    func deleteCustomProviderApiKey(for commandId: UUID) {
        let key = customProviderKeyPrefix + commandId.uuidString
        try? deleteSynchronizable(forKey: key)
    }

    // MARK: - Bootstrap / Nonisolated Synchronous Access

    /// Synchronous read for use during app bootstrap only (e.g. AppSettings.init).
    /// This avoids turning AppSettings into an async singleton. Not for general use.
    nonisolated func bootstrapRetrieve(forKey key: String, scope: ItemScope = .any) -> String? {
        switch scope {
        case .any:
            if let syncValue = bootstrapRetrieveSingle(forKey: key, scope: .synchronizableOnly) {
                return syncValue
            }
            return bootstrapRetrieveSingle(forKey: key, scope: .localOnly)
        case .synchronizableOnly, .localOnly:
            return bootstrapRetrieveSingle(forKey: key, scope: scope)
        }
    }

    nonisolated private func bootstrapRetrieveSingle(forKey key: String, scope: ItemScope) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: synchronizableQueryValue(for: scope)
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Synchronous save for use from non-async contexts (e.g. Decodable init, SwiftUI init).
    /// Uses direct SecItem calls to bypass actor isolation.
    @discardableResult
    nonisolated func bootstrapSave(_ value: String, forKey key: String, synchronizable: Bool = true) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            return false
        }

        guard !value.isEmpty else { return true }
        guard let data = value.data(using: .utf8) else { return false }

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        addQuery[kSecAttrSynchronizable as String] =
            synchronizable ? (kCFBooleanTrue as Any) : (kCFBooleanFalse as Any)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// Synchronous delete for use from non-async contexts.
    @discardableResult
    nonisolated func bootstrapDelete(forKey key: String, scope: ItemScope = .any) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Self.serviceName,
            kSecAttrSynchronizable as String: synchronizableQueryValue(for: scope)
        ]
        let status = SecItemDelete(deleteQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Synchronous retrieve from synchronizable keychain for use from non-async contexts.
    nonisolated func bootstrapRetrieveSynchronizable(forKey key: String) -> String? {
        bootstrapRetrieve(forKey: key, scope: .any)
    }

    /// Synchronous "clear all API keys" for non-async contexts such as
    /// `AppSettings.resetAll()`, where the deletion must complete before the
    /// app shows a "Reset Complete" confirmation or relaunches. Mirrors the
    /// async `clearAllApiKeys()` (service-wide delete across both scopes).
    /// Returns `true` on success or when nothing was present.
    @discardableResult
    nonisolated func clearAllApiKeysSync() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Nonisolated Custom Provider Key Helpers

    /// Synchronous save of a custom provider API key (for use in Decodable.init, SwiftUI views, etc.)
    nonisolated func saveCustomProviderApiKeySync(_ value: String?, for commandId: UUID) {
        let key = "custom_provider_api_key_" + commandId.uuidString
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            _ = bootstrapDelete(forKey: key, scope: .any)
        } else {
            _ = bootstrapSave(trimmed, forKey: key, synchronizable: true)
        }
    }

    /// Synchronous retrieve of a custom provider API key (for use from non-async contexts)
    nonisolated func retrieveCustomProviderApiKeySync(for commandId: UUID) -> String? {
        let key = "custom_provider_api_key_" + commandId.uuidString
        return bootstrapRetrieveSynchronizable(forKey: key)
    }

    /// Synchronous delete of a custom provider API key (for use from non-async contexts)
    nonisolated func deleteCustomProviderApiKeySync(for commandId: UUID) {
        let key = "custom_provider_api_key_" + commandId.uuidString
        _ = bootstrapDelete(forKey: key, scope: .any)
    }

    nonisolated private func synchronizableQueryValue(for scope: ItemScope) -> Any {
        switch scope {
        case .any:
            return kSecAttrSynchronizableAny
        case .synchronizableOnly:
            return kCFBooleanTrue as Any
        case .localOnly:
            return kCFBooleanFalse as Any
        }
    }
}
