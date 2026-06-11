// Zustands- und Steuerungsmodell der App. Bindet die reine Kit-Logik (Policy, Provider,
// SwitchService, Store) an die UI: Import, Reconcile, Usage-Poll, Umschalten, Auto-Switch,
// Headless-Login mit automatischem Import.

import AppKit
import CleverSwitchKit
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    private(set) var state: PersistedState
    private(set) var usage: [String: AccountUsage] = [:]
    private(set) var statusMessage: String?
    private(set) var loginInProgress: Set<String> = []
    // Gespeichert statt berechnet: nur gespeicherte Properties sind @Observable —
    // sonst aktualisiert sich das Häkchen im Menü nach dem Klick nicht.
    private(set) var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    let providers: [AccountProvider]
    private let store: StateStore
    private let credentials: CredentialStore
    private let http: HTTPClient
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var lastAutoSwitchAt: [String: Date] = [:]
    private var nearLimitWarned: Set<String> = []  // Frühwarnung pro Anbieter einmal pro Engpass
    private var loginSessions: [String: HeadlessLogin] = [:]  // laufende Logins (abbrechbar)

    private static let pollInterval: Duration = .seconds(300)
    private static let autoSwitchCooldown: TimeInterval = 60

    init(
        store: StateStore = StateStore(url: StateStore.defaultURL()),
        credentials: CredentialStore = SecurityCLICredentialStore(),
        http: HTTPClient = LiveHTTPClient(),
        providers: [AccountProvider] = [ClaudeProvider(), CodexProvider()]
    ) {
        self.store = store
        self.credentials = credentials
        self.http = http
        self.providers = providers
        self.state = store.load()
        // Reconcile + erster Usage-Fetch laufen async: Keychain-Subprozesse (und ein evtl.
        // Keychain-Dialog) dürfen den MainActor beim Start nicht blockieren.
        Task {
            await self.reconcileLiveIdentities()
            await self.refreshUsage()
        }
        startPolling()
    }

    // MARK: - Lookups fürs Menü

    func provider(_ id: String) -> AccountProvider? { providers.first { $0.id == id } }
    func accounts(for provider: AccountProvider) -> [Account] { state.accounts(provider: provider.id) }
    func mode(for provider: AccountProvider) -> SwitchMode { state.settings.mode(for: provider.id) }

    var removableAccounts: [Account] { state.accounts.filter { !$0.active } }

    /// Usage-Kurztext für die Menüzeile, z.B. "5h 21% (4h 49m) · 7d 45% (5d 20h)".
    func usageText(for account: Account) -> String {
        guard let snapshot = usage[account.id], snapshot.known,
            let provider = provider(account.provider)
        else { return L10n.t("usage_unknown") }
        var parts: [String] = []
        for (key, label) in [
            (UsageWindowKey.session, provider.sessionWindowLabel),
            (UsageWindowKey.weekly, provider.weeklyWindowLabel),
        ] {
            guard let pct = snapshot.pct(key) else { continue }
            let resetsAt = snapshot.windows.first { $0.key == key }?.resetsAt
            let countdown = ResetFormatter.shortCountdown(from: resetsAt).map { " (\($0))" } ?? ""
            parts.append("\(label) \(Int(pct))%\(countdown)")
        }
        return parts.isEmpty ? L10n.t("usage_unknown") : parts.joined(separator: " · ")
    }

    /// Kompakter Text neben dem Menüleisten-Icon: höchste Session-Auslastung unter ALLEN
    /// aktiven Accounts (also der, der gerade am nächsten an seinem Limit ist).
    var menuBarText: String? {
        let sessions = state.accounts
            .filter(\.active)
            .compactMap { usage[$0.id]?.pct(UsageWindowKey.session) }
        guard let worst = sessions.max() else { return nil }
        return "\(Int(worst))%"
    }

    private func persist() {
        do {
            try store.save(state)
        } catch {
            statusMessage = L10n.t("save_failed")
            Log.info("persist FEHLER: \(error)")
        }
    }

    // MARK: - Einstellungen (Anzeige/Notifications)

    var notificationsEnabled: Bool { state.settings.notificationsEnabled }
    var showEmail: Bool { state.settings.showEmail }

    /// Anzeigeform eines Handles: voll oder maskiert (je nach „E-Mail anzeigen").
    func displayHandle(_ handle: String) -> String {
        state.settings.showEmail ? handle : AccountHandle.masked(handle)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        state.settings.notificationsEnabled = enabled
        if enabled { Notifier.requestAuthorization() }
        persist()
    }

    func setShowEmail(_ show: Bool) {
        state.settings.showEmail = show
        persist()
    }

    // MARK: - Import & Reconcile

    /// Gleicht den Live-Slot mit der Account-Liste ab (Start, nach Logins): unbekannte
    /// Live-Identität -> importieren; bekannte, aber nicht aktive -> aktiv markieren.
    /// Keychain-/Datei-I/O läuft detached, nur die `state`-Mutation auf dem MainActor.
    func reconcileLiveIdentities() async {
        for provider in providers {
            let credentials = self.credentials
            let identity = await Task.detached { provider.currentIdentity(credentials: credentials) }.value
            guard let identity else { continue }
            if state.activeAccount(provider: provider.id)?.handle == identity.handle { continue }
            await adopt(identity: identity, for: provider)
        }
    }

    /// Übernimmt den aktuell eingeloggten Account des Anbieters in Liste + Snapshot.
    func importCurrentLogin(for provider: AccountProvider) async {
        let credentials = self.credentials
        let identity = await Task.detached {
            provider.currentIdentity(credentials: credentials)
        }.value
        guard let identity else { return }
        await adopt(identity: identity, for: provider)
        await refreshUsage()
    }

    private func adopt(identity: AccountIdentity, for provider: AccountProvider) async {
        // Handle aus externer Quelle (JWT/JSON) — Steuerzeichen ablehnen (Injection-Schutz).
        guard AccountHandle.isValid(identity.handle) else {
            Log.info("import abgelehnt: ungültiger Handle für \(provider.id)")
            return
        }
        let credentials = self.credentials
        await Task.detached {
            if let live = provider.readLive(credentials: credentials) {
                try? credentials.write(
                    service: provider.snapshotService(handle: identity.handle),
                    account: identity.handle, secret: live)
            }
        }.value
        Log.info("import/reconcile: \(provider.id) \(identity.handle)")
        if let index = state.accounts.firstIndex(where: {
            $0.provider == provider.id && $0.handle == identity.handle
        }) {
            if !identity.label.isEmpty { state.accounts[index].label = identity.label }
            if let payload = identity.sessionPayload { state.accounts[index].sessionPayload = payload }
        } else {
            state.accounts.append(
                Account(
                    provider: provider.id, handle: identity.handle, label: identity.label,
                    active: false, credentialKey: identity.handle,
                    sessionPayload: identity.sessionPayload))
        }
        setActive(identity.handle, provider: provider.id)
    }

    // MARK: - Usage / Poll

    func refreshUsage(allowAutoSwitch: Bool = true) async {
        // Überlappende Refreshes (Poll-Timer + Menü + nach Switch/Login) serialisieren:
        // läuft schon einer, nur darauf warten statt parallel zu arbeiten.
        if let running = refreshTask {
            await running.value
            return
        }
        let task = Task { await performRefresh(allowAutoSwitch: allowAutoSwitch) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Holt Usage für alle Accounts (OHNE Auto-Switch-Auswertung). Reentrant-sicher: berührt
    /// `refreshTask` nicht und darf daher auch aus dem Switch-Pfad heraus aufgerufen werden.
    private func fetchAllUsage() async {
        var labelUpdates: [(provider: String, handle: String, label: String)] = []
        for provider in providers {
            for account in state.accounts(provider: provider.id) {
                // Keychain-Subprozesse + HTTP gehören nicht auf den MainActor (UI-Freeze) —
                // die ganze Beschaffung läuft detached, nur die Mutationen bleiben hier.
                let credentials = self.credentials
                let http = self.http
                let outcome: UsageOutcome? = await Task.detached {
                    let snapshotService = provider.snapshotService(handle: account.handle)
                    let blob =
                        account.active
                        ? provider.readLive(credentials: credentials)
                        : credentials.read(service: snapshotService)
                    guard let blob else { return nil }
                    let outcome = await provider.fetchUsage(blob: blob, http: http)
                    if let refreshed = outcome.refreshedBlob {
                        if account.active {
                            try? provider.writeLive(
                                refreshed, handle: account.handle, credentials: credentials)
                        } else {
                            try? credentials.write(
                                service: snapshotService, account: account.handle, secret: refreshed)
                        }
                    }
                    return outcome
                }.value

                // Direkt in `usage` schreiben (kein Sammel-Snapshot): parallele Mutationen
                // wie remove() gehen sonst zwischen den await-Punkten verloren.
                usage[account.id] = outcome?.usage ?? .unknown
                if let plan = outcome?.planLabel, !plan.isEmpty, plan != account.label {
                    labelUpdates.append((account.provider, account.handle, plan))
                }
            }
        }
        // Plan-Labels aus der Live-Antwort übernehmen (Token-Claims können veraltet sein).
        if !labelUpdates.isEmpty {
            for update in labelUpdates {
                if let index = state.accounts.firstIndex(where: {
                    $0.provider == update.provider && $0.handle == update.handle
                }) {
                    state.accounts[index].label = update.label
                }
            }
            persist()
        }
        syncLaunchAtLogin()  // hält das Häkchen aktuell, auch bei Änderung via System Settings
    }

    private func performRefresh(allowAutoSwitch: Bool) async {
        await fetchAllUsage()
        if allowAutoSwitch { await evaluateAutoSwitch() }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: AppModel.pollInterval)
                if Task.isCancelled { break }
                await self?.refreshUsage()
            }
        }
    }

    // MARK: - Umschalten

    func switchTo(_ target: Account) async {
        guard let provider = provider(target.provider) else { return }
        let current = state.activeAccount(provider: target.provider)
        guard current?.handle != target.handle else { return }
        do {
            let credentials = self.credentials
            let http = self.http
            try await Task.detached {
                try await SwitchService.activate(
                    target: target, current: current, provider: provider,
                    credentials: credentials, http: http)
            }.value
            setActive(target.handle, provider: target.provider)
            statusMessage = nil
            Log.info("switch: \(target.provider) -> \(target.handle)")
            // fetchAllUsage statt refreshUsage: kein Reentrancy auf den laufenden refreshTask
            // (Auto-Switch ruft switchTo aus performRefresh heraus auf -> sonst Deadlock).
            await fetchAllUsage()
        } catch let SwitchService.SwitchError.sessionExpired(handle) {
            statusMessage = L10n.t("session_expired", displayHandle(handle))
            Notifier.post(
                L10n.t("notif_session_expired_title"),
                L10n.t("session_expired", displayHandle(handle)), enabled: notificationsEnabled)
            Log.info("switch FEHLER: \(target.provider) \(handle) session expired")
        } catch {
            statusMessage = L10n.t("switch_failed")
            Log.info("switch FEHLER: \(target.provider) \(target.handle) \(error)")
        }
    }

    private func setActive(_ handle: String, provider providerID: String) {
        for index in state.accounts.indices where state.accounts[index].provider == providerID {
            state.accounts[index].active = (state.accounts[index].handle == handle)
        }
        persist()
    }

    // MARK: - Auto-Switch

    private func evaluateAutoSwitch() async {
        for provider in providers {
            let mode = state.settings.mode(for: provider.id)
            guard mode != .off, let active = state.activeAccount(provider: provider.id) else { continue }
            // Zeitlicher Cooldown gegen Hin-und-her-Schalten (SPEC F5).
            if let last = lastAutoSwitchAt[provider.id],
                Date().timeIntervalSince(last) < Self.autoSwitchCooldown {
                continue
            }
            let accounts = state.accounts(provider: provider.id)
            // Policy erwartet handle-Keys EINES Anbieters — Sub-Map bauen, damit
            // gleiche E-Mails bei verschiedenen Anbietern nicht kollidieren.
            let scopedUsage = Dictionary(
                uniqueKeysWithValues: accounts.map { ($0.handle, usage[$0.id] ?? AccountUsage.unknown) })
            let target = AutoSwitchPolicy.pickTarget(
                mode: mode,
                accounts: accounts,
                activeHandle: active.handle,
                usage: scopedUsage,
                hasCreds: { account in
                    self.credentials.read(service: provider.snapshotService(handle: account.handle)) != nil
                },
                config: state.settings.policy)
            if let target {
                lastAutoSwitchAt[provider.id] = Date()
                nearLimitWarned.remove(provider.id)
                Log.info("auto-switch (\(mode.rawValue)): \(provider.id) -> \(target.handle)")
                await switchTo(target)
                Notifier.post(
                    L10n.t("notif_switched_title"),
                    "\(provider.displayName): \(displayHandle(target.handle))",
                    enabled: notificationsEnabled)
                return  // höchstens ein Auto-Switch pro Durchlauf
            }
            // SPEC F5: Frühwarnung, wenn das aktive Konto nahe am Limit ist und KEIN gesundes
            // Ziel existiert — einmal pro Engpass (nicht bei jedem Poll spammen).
            if AutoSwitchPolicy.isNearLimit(usage[active.id], config: state.settings.policy) {
                if !nearLimitWarned.contains(provider.id) {
                    nearLimitWarned.insert(provider.id)
                    statusMessage = L10n.t("near_limit_no_target", displayHandle(active.handle))
                    Log.info("frühwarnung: \(provider.id) \(active.handle) nahe Limit, kein Ziel")
                    Notifier.post(
                        L10n.t("notif_near_limit_title"),
                        L10n.t("near_limit_no_target", displayHandle(active.handle)),
                        enabled: notificationsEnabled)
                }
            } else {
                nearLimitWarned.remove(provider.id)
            }
        }
    }

    // MARK: - Einstellungen / Add / Remove

    func setMode(_ mode: SwitchMode, for provider: AccountProvider) {
        state.settings.modes[provider.id] = mode
        persist()
    }

    /// Startet den CLI-Login unsichtbar im Hintergrund; importiert danach automatisch.
    func addAccount(for provider: AccountProvider) {
        guard !loginInProgress.contains(provider.id) else { return }
        guard let command = provider.loginCommand() else {
            statusMessage = L10n.t("cli_missing")
            return
        }

        let session = HeadlessLogin()
        loginSessions[provider.id] = session
        loginInProgress.insert(provider.id)
        statusMessage = nil  // Anzeige läuft über den abbrechbaren Menü-Eintrag, nicht die Statuszeile
        Log.info("login gestartet: \(provider.id)")

        let credentials = self.credentials
        let activeSnapshot = state.activeAccount(provider: provider.id)
        Task {
            // Aktiven Account sichern, BEVOR der Login den Live-Slot überschreibt (off-MainActor).
            await Task.detached {
                if let active = activeSnapshot, let live = provider.readLive(credentials: credentials) {
                    try? credentials.write(
                        service: provider.snapshotService(handle: active.handle),
                        account: active.handle, secret: live)
                }
            }.value

            let success = await session.run(command: command)
            let wasCancelled = session.wasCancelled
            self.loginSessions[provider.id] = nil
            self.loginInProgress.remove(provider.id)
            Log.info(
                "login \(success ? "erfolgreich" : wasCancelled ? "abgebrochen" : "fehlgeschlagen"): \(provider.id)")
            // Bei Abbruch keine Fehlermeldung. Bei Fehlschlag schon. In beiden Fällen reconcilen:
            // der Browser-Flow kann erfolgreich gewesen sein, während `script` per Timeout endete.
            self.statusMessage = (success || wasCancelled) ? nil : L10n.t("login_failed")
            await self.importCurrentLogin(for: provider)
        }
    }

    /// Bricht einen laufenden Login ab (beendet den Prozessbaum) und räumt die Anzeige auf.
    func cancelLogin(for provider: AccountProvider) {
        loginSessions[provider.id]?.cancel()
        // loginInProgress/statusMessage werden vom run()-Completion-Handler aufgeräumt.
    }

    // MARK: - Launch at Login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Log.info("launch-at-login: \(enabled ? "an" : "aus")")
        } catch {
            statusMessage = "\(error.localizedDescription)"
            Log.info("launch-at-login FEHLER: \(error)")
        }
        syncLaunchAtLogin()
    }

    /// Status frisch vom System lesen (kann sich auch über System Settings ändern).
    func syncLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func remove(_ account: Account) {
        guard !account.active else { return }
        if let provider = provider(account.provider) {
            credentials.delete(service: provider.snapshotService(handle: account.handle))
        }
        Log.info("entfernt: \(account.provider) \(account.handle)")
        state.accounts.removeAll { $0.provider == account.provider && $0.handle == account.handle }
        usage[account.id] = nil
        persist()
    }
}
