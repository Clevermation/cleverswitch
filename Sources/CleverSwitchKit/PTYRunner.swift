// Führt einen interaktiven CLI-Befehl unsichtbar unter einem Pseudo-Terminal (PTY) aus.
//
// Warum PTY: CLIs wie `claude auth login` prüfen, ob stdin ein TTY ist, und verlangen eines.
// Mit einem echten PTY läuft die CLI „interaktiv", ohne dass ein Terminal-Fenster sichtbar ist —
// die App liest die Ausgabe (z.B. die Browser-URL) und schreibt die Eingabe (den eingefügten
// Code) selbst in das PTY. So ersetzt ein natives CleverSwitch-Fenster das Terminal.

import Foundation

#if canImport(Darwin)
    import Darwin
#endif

public final class PTYRunner: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var masterFD: Int32 = -1
    private var source: DispatchSourceRead?

    public init() {}

    /// Startet `command` unter einem PTY. `onOutput` bekommt jeden Ausgabe-Chunk (UTF-8).
    /// `extraPATH` wird an die (minimale GUI-)PATH angehängt, damit die CLI ihre Tools findet.
    public func start(
        command: [String],
        extraPATH: [String] = [],
        onOutput: @escaping @Sendable (String) -> Void
    ) -> Bool {
        guard !command.isEmpty else { return false }

        var master: Int32 = 0
        var slave: Int32 = 0
        // Sehr breites PTY, damit lange Zeilen (z.B. die Login-URL) NICHT umgebrochen werden —
        // sonst landen \n mitten in der URL und das Auslesen scheitert.
        var size = winsize(ws_row: 60, ws_col: 1000, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { return false }

        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        var env = ProcessInfo.processInfo.environment
        if !extraPATH.isEmpty {
            env["PATH"] = ((env["PATH"] ?? "") + ":" + extraPATH.joined(separator: ":"))
        }
        env["TERM"] = "xterm-256color"
        process.environment = env

        do {
            try process.run()
        } catch {
            close(master)
            close(slave)
            return false
        }
        close(slave)  // Parent braucht den Slave nicht mehr (Child hat eine eigene Kopie).

        lock.lock()
        masterFD = master
        lock.unlock()

        let readSource = DispatchSource.makeReadSource(fileDescriptor: master, queue: .global())
        readSource.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(master, &buffer, buffer.count)
            if count > 0 {
                let text = String(decoding: buffer[0..<count], as: UTF8.self)
                onOutput(text)
            } else {
                self?.source?.cancel()
            }
        }
        readSource.setCancelHandler { close(master) }
        readSource.resume()
        source = readSource
        return true
    }

    /// Schreibt Text (z.B. den eingefügten Code + "\n") in das PTY (= stdin der CLI).
    public func send(_ text: String) {
        lock.lock()
        let fd = masterFD
        lock.unlock()
        guard fd >= 0 else { return }
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBytes { write(fd, $0.baseAddress, bytes.count) }
    }

    public var isRunning: Bool { process.isRunning }

    /// Beendet den Prozess und schließt das PTY.
    public func terminate() {
        if process.isRunning { process.terminate() }
        lock.lock()
        masterFD = -1
        lock.unlock()
        source?.cancel()
    }
}
