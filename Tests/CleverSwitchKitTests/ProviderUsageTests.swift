import Foundation
import Testing

@testable import CleverSwitchKit

/// HTTP-Fake mit Zustand: liefert pro Usage-Aufruf einen vorgegebenen Status (erst 401, dann 200),
/// und einen festen Status für den Token-(Refresh-)Endpoint.
private final class RoutingHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var usageCall = 0
    let usageStatuses: [Int]
    let usageBodies: [Data]
    let tokenStatus: Int
    let tokenBody: Data
    private(set) var tokenCalls = 0

    init(usageStatuses: [Int], usageBodies: [Data], tokenStatus: Int, tokenBody: Data) {
        self.usageStatuses = usageStatuses
        self.usageBodies = usageBodies
        self.tokenStatus = tokenStatus
        self.tokenBody = tokenBody
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let url = request.url?.absoluteString ?? ""
        if url.contains("oauth/usage") {
            let index = lock.withLock { () -> Int in
                let current = min(usageCall, usageStatuses.count - 1)
                usageCall += 1
                return current
            }
            return HTTPResponse(status: usageStatuses[index], body: usageBodies[index])
        }
        lock.withLock { tokenCalls += 1 }
        return HTTPResponse(status: tokenStatus, body: tokenBody)
    }
}

private func claudeBlob() -> String {
    let object: [String: Any] = [
        "claudeAiOauth": ["accessToken": "at-old", "refreshToken": "rt-old", "expiresAt": 0]
    ]
    return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
}

private let usage200 = Data(#"{"five_hour":{"utilization":12.0},"seven_day":{"utilization":5.0}}"#.utf8)
private let token200 = Data(#"{"access_token":"at-new","refresh_token":"rt-new","expires_in":28800}"#.utf8)

@Suite("Usage-Backoff (Provider)")
struct ProviderUsageTests {
    @Test("allowRefresh=false: 401 -> unknown, KEIN Refresh-Aufruf")
    func noRefreshWhenDisallowed() async {
        let http = RoutingHTTP(
            usageStatuses: [401], usageBodies: [Data()], tokenStatus: 200, tokenBody: token200)
        let outcome = await ClaudeProvider().fetchUsage(blob: claudeBlob(), http: http, allowRefresh: false)
        #expect(outcome.usage.known == false)
        #expect(outcome.refreshFailed == false)
        #expect(http.tokenCalls == 0)  // Refresh wurde NICHT versucht
    }

    @Test("allowRefresh=true: 401 + Refresh-429 -> refreshFailed (Backoff-Signal)")
    func refreshFailureSetsFlag() async {
        let http = RoutingHTTP(
            usageStatuses: [401], usageBodies: [Data()],
            tokenStatus: 429, tokenBody: Data(#"{"error":"rate_limit"}"#.utf8))
        let outcome = await ClaudeProvider().fetchUsage(blob: claudeBlob(), http: http, allowRefresh: true)
        #expect(outcome.refreshFailed == true)
        #expect(outcome.usage.known == false)
        #expect(http.tokenCalls == 1)
    }

    @Test("allowRefresh=true: 401 -> Refresh-200 -> Usage-200 = Erfolg + erneuerter Blob")
    func refreshThenSuccess() async {
        let http = RoutingHTTP(
            usageStatuses: [401, 200], usageBodies: [Data(), usage200],
            tokenStatus: 200, tokenBody: token200)
        let outcome = await ClaudeProvider().fetchUsage(blob: claudeBlob(), http: http, allowRefresh: true)
        #expect(outcome.usage.known == true)
        #expect(outcome.usage.pct(UsageWindowKey.session) == 12.0)
        #expect(outcome.refreshFailed == false)
        #expect(outcome.refreshedBlob != nil)
        #expect(ClaudeAuth.accessToken(in: outcome.refreshedBlob ?? "") == "at-new")
    }
}
