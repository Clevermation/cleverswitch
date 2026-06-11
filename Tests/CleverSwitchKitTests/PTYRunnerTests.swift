import Foundation
import Testing

@testable import CleverSwitchKit

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    func append(_ text: String) {
        lock.lock()
        buffer += text
        lock.unlock()
    }
    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

@Suite("PTY-Bridge")
struct PTYRunnerTests {
    @Test("CLI sieht ein TTY, send() wird als stdin gelesen")
    func bridgeReadsInput() async {
        let pty = PTYRunner()
        let out = OutputCollector()
        let started = pty.start(
            command: ["/bin/sh", "-c", "printf 'PROMPT> '; read code; echo RECEIVED:$code"]
        ) { out.append($0) }
        #expect(started)

        try? await Task.sleep(for: .milliseconds(400))
        pty.send("hello-123\n")
        try? await Task.sleep(for: .milliseconds(600))

        let text = out.value
        pty.terminate()
        #expect(text.contains("PROMPT>"))
        #expect(text.contains("RECEIVED:hello-123"))
    }

    @Test("ungültiges Kommando -> start false")
    func invalidCommand() {
        let pty = PTYRunner()
        let ok = pty.start(command: []) { _ in }
        #expect(ok == false)
    }
}
