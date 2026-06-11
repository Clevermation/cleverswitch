// Führt den CLI-Login als NORMALEN Subprozess aus — kein PTY, kein Terminal, kein Fenster.
//
// Schlüssel-Erkenntnis (so machte es auch der alte Switcher): die Login-CLIs öffnen den Browser
// selbst und schließen über einen Hintergrund-Poll (state-Parameter) automatisch ab, sobald der
// User im Browser autorisiert. Das „Paste code here"-Feld ist nur ein Fallback. Mit `stdin=/dev/null`
// (statt eines PTYs) blockiert die CLI NICHT auf eine Eingabe, sondern pollt — Login klappt ohne
// jede sichtbare Oberfläche außer dem Browser.

import Foundation

public final class LoginProcess: @unchecked Sendable {
    private let process = Process()

    public init() {}

    public var isRunning: Bool { process.isRunning }

    /// Startet den Login-Befehl. `onOutput` bekommt die CLI-Ausgabe (für Logging/Browser-URL).
    /// Gibt false zurück, wenn der Start scheitert.
    public func start(
        command: [String],
        extraPATH: [String] = [],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) -> Bool {
        guard !command.isEmpty else { return false }

        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.standardInput = FileHandle.nullDevice  // KEIN TTY -> CLI pollt statt zu blockieren

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        if let onOutput {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) { onOutput(text) }
            }
        }

        var env = ProcessInfo.processInfo.environment
        if !extraPATH.isEmpty {
            env["PATH"] = (env["PATH"] ?? "") + ":" + extraPATH.joined(separator: ":")
        }
        process.environment = env

        process.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        do {
            try process.run()
        } catch {
            return false
        }
        return true
    }

    public func cancel() {
        guard process.isRunning else { return }
        // Kompletten Prozessbaum beenden: die Login-CLIs sind bun/node-Wrapper, die Kinder
        // spawnen — nur terminate() auf den Wurzelprozess liesse die weiterlaufen.
        Self.terminateTree(process.processIdentifier)
    }

    /// SIGTERM an `pid` und rekursiv an alle Nachfahren (Kinder zuerst).
    private static func terminateTree(_ pid: Int32) {
        let children = Subprocess.run("/usr/bin/pgrep", ["-P", "\(pid)"])
        for line in children.stdout.split(separator: "\n") {
            if let child = Int32(line.trimmingCharacters(in: .whitespaces)) {
                terminateTree(child)
            }
        }
        kill(pid, SIGTERM)
    }
}
