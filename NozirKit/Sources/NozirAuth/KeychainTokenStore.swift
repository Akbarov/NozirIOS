import Foundation
import Security

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// The session in the keychain, readable after the first unlock and never
/// migrated to another device by a backup.
///
/// Stored with a plain JSONEncoder (dates as numbers): this blob is read only
/// by this type, and a numeric date reads back exactly.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "parent-session"

    public init(service: String = "tut.mobile.nozirparent.session") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> TokenPair? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(TokenPair.self, from: data)
    }

    public func save(_ tokens: TokenPair) throws {
        let data = try JSONEncoder().encode(tokens)
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
