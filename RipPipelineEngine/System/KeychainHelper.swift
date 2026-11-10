import Foundation
import Security

/// A secure, persistent storage helper backed by the Apple Keychain Services API.
/// Replaces plaintext UserDefaults storage for sensitive API keys, tokens, and passwords.
public final class KeychainHelper: @unchecked Sendable {
    public static let shared = KeychainHelper()
    public static let defaultService = "com.jellyboi.mediapipeline"

    private let lock = NSLock()

    public init() {}

    /// Saves or updates a secret string in Keychain.
    /// If the string is nil or empty, the key is deleted from Keychain.
    @discardableResult
    public func set(_ value: String?, forKey key: String, service: String = KeychainHelper.defaultService) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Clean up legacy or plaintext residue from UserDefaults
        UserDefaults.standard.removeObject(forKey: key)

        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return deleteInternal(forKey: key, service: service)
        }

        return setInternal(value, forKey: key, service: service)
    }

    /// Retrieves a secret string from Keychain.
    /// If not found in Keychain, attempts a one-time transparent migration from UserDefaults
    /// and immediately removes the plaintext key from UserDefaults.
    public func get(forKey key: String, service: String = KeychainHelper.defaultService) -> String? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let string = String(data: data, encoding: .utf8), !string.isEmpty {
            return string
        }

        // Transparent migration fallback: check UserDefaults if not found in Keychain
        let defaults = UserDefaults.standard
        if let legacy = defaults.string(forKey: key), !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaults.removeObject(forKey: key)
            _ = setInternal(legacy, forKey: key, service: service)
            return legacy
        }

        return nil
    }

    // MARK: - Private Helpers (Must be called within lock)

    private func setInternal(_ value: String, forKey key: String, service: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateQuery: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateQuery as CFDictionary)
            return updateStatus == errSecSuccess
        } else {
            // Delete any invalid duplicate before adding
            SecItemDelete(query as CFDictionary)

            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            return addStatus == errSecSuccess
        }
    }

    private func deleteInternal(forKey key: String, service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
