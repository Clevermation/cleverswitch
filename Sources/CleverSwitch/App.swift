import SwiftUI

@main
struct CleverSwitchApp: App {
    static let loginWindowID = "cleverswitch-login"

    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            // Icon + Live-Session-% des aktiven Claude-Accounts (ambient sichtbar).
            if let text = model.menuBarText {
                Text("⇄ \(text)")
            } else {
                Image(systemName: "arrow.left.arrow.right")
            }
        }
        .menuBarExtraStyle(.menu)

        // Natives Login-Fenster (statt Terminal). Wird über das Menü geöffnet und schließt sich
        // selbst, sobald der Login erkannt oder abgebrochen wurde.
        Window(L10n.t("login_window_title"), id: Self.loginWindowID) {
            LoginView(model: model)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
