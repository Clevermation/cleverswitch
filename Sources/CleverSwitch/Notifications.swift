// Dünner Wrapper um UserNotifications: postet macOS-Benachrichtigungen für Switch-Events,
// Frühwarnungen und abgelaufene Sitzungen — nur wenn der Nutzer sie in den Einstellungen
// aktiviert hat. Berechtigung wird lazy beim ersten Aktivieren angefragt.

import UserNotifications

enum Notifier {
    /// Fragt die Benachrichtigungs-Berechtigung an (beim Einschalten in den Einstellungen).
    /// `completion` liefert, ob die Berechtigung erteilt wurde — false auch dann, wenn sie zuvor
    /// abgelehnt wurde (macOS zeigt dann keinen Dialog mehr).
    static func requestAuthorization(_ completion: @escaping @Sendable (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
            granted, _ in completion(granted)
        }
    }

    /// Liest den tatsächlichen System-Berechtigungsstatus (für „wurde in den Systemeinstellungen
    /// entzogen?"). true bei authorized/provisional.
    static func authorizationStatus(_ completion: @escaping @Sendable (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            completion(status == .authorized || status == .provisional)
        }
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
