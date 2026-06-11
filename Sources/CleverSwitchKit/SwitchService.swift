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
        // 1. Aktuellen Live-Slot sichern (frische Creds des bisher aktiven Accounts).
        if let current, let liveBlob = provider.readLive(credentials: credentials) {
            try credentials.write(
                service: provider.snapshotService(handle: current.handle),
                account: current.handle,
                secret: liveBlob
            )
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
        try provider.writeLive(targetBlob, handle: target.handle, credentials: credentials)
        if didRefresh {
            try? credentials.write(
                service: snapshotService, account: target.handle, secret: targetBlob)
        }
        provider.didActivate(account: target)
    }
}
