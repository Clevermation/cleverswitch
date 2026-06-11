import Foundation
import Testing

@testable import CleverSwitchKit

/// HTTP-Client mit fester, vorgegebener Antwort — für deterministische Tests.
private struct FakeHTTPClient: HTTPClient {
    let response: HTTPResponse
    func send(_ request: URLRequest) async throws -> HTTPResponse { response }
}

private func blob(accessToken: String = "old-access", refreshToken: String = "old-refresh", expiresAtMillis: Double) -> String {
    """
    {"claudeAiOauth":{"accessToken":"\(accessToken)","refreshToken":"\(refreshToken)","expiresAt":\(Int(expiresAtMillis)),"subscriptionType":"max","rateLimitTier":"keep-me"}}
    """
}

@Suite("Claude-OAuth")
struct ClaudeAuthTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("isExpired erkennt abgelaufenen Token")
    func isExpiredPast() {
        let past = blob(expiresAtMillis: (now.timeIntervalSince1970 - 60) * 1000)
        #expect(ClaudeAuth.isExpired(past, now: now))
    }

    @Test("isExpired erkennt gültigen Token")
    func isExpiredFuture() {
        let future = blob(expiresAtMillis: (now.timeIntervalSince1970 + 3600) * 1000)
        #expect(!ClaudeAuth.isExpired(future, now: now))
    }

    @Test("isExpired ohne expiresAt ist false")
    func isExpiredMissing() {
        #expect(!ClaudeAuth.isExpired("{\"claudeAiOauth\":{}}", now: now))
    }

    @Test("Token-Helfer lesen die Felder")
    func tokenAccessors() {
        let b = blob(expiresAtMillis: 123_000)
        #expect(ClaudeAuth.accessToken(in: b) == "old-access")
        #expect(ClaudeAuth.refreshToken(in: b) == "old-refresh")
        #expect(ClaudeAuth.expiresAtMillis(in: b) == 123_000)
    }

    @Test("applyTokenResponse merged Felder und erhält Unbekanntes")
    func applyResponsePreservesUnknown() throws {
        let original = blob(expiresAtMillis: 0)
        let responseBody = Data(
            #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8)
        let updated = try #require(ClaudeAuth.applyTokenResponse(into: original, responseBody: responseBody, now: now))
        #expect(ClaudeAuth.accessToken(in: updated) == "new-access")
        #expect(ClaudeAuth.refreshToken(in: updated) == "new-refresh")
        #expect(ClaudeAuth.expiresAtMillis(in: updated) == (now.timeIntervalSince1970 + 3600) * 1000)
        // unbekanntes Feld bleibt erhalten
        #expect(updated.contains("keep-me"))
    }

    @Test("refresh: 200 liefert aktualisierten Blob")
    func refresh200() async throws {
        let original = blob(expiresAtMillis: 0)
        let body = Data(#"{"access_token":"fresh","refresh_token":"rot","expires_in":1800}"#.utf8)
        let http = FakeHTTPClient(response: HTTPResponse(status: 200, body: body))
        let updated = try await ClaudeAuth.refresh(original, http: http, now: now)
        #expect(ClaudeAuth.accessToken(in: updated) == "fresh")
        #expect(ClaudeAuth.refreshToken(in: updated) == "rot")
    }

    @Test("refresh: 401 invalid_grant -> ExpiredCredentialsError")
    func refresh401InvalidGrant() async {
        let http = FakeHTTPClient(
            response: HTTPResponse(status: 401, body: Data(#"{"error":"invalid_grant"}"#.utf8)))
        await #expect(throws: CredentialsExpiredError.self) {
            _ = try await ClaudeAuth.refresh(blob(expiresAtMillis: 0), http: http, now: now)
        }
    }

    @Test("refresh: 429 -> TransientRefreshError")
    func refresh429Transient() async {
        let http = FakeHTTPClient(
            response: HTTPResponse(status: 429, body: Data(#"{"error":"rate_limit"}"#.utf8)))
        await #expect(throws: TransientRefreshError(status: 429)) {
            _ = try await ClaudeAuth.refresh(blob(expiresAtMillis: 0), http: http, now: now)
        }
    }
}
