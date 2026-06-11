import Foundation
import Testing

@testable import CleverSwitchKit

@Suite("Persistenz (StateStore)")
struct StoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cleverswitch-test-\(UUID().uuidString)")
            .appendingPathComponent("state.json")
    }

    @Test("fehlende Datei -> leerer Default")
    func missingFileGivesDefault() {
        let store = StateStore(url: tempURL())
        let state = store.load()
        #expect(state.accounts.isEmpty)
        #expect(state.settings.mode(for: "claude") == .off)
    }

    @Test("save -> load Round-Trip")
    func roundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = StateStore(url: url)

        var settings = AppSettings()
        settings.modes["claude"] = .balance
        let state = PersistedState(
            accounts: [
                Account(provider: "claude", handle: "a@x.com", label: "max", active: true,
                        credentialKey: "claude:a@x.com"),
                Account(provider: "claude", handle: "b@x.com", label: "max",
                        credentialKey: "claude:b@x.com"),
            ],
            settings: settings
        )
        try store.save(state)

        let loaded = store.load()
        #expect(loaded == state)
        #expect(loaded.activeAccount(provider: "claude")?.handle == "a@x.com")
        #expect(loaded.accounts(provider: "claude").count == 2)
        #expect(loaded.settings.mode(for: "claude") == .balance)
    }

    @Test("Datei wird mit 0600-Rechten geschrieben")
    func filePermissions() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try StateStore(url: url).save(PersistedState())
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)
    }

    @Test("setting(_:for:) ändert nur einen Anbieter")
    func settingForProvider() {
        let settings = AppSettings().setting(.failover, for: "claude")
        #expect(settings.mode(for: "claude") == .failover)
        #expect(settings.mode(for: "codex") == .off)
    }

    @Test("menuBarSource: Default + Round-Trip + alte JSON ohne Feld")
    func menuBarSourcePersistence() throws {
        // Default ist "highest".
        #expect(AppSettings().menuBarSource == "highest")

        // Round-Trip über den Store.
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var settings = AppSettings()
        settings.menuBarSource = "codex"
        try StateStore(url: url).save(PersistedState(settings: settings))
        #expect(StateStore(url: url).load().settings.menuBarSource == "codex")

        // Alte state.json ohne das Feld -> faellt auf "highest" zurueck.
        let legacy = #"{"notificationsEnabled":true,"showEmail":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(decoded.menuBarSource == "highest")
    }
}
