// Lokale Persistenz von Account-Liste + Einstellungen als JSON.
//
// Enthält bewusst KEINE Secrets (die liegen im Keychain / in der CLI-Datei). Der Speicherort
// ist injizierbar -> frei testbar gegen ein temporäres Verzeichnis.

import Foundation

/// App-Einstellungen: Auto-Switch-Modus pro Anbieter + Policy-Schwellen.
public struct AppSettings: Codable, Equatable, Sendable {
    public var modes: [String: SwitchMode]
    public var policy: PolicyConfig
    /// macOS-Benachrichtigungen für Switch/Frühwarnung/abgelaufene Sitzung.
    public var notificationsEnabled: Bool
    /// E-Mail-Adressen im Menü anzeigen (false = maskiert, z.B. für Screen-Recordings/Streamer).
    public var showEmail: Bool
    /// Quelle der Menüleisten-Zahl: "highest" (alle aktiven), "claude" oder "codex".
    public var menuBarSource: String

    public init(
        modes: [String: SwitchMode] = [:],
        policy: PolicyConfig = .default,
        notificationsEnabled: Bool = true,
        showEmail: Bool = true,
        menuBarSource: String = "highest"
    ) {
        self.modes = modes
        self.policy = policy
        self.notificationsEnabled = notificationsEnabled
        self.showEmail = showEmail
        self.menuBarSource = menuBarSource
    }

    // Optionale Decodierung: ältere state.json ohne diese Felder bleiben lesbar.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modes = try container.decodeIfPresent([String: SwitchMode].self, forKey: .modes) ?? [:]
        policy = try container.decodeIfPresent(PolicyConfig.self, forKey: .policy) ?? .default
        notificationsEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        showEmail = try container.decodeIfPresent(Bool.self, forKey: .showEmail) ?? true
        menuBarSource =
            try container.decodeIfPresent(String.self, forKey: .menuBarSource) ?? "highest"
    }

    /// Auto-Switch-Modus eines Anbieters (Default: off).
    public func mode(for provider: String) -> SwitchMode {
        modes[provider] ?? .off
    }

    public func setting(_ mode: SwitchMode, for provider: String) -> AppSettings {
        var copy = self
        copy.modes[provider] = mode
        return copy
    }
}

/// Der persistierte Gesamtzustand.
public struct PersistedState: Codable, Equatable, Sendable {
    public var version: Int
    public var accounts: [Account]
    public var settings: AppSettings

    public init(
        version: Int = StateStore.schemaVersion, accounts: [Account] = [], settings: AppSettings = AppSettings()
    ) {
        self.version = version
        self.accounts = accounts
        self.settings = settings
    }

    /// Aktiver Account eines Anbieters, oder nil.
    public func activeAccount(provider: String) -> Account? {
        accounts.first { $0.provider == provider && $0.active }
    }

    /// Accounts eines Anbieters.
    public func accounts(provider: String) -> [Account] {
        accounts.filter { $0.provider == provider }
    }
}

/// Liest/schreibt den `PersistedState` als JSON-Datei.
public struct StateStore: Sendable {
    public static let schemaVersion = 1

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Standard-Speicherort: ~/Library/Application Support/CleverSwitch/state.json
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CleverSwitch/state.json")
    }

    /// Lädt den Zustand; bei fehlender Datei einen leeren Default. Eine vorhandene, aber nicht
    /// dekodierbare Datei (kaputt oder aus neuerem Schema) wird NICHT still verworfen, sondern
    /// nach `state.json.bak` gesichert — Datenverlust-Schutz über App-Updates hinweg.
    public func load() -> PersistedState {
        guard let data = try? Data(contentsOf: url) else { return PersistedState() }
        if let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            return state
        }
        let backup = url.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
        return PersistedState()
    }

    /// Schreibt den Zustand atomar mit privaten Dateirechten (0600).
    public func save(_ state: PersistedState) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
