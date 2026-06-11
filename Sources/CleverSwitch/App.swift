import SwiftUI

@main
struct CleverSwitchApp: App {
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
    }
}
