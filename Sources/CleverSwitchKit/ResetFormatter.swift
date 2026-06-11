// Formatiert "resets at"-Zeitstempel als kurzen Countdown ("4h 49m").
//
// Claude liefert ISO-8601-Strings (mit Sekundenbruchteilen), Codex Unix-Timestamps —
// `UsageWindow.resetsAt` transportiert beide als String; hier werden beide geparst.

import Foundation

public enum ResetFormatter {
    // ISO8601DateFormatter ist thread-safe und teuer im Aufbau -> einmalig anlegen
    // (parse läuft pro Menü-Render pro Account).
    // nonisolated(unsafe) ist hier korrekt: ISO8601DateFormatter ist laut Doku thread-safe.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let isoPlain = ISO8601DateFormatter()

    /// Parst ISO-8601 (mit/ohne Sekundenbruchteile) oder einen Unix-Timestamp-String.
    public static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let date = isoFractional.date(from: trimmed) { return date }
        if let date = isoPlain.date(from: trimmed) { return date }
        if let unix = Double(trimmed), unix > 1_000_000_000 {
            return Date(timeIntervalSince1970: unix)
        }
        return nil
    }

    /// Kurzer Countdown bis zum Reset ("6d 21h", "4h 49m", "12m"), oder nil
    /// wenn nicht parsebar bzw. bereits in der Vergangenheit.
    public static func shortCountdown(from raw: String?, now: Date = Date()) -> String? {
        guard let raw, let target = parse(raw) else { return nil }
        let total = Int(target.timeIntervalSince(now))
        guard total > 0 else { return nil }
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
