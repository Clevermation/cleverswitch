// Kleiner synchroner Subprozess-Helfer (für das `security`-CLI u.ä.).

import Foundation

public enum Subprocess {
    public struct Result: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
    }

    /// Führt ein Kommando aus und liefert Exit-Code + Ausgaben.
    /// `stdin` wird (falls gesetzt) in den Prozess geschrieben — fuer Secrets nutzen,
    /// damit sie nie in argv landen (argv ist fuer alle lokalen Prozesse via ps sichtbar).
    @discardableResult
    public static func run(_ executable: String, _ arguments: [String], stdin: String? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let input = Pipe()
        if stdin != nil { process.standardInput = input }
        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: "\(error)")
        }
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
