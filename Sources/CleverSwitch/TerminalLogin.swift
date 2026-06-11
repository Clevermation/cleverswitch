// Öffnet einen sauberen, gebrandeten Sign-in-Tab in Terminal.app und lässt dort den offiziellen
// CLI-Login laufen.
//
// Warum sichtbar statt headless: Claudes Login nutzt einen „Code einfügen"-Flow (der Browser
// zeigt einen Code, den man in die CLI pasten muss). Das BRAUCHT eine Eingabemöglichkeit — ein
// unsichtbarer Prozess hat keine. Die CLI erledigt dafür alles korrekt (Identität, ~/.claude.json,
// Token-Format). Den Abschluss erkennt die App selbst per Polling (siehe AppModel.watchLogin).

import Foundation

enum TerminalLogin {
    /// Schreibt ein temporäres .command-Skript und öffnet es in Terminal.app.
    static func open(command: [String], providerName: String) {
        let quoted = command.map(shellQuote).joined(separator: " ")
        let script = """
            #!/bin/zsh
            clear
            printf '\\n  \\033[1mCleverSwitch — sign in to %s\\033[0m\\n\\n' "\(providerName)"
            echo "  A browser window will open. Finish the login there."
            echo "  If you are shown a code, paste it here and press Return."
            echo ""
            \(quoted)
            status=$?
            echo ""
            if [ $status -eq 0 ]; then
              echo "  ✓ Signed in. CleverSwitch picked it up — you can close this window."
            else
              echo "  Login was cancelled. You can close this window."
            fi
            echo ""
            read -k 1 -s "?Press any key to close…"
            """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleverswitch-login-\(UUID().uuidString).command")
        guard (try? Data(script.utf8).write(to: url)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)

        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [url.path]
        try? open.run()
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
