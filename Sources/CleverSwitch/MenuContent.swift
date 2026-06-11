// Inhalt des Menüleisten-Menüs (MenuBarExtra). Reine Darstellung; alle Aktionen gehen ans AppModel.

import CleverSwitchKit
import SwiftUI

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        ForEach(model.providers, id: \.id) { provider in
            Section(provider.displayName) {
                accountRows(for: provider)
                autoSwitchMenu(for: provider)
                if model.loginInProgress.contains(provider.id) {
                    Label(L10n.t("login_running"), systemImage: "hourglass")
                } else {
                    Button {
                        model.addAccount(for: provider)
                    } label: {
                        Label(L10n.t("add_account"), systemImage: "plus.circle")
                    }
                }
            }
        }

        Divider()

        Button {
            Task { await model.refreshUsage() }
        } label: {
            Label(L10n.t("refresh_usage"), systemImage: "arrow.clockwise")
        }

        if !model.removableAccounts.isEmpty {
            Menu {
                ForEach(model.removableAccounts, id: \.id) { account in
                    Button("\(account.provider): \(model.displayHandle(account.handle))") {
                        model.remove(account)
                    }
                }
            } label: {
                Label(L10n.t("remove_account"), systemImage: "minus.circle")
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
        let accounts = model.accounts(for: provider)
        if accounts.isEmpty {
            Label(L10n.t("no_accounts"), systemImage: "person.crop.circle.badge.questionmark")
        } else {
            ForEach(accounts, id: \.id) { account in
                Button {
                    Task { await model.switchTo(account) }
                } label: {
                    let plan = account.label.isEmpty ? "" : " (\(account.label))"
                    Label(
                        "\(model.displayHandle(account.handle))\(plan)  —  \(model.usageText(for: account))",
                        systemImage: account.active ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        }
    }

    private var settingsMenu: some View {
        Menu {
            toggle(
                L10n.t("launch_at_login"), isOn: model.launchAtLogin,
                action: { model.setLaunchAtLogin(!model.launchAtLogin) })
            toggle(
                L10n.t("notifications"), isOn: model.notificationsEnabled,
                action: { model.setNotificationsEnabled(!model.notificationsEnabled) })
            toggle(
                L10n.t("show_email"), isOn: model.showEmail,
                action: { model.setShowEmail(!model.showEmail) })
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
                        systemImage: current == mode ? "checkmark" : "circle.dotted"
                    )
                }
            }
        } label: {
            Label(
                "\(L10n.t("auto_switch"))  ·  \(L10n.t("mode_\(current.rawValue)"))",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
    }
}
