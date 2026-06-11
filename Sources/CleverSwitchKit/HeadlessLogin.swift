// Führt einen interaktiven CLI-Login unsichtbar im Hintergrund aus.
//
// Die Login-Flows von `claude auth login` / `codex login` öffnen selbst den Browser und
// schließen ohne Terminal-Eingabe ab — ein Terminal-Fenster ist also unnötig. Manche CLIs
// verlangen aber ein TTY; deshalb läuft der Prozess unter `/usr/bin/script` (Pseudo-TTY).

import Foundation

public enum HeadlessLogin {
    /// Startet den Login-Befehl headless. Liefert true bei Exit-Code 0 (Login erfolgreich).
    public static func run(command: [String], timeout: TimeInterval = 300) async -> Bool {
        guard !command.isEmpty else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null"] + command
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            let finished = Locked(false)
            // Timeout-Wächter als WorkItem: wird bei normalem Ende gecancelt, damit weder
            // ein nutzloser Timer 5 Minuten liegen bleibt noch parallel auf den (nicht
            // thread-sicheren) Process zugegriffen wird.
            let timeoutItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()  // terminationHandler feuert und antwortet mit false
                }
            }
            // DispatchWorkItem.cancel() ist thread-safe; Box nur für Swift-6-Sendable-Check.
            let timeoutBox = SendableBox(timeoutItem)
            process.terminationHandler = { proc in
                timeoutBox.value.cancel()
                if finished.exchange(true) { return }
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                if !finished.exchange(true) { continuation.resume(returning: false) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        }
    }
}

/// Hüllt einen thread-sicheren Wert für Swift-6-Sendable-Checks ein.
final class SendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Minimaler threadsicherer Bool-Container (für den Continuation-Schutz).
final class Locked: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) { self.value = value }

    /// Setzt den Wert und liefert den vorherigen.
    func exchange(_ newValue: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = newValue
        return old
    }
}
