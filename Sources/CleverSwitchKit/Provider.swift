// Anbieter-Adapter: kapselt das anbieter-spezifische Verhalten (Live-Slot-Ort, Token-Format,
// Endpoints, Login-Kommando) hinter einem einheitlichen Protokoll. Die Kernlogik (Policy,
// Switch-Orchestrierung) bleibt anbieter-neutral.
//
// Live-Slot: bei Claude ein Keychain-Eintrag, bei Codex eine Datei — deshalb lesen/schreiben
// die Provider ihren Live-Slot selbst. Snapshots liegen für alle im CredentialStore.

import Foundation

/// Ergebnis eines Usage-Abrufs (Struct statt 3er-Tuple: erweiterbar + selbstdokumentierend).
public struct UsageOutcome: Sendable {
    public let usage: AccountUsage
    /// Erneuerter Credentials-Blob, falls beim Abruf refresht wurde (zurückspeichern!).
    public let refreshedBlob: String?
    /// Live-Plan-Bezeichnung laut Server (verlässlicher als gecachte Token-Claims).
    public let planLabel: String?
    /// Ein nötiger Refresh ist gescheitert (429/Netzwerk/tot) → Aufrufer soll BACKOFF setzen,
    /// damit nicht bei jedem Poll erneut gehämmert wird (das hält das Rate-Limit am Leben).
    public let refreshFailed: Bool

    public init(
        usage: AccountUsage, refreshedBlob: String? = nil, planLabel: String? = nil,
        refreshFailed: Bool = false
    ) {
        self.usage = usage
        self.refreshedBlob = refreshedBlob
        self.planLabel = planLabel
        self.refreshFailed = refreshFailed
    }
}

/// Identität eines Accounts (für den Import des aktuell eingeloggten Kontos).
public struct AccountIdentity: Sendable, Equatable {
    public let handle: String
    public let label: String
    /// Anbieter-spezifische Sitzungs-Metadaten (z.B. das oauthAccount-JSON aus ~/.claude.json),
    /// die beim Aktivieren zurückgespielt werden.
    public let sessionPayload: String?

    public init(handle: String, label: String, sessionPayload: String? = nil) {
        self.handle = handle
        self.label = label
        self.sessionPayload = sessionPayload
    }
}

public protocol AccountProvider: Sendable {
    /// Stabile ID (z.B. "claude").
    var id: String { get }
    /// Anzeigename fürs Menü (z.B. "Claude Code").
    var displayName: String { get }
    /// Anzeige-Labels der beiden Usage-Fenster (z.B. "5h"/"7d" bzw. "1h"/"7d").
    var sessionWindowLabel: String { get }
    var weeklyWindowLabel: String { get }

    /// Keychain-Service unseres gespeicherten Snapshots eines Accounts.
    func snapshotService(handle: String) -> String
    /// Liest den Live-Slot (das, was die CLI gerade benutzt).
    func readLive(credentials: CredentialStore) -> String?
    /// Schreibt den Live-Slot.
    func writeLive(_ blob: String, handle: String, credentials: CredentialStore) throws

    /// Ist der Token (zeitstempelbasiert) abgelaufen bzw. sollte vor Aktivierung erneuert werden?
    func isExpired(_ blob: String) -> Bool
    /// Erneuert den Token via Refresh-Token. Wirft `CredentialsExpiredError` bei totem Token.
    func refresh(_ blob: String, http: HTTPClient) async throws -> String
    /// Holt Usage für einen Blob. Bei 401 wird — NUR wenn `allowRefresh` — einmal erneuert
    /// (refreshedBlob zurückspeichern). Scheitert der Refresh, ist `refreshFailed` gesetzt.
    func fetchUsage(blob: String, http: HTTPClient, allowRefresh: Bool) async -> UsageOutcome

    /// Bereinigt doppelte Live-Slot-Einträge. `claude auth login` legt bei jedem Login einen
    /// NEUEN Keychain-Eintrag an, ohne den alten zu löschen → `security -w` liefert dann den
    /// falschen (alten, abgelaufenen). Hier wird auf den frischesten Token reduziert.
    func consolidateLive(credentials: CredentialStore)
    /// Identität des aktuell im Live-Slot eingeloggten Accounts (für Import), oder nil.
    func currentIdentity(credentials: CredentialStore) -> AccountIdentity?
    /// Nach dem Aktivieren: anbieter-spezifische Sitzungsdaten nachziehen (z.B. ~/.claude.json).
    func didActivate(account: Account)
    /// Interaktiver CLI-Login-Befehl (wird headless mit Pseudo-TTY ausgeführt), oder nil.
    func loginCommand() -> [String]?
}

