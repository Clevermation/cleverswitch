import Foundation
import Testing

@testable import CleverSwitchKit

/// Fake-Store mit Duplikaten pro Service (wie der echte Keychain bei mehrfachen
/// add-generic-password-Einträgen): read/readAccount liefern den OBERSTEN Eintrag,
/// delete entfernt ihn — genau die Semantik, auf die consolidateLive aufbaut.
private final class DuplicateStore: CredentialStore, @unchecked Sendable {
    var entries: [String: [(account: String, secret: String)]] = [:]

    func read(service: String) -> String? { entries[service]?.first?.secret }
    func readAccount(service: String) -> String? { entries[service]?.first?.account }
    func write(service: String, account: String, secret: String) throws {
        entries[service, default: []].append((account, secret))
    }
    func delete(service: String) {
        guard var list = entries[service], !list.isEmpty else { return }
        list.removeFirst()
        entries[service] = list.isEmpty ? nil : list
    }
}

@Suite("consolidateLive (Keychain-Duplikate)")
struct ConsolidateLiveTests {
    private func blob(expiresAt: Int) -> String {
        #"{"claudeAiOauth":{"accessToken":"t\#(expiresAt)","refreshToken":"r","expiresAt":\#(expiresAt)}}"#
    }

    @Test("frischester Token überlebt, Duplikate verschwinden")
    func freshestSurvives() {
        let provider = ClaudeProvider()
        let store = DuplicateStore()
        let service = provider.liveCredentialService
        store.entries[service] = [
            ("a@x.com", blob(expiresAt: 100)),  // alt — würde von read zuerst geliefert
            ("a@x.com", blob(expiresAt: 9999)),  // frisch
            ("a@x.com", blob(expiresAt: 500)),
        ]
        provider.consolidateLive(credentials: store)
        let remaining = store.entries[service] ?? []
        #expect(remaining.count == 1)
        #expect(remaining.first?.secret == blob(expiresAt: 9999))
        #expect(remaining.first?.account == "a@x.com")
    }

    @Test("leerer Live-Slot ist ein No-Op")
    func emptyIsNoop() {
        let provider = ClaudeProvider()
        let store = DuplicateStore()
        provider.consolidateLive(credentials: store)
        #expect(store.entries.isEmpty)
    }

    @Test("Blob ohne expiresAt verliert gegen Blob mit Zeitstempel")
    func missingTimestampLoses() {
        let provider = ClaudeProvider()
        let store = DuplicateStore()
        let service = provider.liveCredentialService
        let broken = #"{"claudeAiOauth":{"accessToken":"x","refreshToken":"r"}}"#
        store.entries[service] = [
            ("a@x.com", broken),
            ("a@x.com", blob(expiresAt: 100)),
        ]
        provider.consolidateLive(credentials: store)
        #expect(store.entries[service]?.count == 1)
        #expect(store.entries[service]?.first?.secret == blob(expiresAt: 100))
    }
}
