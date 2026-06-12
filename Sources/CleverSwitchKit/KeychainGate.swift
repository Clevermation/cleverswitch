// Serialisiert alle App-seitigen Schreibzugriffe auf Credential-Slots. Hintergrund:
// consolidateLive (read+delete+write-Sequenz) darf nie mit einem gleichzeitigen Switch-
// oder Refresh-Write verzahnt laufen — sonst kann ein Eintrag des falschen Accounts
// überleben (Token-Vermischungs-Klasse). Die CLI selbst schreibt außerhalb unserer
// Kontrolle; dieser Gate eliminiert wenigstens alle App-internen Races.

import Foundation

public actor KeychainGate {
    public static let shared = KeychainGate()
    private init() {}

    public func run<T: Sendable>(_ body: @Sendable () throws -> T) rethrows -> T {
        try body()
    }
}