extension AccountProvider {
    public var sessionWindowLabel: String { "5h" }
    public var weeklyWindowLabel: String { "7d" }
    /// Default: nichts zu bereinigen (z.B. bei Datei-basiertem Live-Slot wie Codex).
    public func consolidateLive(credentials: CredentialStore) {}
}

// MARK: - Claude Code

public struct ClaudeProvider: AccountProvider {
    public let id = "claude"
    public let displayName = "Claude Code"
    public let liveCredentialService = "Claude Code-credentials"

    private var claudeStateFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    }

    public init() {}

    public func snapshotService(handle: String) -> String {
        "cleverswitch:claude:\(handle)"
    }

    public func readLive(credentials: CredentialStore) -> String? {
        credentials.read(service: liveCredentialService)
    }

    public func writeLive(_ blob: String, handle: String, credentials: CredentialStore) throws {
        try credentials.write(service: liveCredentialService, account: handle, secret: blob)
    }

    public func isExpired(_ blob: String) -> Bool {
        ClaudeAuth.isExpired(blob)
    }

    public func refresh(_ blob: String, http: HTTPClient) async throws -> String {
        try await ClaudeAuth.refresh(blob, http: http)
    }

    public func fetchUsage(blob: String, http: HTTPClient, allowRefresh: Bool) async -> UsageOutcome {
        guard let token = ClaudeAuth.accessToken(in: blob) else { return UsageOutcome(usage: .unknown) }
        let label = ClaudeAuth.subscriptionType(in: blob)

        let first = (try? await ClaudeUsageAPI.fetch(accessToken: token, http: http)) ?? .failed
        switch first {
        case .ok(let usage):
            return UsageOutcome(usage: usage, planLabel: label)
        case .failed:
            return UsageOutcome(usage: .unknown)
        case .unauthorized:
            // Token abgelaufen/widerrufen. Nur refreshen, wenn erlaubt (sonst Backoff aktiv).
            guard allowRefresh else { return UsageOutcome(usage: .unknown) }
            let refreshed: String
            do {
                refreshed = try await refresh(blob, http: http)
            } catch {
                // 429/Netzwerk/tot -> Backoff signalisieren, NICHT bei jedem Poll neu hämmern.
                return UsageOutcome(usage: .unknown, refreshFailed: true)
            }
            guard let freshToken = ClaudeAuth.accessToken(in: refreshed) else {
                return UsageOutcome(usage: .unknown, refreshedBlob: refreshed)
            }
            let second = (try? await ClaudeUsageAPI.fetch(accessToken: freshToken, http: http)) ?? .failed
            if case .ok(let usage) = second {
                return UsageOutcome(
                    usage: usage, refreshedBlob: refreshed,
                    planLabel: ClaudeAuth.subscriptionType(in: refreshed))
            }
            return UsageOutcome(usage: .unknown, refreshedBlob: refreshed)
        }
    }

    public func consolidateLive(credentials: CredentialStore) {
        // Alle Einträge des Live-Service draften (read+delete enumeriert sie) und den frischesten
        // Token (höchstes expiresAt) als EINZIGEN wieder schreiben. Cap gegen Endlosschleife.
        var entries: [(account: String, secret: String, expiresAt: Double)] = []
        for _ in 0..<10 {
            guard let secret = credentials.read(service: liveCredentialService) else { break }
            let account = credentials.readAccount(service: liveCredentialService) ?? "unknown"
            entries.append((account, secret, ClaudeAuth.expiresAtMillis(in: secret) ?? 0))
            credentials.delete(service: liveCredentialService)
        }
        guard let freshest = entries.max(by: { $0.expiresAt < $1.expiresAt }) else { return }
        try? credentials.write(
            service: liveCredentialService, account: freshest.account, secret: freshest.secret)
    }

    public func currentIdentity(credentials: CredentialStore) -> AccountIdentity? {
        guard let data = try? Data(contentsOf: claudeStateFile),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauthAccount = object["oauthAccount"] as? [String: Any],
            let email = oauthAccount["emailAddress"] as? String
        else { return nil }
        let label = readLive(credentials: credentials).flatMap { ClaudeAuth.subscriptionType(in: $0) } ?? ""
        let payload = (try? JSONSerialization.data(withJSONObject: oauthAccount))
            .flatMap { String(data: $0, encoding: .utf8) }
        return AccountIdentity(handle: email, label: label, sessionPayload: payload)
    }

    /// Spielt das gespeicherte oauthAccount-JSON in ~/.claude.json zurück, damit die CLI
    /// (Statusanzeige) und unser Reconcile die richtige Identität sehen.
    public func didActivate(account: Account) {
        guard let payload = account.sessionPayload,
            let payloadData = payload.data(using: .utf8),
            let oauthAccount = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let stateData = try? Data(contentsOf: claudeStateFile),
            var state = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any]
        else { return }
        state["oauthAccount"] = oauthAccount
        if let updated = try? JSONSerialization.data(withJSONObject: state) {
            try? updated.write(to: claudeStateFile, options: .atomic)
        }
    }

    public func loginCommand() -> [String]? {
        guard let claude = Self.findExecutable("claude") else { return nil }
        return [claude, "auth", "login"]
    }

    static func findExecutable(_ name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // 1. Bekannte Installationsorte (claude-Installer, bun, Homebrew).
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "\(home)/.bun/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
        ]
        if let direct = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return direct
        }
        // 2. Interaktive Login-Shell nach dem Binary fragen — lädt die volle User-PATH inkl.
        //    .zshrc (wo bun/mise/nvm ihre PATH oft setzen). Eine GUI-App startet mit minimaler
        //    PATH, deshalb reicht das Abklappern fester Pfade nicht. Letzte gültige Zeile nehmen,
        //    falls .zshrc Rauschen ausgibt.
        let result = Subprocess.run("/bin/zsh", ["-ilc", "command -v \(name) 2>/dev/null"])
        for line in result.stdout.split(separator: "\n").reversed() {
            let path = line.trimmingCharacters(in: .whitespaces)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}

