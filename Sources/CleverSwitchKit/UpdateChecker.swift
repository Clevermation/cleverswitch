// Update-Prüfung über die GitHub-Releases-API — ohne Sparkle/Notarisierung die einzige
// Update-Brücke. Installation läuft über `brew upgrade` (siehe AppModel.installUpdate).

import Foundation

public enum UpdateChecker {
    public static let latestReleaseAPI = URL(
        string: "https://api.github.com/repos/Clevermation/cleverswitch/releases/latest")!
    public static let releasesPage = URL(
        string: "https://github.com/Clevermation/cleverswitch/releases/latest")!

    /// Fragt das neueste Release ab und liefert dessen Version, wenn sie neuer als `current` ist.
    /// Fehler (offline, Rate-Limit) ergeben still nil — Update-Check darf nie stören.
    public static func check(current: String, http: HTTPClient) async -> String? {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let response = try? await http.send(request), response.status == 200,
            let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
            let tag = object["tag_name"] as? String
        else { return nil }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isNewer(latest, than: current) ? latest : nil
    }

    /// Numerischer Semver-Vergleich; fehlende Komponenten zählen als 0,
    /// nicht-numerische (z.B. "4-beta") ebenfalls.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let b = current.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
