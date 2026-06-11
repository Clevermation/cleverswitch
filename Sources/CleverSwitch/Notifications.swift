// Dünner Wrapper um UserNotifications: postet macOS-Benachrichtigungen für Switch-Events,
// Frühwarnungen und abgelaufene Sitzungen — nur wenn der Nutzer sie in den Einstellungen
// aktiviert hat. Berechtigung wird lazy beim ersten Aktivieren angefragt.

import UserNotifications

enum Notifier {
    /// Fragt die Benachrichtigungs-Berechtigung an (beim Einschalten in den Einstellungen).
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Postet eine Benachrichtigung, sofern `enabled`. Fehlende Berechtigung wird still ignoriert
    /// (die Info steht ohnehin auch im Menü).
    static func post(_ title: String, _ body: String, enabled: Bool) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
