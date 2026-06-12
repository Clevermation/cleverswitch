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
    /// Anbieter mit gerade laufendem Login (für die Menü-Statuszeile).
    private(set) var loginInProgress: Set<String> = []
    // Gespeichert statt berechnet: nur gespeicherte Properties sind @Observable —
    // sonst aktualisiert sich das Häkchen im Menü nach dem Klick nicht.
    private(set) var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    /// Tatsächliche macOS-Benachrichtigungs-Berechtigung (live abgefragt). Wird mit dem
    /// gespeicherten Wunsch (`notificationsEnabled`) zu `notificationsActive` kombiniert, damit
    /// das Häkchen nicht „lügt", wenn die Berechtigung in den Systemeinstellungen entzogen wurde.
    private(set) var notificationsAuthorized: Bool = true
    /// True genau dann, wenn beim Start noch keine state.json existierte (allererster Start).
    private let isFirstLaunch: Bool

    let providers: [AccountProvider]
    private let store: StateStore
    private let credentials: CredentialStore
    private let http: HTTPClient
    private var pollTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var lastAutoSwitchAt: [String: Date] = [:]
    private var nearLimitWarned: Set<String> = []  // Frühwarnung pro Anbieter einmal pro Engpass
    private var loginProcesses: [String: LoginProcess] = [:]  // laufende Login-Subprozesse
    private var loginWatchTasks: [String: Task<Void, Never>] = [:]  // beobachten den Login-Abschluss
    private var refreshBackoffUntil: [String: Date] = [:]  // Account-ID -> kein Refresh vor diesem Zeitpunkt
    private static let refreshBackoff: TimeInterval = 900  // 15 Min Pause nach gescheitertem Refresh

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
        // VOR dem ersten persist() festhalten, ob das ein allererster Start ist
        // (state.json existiert noch nicht) — Trigger für das Onboarding.
        let firstLaunch = !FileManager.default.fileExists(atPath: store.url.path)
        self.isFirstLaunch = firstLaunch
        self.state = store.load()
        // Benachrichtigungs-Berechtigung früh anfragen, wenn aktiviert (sonst erscheint die
        // Nachfrage nie und Notifications bleiben still — genau das ist Theo passiert).
        if self.state.settings.notificationsEnabled {
            Notifier.requestAuthorization()
            syncNotifications()
        }
        // Reconcile + erster Usage-Fetch laufen async: Keychain-Subprozesse (und ein evtl.
        // Keychain-Dialog) dürfen den MainActor beim Start nicht blockieren.
        Task {
            await self.detectCLIs()  // früh, damit das Onboarding den CLI-Status zeigen kann
            await self.reconcileLiveIdentities()
            // Allererster Start ODER (noch) keine Accounts -> geführte Ersteinrichtung
            // SOFORT zeigen, nicht erst nach dem mehrsekündigen Usage-Fetch. Auto-importierte
            // CLI-Logins (Reconcile) zählen nicht als „kennt die App schon".
            if self.isFirstLaunch || self.state.accounts.isEmpty {
                OnboardingWindow.show(model: self)
            }
            await self.refreshUsage()
        }
        startPolling()
        // Minuten-Tick für die relative „Aktualisiert vor X"-Zeile.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.clockTick = Date()
            }
        }
    }

    // MARK: - Lookups fürs Menü

    func provider(_ id: String) -> AccountProvider? { providers.first { $0.id == id } }
    func accounts(for provider: AccountProvider) -> [Account] { state.accounts(provider: provider.id) }
    func mode(for provider: AccountProvider) -> SwitchMode { state.settings.mode(for: provider.id) }

    var removableAccounts: [Account] { state.accounts.filter { !$0.active } }

    /// Kompakter Text neben dem Menüleisten-Icon: höchste Session-Auslastung. Welche Accounts
    /// einbezogen werden, steuert `menuBarSource` ("highest" = alle aktiven, sonst nur ein Anbieter).
    var menuBarText: String? {
        let source = state.settings.menuBarSource
        let active = state.accounts.filter(\.active)
        // Liefert die Quelle nichts (Anbieter ohne aktiven Account, veralteter Wert in
        // state.json), auf alle aktiven zurückfallen statt still gar nichts anzuzeigen.
        var scoped = source == "highest" ? active : active.filter { $0.provider == source }
        if scoped.isEmpty { scoped = active }
        let sessions = scoped.compactMap { usage[$0.id]?.pct(UsageWindowKey.session) }
        guard let worst = sessions.max() else { return nil }
        return "\(Int(worst))%"
    }

    var menuBarSource: String { state.settings.menuBarSource }
    func setMenuBarSource(_ source: String) {
        state.settings.menuBarSource = source
        persist()
    }

    /// Zeitpunkt des letzten erfolgreichen Usage-Abrufs (für die „zuletzt aktualisiert"-Zeile).
    private(set) var lastRefreshAt: Date?
    /// Minuten-Tick: @Observable trackt kein Date() — ohne gespeicherte, tickende Abhängigkeit
    /// friert die relative Anzeige zwischen zwei Polls auf dem alten Wert ein.
    private(set) var clockTick = Date()
    /// Relative „vor X" Anzeige. Wird bei jedem Menü-Öffnen frisch berechnet.
    var lastUpdatedText: String? {
        _ = clockTick  // Abhängigkeit registrieren (invalidiert die Zeile pro Minute)
        guard let at = lastRefreshAt else { return nil }
        let secs = Int(Date().timeIntervalSince(at))
        if secs < 60 { return L10n.t("updated_just_now") }
        if secs < 3600 { return L10n.t("last_updated", "\(secs / 60) min") }
        return L10n.t("last_updated", "\(secs / 3600) h")
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
    /// Effektiver Zustand fürs Menü-Häkchen: gewünscht UND vom System erlaubt.
    var notificationsActive: Bool { notificationsEnabled && notificationsAuthorized }
    var showEmail: Bool { state.settings.showEmail }

    /// Anzeigeform eines Handles: voll oder maskiert (je nach „E-Mail anzeigen").
    func displayHandle(_ handle: String) -> String {
        state.settings.showEmail ? handle : AccountHandle.masked(handle)
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        state.settings.notificationsEnabled = enabled
        if enabled {
            // Berechtigung anfragen. Wurde sie früher abgelehnt, zeigt macOS keinen Dialog mehr —
            // dann den Systemeinstellungen-Bereich öffnen, damit der Nutzer sie erteilen kann.
            Notifier.requestAuthorization { [weak self] granted in
                Task { @MainActor in
                    self?.notificationsAuthorized = granted
                    if !granted { self?.openNotificationSettings() }
                }
            }
        } else {
            notificationsAuthorized = true  // Wunsch ist aus -> kein „abgewiesen"-Zustand
        }
        persist()
    }

    /// Gleicht `notificationsAuthorized` mit dem echten System-Status ab (z.B. nach Entzug in den
    /// Systemeinstellungen). Läuft bei jedem Poll mit.
    func syncNotifications() {
        guard state.settings.notificationsEnabled else {
            notificationsAuthorized = true
            return
        }
        Notifier.authorizationStatus { [weak self] ok in
            Task { @MainActor in self?.notificationsAuthorized = ok }
        }
    }

    /// Öffnet den Benachrichtigungs-Bereich der Systemeinstellungen.
    private func openNotificationSettings() {
        // Seit macOS 13 heißt das Pane so — die alte preference.notifications-URL landet
        // nur noch auf der Startseite der Systemeinstellungen.
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
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
            // Doppelte Live-Slot-Einträge bereinigen (frischesten Token nach vorne) — sonst liest
            // `security -w` evtl. einen alten, abgelaufenen Token (claude-login-Duplikate).
            await Task.detached { provider.consolidateLive(credentials: credentials) }.value
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
                // Refresh nur erlauben, wenn dieser Account nicht im Backoff steckt. Sonst würde
                // ein abgelaufener Token bei JEDEM Poll erneut einen (rate-limitierten) Refresh
                // auslösen — und das Rate-Limit damit dauerhaft am Leben halten.
                let allowRefresh = (refreshBackoffUntil[account.id].map { $0 <= Date() } ?? true)
                let outcome: UsageOutcome? = await Task.detached {
                    let snapshotService = provider.snapshotService(handle: account.handle)
                    let blob =
                        account.active
                        ? provider.readLive(credentials: credentials)
                        : credentials.read(service: snapshotService)
                    guard let blob else { return nil }
                    return await provider.fetchUsage(
                        blob: blob, http: http, allowRefresh: allowRefresh)
                }.value

                // Erneuerten Blob nach dem AKTUELLEN Zustand routen, nicht nach dem von vor dem
                // Fetch: hat der User währenddessen gewechselt, würde der Blob sonst den
                // Live-Slot des NEUEN aktiven Accounts überschreiben (Token-Vermischung).
                if let refreshed = outcome?.refreshedBlob,
                    let nowAccount = state.accounts.first(where: { $0.id == account.id })
                {
                    await Task.detached {
                        if nowAccount.active {
                            try? provider.writeLive(
                                refreshed, handle: nowAccount.handle, credentials: credentials)
                        } else {
                            try? credentials.write(
                                service: provider.snapshotService(handle: nowAccount.handle),
                                account: nowAccount.handle, secret: refreshed)
                        }
                    }.value
                }

                // Direkt in `usage` schreiben (kein Sammel-Snapshot): parallele Mutationen
                // wie remove() gehen sonst zwischen den await-Punkten verloren. Wurde der
                // Account WÄHREND des Fetch entfernt, keinen stalen Eintrag wieder anlegen.
                guard state.accounts.contains(where: { $0.id == account.id }) else { continue }
                usage[account.id] = outcome?.usage ?? .unknown
                if let plan = outcome?.planLabel, !plan.isEmpty, plan != account.label {
                    labelUpdates.append((account.provider, account.handle, plan))
                }
                // Backoff steuern: gescheiterter Refresh -> Pause; Erfolg -> Pause löschen.
                if outcome?.refreshFailed == true {
                    refreshBackoffUntil[account.id] = Date().addingTimeInterval(Self.refreshBackoff)
                    Log.info("usage refresh backoff (\(Int(Self.refreshBackoff / 60))min): \(account.id)")
                } else if outcome?.usage.known == true {
                    refreshBackoffUntil[account.id] = nil
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
        lastRefreshAt = Date()
        syncLaunchAtLogin()  // hält das Häkchen aktuell, auch bei Änderung via System Settings
        syncNotifications()  // dito für die Benachrichtigungs-Berechtigung
    }

    private func performRefresh(allowAutoSwitch: Bool) async {
        await fetchAllUsage()
        if allowAutoSwitch { await evaluateAutoSwitch() }
        await checkForUpdateIfDue()
        await detectCLIs()
    }

    /// Manuelles „Usage aktualisieren": setzt den Refresh-Backoff zurück und holt sofort neu —
    /// der User will JETZT eine Antwort, nicht erst nach Ablauf der Backoff-Pause.
    func forceRefresh() {
        refreshBackoffUntil.removeAll()
        Task { await refreshUsage() }
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
                L10n.t("session_expired", displayHandle(handle)), enabled: notificationsActive)
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
                    enabled: notificationsActive)
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
                        enabled: notificationsActive)
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

    // Gemeinsame CLI-Pfadliste aus dem Kit (eine Quelle, auch von findExecutable genutzt).
    private static let cliSearchPATH = ClaudeProvider.cliSearchPaths

    /// Startet den offiziellen CLI-Login als normalen Subprozess (KEIN Terminal, KEIN Fenster):
    /// Die CLI öffnet den Browser selbst und schließt per Hintergrund-Poll automatisch ab. Den
    /// Abschluss erkennt die App selbst (neue Identität im Live-Slot) und importiert automatisch.
    func addAccount(for provider: AccountProvider) {
        guard !loginInProgress.contains(provider.id) else { return }
        guard let command = provider.loginCommand() else {
            statusMessage = L10n.t("cli_missing")
            return
        }
        Log.info("login gestartet: \(provider.id)")

        let credentials = self.credentials
        let before = state.activeAccount(provider: provider.id)?.handle
        // Aktiven Account sichern, BEVOR der Login den Live-Slot überschreibt.
        if let before, let live = provider.readLive(credentials: credentials) {
            try? credentials.write(
                service: provider.snapshotService(handle: before), account: before, secret: live)
        }

        let process = LoginProcess()
        let started = process.start(command: command, extraPATH: Self.cliSearchPATH) { chunk in
            // Keine URLs loggen: die Login-CLI gibt OAuth-Redirect-URLs aus (state/code-Parameter)
            // — die gehören nicht persistiert ins Log.
            let safe = chunk
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.contains("://") }
                .joined(separator: " ")
            if !safe.isEmpty { Log.info("login-cli: \(safe.prefix(120))") }
        }
        guard started else {
            statusMessage = L10n.t("cli_missing")
            return
        }
        loginProcesses[provider.id] = process
        loginInProgress.insert(provider.id)
        // Klarer Hinweis: der Browser öffnet sich – dort muss der User autorisieren. Ohne das
        // bleibt der Login hängen (der häufigste Stolperstein beim fensterlosen Flow).
        statusMessage = L10n.t("login_browser_hint")
        Notifier.post(
            L10n.t("login_title", provider.displayName), L10n.t("login_browser_hint"),
            enabled: notificationsActive)
        loginWatchTasks[provider.id] = Task { await watchLogin(for: provider, before: before) }
    }

    func cancelLogin(for provider: AccountProvider) {
        Log.info("login abgebrochen: \(provider.id)")
        finishLogin(for: provider.id, error: nil)
    }

    private static let loginWatchTimeout: TimeInterval = 240
    private static let loginPollInterval: Duration = .seconds(2)

    private func watchLogin(for provider: AccountProvider, before: String?) async {
        let credentials = self.credentials
        let deadline = Date().addingTimeInterval(Self.loginWatchTimeout)
        while Date() < deadline {
            try? await Task.sleep(for: Self.loginPollInterval)
            if Task.isCancelled { return }
            let identity = await Task.detached { provider.currentIdentity(credentials: credentials) }.value
            // Cancel (User-Abbruch) kann während des detached-Awaits passieren — danach nichts
            // mehr adoptieren, sonst importiert ein abgebrochener Login trotzdem einen Account.
            if Task.isCancelled { return }
            if let identity, identity.handle != before {
                Log.info("login erkannt: \(provider.id) \(identity.handle)")
                // Der Login hat einen frischen Token-Eintrag angelegt — Duplikate bereinigen,
                // damit der Live-Slot den NEUEN (gültigen) Token liefert, nicht den alten.
                await Task.detached { provider.consolidateLive(credentials: credentials) }.value
                await adopt(identity: identity, for: provider)
                await refreshUsage()
                finishLogin(for: provider.id, error: nil)
                return
            }
        }
        Log.info("login timeout: \(provider.id)")
        finishLogin(for: provider.id, error: L10n.t("login_failed"))
    }

    /// Räumt Login-Subprozess + Beobachtung für einen Anbieter auf.
    private func finishLogin(for providerID: String, error: String?) {
        loginWatchTasks[providerID]?.cancel()
        loginWatchTasks[providerID] = nil
        loginProcesses[providerID]?.cancel()
        loginProcesses[providerID] = nil
        loginInProgress.remove(providerID)
        statusMessage = error  // nil bei Erfolg/Abbruch -> löscht den „Browser-Tab"-Hinweis
    }

    // MARK: - Update-Check (GitHub Releases) + brew-Update

    /// Neuere verfügbare Version (z.B. "0.2.0"), oder nil. Gespeichert -> @Observable.
    private(set) var updateAvailable: String?
    private(set) var updateInProgress = false
    private var lastUpdateCheckAt: Date?
    private static let updateCheckInterval: TimeInterval = 6 * 3600  // 6 h reicht völlig

    /// Prüft höchstens alle 6 h gegen die GitHub-Releases-API (läuft im Poll mit).
    private func checkForUpdateIfDue() async {
        if let last = lastUpdateCheckAt, Date().timeIntervalSince(last) < Self.updateCheckInterval {
            return
        }
        lastUpdateCheckAt = Date()
        let http = self.http
        await refreshCLILatestVersions()  // CLI-Versionen im selben Rhythmus prüfen
        let found = await Task.detached {
            await UpdateChecker.check(current: cleverSwitchVersion, http: http)
        }.value
        if let found {
            updateAvailable = found
            Log.info("update verfügbar: \(found) (installiert: \(cleverSwitchVersion))")
        }
    }

    /// Bis wann „auf dem neuesten Stand" angezeigt wird (gesetzt nach manueller Prüfung
    /// ohne Fund; läuft mit dem nächsten 6-h-Fenster ab).
    private(set) var upToDateUntil: Date?
    var showUpToDate: Bool {
        _ = clockTick  // Minuten-Tick als Abhängigkeit, damit der Zustand von selbst abläuft
        guard updateAvailable == nil, let until = upToDateUntil else { return false }
        return until > Date()
    }

    /// Manuelle Prüfung (Einstellungen) — zeigt danach „auf dem neuesten Stand" im Menü.
    func checkForUpdateNow() {
        lastUpdateCheckAt = nil
        Task {
            await checkForUpdateIfDue()
            if updateAvailable == nil {
                upToDateUntil = Date().addingTimeInterval(Self.updateCheckInterval)
            }
        }
    }

    /// Installiert das Update über Homebrew und startet die App danach neu.
    /// Schlägt brew fehl (oder ist die App manuell installiert), öffnet die Releases-Seite.
    func installUpdate() {
        guard !updateInProgress else { return }
        updateInProgress = true
        statusMessage = L10n.t("update_running")
        Log.info("update gestartet (brew upgrade)")
        Task {
            let ok = await Task.detached { () -> Bool in
                let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
                    .first { FileManager.default.isExecutableFile(atPath: $0) }
                guard let brew else { return false }
                let result = Subprocess.run(
                    brew, ["upgrade", "--cask", "clevermation/tap/cleverswitch"])
                if result.status != 0 {
                    Log.info("brew upgrade fehlgeschlagen: \(result.stderr.prefix(200))")
                }
                return result.status == 0
            }.value
            if ok {
                // Neue Version liegt in /Applications -> frische Instanz starten, diese beenden.
                // Scheitert der Relaunch-Start, NICHT beenden (sonst ist die App einfach weg).
                Log.info("update installiert -> Neustart")
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                relaunch.arguments = ["-n", "/Applications/CleverSwitch.app"]
                do {
                    try relaunch.run()
                    NSApplication.shared.terminate(nil)
                } catch {
                    Log.info("update relaunch FEHLER: \(error)")
                }
            }
            if !ok {
                statusMessage = L10n.t("update_failed")
                NSWorkspace.shared.open(UpdateChecker.releasesPage)
            }
            updateInProgress = false
        }
    }

    // MARK: - CLI-Erkennung (Onboarding)

    /// Pro Anbieter: ist die CLI installiert? nil = noch nicht geprüft.
    private(set) var cliFound: [String: Bool] = [:]
    /// Pro Anbieter: Pfad, Install-Variante (native/npm/bun/brew), Versionen.
    private(set) var cliStatus: [String: CLIStatus] = [:]
    /// Anbieter mit gerade laufendem CLI-Update.
    private(set) var cliUpdateInProgress: Set<String> = []

    /// Prüft (gecacht, einmal pro Poll) ob die Anbieter-CLIs auffindbar sind — inkl.
    /// Install-Variante und installierter Version.
    func detectCLIs() async {
        for provider in providers {
            // Einmal erkannt = fertig (CLIs deinstallieren sich nicht von selbst) — sonst
            // startet jeder Poll eine zsh-Login-Shell. Nur „fehlt noch" wird erneut geprüft.
            if cliFound[provider.id] == true, cliStatus[provider.id] != nil { continue }
            let probed = await Task.detached { Self.probeCLI(provider: provider) }.value
            cliFound[provider.id] = probed != nil
            if var status = probed {
                status.latestVersion = cliStatus[provider.id]?.latestVersion  // Latest behalten
                cliStatus[provider.id] = status
            }
        }
    }

    /// Liest Pfad, Variante und Version einer CLI (blockierende Subprozesse -> detached rufen).
    private nonisolated static func probeCLI(provider: AccountProvider) -> CLIStatus? {
        guard let path = provider.loginCommand()?.first else { return nil }
        let versionOutput = Subprocess.run(path, ["--version"]).stdout
        let installed = CLIUpdateChecker.parseVersion(versionOutput)
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        // Erste Zeile fuer die Node-Shebang-Erkennung (npm/bun-Shims).
        var firstLine: String?
        if let handle = FileHandle(forReadingAtPath: resolved) {
            if let data = try? handle.read(upToCount: 64) {
                firstLine = String(data: data, encoding: .utf8)?
                    .split(separator: "\n").first.map(String.init)
            }
            try? handle.close()
        }
        let variant = CLIUpdateChecker.detectVariant(
            binaryPath: path, resolvedPath: resolved, firstLine: firstLine,
            home: FileManager.default.homeDirectoryForCurrentUser.path)
        return CLIStatus(binaryPath: path, variant: variant, installedVersion: installed)
    }

    /// Holt die neuesten CLI-Versionen aus der npm-Registry (läuft im 6-h-Update-Fenster mit).
    private func refreshCLILatestVersions() async {
        let http = self.http
        for provider in providers {
            guard var status = cliStatus[provider.id] else { continue }
            let npmPackage = provider.npmPackage
            guard !npmPackage.isEmpty else { continue }
            let latest = await Task.detached {
                await CLIUpdateChecker.latestVersion(npmPackage: npmPackage, http: http)
            }.value
            if let latest {
                status.latestVersion = latest
                cliStatus[provider.id] = status
                if status.updateAvailable {
                    Log.info(
                        "cli-update verfügbar: \(provider.id) \(status.installedVersion ?? "?") -> \(latest)")
                }
            }
        }
    }

    /// Führt das zur Install-Variante passende CLI-Update aus (zsh-Login-Shell, damit
    /// npm/bun/brew im User-PATH gefunden werden) und erkennt die CLI danach neu.
    func updateCLI(for provider: AccountProvider) {
        guard let status = cliStatus[provider.id],
            let command = CLIUpdateChecker.updateCommand(
                variant: status.variant, cliName: provider.cliName,
                npmPackage: provider.npmPackage, brewCask: provider.brewCask),
            !cliUpdateInProgress.contains(provider.id)
        else { return }
        cliUpdateInProgress.insert(provider.id)
        statusMessage = L10n.t("cli_updating")
        Log.info("cli-update (\(provider.id), \(status.variant.rawValue)): \(command)")
        Task {
            let result = await Task.detached { Subprocess.run("/bin/zsh", ["-lc", command]) }.value
            cliUpdateInProgress.remove(provider.id)
            if result.status == 0 {
                statusMessage = nil
                cliStatus[provider.id] = nil  // neu erkennen (Version/Variante)
                await detectCLIs()
                await refreshCLILatestVersions()
            } else {
                statusMessage = L10n.t("update_failed")
                Log.info("cli-update FEHLER (\(provider.id)): \(result.stderr.prefix(200))")
            }
        }
    }

    // MARK: - Launch at Login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                // macOS kann die Freigabe verlangen (z.B. nach Neuinstallation) — dann den
                // Anmeldeobjekte-Bereich öffnen, statt dass „nichts passiert".
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
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
