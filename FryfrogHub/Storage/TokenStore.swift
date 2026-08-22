import Foundation

/// Token 持久化（Keychain）
final class TokenStore {
    static let shared = TokenStore()

    private let service = "com.fryfrog.hub.token"

    private init() {}

    func read() -> String? {
        // 优先新查询（带 account），兼容旧版本无 account 的存量 token
        for query in [keychainQuery(), legacyKeychainQuery()] {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            let status = SecItemCopyMatching(q as CFDictionary, &result)
            guard status == errSecSuccess, let data = result as? Data,
                  let token = String(data: data, encoding: .utf8), !token.isEmpty else { continue }
            // 命中旧格式则迁移到新格式
            if q as NSDictionary == legacyKeychainQuery() as NSDictionary {
                save(token)
            }
            return token
        }
        return nil
    }

    func save(_ token: String) {
        delete()
        var query = keychainQuery()
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            assertionFailure("Keychain save failed: \(status)")
        }
    }

    func delete() {
        SecItemDelete(keychainQuery() as CFDictionary)
        SecItemDelete(legacyKeychainQuery() as CFDictionary)
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "authToken",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
    }

    private func legacyKeychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }
}
