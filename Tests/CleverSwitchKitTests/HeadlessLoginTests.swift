import Foundation
import Testing

@testable import CleverSwitchKit

@Suite("Headless-Login (Abbruch)")
struct HeadlessLoginTests {
    @Test("cancel() beendet den Login schnell und liefert false")
    func cancelStopsLogin() async {
        let login = HeadlessLogin()
        async let result = login.run(command: ["/bin/sleep", "30"])
        // kurz anlaufen lassen, dann abbrechen
        try? await Task.sleep(for: .milliseconds(400))
        login.cancel()
        let ok = await result
        #expect(ok == false)
        #expect(login.wasCancelled == true)
    }

    @Test("leeres Kommando -> sofort false")
    func emptyCommandFails() async {
        let ok = await HeadlessLogin().run(command: [])
        #expect(ok == false)
    }

    @Test("erfolgreiches Kommando (Exit 0) -> true")
    func successfulCommand() async {
        let ok = await HeadlessLogin().run(command: ["/usr/bin/true"], timeout: 10)
        #expect(ok == true)
    }
}
