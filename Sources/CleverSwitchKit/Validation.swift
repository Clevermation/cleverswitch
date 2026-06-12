// Validierung von Account-Handles.
//
// Handles stammen aus extern kontrollierten Quellen (E-Mail aus einem JWT-Payload bzw. aus
// ~/.claude.json). Sie fließen in Keychain-Service-/Account-Namen ein. Steuerzeichen (v.a.
// Newlines) müssen abgelehnt werden, bevor ein Handle übernommen oder in einen Keychain-Befehl
// geschrieben wird.

import Foundation

public enum AccountHandle {
    /// Akzeptiert nur unbedenkliche Handles: keine Steuerzeichen, sinnvolle Länge.
    public static func isValid(_ handle: String) -> Bool {
        guard (1...254).contains(handle.count) else { return false }
        return !handle.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// Maskiert eine E-Mail für die Anzeige, ohne sie zu leaken (z.B. für Screen-Recordings):
    /// "anna@example.com" -> "a•••@e•••.com". Erster Zeichen des lokalen Teils + erster
    /// Domain-Buchstabe + TLD bleiben sichtbar; der Rest wird zu Punkten. Eingaben ohne "@"
    /// werden auf das erste Zeichen + Punkte reduziert.
    public static func masked(_ handle: String) -> String {
        let dots = "•••"
        guard let at = handle.firstIndex(of: "@") else {
            guard let first = handle.first else { return dots }
            return "\(first)\(dots)"
        }
        let local = String(handle[handle.startIndex..<at])
        let domain = String(handle[handle.index(after: at)...])
        let localMasked = (local.first.map { "\($0)" } ?? "") + dots

        if let lastDot = domain.lastIndex(of: "."), lastDot != domain.startIndex {
            let name = String(domain[domain.startIndex..<lastDot])
            let tld = String(domain[domain.index(after: lastDot)...])
            let nameMasked = (name.first.map { "\($0)" } ?? "") + dots
            return "\(localMasked)@\(nameMasked).\(tld)"
        }
        let domainMasked = (domain.first.map { "\($0)" } ?? "") + dots
        return "\(localMasked)@\(domainMasked)"
    }
}
