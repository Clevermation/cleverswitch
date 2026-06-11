// Parst die (unsichtbare) CLI-Ausgabe des Login-Prozesses: findet die Browser-URL und erkennt
// die „Code einfügen"-Aufforderung. Rein und testbar.

import Foundation

public enum LoginOutputParser {
    /// Extrahiert die OAuth-Authorize-URL aus der CLI-Ausgabe, oder nil.
    public static func authorizeURL(in text: String) -> URL? {
        // Auf Whitespace UND ANSI-Escape (\u{1B}) splitten; Klammern/Quotes abschneiden.
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{1B}"))
        for raw in text.components(separatedBy: separators) {
            let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'()[]"))
            guard token.hasPrefix("https://"),
                token.contains("authorize") || token.contains("oauth")
            else { continue }
            if let url = URL(string: token) { return url }
        }
        return nil
    }

    /// True, wenn die Ausgabe nach einem einzufügenden Code fragt.
    public static func asksForCode(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("paste") || lower.contains("paste code") || lower.contains("enter the code")
    }
}
