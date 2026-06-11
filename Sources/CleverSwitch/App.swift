import SwiftUI

@main
struct CleverSwitchApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            // Icon + höchste Live-Session-Auslastung (ambient sichtbar, ohne Klick).
            if let text = model.menuBarText {
                Text("⇄ \(text)")
            } else {
                Image(systemName: "arrow.left.arrow.right")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
