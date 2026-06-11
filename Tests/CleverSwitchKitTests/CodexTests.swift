import Foundation
import Testing

@testable import CleverSwitchKit

/// Baut ein unsigniertes Test-JWT mit gegebener Payload (Signaturteil ist Dummy).
private func fakeJWT(payload: [String: Any]) -> String {
    func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let header = b64url(Data(#"{"alg":"none"}"#.utf8))
    let body = b64url(try! JSONSerialization.data(withJSONObject: payload))
    return "\(header).\(body).sig"
}

private func codexBlob(email: String = "dev@x.com", plan: String = "prolite", accountID: String? = "acc-1")
    -> String {
    var authClaim: [String: Any] = ["chatgpt_plan_type": plan]
    if let accountID { authClaim["chatgpt_account_id"] = accountID }
    let jwt = fakeJWT(payload: ["email": email, "https://api.openai.com/auth": authClaim])
    let tokens: [String: Any] = [
        "access_token": "at-1", "refresh_token": "rt-1", "id_token": jwt,
    ]
    let root: [String: Any] = ["tokens": tokens, "last_refresh": "2026-01-01T00:00:00Z"]
    return String(data: try! JSONSerialization.data(withJSONObject: root), encoding: .utf8)!
}

private struct FixedHTTP: HTTPClient {
    let response: HTTPResponse
    func send(_ request: URLRequest) async throws -> HTTPResponse { response }
}

@Suite("Codex-Auth")
struct CodexAuthTests {
    @Test("JWT-Payload wird dekodiert (base64url)")
    func decodesJWT() throws {
        let jwt = fakeJWT(payload: ["email": "a@b.c", "n": 1])
        let payload = try #require(CodexAuth.decodeJWTPayload(jwt))
        #expect(payload["email"] as? String == "a@b.c")
    }

    @Test("Identität aus dem Blob: email, plan, account_id")
    func identityFromBlob() {
        let blob = codexBlob(email: "theo@x.com", plan: "prolite", accountID: "acc-9")
        #expect(CodexAuth.email(in: blob) == "theo@x.com")
        #expect(CodexAuth.planType(in: blob) == "prolite")
        #expect(CodexAuth.accountID(in: blob) == "acc-9")
        #expect(CodexAuth.accessToken(in: blob) == "at-1")
        #expect(CodexAuth.refreshToken(in: blob) == "rt-1")
    }

    @Test("refresh: 200 rotiert die Tokens im Blob")
    func refreshRotates() async throws {
        let http = FixedHTTP(
            response: HTTPResponse(
                status: 200,
                body: Data(#"{"access_token":"at-2","refresh_token":"rt-2"}"#.utf8)))
        let updated = try await CodexAuth.refresh(codexBlob(), http: http)
        #expect(CodexAuth.accessToken(in: updated) == "at-2")
        #expect(CodexAuth.refreshToken(in: updated) == "rt-2")
        // id_token bleibt erhalten
        #expect(CodexAuth.email(in: updated) == "dev@x.com")
    }

    @Test("refresh: invalid_grant -> CredentialsExpiredError")
    func refreshInvalidGrant() async {
        let http = FixedHTTP(
            response: HTTPResponse(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)))
        await #expect(throws: CredentialsExpiredError.self) {
            _ = try await CodexAuth.refresh(codexBlob(), http: http)
        }
    }
}

@Suite("Codex-Usage-Mapping")
struct CodexUsageTests {
    @Test("primary_window->session, secondary_window->weekly")
    func mapsWindows() throws {
        let body = Data(
            #"{"rate_limit":{"primary_window":{"used_percent":72.0,"reset_at":1765432100},"secondary_window":{"used_percent":16.0,"reset_at":1765432200}}}"#
                .utf8)
        let usage = try #require(CodexUsageAPI.mapUsage(responseBody: body))
        #expect(usage.pct(UsageWindowKey.session) == 72.0)
        #expect(usage.pct(UsageWindowKey.weekly) == 16.0)
    }

    @Test("login_required -> nil")
    func loginRequiredIsNil() {
        let body = Data(#"{"error":{"code":"login_required"}}"#.utf8)
        #expect(CodexUsageAPI.mapUsage(responseBody: body) == nil)
    }

    @Test("plan_type kommt aus der Usage-Response (Live-Wahrheit, nicht JWT)")
    func planTypeFromResponse() {
        let body = Data(#"{"plan_type":"pro","rate_limit":{}}"#.utf8)
        #expect(CodexUsageAPI.planType(responseBody: body) == "pro")
        #expect(CodexUsageAPI.planType(responseBody: Data("{}".utf8)) == nil)
    }
}

@Suite("Codex-Provider (Datei-Live-Slot)")
struct CodexProviderTests {
    private final class NoopStore: CredentialStore, @unchecked Sendable {
        func read(service: String) -> String? { nil }
        func readAccount(service: String) -> String? { nil }
        func write(service: String, account: String, secret: String) throws {}
        func delete(service: String) {}
    }

    private func tempProvider() -> (CodexProvider, URL) {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleverswitch-codex-\(UUID().uuidString)")
        return (CodexProvider(codexHome: home), home)
    }

    @Test("writeLive/readLive Round-Trip über auth.json")
    func liveRoundTrip() throws {
        let (provider, home) = tempProvider()
        defer { try? FileManager.default.removeItem(at: home) }
        let blob = codexBlob()
        try provider.writeLive(blob, handle: "dev@x.com", credentials: NoopStore())
        #expect(provider.readLive(credentials: NoopStore()) == blob)
        // Datei hat private Rechte
        let attrs = try FileManager.default.attributesOfItem(
            atPath: home.appendingPathComponent("auth.json").path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("currentIdentity liest E-Mail + Plan aus dem JWT")
    func identityFromLive() throws {
        let (provider, home) = tempProvider()
        defer { try? FileManager.default.removeItem(at: home) }
        try provider.writeLive(
            codexBlob(email: "theo@x.com", plan: "prolite"), handle: "theo@x.com",
            credentials: NoopStore())
        let identity = provider.currentIdentity(credentials: NoopStore())
        #expect(identity?.handle == "theo@x.com")
        #expect(identity?.label == "prolite")
    }

    @Test("fehlende auth.json -> keine Identität")
    func missingFileNoIdentity() {
        let (provider, _) = tempProvider()
        #expect(provider.currentIdentity(credentials: NoopStore()) == nil)
        #expect(provider.readLive(credentials: NoopStore()) == nil)
    }
}
