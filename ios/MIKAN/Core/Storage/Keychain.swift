import Foundation
import os
import Security

/// Minimal generic-password Keychain wrapper for the auth token.
nonisolated enum Keychain {
    static let tokenAccount = "authToken"
    private static let service = "com.mikanstudio.crm"
    private static let logger = Logger(subsystem: "com.mikanstudio.crm", category: "keychain")

    static func string(for account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain read failed: \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `value`, or deletes the item when `value` is `nil`.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        guard let value else { return true }

        let attributes = baseQuery.merging([
            kSecValueData: Data(value.utf8),
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { _, new in new }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain write failed: \(status)")
        }
        return status == errSecSuccess
    }
}
