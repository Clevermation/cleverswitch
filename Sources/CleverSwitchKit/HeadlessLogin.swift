// Führt einen interaktiven CLI-Login unsichtbar im Hintergrund aus — abbrechbar.
//
// Die Login-Flows von `claude auth login` / `codex login` öffnen selbst den Browser und
// schließen ohne Terminal-Eingabe ab — ein Terminal-Fenster ist also unnötig. Manche CLIs
// verlangen aber ein TTY; deshalb läuft der Prozess unter `/usr/bin/script` (Pseudo-TTY).
//
// `cancel()` (manuell oder per Timeout) beendet den GANZEN Prozessbaum: erst den Kindprozess
// (die eigentliche CLI unter `script`), dann `script` selbst — sonst bliebe die CLI verwaist
// im Hintergrund hängen.

import Foundation

public final class HeadlessLogin: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Startet den Login headless. true bei Exit 0 (erfolgreich), false bei Fehler/Abbruch.
    public func run(command: [String], timeout: TimeInterval = 300) async -> Bool {
        guard !command.isEmpty else { return false }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = ["-q", "/dev/null"] + command
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            let resumed = Locked(false)
            // Timeout-Wächter: bricht nach `timeout` ab; wird bei normalem Ende gecancelt.
            let timeoutItem = DispatchWorkItem { [weak self] in self?.cancel() }
            let timeoutBox = SendableBox(timeoutItem)
            process.terminationHandler = { [weak self] proc in
                timeoutBox.value.cancel()
                if resumed.exchange(true) { return }
                let ok = (self?.wasCancelled == false) && proc.terminationStatus == 0
                continuation.resume(returning: ok)
            }
            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                if !resumed.exchange(true) { continuation.resume(returning: false) }
                return
            }
            // Falls cancel() bereits vor process.run() kam: jetzt nachholen.
            if wasCancelled { killTree() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
        }
    }

    /// Bricht den Login ab und beendet den kompletten Prozessbaum.
    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        killTree()
    }

    private func killTree() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        guard pid > 0 else {
            process.terminate()
            return
        }
        // Kindprozesse (die CLI unter `script`) zuerst, dann `script` selbst.
        Subprocess.run("/usr/bin/pkill", ["-TERM", "-P", "\(pid)"])
        process.terminate()
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