// MARK: - Codex CLI

public struct CodexProvider: AccountProvider {
    public let id = "codex"
    public let displayName = "Codex CLI"
    public let sessionWindowLabel = "1h"

    /// Injizierbar für Tests; Default ~/.codex.
    public let codexHome: URL

    public init(codexHome: URL? = nil) {
        self.codexHome =
            codexHome
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    private var authFile: URL { codexHome.appendingPathComponent("auth.json") }

    public func snapshotService(handle: String) -> String {
        "cleverswitch:codex:\(handle)"
    }

    public func readLive(credentials: CredentialStore) -> String? {
        guard let data = try? Data(contentsOf: authFile),
            let blob = String(data: data, encoding: .utf8),
            !blob.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return blob
    }

    public func writeLive(_ blob: String, handle: String, credentials: CredentialStore) throws {
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try Data(blob.utf8).write(to: authFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authFile.path)
    }

    /// Codex-Blobs tragen keinen Ablauf-Zeitstempel — vor Aktivierung immer erneuern (rotiert).
    public func isExpired(_ blob: String) -> Bool { true }

    public func refresh(_ blob: String, http: HTTPClient) async throws -> String {
        try await CodexAuth.refresh(blob, http: http)
    }

    public func fetchUsage(blob: String, http: HTTPClient, allowRefresh: Bool) async -> UsageOutcome {
        guard let token = CodexAuth.accessToken(in: blob), let accountID = CodexAuth.accountID(in: blob)
        else { return UsageOutcome(usage: .unknown) }

        let first =
            (try? await CodexUsageAPI.fetch(accessToken: token, accountID: accountID, http: http))
            ?? (.failed, nil)
        switch first.result {
        case .ok(let usage):
            return UsageOutcome(usage: usage, planLabel: first.planType)
        case .failed:
            return UsageOutcome(usage: .unknown)
        case .unauthorized:
            guard allowRefresh else { return UsageOutcome(usage: .unknown) }
            let refreshed: String
            do {
                refreshed = try await refresh(blob, http: http)
            } catch {
                return UsageOutcome(usage: .unknown, refreshFailed: true)
            }
            guard let freshToken = CodexAuth.accessToken(in: refreshed),
                let freshAccount = CodexAuth.accountID(in: refreshed)
            else { return UsageOutcome(usage: .unknown, refreshedBlob: refreshed) }
            let second =
                (try? await CodexUsageAPI.fetch(
                    accessToken: freshToken, accountID: freshAccount, http: http))
                ?? (.failed, nil)
            if case .ok(let usage) = second.result {
                return UsageOutcome(usage: usage, refreshedBlob: refreshed, planLabel: second.planType)
            }
            return UsageOutcome(usage: .unknown, refreshedBlob: refreshed)
        }
    }

    public func currentIdentity(credentials: CredentialStore) -> AccountIdentity? {
        guard let blob = readLive(credentials: credentials),
            let email = CodexAuth.email(in: blob)
        else { return nil }
        return AccountIdentity(handle: email, label: CodexAuth.planType(in: blob) ?? "")
    }

    public func didActivate(account: Account) {}

    public func loginCommand() -> [String]? {
        guard let codex = ClaudeProvider.findExecutable("codex") else { return nil }
        return [codex, "login", "-c", "cli_auth_credentials_store=\"file\""]
    }
}
