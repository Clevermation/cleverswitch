// Natives Login-Fenster: ersetzt das Terminal. Die CLI läuft unsichtbar unter einem PTY
// (siehe AppModel.addAccount); hier gibt der User nur den Code aus dem Browser ein.

import AppKit
import SwiftUI

/// Zustand des aktiven Logins, der das Fenster treibt.
struct LoginUI: Equatable {
    let providerID: String
    let providerName: String
    var status: String
    var browserURL: URL?
    var needsCode: Bool = false
    var submitting: Bool = false
}

struct LoginView: View {
    @Bindable var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let login = model.login {
                content(login)
            } else {
                Color.clear.frame(width: 380, height: 1)
            }
        }
        .onChange(of: model.login == nil) { _, isNil in
            if isNil { dismissWindow(id: CleverSwitchApp.loginWindowID) }
        }
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    @ViewBuilder
    private func content(_ login: LoginUI) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.key")
                    .foregroundStyle(.tint)
                Text(L10n.t("login_title", login.providerName))
                    .font(.headline)
            }

            Text(login.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if login.browserURL != nil {
                Button(action: model.openLoginBrowser) {
                    Label(L10n.t("login_open_browser"), systemImage: "safari")
                }
            }

            if login.needsCode {
                Divider()
                Text(L10n.t("login_paste_prompt"))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField(L10n.t("login_code_placeholder"), text: $model.loginCode)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(model.submitLoginCode)
                        .disabled(login.submitting)
                    Button(L10n.t("login_submit"), action: model.submitLoginCode)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.loginCode.isEmpty || login.submitting)
                }
            }

            Divider()
            HStack {
                if login.submitting {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("login_signing_in")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.t("cancel"), role: .cancel, action: model.cancelLogin)
            }
        }
        .padding(20)
        .frame(width: 430)
    }
}
