// Abstraktion über den Credential-Speicher, damit die Switch-Orchestrierung ohne echtes
// Keychain testbar ist. Produktiv: `SecurityCLICredentialStore` (keine Erlaubnis-Dialoge
// nach ad-hoc-Rebuilds); `KeychainCredentialStore` bleibt als SecItem-Alternative erhalten,
// falls die App später notarisiert/stabil signiert wird. In Tests: ein In-Memory-Fake.

import Foundation
import Security

public protocol CredentialStore: Sendable {
    func read(service: String) -> String?
    func readAccount(service: String) -> String?
    func write(service: String, account: String, secret: String) throws
    func delete(service: String)
}

/// Implementierung über SecItem (Security-Framework) — direkt aus dem eigenen Binary.
/// Achtung: aus einem ad-hoc-signierten Binary fragt macOS pro Build neu nach Erlaubnis.
public struct KeychainCredentialStore: CredentialStore {
    public init() {}

    public func read(service: String) -> String? {
        Keychain.readSecret(service: service)
    }

    public func readAccount(service: String) -> String? {
        Keychain.readAccountAttribute(service: service)
    }

    public func write(service: String, account: String, secret: String) throws {
        try Keychain.writeSecret(service: service, account: account, secret: secret)
    }

    public func delete(service: String) {
        Keychain.delete(service: service)
    }
}

/// Implementierung über das Apple-signierte `security`-CLI (Subprozess).
///
/// Produktiv-Default: dem `security`-Binary hat der User i.d.R. dauerhaft Zugriff gewährt,
/// dadurch entfallen wiederkehrende Erlaubnis-Dialoge nach jedem (ad-hoc-)Rebuild.
public struct SecurityCLICredentialStore: CredentialStore {
    private static let securityPath = "/usr/bin/security"

    public init() {}

    public func read(service: String) -> String? {
        let result = Subprocess.run(Self.securityPath, ["find-generic-password", "-s", service, "-w"])
        guard result.status == 0 else { return nil }
        let secret = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return secret.isEmpty ? nil : secret
    }

    public func readAccount(service: String) -> String? {
        let result = Subprocess.run(Self.securityPath, ["find-generic-password", "-s", service])
        guard result.status == 0 else { return nil }
        // Zeile der Form: "acct"<blob>="<wert>" — explizit bis zum letzten schließenden
        // Anführungszeichen lesen statt blind dropLast() (sonst wird der Handle bei
        // abweichendem security-Output still um ein Zeichen gekürzt).
        for line in result.stdout.split(separator: "\n") where line.contains("\"acct\"<blob>=") {
            if let open = line.range(of: "=\"") {
                let rest = line[open.upperBound...]
                if let close = rest.lastIndex(of: "\"") {
                    return String(rest[..<close])
                }
            }
        }
        return nil
    }

    public func write(service: String, account: String, secret: String) throws {
        // SICHERHEIT: service/account dürfen keine Steuerzeichen enthalten — sonst könnte ein
        // Newline im interaktiven `security -i`-Strom eine zweite (injizierte) Befehlszeile
        // einschleusen. Secret darf alles enthalten (steht in einem quotierten Argument am
        // Zeilenende, keine nachfolgende Befehlszeile mehr).
        guard !Self.hasControlChars(service), !Self.hasControlChars(account) else {
            throw Keychain.KeychainError(status: errSecParam)
        }
        // Secret NIE als argv übergeben (für jeden lokalen Prozess via ps sichtbar) —
        // stattdessen interaktiver Modus: das Kommando inkl. Secret geht über stdin.
        // Zuerst schreiben/aktualisieren (-U), dann nur bei Erfolg Duplikate aufräumen, damit
        // ein fehlgeschlagener Write nicht erst den alten Eintrag gelöscht zurücklässt.
        let command =
            "add-generic-password -U -s \(Self.quoted(service)) "
            + "-a \(Self.quoted(account)) -w \(Self.quoted(secret))\n"
        let result = Subprocess.run(Self.securityPath, ["-i"], stdin: command)
        guard result.status == 0 else {
            throw Keychain.KeychainError(status: result.status)
        }
    }

    private static func hasControlChars(_ value: String) -> Bool {
        value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Quotet einen String für den security-Kommandozeilen-Parser (interactive mode).
    private static func quoted(_ value: String) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public func delete(service: String) {
        Subprocess.run(Self.securityPath, ["delete-generic-password", "-s", service])
    }
}
