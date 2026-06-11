import Testing

@testable import CleverSwitchKit

private func acc(_ handle: String, active: Bool = false) -> Account {
    Account(provider: "claude", handle: handle, active: active, credentialKey: "claude:\(handle)")
}

private func usage(session: Double? = nil, weekly: Double? = nil, known: Bool = true) -> AccountUsage {
    var windows: [UsageWindow] = []
    if let session { windows.append(UsageWindow(key: UsageWindowKey.session, usedPct: session)) }
    if let weekly { windows.append(UsageWindow(key: UsageWindowKey.weekly, usedPct: weekly)) }
    return AccountUsage(known: known, windows: windows)
}

private let accountA = acc("a@x.com", active: true)
private let accountB = acc("b@x.com")
private let accounts = [accountA, accountB]

private func pick(
    _ mode: SwitchMode,
    _ usage: [String: AccountUsage],
    accounts: [Account] = accounts,
    hasCreds: (Account) -> Bool = { _ in true },
    config: PolicyConfig = .default
) -> Account? {
    AutoSwitchPolicy.pickTarget(
        mode: mode, accounts: accounts, activeHandle: "a@x.com", usage: usage,
        hasCreds: hasCreds, config: config
    )
}

@Suite("Auto-Switch-Policy")
struct PolicyTests {
    // MARK: failover

    @Test("failover wechselt bei nahem Session-Limit")
    func failoverNearSessionLimit() {
        let u = ["a@x.com": usage(session: 86, weekly: 40), "b@x.com": usage(session: 10, weekly: 20)]
        #expect(pick(.failover, u) == accountB)
    }

    @Test("failover bleibt unter der Schwelle")
    func failoverBelowThreshold() {
        let u = ["a@x.com": usage(session: 50, weekly: 40), "b@x.com": usage(session: 10, weekly: 20)]
        #expect(pick(.failover, u) == nil)
    }

    @Test("failover verwirft Ziel, das im Weekly-Fenster ungesund ist")
    func failoverRejectsWeeklyUnhealthyTarget() {
        let u = ["a@x.com": usage(session: 90, weekly: 40), "b@x.com": usage(session: 10, weekly: 95)]
        #expect(pick(.failover, u) == nil)
    }

    @Test("failover greift auch über das Weekly-Fenster des aktiven Kontos")
    func failoverTriggersOnWeekly() {
        let u = ["a@x.com": usage(session: 40, weekly: 93), "b@x.com": usage(session: 10, weekly: 20)]
        #expect(pick(.failover, u) == accountB)
    }

    // MARK: balance

    @Test("balance wechselt bei ausreichendem Vorsprung")
    func balanceSwitchesOnGap() {
        let u = ["a@x.com": usage(session: 40, weekly: 30), "b@x.com": usage(session: 20, weekly: 15)]
        #expect(pick(.balance, u) == accountB)
    }

    @Test("balance hält innerhalb der Hysterese")
    func balanceHoldsWithinHysteresis() {
        let u = ["a@x.com": usage(session: 40, weekly: 30), "b@x.com": usage(session: 33, weekly: 15)]
        #expect(pick(.balance, u) == nil)
    }

    @Test("balance wechselt an der Obergrenze")
    func balanceSwitchesAtCeiling() {
        let u = ["a@x.com": usage(session: 88, weekly: 30), "b@x.com": usage(session: 60, weekly: 15)]
        #expect(pick(.balance, u) == accountB)
    }

    // MARK: Edge Cases

    @Test("off wechselt nie")
    func offNeverSwitches() {
        let u = ["a@x.com": usage(session: 99, weekly: 99), "b@x.com": usage(session: 1, weekly: 1)]
        #expect(pick(.off, u) == nil)
    }

    @Test("ein einzelner Account wechselt nie")
    func singleAccountNeverSwitches() {
        let u = ["a@x.com": usage(session: 99, weekly: 99)]
        #expect(pick(.failover, u, accounts: [accountA]) == nil)
    }

    @Test("alle erschöpft -> kein Ziel")
    func allExhaustedNoTarget() {
        let u = ["a@x.com": usage(session: 95, weekly: 90), "b@x.com": usage(session: 92, weekly: 88)]
        #expect(pick(.failover, u) == nil)
    }

    @Test("Ziel ohne Credentials wird ignoriert")
    func targetWithoutCredentialsIgnored() {
        let u = ["a@x.com": usage(session: 90, weekly: 40), "b@x.com": usage(session: 10, weekly: 20)]
        #expect(pick(.failover, u, hasCreds: { $0.handle == "a@x.com" }) == nil)
    }

    @Test("unbekannte Auslastung des aktiven Kontos -> keine Entscheidung")
    func unknownActiveUsageNoDecision() {
        let u = ["a@x.com": AccountUsage.unknown, "b@x.com": usage(session: 10, weekly: 20)]
        #expect(pick(.failover, u) == nil)
        #expect(pick(.balance, u) == nil)
    }

    @Test("eigene Konfiguration senkt die Schwelle")
    func customConfigLowersThreshold() {
        let cfg = PolicyConfig(failoverSessionAt: 60)
        let u = ["a@x.com": usage(session: 65, weekly: 30), "b@x.com": usage(session: 10, weekly: 20)]
        #expect(pick(.failover, u, config: cfg) == accountB)
    }
}
