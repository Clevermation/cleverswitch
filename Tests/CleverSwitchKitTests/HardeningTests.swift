import Foundation
import Testing

@testable import CleverSwitchKit

@Suite("Handle-Validierung")
struct ValidationTests {
    @Test("normale E-Mails sind gültig")
    func validEmails() {
        #expect(AccountHandle.isValid("anna@example.com"))
        #expect(AccountHandle.isValid("a.b+c@x.io"))
    }

    @Test("Steuerzeichen / Newline / leer sind ungültig (Injection-Schutz)")
    func invalidHandles() {
        #expect(!AccountHandle.isValid(""))
        #expect(!AccountHandle.isValid("evil@x.com\ndelete-generic-password -s victim"))
        #expect(!AccountHandle.isValid("a\u{0}b"))
        #expect(!AccountHandle.isValid(String(repeating: "x", count: 300)))
    }

    @Test("E-Mail-Maskierung leakt die Adresse nicht, bleibt aber unterscheidbar")
    func emailMasking() {
        #expect(AccountHandle.masked("anna@example.com") == "a•••@e•••.com")
        #expect(AccountHandle.masked("max@firma-beispiel.de") == "m•••@f•••.de")
        #expect(AccountHandle.masked("a@b.io") == "a•••@b•••.io")
        // kein @ -> nur erstes Zeichen
        #expect(AccountHandle.masked("weird") == "w•••")
        // Domain ohne Punkt
        #expect(AccountHandle.masked("x@localhost") == "x•••@l•••")
    }
}

@Suite("AppSettings-Abwärtskompatibilität")
struct AppSettingsDecodeTests {
    @Test("alte settings ohne neue Felder -> Defaults (Notifications an, E-Mail an)")
    func decodesLegacy() throws {
        let json = Data(
            #"{"modes":{"claude":"failover"},"policy":{"failoverSessionAt":85,"failoverWeeklyAt":92,"targetSessionMax":70,"targetWeeklyMax":90,"balanceMinGap":12,"balanceCeiling":85}}"#
                .utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)
        #expect(settings.mode(for: "claude") == .failover)
        #expect(settings.notificationsEnabled == true)
        #expect(settings.showEmail == true)
    }
}

private struct FixedHTTP: HTTPClient {
    let response: HTTPResponse
    func send(_ request: URLRequest) async throws -> HTTPResponse { response }
}

@Suite("OAuth-Fehlerklassifikation")
struct OAuthClassificationTests {
    private func claudeBlob() -> String {
        #"{"claudeAiOauth":{"accessToken":"a","refreshToken":"r","expiresAt":0}}"#
    }

    @Test("invalid_request ist transient, NICHT 'abgelaufen'")
    func invalidRequestIsTransient() async {
        let http = FixedHTTP(
            response: HTTPResponse(status: 400, body: Data(#"{"error":"invalid_request"}"#.utf8)))
        await #expect(throws: TransientRefreshError.self) {
            _ = try await ClaudeAuth.refresh(claudeBlob(), http: http)
        }
    }

    @Test("invalid_grant bleibt 'endgültig tot'")
    func invalidGrantIsExpired() async {
        let http = FixedHTTP(
            response: HTTPResponse(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)))
        await #expect(throws: CredentialsExpiredError.self) {
            _ = try await ClaudeAuth.refresh(claudeBlob(), http: http)
        }
    }
}

@Suite("Store-Robustheit")
struct StoreHardeningTests {
    @Test("kaputte Datei wird gesichert statt still verworfen")
    func corruptFileIsBackedUp() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleverswitch-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("state.json")
        try Data("{ kaputt ".utf8).write(to: url)

        let state = StateStore(url: url).load()
        #expect(state.accounts.isEmpty)  // Default zurück
        // Original gesichert, nicht gelöscht
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
    }
}

@Suite("SwitchService-Reihenfolge")
struct SwitchOrderTests {
    private final class MemStore: CredentialStore, @unchecked Sendable {
        var items: [String: String] = [:]
        func read(service: String) -> String? { items[service] }
        func readAccount(service: String) -> String? { nil }
        func write(service: String, account: String, secret: String) throws { items[service] = secret }
        func delete(service: String) { items[service] = nil }
    }

    private func freshBlob(expiresAt: Double) -> String {
        #"{"claudeAiOauth":{"accessToken":"old","refreshToken":"r","expiresAt":\#(Int(expiresAt))}}"#
    }

    @Test("erneuerter Token landet live UND im Snapshot")
    func refreshedTokenLiveAndSnapshot() async throws {
        let provider = ClaudeProvider()
        let store = MemStore()
        store.items[provider.snapshotService(handle: "b@x.com")] = freshBlob(expiresAt: 0)  // abgelaufen
        let http = FixedHTTP(
            response: HTTPResponse(
                status: 200,
                body: Data(#"{"access_token":"new","refresh_token":"r2","expires_in":3600}"#.utf8)))

        try await SwitchService.activate(
            target: Account(provider: "claude", handle: "b@x.com"), current: nil,
            provider: provider, credentials: store, http: http)

        let live = try #require(store.read(service: provider.liveCredentialService))
        #expect(ClaudeAuth.accessToken(in: live) == "new")  // live aktualisiert
        let snapshot = try #require(store.read(service: provider.snapshotService(handle: "b@x.com")))
        #expect(ClaudeAuth.accessToken(in: snapshot) == "new")  // Snapshot ebenfalls aktualisiert
    }
}
