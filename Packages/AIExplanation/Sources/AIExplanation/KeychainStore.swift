//
//  KeychainStore.swift
//  AIExplanation
//
//  A tiny Keychain wrapper for the single secret this feature needs: the user's
//  Anthropic API key. We keep the key out of the SwiftData store and the JSON
//  backup (which round-trips the whole Profile) so it can't leak through an
//  export — the Keychain is the only place it lives.
//

import Foundation
import Security
import CoreModels

/// The Keychain-backed `APIKeyStore` injected into the Profile settings at the
/// composition root. Wraps the static `KeychainStore` operations.
public struct KeychainAPIKeyStore: APIKeyStore {
    public init() {}
    public var hasKey: Bool { KeychainStore.hasAPIKey }
    public func setKey(_ key: String) { KeychainStore.saveAPIKey(key) }
    public func clearKey() { KeychainStore.deleteAPIKey() }
}

/// Stores/loads a single API-key string in the Keychain under a fixed account.
/// A caseless namespace — there's no instance state worth holding.
public enum KeychainStore {
    /// Service + account identifying our one item. Matches the app's bundle id.
    private static let service = "com.markwise.app"
    private static let account = "anthropicAPIKey"

    /// Persist (or replace) the API key. An empty/whitespace string clears it.
    @discardableResult
    public static func saveAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deleteAPIKey() }
        guard let data = trimmed.data(using: .utf8) else { return false }

        // Delete any existing item, then add fresh — simplest correct upsert.
        deleteAPIKey()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// The stored API key, or nil if none is set.
    public static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty
        else { return nil }
        return key
    }

    /// Whether a key is currently stored.
    public static var hasAPIKey: Bool { loadAPIKey() != nil }

    @discardableResult
    public static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
