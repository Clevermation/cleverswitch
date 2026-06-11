import Testing

@testable import CleverSwitchKit

@Suite("Datenmodelle")
struct ModelsTests {
    @Test("pct liefert den Fensterwert")
    func pctReturnsWindowValue() {
        let u = AccountUsage(
            known: true,
            windows: [
                UsageWindow(key: UsageWindowKey.session, usedPct: 21),
                UsageWindow(key: UsageWindowKey.weekly, usedPct: 45),
            ]
        )
        #expect(u.pct(UsageWindowKey.session) == 21)
        #expect(u.pct(UsageWindowKey.weekly) == 45)
    }

    @Test("pct für fehlendes Fenster ist nil")
    func pctMissingWindowIsNil() {
        let u = AccountUsage(known: true, windows: [UsageWindow(key: UsageWindowKey.session, usedPct: 5)])
        #expect(u.pct(UsageWindowKey.weekly) == nil)
    }

    @Test("worstPct ist das Maximum")
    func worstPctIsMax() {
        let u = AccountUsage(
            known: true,
            windows: [
                UsageWindow(key: UsageWindowKey.session, usedPct: 21),
                UsageWindow(key: UsageWindowKey.weekly, usedPct: 45),
            ]
        )
        #expect(u.worstPct == 45)
    }

    @Test("worstPct ohne Fenster ist nil")
    func worstPctEmptyIsNil() {
        #expect(AccountUsage(known: true).worstPct == nil)
    }

    @Test("unknown-Sentinel")
    func unknownSentinel() {
        #expect(AccountUsage.unknown.known == false)
        #expect(AccountUsage.unknown.worstPct == nil)
    }
}
