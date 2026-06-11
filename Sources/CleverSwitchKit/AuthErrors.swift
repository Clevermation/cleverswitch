// Geteilte Fehlertypen der Anbieter-Auth (Claude + Codex).

/// Refresh-Token endgültig ungültig -> Account muss neu angemeldet werden.
public struct CredentialsExpiredError: Error, Equatable {
    public init() {}
}

/// Vorübergehender Fehler (Netzwerk, 429, 5xx) — später erneut versuchen.
public struct TransientRefreshError: Error, Equatable {
    public let status: Int
    public init(status: Int) { self.status = status }
}
