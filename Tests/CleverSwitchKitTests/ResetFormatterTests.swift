import Foundation
import Testing

@testable import CleverSwitchKit

@Suite("Reset-Countdown")
struct ResetFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_765_000_000)

    @Test("ISO-8601 mit Sekundenbruchteilen (Claude-Format)")
    func parsesISOWithFraction() {
        let raw = "2026-06-17T06:00:00.347238+00:00"
        #expect(ResetFormatter.parse(raw) != nil)
    }

    @Test("Unix-Timestamp-String (Codex-Format)")
    func parsesUnixString() {
        let date = ResetFormatter.parse("1765432100")
        #expect(date == Date(timeIntervalSince1970: 1_765_432_100))
        // auch mit Nachkommastellen (String(Double))
        #expect(ResetFormatter.parse("1765432100.0") == Date(timeIntervalSince1970: 1_765_432_100))
    }

    @Test("Countdown-Formate: Tage, Stunden, Minuten")
    func countdownFormats() {
        func at(_ seconds: Int) -> String { String(now.timeIntervalSince1970 + Double(seconds)) }
        #expect(ResetFormatter.shortCountdown(from: at(6 * 86400 + 21 * 3600), now: now) == "6d 21h")
        #expect(ResetFormatter.shortCountdown(from: at(4 * 3600 + 49 * 60), now: now) == "4h 49m")
        #expect(ResetFormatter.shortCountdown(from: at(12 * 60), now: now) == "12m")
    }

    @Test("Vergangenheit / Müll -> nil")
    func pastAndGarbage() {
        #expect(ResetFormatter.shortCountdown(from: "100", now: now) == nil)  // weit in der Vergangenheit
        #expect(ResetFormatter.shortCountdown(from: "kein datum", now: now) == nil)
        #expect(ResetFormatter.shortCountdown(from: nil, now: now) == nil)
    }
}
