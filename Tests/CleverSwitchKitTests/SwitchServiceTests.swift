import Foundation
import Testing

@testable import CleverSwitchKit

/// In-Memory-Credential-Store für Tests (ersetzt das echte Keychain).
private final class MemStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: (account: String, secret: String)] = [:]

    func read(service: String) -> String? { lock.withLock { data[service]?.secret } }
    func readAccount(service: String) -> String? { lock.withLock { data[service]?.account } }
    func write(service: String, account: String, secret: String) throws {
        lock.withLock { data[service] = (account, secret) }
    }

    func delete(service: String) {
        lock.withLock { data[service] = nil }
    }

    func seed(service: String, secret: String, account: String = "x") {
        try? write(service: service, account: account, secret: secret)
    }
}

private struct FixedHTTP: HTTPClient {
    let response: HTTPResponse
    func send(_ request: URLRequest) async throws -> HTTPResponse { response }
}

// Deterministische Blobs (feste expiresAt, kein Date()).
private let futureBlob = #"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r","expiresAt":99999999999999}}"#
private let pastBlob = #"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r","expiresAt":1000}}"#

private let refreshOK = FixedHTTP(
    response: HTTPResponse(
        status: 200,
        body: Data(#"{"access_token":"fresh","refresh_token":"rot","expires_in":3600}"#.utf8)))
private let refreshDead = FixedHTTP(
    response: HTTPResponse(status: 401, body: Data(#"{"error":"invalid_grant"}"#.utf8)))

@Suite("Switch-Service")
struct SwitchServiceTests {
    private let provider = ClaudeProvider()

    private func account(_ handle: String, active: Bool = false) -> Account {
        Account(provider: "claude", handle: handle, active: active)
    }

    @Test("sichert den aktiven Account und aktiviert das gültige Ziel")
    func activatesValidTarget() async throws {
        let store = MemStore()
        store.seed(service: provider.liveCredentialService, secret: "CURRENT-LIVE")
        store.seed(service: provider.snapshotService(handle: "b@x.com"), secret: futureBlob)

        try await SwitchService.activate(
            target: account("b@x.com"), current: account("a@x.com", active: true),
            provider: provider, credentials: store, http: refreshOK)

        // bisheriger Live-Slot wurde im a-Snapshot gesichert
        #expect(store.read(service: provider.snapshotService(handle: "a@x.com")) == "CURRENT-LIVE")
        // Ziel liegt unverändert im Live-Slot (kein Refresh nötig)
        #expect(store.read(service: provider.liveCredentialService) == futureBlob)
    }

    @Test("erneuert einen abgelaufenen Ziel-Token vor dem Aktivieren")
    func refreshesExpiredTarget() async throws {
        let store = MemStore()
        store.seed(service: provider.snapshotService(handle: "b@x.com"), secret: pastBlob)

        try await SwitchService.activate(
            target: account("b@x.com"), current: nil,
            provider: provider, credentials: store, http: refreshOK)

        let live = try #require(store.read(service: provider.liveCredentialService))
        #expect(ClaudeAuth.accessToken(in: live) == "fresh")
        // erneuerter Blob wurde auch in den Snapshot zurückgeschrieben
        let snapshot = try #require(store.read(service: provider.snapshotService(handle: "b@x.com")))
        #expect(ClaudeAuth.accessToken(in: snapshot) == "fresh")
    }

    @Test("toter Refresh-Token -> sessionExpired (kein kaputter Live-Slot)")
    func deadRefreshThrowsSessionExpired() async {
        let store = MemStore()
        store.seed(service: provider.snapshotService(handle: "b@x.com"), secret: pastBlob)

        await #expect(throws: SwitchService.SwitchError.sessionExpired(handle: "b@x.com")) {
            try await SwitchService.activate(
                target: account("b@x.com"), current: nil,
                provider: provider, credentials: store, http: refreshDead)
        }
        // Live-Slot bleibt leer — kein abgelaufener Token landet live
        #expect(store.read(service: provider.liveCredentialService) == nil)
    }

    @Test("fehlender Snapshot -> missingCredentials")
    func missingSnapshotThrows() async {
        await #expect(throws: SwitchService.SwitchError.missingCredentials(handle: "ghost@x.com")) {
            try await SwitchService.activate(
                target: account("ghost@x.com"), current: nil,
                provider: provider, credentials: MemStore(), http: refreshOK)
        }
    }

    @Test("transienter Refresh-Fehler (429) -> Switch läuft mit vorhandenem Blob weiter")
    func transientRefreshProceeds() async throws {
        let store = MemStore()
        store.seed(service: provider.snapshotService(handle: "b@x.com"), secret: pastBlob)
        let rateLimited = FixedHTTP(
            response: HTTPResponse(status: 429, body: Data(#"{"error":"rate_limit"}"#.utf8)))

        try await SwitchService.activate(
            target: account("b@x.com"), current: nil,
            provider: provider, credentials: store, http: rateLimited)

        // Best effort: der (abgelaufene) Blob landet trotzdem im Live-Slot statt eines Abbruchs.
        #expect(store.read(service: provider.liveCredentialService) == pastBlob)
    }
}
