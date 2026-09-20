import Foundation
import Security

enum Keychain {
    static let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "local.ClockifyEarnings", kSecAttrAccount as String: "api-key"]
    static func read() throws -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { throw failure(status) }
        return value
    }
    static func save(_ value: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = base.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }
    static func delete() throws {
        let status = SecItemDelete(base as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey:
            "Keychainを利用できません（\(status)）。Macのロックを解除し、アクセスを許可してください。"])
    }
}

// Credentials remain only in process memory; persistent storage stays in Keychain.
final class SessionCredential {
    private var value: String?
    func read(using load: () throws -> String?) throws -> String {
        if let value { return value }
        guard let loaded = try load(), !loaded.isEmpty else {
            throw Keychain.failure(errSecItemNotFound)
        }
        value = loaded
        return loaded
    }
    func replace(with key: String) { value = key }
    func clear() { value = nil }
}
