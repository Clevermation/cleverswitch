// Inhalt des Menüleisten-Menüs (MenuBarExtra). Reine Darstellung; alle Aktionen gehen ans AppModel.

import CleverSwitchKit
import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        // Update verfügbar -> prominent ganz oben (Installation läuft über brew + Neustart).
        if let version = model.updateAvailable {
            Button {
                model.installUpdate()
            } label: {
                Label(
                    L10n.t("update_available", version),
                    systemImage: "arrow.down.circle.fill")
            }
            .disabled(model.updateInProgress)
            Divider()
        }

        // CLI-Updates (claude/codex): Befehl passend zur Install-Variante (native/npm/bun/brew).
        ForEach(model.providers, id: \.id) { provider in
            if let status = model.cliStatus[provider.id], status.updateAvailable,
                let latest = status.latestVersion
            {
                Button {
                    model.updateCLI(for: provider)
                } label: {
                    Label(
                        "\(provider.displayName) CLI: \(L10n.t("update_available", latest))",
                        systemImage: "terminal")
                }
                .disabled(model.cliUpdateInProgress.contains(provider.id))
            }
        }

        ForEach(model.providers, id: \.id) { provider in
            Section(provider.displayName) {
                accountRows(for: provider)
                // Auto-Switch nur anbieten, wenn es mind. 2 Accounts gibt — sonst ist „wechseln"
                // sinnlos.
                if model.accounts(for: provider).count >= 2 {
                    autoSwitchMenu(for: provider)
                }
                // Läuft gerade ein Login für DIESEN Anbieter, Abbrechen anbieten.
                if model.loginInProgress.contains(provider.id) {
                    Button {
                        model.cancelLogin(for: provider)
                    } label: {
                        Label(L10n.t("login_cancel"), systemImage: "xmark.circle")
                    }
                }
            }
        }

        Divider()

        Button {
            model.forceRefresh()
        } label: {
            // „Aktualisiert vor X" direkt hinter dem Titel (eine Zeile statt eigener Reihe).
            Label {
                if let updated = model.lastUpdatedText {
                    Text(L10n.t("refresh_usage")) + Text("  ·  \(updated)").foregroundStyle(.secondary)
                } else {
                    Text(L10n.t("refresh_usage"))
                }
            } icon: {
                Image(systemName: "arrow.clockwise")
            }
        }

        // Account hinzufügen — ein Eintrag mit Anbieter-Auswahl (Claude Code / Codex CLI).
        Menu {
            ForEach(model.providers, id: \.id) { provider in
                Button(provider.displayName) { model.addAccount(for: provider) }
                    .disabled(model.loginInProgress.contains(provider.id))
            }
        } label: {
            Label(L10n.t("add_account"), systemImage: "plus.circle")
        }

        if !model.removableAccounts.isEmpty {
            Menu {
                ForEach(model.removableAccounts, id: \.id) { account in
                    // Anzeigename statt roher Provider-ID ("Claude Code" statt "claude").
                    let providerName = model.provider(account.provider)?.displayName ?? account.provider
                    Button("\(providerName): \(model.displayHandle(account.handle))") {
                        model.remove(account)
                    }
                }
            } label: {
                Label(L10n.t("remove_account"), systemImage: "minus.circle")
            }
        }

        // Ersteinrichtung anbieten, solange noch gar kein Account existiert.
        if model.providers.allSatisfy({ model.accounts(for: $0).isEmpty }) {
            Button {
                OnboardingWindow.show(model: model)
            } label: {
                Label(L10n.t("open_onboarding"), systemImage: "sparkles")
            }
        }

        settingsMenu

        if let message = model.statusMessage {
            Divider()
            Label(message, systemImage: "exclamationmark.triangle")
        }

        Divider()
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label(L10n.t("quit"), systemImage: "power")
        }
    }

    @ViewBuilder
    private func accountRows(for provider: AccountProvider) -> some View {
        let raw = model.accounts(for: provider)
        // Aktiver Account immer zuerst (stabil, ohne die übrige Reihenfolge zu verwürfeln).
        let accounts = raw.filter(\.active) + raw.filter { !$0.active }
        // Abo-Spalte so breit wie das längste Label dieses Anbieters (min. 4), sonst bricht
        // die Ausrichtung sobald ein Plan-Name länger als 4 Zeichen ist (z.B. "Team").
        let labelWidth = max(4, accounts.map(\.label.count).max() ?? 4)
        if accounts.isEmpty {
            // Onboarding light direkt im Menü: fehlt die CLI, Install-Link statt totem Hinweis.
            if model.cliFound[provider.id] == false {
                Button {
                    NSWorkspace.shared.open(provider.installURL)
                } label: {
                    Label(L10n.t("cli_missing_install"), systemImage: "arrow.down.circle")
                }
            } else {
                Label(L10n.t("no_accounts"), systemImage: "person.crop.circle.badge.questionmark")
            }
        } else {
            ForEach(accounts, id: \.id) { account in
                Button {
                    Task { await model.switchTo(account) }
                } label: {
                    Label(
                        model.displayHandle(account.handle),
                        systemImage: account.active ? "checkmark.circle.fill" : "circle"
                    )
                }
                // Plan + Usage in zweiter Zeile, monospaced -> Spalten (Abo · Session · Woche)
                // richten sich über alle Accounts hinweg sauber aus.
                usageLine(for: account, labelWidth: labelWidth)
                    .font(.system(.callout, design: .monospaced))
            }
        }
    }

    /// Zweite Zeile pro Account: Plan + Usage in festen Spaltenbreiten (monospaced gesetzt in
    /// `accountRows`), damit Abo · Session · Woche über alle Accounts hinweg untereinander stehen.
    /// Die Prozent-Zahl ist je nach Auslastung eingefärbt (grün < 60 %, orange < 85 %, rot darüber).
    private func usageLine(for account: Account, labelWidth: Int) -> Text {
        // Dynamische Ampel-Farben: die System-Grün/Orange-Töne sind im HELLEN Modus auf
        // weißem Menü kaum lesbar (Theos Fund) — dort kräftig-dunkle Varianten, im dunklen
        // Modus die leuchtenden Systemfarben.
        func color(_ pct: Double) -> Color {
            let dynamic = NSColor(name: nil) { appearance in
                let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                if pct >= 85 {
                    return dark ? .systemRed : NSColor(red: 0.72, green: 0.05, blue: 0.10, alpha: 1)
                }
                if pct >= 60 {
                    return dark ? .systemOrange : NSColor(red: 0.72, green: 0.38, blue: 0.0, alpha: 1)
                }
                return dark ? .systemGreen : NSColor(red: 0.0, green: 0.50, blue: 0.16, alpha: 1)
            }
            return Color(nsColor: dynamic)
        }
        // Rechts-/linksbündig auf feste Zeichenbreite auffüllen (wirkt nur monospaced sauber).
        func pad(_ s: String, _ n: Int, right: Bool = false) -> String {
            let gap = String(repeating: " ", count: max(0, n - s.count))
            return right ? gap + s : s + gap
        }
        let dash = Text(L10n.t("usage_unknown")).foregroundStyle(.secondary)
        guard let snapshot = model.usage[account.id], snapshot.known,
            let provider = model.provider(account.provider)
        else { return dash }

        // Abo-Label linksbündig, Breite = längstes Label des Anbieters (z.B. "max ", "pro ").
        var line = Text(pad(account.label, labelWidth)).foregroundStyle(.secondary)
        var any = false
        for (key, label) in [
            (UsageWindowKey.session, provider.sessionWindowLabel),
            (UsageWindowKey.weekly, provider.weeklyWindowLabel),
        ] {
            guard let pct = snapshot.pct(key) else { continue }
            any = true
            let pctStr = "\(Int(pct))%"
            let resetsAt = snapshot.windows.first { $0.key == key }?.resetsAt
            let countdown = ResetFormatter.shortCountdown(from: resetsAt).map { "(\($0))" } ?? ""
            line =
                line
                + Text(" · \(pad(label, 2)) ").foregroundStyle(.secondary)
                + Text(pad(pctStr, 4, right: true)).foregroundStyle(color(pct))  // rechtsbündig: "  8%"
                + Text(" \(pad(countdown, 9))").foregroundStyle(.secondary)  // feste Breite -> Spalte
        }
        return any ? line : dash
    }

    private var settingsMenu: some View {
        Menu {
            toggle(
                L10n.t("launch_at_login"), isOn: model.launchAtLogin,
                action: { model.setLaunchAtLogin(!model.launchAtLogin) })
            toggle(
                L10n.t("notifications"), isOn: model.notificationsActive,
                // WICHTIG: Negation des SICHTBAREN Zustands (notificationsActive), nicht des
                // gespeicherten Wunsches — sonst schaltet der erste Klick bei fehlender
                // System-Erlaubnis nur den Wunsch aus und „nichts passiert".
                action: { model.setNotificationsEnabled(!model.notificationsActive) })
            toggle(
                L10n.t("show_email"), isOn: model.showEmail,
                action: { model.setShowEmail(!model.showEmail) })
            // Quelle der Menüleisten-Zahl wählen (nur sinnvoll bei mehr als einem Anbieter).
            if model.providers.count >= 2 {
                Divider()
                Menu {
                    toggle(
                        L10n.t("menubar_source_highest"), isOn: model.menuBarSource == "highest",
                        action: { model.setMenuBarSource("highest") })
                    ForEach(model.providers, id: \.id) { provider in
                        toggle(
                            provider.displayName, isOn: model.menuBarSource == provider.id,
                            action: { model.setMenuBarSource(provider.id) })
                    }
                } label: {
                    Label(L10n.t("menubar_source"), systemImage: "number")
                }
            }
            Divider()
            Button {
                OnboardingWindow.show(model: model)
            } label: {
                Label(L10n.t("open_onboarding"), systemImage: "sparkles")
            }
            // Version + manuelle Update-Prüfung.
            Button("CleverSwitch \(cleverSwitchVersion)") {
                NSWorkspace.shared.open(UpdateChecker.releasesPage)
            }
            if model.showUpToDate {
                // Nach manueller Prüfung ohne Fund: Zustand statt Dauer-Statusmeldung —
                // verschwindet mit dem nächsten 6-h-Fenster von selbst.
                Label(L10n.t("up_to_date"), systemImage: "checkmark.seal")
            } else {
                Button(L10n.t("check_updates")) { model.checkForUpdateNow() }
            }
        } label: {
            Label(L10n.t("settings"), systemImage: "gearshape")
        }
    }

    @ViewBuilder
    private func toggle(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: isOn ? "checkmark.circle.fill" : "circle")
        }
    }

    @ViewBuilder
    private func autoSwitchMenu(for provider: AccountProvider) -> some View {
        let current = model.mode(for: provider)
        Menu {
            ForEach(SwitchMode.allCases, id: \.self) { mode in
                Button {
                    model.setMode(mode, for: provider)
                } label: {
                    Label(
                        L10n.t("mode_\(mode.rawValue)"),
                        // Gleiche Icon-Sprache wie Accounts + Einstellungen (Konsistenz).
                        systemImage: current == mode ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        } label: {
            // Kurzes Label im Eltern-Eintrag (z.B. „Auto-Switch · Failover") — die lange
            // Beschreibung steht im Untermenü. Sonst wird das ganze Menü unnötig breit.
            Label(
                "\(L10n.t("auto_switch")) · \(L10n.t("mode_\(current.rawValue)_short"))",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
    }
}
