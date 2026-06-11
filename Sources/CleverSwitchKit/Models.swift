// Anbieter-neutrale Datenmodelle für Accounts und Auslastung.
//
// Reine Value-Typen (Sendable, frei testbar). Die beiden Auslastungs-Fenster heißen bewusst
// neutral `session` (rollendes Kurzzeit-Limit, typischerweise 5 Stunden) und `weekly`
// (7-Tage-Limit); die Anbieter-Adapter mappen ihre API-Felder auf diese Schlüssel.

/// Schlüssel der beiden Auslastungs-Fenster.
public enum UsageWindowKey {
    public static let session = "session"
    public static let weekly = "weekly"
}

/// Auslastung eines einzelnen Limit-Fensters.
public struct UsageWindow: Equatable, Sendable {
    public let key: String
    public let usedPct: Double
    public let resetsAt: String?  // ISO-8601-Zeitstempel oder nil

    public init(key: String, usedPct: Double, resetsAt: String? = nil) {
        self.key = key
        self.usedPct = usedPct
        self.resetsAt = resetsAt
    }
}

/// Auslastung eines Accounts über alle bekannten Fenster.
///
/// `known == false` bedeutet: für diesen Account liegt gerade keine verlässliche
/// Auslastung vor (Netzwerkfehler, fehlender Token o.ä.).
public struct AccountUsage: Equatable, Sendable {
    public let known: Bool
    public let windows: [UsageWindow]

    public init(known: Bool, windows: [UsageWindow] = []) {
        self.known = known
        self.windows = windows
    }

    /// Auslastung eines Fensters in Prozent, oder nil wenn unbekannt.
    public func pct(_ key: String) -> Double? {
        windows.first { $0.key == key }?.usedPct
    }

    /// Höchste bekannte Auslastung über alle Fenster, oder nil.
    public var worstPct: Double? {
        windows.map(\.usedPct).max()
    }

    /// Sentinel für „Auslastung nicht ermittelbar".
    public static let unknown = AccountUsage(known: false)
}

/// Ein verwalteter CLI-Account eines Anbieters.
///
/// Enthält bewusst KEINE Secrets — die liegen im Keychain/der CLI-Datei und werden
/// über `credentialKey` referenziert.
public struct Account: Equatable, Hashable, Sendable, Codable {
    public let provider: String  // z.B. "claude" oder "codex"
    public let handle: String  // eindeutige Kennung, i.d.R. die E-Mail
    public var label: String  // Abo-/Plan-Bezeichnung zur Anzeige
    public var active: Bool  // liegt dieser Account gerade im Live-Slot?
    public var credentialKey: String  // Referenz auf den Credential-Speicher
    // Anbieter-spezifische Sitzungs-Metadaten (z.B. oauthAccount-JSON), beim Aktivieren
    // zurückgespielt. Optional -> ältere state.json bleiben lesbar.
    public var sessionPayload: String?

    public init(
        provider: String,
        handle: String,
        label: String = "",
        active: Bool = false,
        credentialKey: String = "",
        sessionPayload: String? = nil
    ) {
        self.provider = provider
        self.handle = handle
        self.label = label
        self.active = active
        self.credentialKey = credentialKey
        self.sessionPayload = sessionPayload
    }

    /// Global eindeutige ID. WICHTIG: `handle` allein ist nur PRO Anbieter eindeutig —
    /// dieselbe E-Mail kann bei Claude UND Codex existieren. Für Dictionary-Keys und
    /// SwiftUI-ForEach-IDs immer diese zusammengesetzte ID verwenden.
    public var id: String { "\(provider):\(handle)" }
}
