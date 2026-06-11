// Auto-Switch-Policy — reine Entscheidungslogik (keine Seiteneffekte, voll testbar).
//
// Drei Modi (siehe docs/SPEC.md, F5):
// - off       — nie automatisch wechseln.
// - failover  — rechtzeitig VOR dem Limit auf einen gesunden Account wechseln.
// - balance   — Verbrauch gleichmäßig verteilen (immer der gesündeste Account, mit Hysterese).
//
// Leitgedanke: Das `session`-Fenster (Kurzzeit-Limit) ist das bindende; ein Ziel-Account muss
// in BEIDEN Fenstern genug Luft haben, sonst kippt er direkt nach dem Wechsel zurück ins Limit.

/// Betriebsmodus des Auto-Switch pro Anbieter.
public enum SwitchMode: String, Sendable, CaseIterable, Codable {
    case off
    case failover
    case balance
}

/// Einstellbare Schwellen der Auto-Switch-Entscheidung (Prozent-Auslastung).
public struct PolicyConfig: Equatable, Sendable, Codable {
    // FAILOVER: aktives Konto gilt als „nahe am Limit" ab diesen Werten.
    public var failoverSessionAt: Double
    public var failoverWeeklyAt: Double
    // Ein Ziel-Account ist nur „gesund", wenn er unter diesen Werten liegt.
    public var targetSessionMax: Double
    public var targetWeeklyMax: Double
    // BALANCE: Mindest-Vorsprung des Ziels (Hysterese) bzw. Notfall-Obergrenze.
    public var balanceMinGap: Double
    public var balanceCeiling: Double

    public init(
        failoverSessionAt: Double = 85,
        failoverWeeklyAt: Double = 92,
        targetSessionMax: Double = 70,
        targetWeeklyMax: Double = 90,
        balanceMinGap: Double = 12,
        balanceCeiling: Double = 85
    ) {
        self.failoverSessionAt = failoverSessionAt
        self.failoverWeeklyAt = failoverWeeklyAt
        self.targetSessionMax = targetSessionMax
        self.targetWeeklyMax = targetWeeklyMax
        self.balanceMinGap = balanceMinGap
        self.balanceCeiling = balanceCeiling
    }

    public static let `default` = PolicyConfig()
}

/// Reine Entscheidungsfunktionen für den Auto-Switch.
public enum AutoSwitchPolicy {
    /// Wählt den Account, auf den umgeschaltet werden soll — oder nil (nicht wechseln).
    ///
    /// `accounts` enthält die Accounts EINES Anbieters. `usage` bildet Handle -> AccountUsage ab.
    public static func pickTarget(
        mode: SwitchMode,
        accounts: [Account],
        activeHandle: String,
        usage: [String: AccountUsage],
        hasCreds: (Account) -> Bool = { _ in true },
        config: PolicyConfig = .default
    ) -> Account? {
        switch mode {
        case .off:
            return nil
        case .failover:
            return failoverTarget(
                accounts: accounts, activeHandle: activeHandle, usage: usage,
                hasCreds: hasCreds, config: config
            )
        case .balance:
            return balanceTarget(
                accounts: accounts, activeHandle: activeHandle, usage: usage,
                hasCreds: hasCreds, config: config
            )
        }
    }

    /// True, wenn das aktive Konto die Failover-Schwelle in irgendeinem Fenster erreicht.
    public static func isNearLimit(_ usage: AccountUsage?, config: PolicyConfig = .default) -> Bool {
        guard let usage, usage.known else { return false }
        let sessionNear = usage.pct(UsageWindowKey.session).map { $0 >= config.failoverSessionAt } ?? false
        let weeklyNear = usage.pct(UsageWindowKey.weekly).map { $0 >= config.failoverWeeklyAt } ?? false
        return sessionNear || weeklyNear
    }

    // MARK: - Intern

    /// Ein Account taugt nur als Ziel, wenn BEIDE Fenster genug Luft haben.
    static func isHealthyTarget(_ usage: AccountUsage, config: PolicyConfig) -> Bool {
        guard usage.known else { return false }
        let session = usage.pct(UsageWindowKey.session)
        let weekly = usage.pct(UsageWindowKey.weekly)
        if session == nil && weekly == nil { return false }
        let sessionOk = session.map { $0 < config.targetSessionMax } ?? true
        let weeklyOk = weekly.map { $0 < config.targetWeeklyMax } ?? true
        return sessionOk && weeklyOk
    }

    /// Gesunde Kandidaten, aufsteigend nach Session-Auslastung (gesündester zuerst).
    static func healthyTargets(
        accounts: [Account],
        activeHandle: String,
        usage: [String: AccountUsage],
        hasCreds: (Account) -> Bool,
        config: PolicyConfig
    ) -> [Account] {
        var scored: [(account: Account, session: Double)] = []
        for account in accounts where account.handle != activeHandle && hasCreds(account) {
            guard let state = usage[account.handle], isHealthyTarget(state, config: config) else {
                continue
            }
            scored.append((account, state.pct(UsageWindowKey.session) ?? 0))
        }
        scored.sort { $0.session < $1.session }
        return scored.map(\.account)
    }

    static func failoverTarget(
        accounts: [Account],
        activeHandle: String,
        usage: [String: AccountUsage],
        hasCreds: (Account) -> Bool,
        config: PolicyConfig
    ) -> Account? {
        guard isNearLimit(usage[activeHandle], config: config) else { return nil }
        return healthyTargets(
            accounts: accounts, activeHandle: activeHandle, usage: usage,
            hasCreds: hasCreds, config: config
        ).first
    }

    static func balanceTarget(
        accounts: [Account],
        activeHandle: String,
        usage: [String: AccountUsage],
        hasCreds: (Account) -> Bool,
        config: PolicyConfig
    ) -> Account? {
        guard let active = usage[activeHandle], active.known,
            let activeSession = active.pct(UsageWindowKey.session)
        else { return nil }
        let targets = healthyTargets(
            accounts: accounts, activeHandle: activeHandle, usage: usage,
            hasCreds: hasCreds, config: config
        )
        guard let best = targets.first else { return nil }
        let bestSession = usage[best.handle]?.pct(UsageWindowKey.session) ?? 0
        // Notfall (Obergrenze erreicht) ODER lohnender Vorsprung (Hysterese).
        if activeSession >= config.balanceCeiling || (activeSession - bestSession) >= config.balanceMinGap {
            return best
        }
        return nil
    }
}
