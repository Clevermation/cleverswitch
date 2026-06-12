import Foundation
import Testing

@testable import CleverSwitchKit

/// Fake-Store mit Duplikaten pro Service (wie der echte Keychain bei mehrfachen
/// add-generic-password-Einträgen): read/readAccount liefern den OBERSTEN (= ältesten)
/// Eintrag, delete entfernt ihn — genau die Semantik, auf die consolidateLive aufbaut.
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
    private func blob(token: String, expiresAt: Int) -> String {
        #"{"claudeAiOauth":{"accessToken":"\#(token)","refreshToken":"r","expiresAt":\#(expiresAt)}}"#
    }

    @Test("neuester Eintrag überlebt — auch wenn ein älterer SPÄTER abläuft (Token-Vermischungs-Bug)")
    func newestSurvivesEvenIfOlderExpiresLater() {
        // Realer Fall (12.06.): paul aktiv (frisch refresht, läuft SPÄT ab), theo loggt sich neu
        // ein (Login-Token läuft FRÜHER ab). max(expiresAt) behielt fälschlich pauls Token und
        // löschte theos neuen Login — beide Accounts zeigten danach dieselbe Usage.
        let provider = ClaudeProvider()
        let store = DuplicateStore()
        let service = provider.liveCredentialService
        store.entries[service] = [
            ("mac-user", blob(token: "paul-alt", expiresAt: 999_999)),  // alt, läuft spät ab
            ("mac-user", blob(token: "theo-neu", expiresAt: 100)),  // NEUER Login, läuft früher ab
        ]
        provider.consolidateLive(credentials: store)
        let remaining = store.entries[service] ?? []
        #expect(remaining.count == 1)
        #expect(remaining.first?.secret == blob(token: "theo-neu", expiresAt: 100))
    }

    @Test("drei Duplikate -> nur der zuletzt angelegte bleibt")
    func threeDuplicatesKeepLast() {
        let provider = ClaudeProvider()
        let store = DuplicateStore()
        let service = provider.liveCredentialService
        store.entries[service] = [
            ("a", blob(token: "t1", expiresAt: 1)),
            ("a", blob(token: "t2", expiresAt: 2)),
            ("a", blob(token: "t3", expiresAt: 3)),
        ]
        provider.consolidateLive(credentials: store)
        #expect(store.entries[service]?.count == 1)
        #expect(store.entries[service]?.first?.secret == blob(token: "t3", expiresAt: 3))
    }

    @Test("leerer Live-Slot ist ein No-Op")
    func emptyIsNoop() {
        let provider = ClaudeProvider()
        let store = DuplicateStore()
        provider.consolidateLive(credentials: store)
        #expect(store.entries.isEmpty)
    }
}

@Suite("SwitchService Identitäts-Guard")
struct SwitchIdentityGuardTests {
    /// Claude-Identität kommt aus ~/.claude.json — dieser Fake-Provider injiziert sie direkt,
    /// damit der Guard ohne Dateisystem testbar ist.
    private struct IdentityProvider: AccountProvider {
        let id = "claude"
        let displayName = "Claude Code"
        let sessionWindowLabel = "5h"
        let weeklyWindowLabel = "7d"
        var identity: AccountIdentity?

        var liveCredentialService: String { "live" }
        func snapshotService(handle: String) -> String { "snap:\(handle)" }
        func readLive(credentials: CredentialStore) -> String? { credentials.read(service: "live") }
        func writeLive(_ blob: String, handle: String, credentials: CredentialStore) throws {
            try credentials.write(service: "live", account: handle, secret: blob)
        }
        func currentIdentity(credentials: CredentialStore) -> AccountIdentity? { identity }
        func isExpired(_ blob: String) -> Bool { false }
        func refresh(_ blob: String, http: HTTPClient) async throws -> String { blob }
        func fetchUsage(blob: String, http: HTTPClient, allowRefresh: Bool) async -> UsageOutcome {
            UsageOutcome(usage: .unknown, refreshedBlob: nil)
        }
        func loginCommand() -> [String]? { nil }
        func didActivate(account: Account) {}
    }

    private final class MemStore: CredentialStore, @unchecked Sendable {
        var items: [String: String] = [:]
        func read(service: String) -> String? { items[service] }
        func readAccount(service: String) -> String? { nil }
        func write(service: String, account: String, secret: String) throws { items[service] = secret }
        func delete(service: String) { items[service] = nil }
    }

    private struct NoopHTTP: HTTPClient {
        func send(_ request: URLRequest) async throws -> HTTPResponse {
            HTTPResponse(status: 500, body: Data())
        }
    }

    @Test("Live-Slot mit FREMDER Identität wird NICHT in den Snapshot des bisherigen Accounts kopiert")
    func foreignLiveBlobIsNotSnapshotted() async throws {
        var provider = IdentityProvider()
        // Live enthält in Wahrheit theos Token, state glaubt aber paul sei aktiv:
        provider.identity = AccountIdentity(handle: "theo@x.com", label: "", sessionPayload: nil)
        let store = MemStore()
        store.items["live"] = "theo-token"
        store.items["snap:paul@x.com"] = "paul-token"
        store.items["snap:theo@x.com"] = "theo-token"

        try await SwitchService.activate(
            target: Account(provider: "claude", handle: "theo@x.com"),
            current: Account(provider: "claude", handle: "paul@x.com"),
            provider: provider, credentials: store, http: NoopHTTP())

        // pauls Snapshot bleibt unangetastet (vorher wurde theo-token hineinkopiert!)
        #expect(store.items["snap:paul@x.com"] == "paul-token")
        #expect(store.items["live"] == "theo-token")
    }

    @Test("Live-Slot mit PASSENDER Identität wird normal gesichert")
    func matchingLiveBlobIsSnapshotted() async throws {
        var provider = IdentityProvider()
        provider.identity = AccountIdentity(handle: "paul@x.com", label: "", sessionPayload: nil)
        let store = MemStore()
        store.items["live"] = "paul-frisch"
        store.items["snap:paul@x.com"] = "paul-alt"
        store.items["snap:theo@x.com"] = "theo-token"

        try await SwitchService.activate(
            target: Account(provider: "claude", handle: "theo@x.com"),
            current: Account(provider: "claude", handle: "paul@x.com"),
            provider: provider, credentials: store, http: NoopHTTP())

        #expect(store.items["snap:paul@x.com"] == "paul-frisch")  // gesichert
        #expect(store.items["live"] == "theo-token")  // Ziel aktiviert
    }
}
