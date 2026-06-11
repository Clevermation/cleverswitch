// Einfaches Datei-Logging nach ~/Library/Logs/CleverSwitch.log.
// Bewusst minimal: Zeitstempel + Zeile, append-only, Rotation bei 1 MB.

import Foundation

enum Log {
    private static let url = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/CleverSwitch.log")
    private static let maxBytes = 1_000_000
    private static let queue = DispatchQueue(label: "cleverswitch.log")

    // ISO8601DateFormatter ist laut Doku thread-safe.
    nonisolated(unsafe) private static let formatter = ISO8601DateFormatter()

    static func info(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            rotateIfNeeded()
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                // Log enthält E-Mail-Adressen (PII) -> Datei direkt mit 0600 anlegen
                // (kein Race-Window zwischen Schreiben und nachträglichem chmod).
                FileManager.default.createFile(
                    atPath: url.path, contents: Data(line.utf8),
                    attributes: [.posixPermissions: 0o600])
            }
        }
    }

    private static func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
            size > maxBytes
        else { return }
        let old = url.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
}
