import Foundation
import Testing

@testable import CleverSwitchKit

private struct FixedHTTP: HTTPClient {
    let response: HTTPResponse
    func send(_ request: URLRequest) async throws -> HTTPResponse { response }
}

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    @Test("isNewer: numerischer Semver-Vergleich (inkl. zweistelliger Komponenten)")
    func semverComparison() {
        #expect(UpdateChecker.isNewer("0.2.0", than: "0.1.3"))
        #expect(UpdateChecker.isNewer("1.0", than: "0.9.9"))
        #expect(UpdateChecker.isNewer("0.1.10", than: "0.1.9"))  // 10 > 9, kein String-Vergleich
        #expect(!UpdateChecker.isNewer("0.1.3", than: "0.1.3"))
        #expect(!UpdateChecker.isNewer("0.1.2", than: "0.1.3"))
        #expect(!UpdateChecker.isNewer("0.1", than: "0.1.0"))  // fehlende Komponente == 0
    }

    @Test("check: neue Version aus tag_name (v-Präfix entfernt)")
    func checkFindsNewer() async {
        let http = FixedHTTP(
            response: HTTPResponse(status: 200, body: Data(#"{"tag_name":"v9.9.9"}"#.utf8)))
        let found = await UpdateChecker.check(current: "0.1.3", http: http)
        #expect(found == "9.9.9")
    }

    @Test("check: nil wenn bereits aktuell oder bei API-Fehler")
    func checkQuietOnCurrentOrError() async {
        let current = FixedHTTP(
            response: HTTPResponse(status: 200, body: Data(#"{"tag_name":"v0.0.1"}"#.utf8)))
        #expect(await UpdateChecker.check(current: "0.1.3", http: current) == nil)

        let rateLimited = FixedHTTP(response: HTTPResponse(status: 403, body: Data()))
        #expect(await UpdateChecker.check(current: "0.1.3", http: rateLimited) == nil)

        let broken = FixedHTTP(response: HTTPResponse(status: 200, body: Data("kaputt".utf8)))
        #expect(await UpdateChecker.check(current: "0.1.3", http: broken) == nil)
    }
}
