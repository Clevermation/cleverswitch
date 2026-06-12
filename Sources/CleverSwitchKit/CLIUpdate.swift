// Update-Erkennung für die Anbieter-CLIs (claude/codex) — KRITISCH ist die
// Install-Variante: dieselbe CLI kann nativ (curl-Installer), via npm, bun oder
// Homebrew installiert sein, und jede Variante hat ihren eigenen Update-Weg.
// Der falsche Befehl (z.B. npm-Update bei nativer Installation) erzeugt eine
// ZWEITE Installation, und die PATH-Reihenfolge entscheidet dann zufällig,
// welche läuft. Erkennungs-Heuristik entspricht der der offiziellen Installer
// (classify_existing_codex in install.sh bzw. claude doctor).

import Foundation

/// Wie wurde eine CLI installiert?
public enum CLIVariant: String, Sendable, Equatable {
    case native  // offizieller curl-Installer (~/.local/bin, eigener Self-Updater)
    case npm  // npm install -g (Node-Shim)
    case bun  // bun install -g (~/.bun/bin, Node-Shim)
    case brew  // Homebrew-Cask (/opt/homebrew bzw. /usr/local)
    case unknown
}

/// Zustand einer Anbieter-CLI: wo, welche Variante, Versionen.
public struct CLIStatus: Sendable, Equatable {
    public let binaryPath: String
    public let variant: CLIVariant
    public let installedVersion: String?
    public var latestVersion: String?

    public init(
        binaryPath: String, variant: CLIVariant,
        installedVersion: String?, latestVersion: String? = nil
    ) {
        self.binaryPath = binaryPath
        self.variant = variant
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
    }

    public var updateAvailable: Bool {
        guard let installed = installedVersion, let latest = latestVersion else { return false }
        return UpdateChecker.isNewer(latest, than: installed)
    }
}

public enum CLIUpdateChecker {
    /// Erkennt die Install-Variante aus dem (Symlink-aufgelösten) Pfad + erster Datei-Zeile.
    /// `resolvedPath` = realer Pfad nach Symlink-Auflösung, `firstLine` = erste Zeile der
    /// Datei (für die Node-Shebang-Erkennung); beide injizierbar -> pur testbar.
    public static func detectVariant(
        binaryPath: String, resolvedPath: String, firstLine: String?, home: String
    ) -> CLIVariant {
        let paths = binaryPath + "\n" + resolvedPath
        if paths.contains("/.bun/") { return .bun }
        if binaryPath.hasPrefix("/opt/homebrew/") || binaryPath.hasPrefix("/usr/local/")
            || resolvedPath.contains("/Caskroom/")
        {
            return .brew
        }
        // Node-Shim (#!/usr/bin/env node) ohne bun-Pfad = npm.
        if let firstLine, firstLine.hasPrefix("#!"), firstLine.contains("node") { return .npm }
        // Echtes Binary unter ~/.local/bin = offizieller curl-Installer.
        if binaryPath.hasPrefix("\(home)/.local/bin") || resolvedPath.contains("/.local/share/")
            || resolvedPath.contains("/.codex/packages/standalone/")
        {
            return .native
        }
        return .unknown
    }

    /// Zieht die Version aus der `--version`-Ausgabe: "2.1.175 (Claude Code)" -> "2.1.175",
    /// "codex-cli 0.136.0" -> "0.136.0".
    public static func parseVersion(_ output: String) -> String? {
        for token in output.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let candidate = token.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let parts = candidate.split(separator: ".")
            if parts.count >= 2, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
                return candidate
            }
        }
        return nil
    }

    /// Neueste veröffentlichte Version aus der npm-Registry (latest-dist-tag) — eine Quelle
    /// für alle Install-Varianten (brew/curl ziehen dieselben GitHub-Releases nach).
    public static func latestVersion(npmPackage: String, http: HTTPClient) async -> String? {
        guard
            let url = URL(
                string: "https://registry.npmjs.org/\(npmPackage)/latest")
        else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let response = try? await http.send(request), response.status == 200,
            let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        else { return nil }
        return object["version"] as? String
    }

    /// Der zur Variante passende Update-Befehl (als Shell-Zeile für `zsh -lc`).
    /// WICHTIG bei npm: explizit @latest — `npm update -g` bleibt in der Semver-Range hängen.
    public static func updateCommand(
        variant: CLIVariant, cliName: String, npmPackage: String, brewCask: String
    ) -> String? {
        switch variant {
        case .native: return "\(cliName) update"
        case .npm: return "npm install -g \(npmPackage)@latest"
        case .bun: return "bun install -g \(npmPackage)"
        case .brew: return "brew upgrade --cask \(brewCask)"
        case .unknown: return nil
        }
    }
}
