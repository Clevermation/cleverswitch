// Dünner Wrapper um das macOS-Keychain (generic passwords) über das Security-Framework.
//
// Hier liegen die Credential-Blobs: der Live-Slot der CLI (z.B. Service "Claude Code-credentials",
// den die `claude`-CLI liest) sowie unsere eigenen Snapshots ("cleverswitch:<provider>:<handle>").

import Foundation
import Security

public enum Keychain {
    public struct KeychainError: Error {
        public let status: OSStatus
    }

    /// Liest das Secret eines generic-password-Eintrags, oder nil.
    public static func readSecret(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Liest das `account`-Attribut eines Eintrags (wird beim Schreiben erhalten).
    public static func readAccountAttribute(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let attributes = item as? [String: Any]
        else { return nil }
        return attributes[kSecAttrAccount as String] as? String
    }

    /// Entfernt einen Eintrag. True, wenn etwas gelöscht wurde.
    @discardableResult
    public static func delete(service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    /// Schreibt ein Secret und ersetzt dabei alle bestehenden Einträge desselben Service.
    public static func writeSecret(service: String, account: String, secret: String) throws {
        while delete(service: service) {}
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(secret.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
