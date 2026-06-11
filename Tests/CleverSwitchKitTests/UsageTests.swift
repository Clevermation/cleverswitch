import Foundation
import Testing

@testable import CleverSwitchKit

@Suite("Usage-Mapping")
struct UsageTests {
    @Test("mappt five_hour->session, seven_day->weekly")
    func mapsWindows() throws {
        let body = Data(
            #"{"five_hour":{"utilization":21.0,"resets_at":"2026-06-17T06:00:00Z"},"seven_day":{"utilization":45.0,"resets_at":null}}"#
                .utf8)
        let usage = try #require(ClaudeUsageAPI.mapUsage(responseBody: body))
        #expect(usage.known)
        #expect(usage.pct(UsageWindowKey.session) == 21.0)
        #expect(usage.pct(UsageWindowKey.weekly) == 45.0)
        #expect(usage.worstPct == 45.0)
    }

    @Test("leere/kaputte Antwort -> nil")
    func emptyIsNil() {
        #expect(ClaudeUsageAPI.mapUsage(responseBody: Data("{}".utf8)) == nil)
        #expect(ClaudeUsageAPI.mapUsage(responseBody: Data("not json".utf8)) == nil)
    }

    @Test("resets_at bleibt erhalten")
    func resetsAtPreserved() throws {
        let body = Data(#"{"five_hour":{"utilization":5.0,"resets_at":"X"}}"#.utf8)
        let usage = try #require(ClaudeUsageAPI.mapUsage(responseBody: body))
        #expect(usage.windows.first?.resetsAt == "X")
    }
}
