// Geführte Ersteinrichtung: ein einzelnes, schlichtes Fenster mit drei Schritten
// (CLI-Status -> Accounts hinzufügen -> Einstellungen/Berechtigungen). Öffnet sich
// automatisch beim ersten Start ohne Accounts; manuell über das Menü erreichbar.
//
// AppKit-Host statt SwiftUI-Window-Scene: aus einer LSUIElement-Menüleisten-App lässt
// sich ein NSWindow direkt und zuverlässig zeigen (kein Scene-/Fokus-Gefrickel).

import AppKit
import CleverSwitchKit
import SwiftUI

@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: OnboardingView(model: model, close: { hide() }))
        let w = NSWindow(contentViewController: hosting)
        w.title = L10n.t("onboarding_title")
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hide() {
        window?.orderOut(nil)
    }
}

private struct OnboardingView: View {
    let model: AppModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            step(number: 1, title: L10n.t("onboarding_step_cli")) { cliRows }
            step(number: 2, title: L10n.t("onboarding_step_accounts")) { accountRows }
            step(number: 3, title: L10n.t("onboarding_step_settings")) { settingsRows }
            if let message = model.statusMessage {
                Label(message, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Spacer()
                Button(L10n.t("onboarding_done")) { close() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("onboarding_title")).font(.title2.bold())
                Text(L10n.t("onboarding_intro"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step(number: Int, title: String, @ViewBuilder content: () -> some View)
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.callout.bold())
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.tint.opacity(0.18)))
                Text(title).font(.headline)
            }
            VStack(alignment: .leading, spacing: 6) { content() }
                .padding(.leading, 30)
        }
    }

    private var cliRows: some View {
        ForEach(model.providers, id: \.id) { provider in
            HStack {
                if let found = model.cliFound[provider.id] {
                    Image(systemName: found ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(found ? .green : .red)
                    Text(provider.displayName)
                    Text(found ? L10n.t("cli_found") : L10n.t("cli_not_found"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !found {
                        Button(L10n.t("install_cli")) { NSWorkspace.shared.open(provider.installURL) }
                    }
                } else {
                    ProgressView().controlSize(.small)
                    Text(provider.displayName)
                    Spacer()
                }
            }
        }
    }

    private var accountRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("onboarding_accounts_hint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.providers, id: \.id) { provider in
                HStack {
                    Button {
                        model.addAccount(for: provider)
                    } label: {
                        Label(
                            "\(provider.displayName)…",
                            systemImage: model.loginInProgress.contains(provider.id)
                                ? "hourglass" : "plus.circle")
                    }
                    .disabled(
                        model.loginInProgress.contains(provider.id)
                            || model.cliFound[provider.id] == false)
                    // Bereits eingerichtete Accounts dieses Anbieters zeigen.
                    let handles = model.accounts(for: provider).map {
                        model.displayHandle($0.handle)
                    }
                    if !handles.isEmpty {
                        Text(handles.joined(separator: ", "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
        }
    }

    private var settingsRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                L10n.t("launch_at_login"),
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
            Toggle(
                L10n.t("notifications"),
                isOn: Binding(
                    get: { model.notificationsActive },
                    set: { model.setNotificationsEnabled($0) }))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
