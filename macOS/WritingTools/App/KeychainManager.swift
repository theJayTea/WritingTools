//
//  KeychainManager.swift
//  WritingTools
//
//  Created by Arya Mirsepasi on 04.11.25.
//

import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    
    private init() {}
    
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
    
    func save(_ value: String, forKey key: String) throws {
        guard !value.isEmpty else {
            try delete(forKey: key)
            return
        }
        
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.failedToSave(-1)
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.aryamirsepasi.writing-tools",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // Try to delete existing first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.failedToSave(status)
        }
    }
    
    // MARK: - Read
    
    func retrieve(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.aryamirsepasi.writing-tools",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
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
    
    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.aryamirsepasi.writing-tools"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.failedToDelete(status)
        }
    }
    
    // MARK: - Clear All
    
    func clearAllApiKeys() throws {
        let apiKeyNames = [
            "gemini_api_key",
            "openai_api_key",
            "mistral_api_key",
            "anthropic_api_key",
            "openrouter_api_key"
        ]
        
        for keyName in apiKeyNames {
            try? delete(forKey: keyName)
        }
    }
    
    func hasMigratedKey(forKey key: String) -> Bool {
        do {
            let value = try retrieve(forKey: key)
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
}
