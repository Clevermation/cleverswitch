// Orchestriert das Umschalten der aktiven Sitzung auf einen anderen Account.
//
// Ablauf (siehe docs/SPEC.md, F2):
// 1. aktuellen Live-Slot in den Snapshot des aktiven Accounts sichern,
// 2. Ziel-Snapshot lesen,
// 3. abgelaufenen Ziel-Token VOR dem Aktivieren erneuern (sonst Re-Login nötig);
//    transiente Refresh-Fehler sind kein Abbruch — dann wird der vorhandene Blob verwendet,
// 4. Ziel-Blob in den Live-Slot schreiben + anbieter-spezifische Sitzungsdaten nachziehen.

import Foundation

public enum SwitchService {
    public enum SwitchError: Error, Equatable {
        case missingCredentials(handle: String)
        case sessionExpired(handle: String)
    }

    public static func activate(
        target: Account,
        current: Account?,
        provider: AccountProvider,
        credentials: CredentialStore,
        http: HTTPClient
    ) async throws {
        // 1. Aktuellen Live-Slot sichern (frische Creds des bisher aktiven Accounts) —
        //    aber NUR, wenn der Live-Slot laut Anbieter-Identität wirklich diesem Account
        //    gehört. Sonst würde ein fremder Token in den falschen Snapshot kopiert und
        //    der Fehler bei jedem weiteren Switch zementiert (Token-Vermischungs-Bug).
        try await KeychainGate.shared.run {
            if let current, let liveBlob = provider.readLive(credentials: credentials),
                provider.currentIdentity(credentials: credentials)?.handle == current.handle
            {
                // Nur sichern, wenn die Live-Identität BESTÄTIGT diesem Account gehört. Bei
                // unbekannter Identität (fehlende/korrupte Zustandsdatei) lieber den älteren
                // Snapshot behalten als einen fremden/kaputten Blob hineinzukopieren.
                try credentials.write(
                    service: provider.snapshotService(handle: current.handle),
                    account: current.handle,
                    secret: liveBlob
                )
            }
        }

        // 2. Ziel-Snapshot lesen.
        let snapshotService = provider.snapshotService(handle: target.handle)
        guard var targetBlob = credentials.read(service: snapshotService) else {
            throw SwitchError.missingCredentials(handle: target.handle)
        }

        // 3. Abgelaufenen Token VOR dem Aktivieren erneuern.
        var didRefresh = false
        if provider.isExpired(targetBlob) {
            do {
                targetBlob = try await provider.refresh(targetBlob, http: http)
                didRefresh = true
            } catch is CredentialsExpiredError {
                throw SwitchError.sessionExpired(handle: target.handle)
            } catch {
                // Transient (Netzwerk/429): mit dem vorhandenen Blob weitermachen.
            }
        }

        // 4. ZUERST in den Live-Slot schreiben (das ist der Sinn der Aktion),
        //    DANN den erneuerten Blob in den Snapshot zurückschreiben. Reihenfolge wichtig:
        //    bei einem Crash dazwischen liegt der gültige Token live, nicht nur im Snapshot
        //    (sonst wäre der noch live liegende `current` durch Token-Rotation invalidiert).
        let blob = targetBlob
        let refreshed = didRefresh
        try await KeychainGate.shared.run {
            try provider.writeLive(blob, handle: target.handle, credentials: credentials)
            if refreshed {
                try? credentials.write(
                    service: snapshotService, account: target.handle, secret: blob)
            }
        }
        provider.didActivate(account: target)
    }
}
