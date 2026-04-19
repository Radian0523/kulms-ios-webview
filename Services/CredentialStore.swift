import Foundation
import Security

/// ECS-ID/パスワードを iOS Keychain に保存・読み出しするユーティリティ。
enum CredentialStore {
    private static let service = "com.radian0523.kulms-plus-for-ios.credentials"
    private static let usernameAccount = "kulms_username"
    private static let passwordAccount = "kulms_password"

    /// 認証情報を保存する。
    static func save(username: String, password: String) {
        saveItem(account: usernameAccount, value: username)
        saveItem(account: passwordAccount, value: password)
    }

    /// 保存済み認証情報を返す。未保存または失敗時は nil。
    static func load() -> (username: String, password: String)? {
        guard let u = loadItem(account: usernameAccount),
              let p = loadItem(account: passwordAccount) else { return nil }
        return (u, p)
    }

    /// 保存済み認証情報を削除する。
    static func clear() {
        deleteItem(account: usernameAccount)
        deleteItem(account: passwordAccount)
    }

    /// 認証情報が保存されているかを返す。
    static func hasCredentials() -> Bool {
        loadItem(account: usernameAccount) != nil &&
        loadItem(account: passwordAccount) != nil
    }

    // MARK: - Keychain helpers

    private static func saveItem(account: String, value: String) {
        let data = Data(value.utf8)
        // 既存項目を消してから書き込む
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func loadItem(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
