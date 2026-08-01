import Foundation
import Security

/// Stores the access/refresh token pair in the Keychain — never `UserDefaults` (hard rule carried
/// over from the ecommerce/social Swift ports' `Support/KeychainTokenStore.swift`, ported verbatim
/// aside from the default `service` string).
struct KeychainTokenStore: Sendable {
    struct StoredSession: Sendable, Equatable {
        let accessToken: String
        let refreshToken: String
    }

    private let service: String
    private let accessTokenAccount = "mudbase.accessToken"
    private let refreshTokenAccount = "mudbase.refreshToken"

    init(service: String = "dev.mudbase.showcase.events") {
        self.service = service
    }

    func save(_ session: StoredSession) {
        set(session.accessToken, account: accessTokenAccount)
        set(session.refreshToken, account: refreshTokenAccount)
    }

    func load() -> StoredSession? {
        guard let accessToken = get(account: accessTokenAccount),
              let refreshToken = get(account: refreshTokenAccount)
        else { return nil }
        return StoredSession(accessToken: accessToken, refreshToken: refreshToken)
    }

    func clear() {
        delete(account: accessTokenAccount)
        delete(account: refreshTokenAccount)
    }

    private func set(_ value: String, account: String) {
        delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)
    }

    private func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
