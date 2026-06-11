// Claude-OAuth: Token-Refresh + Helfer auf dem Credential-Blob.
//
// Der Blob ist JSON: {"claudeAiOauth": {"accessToken", "refreshToken", "expiresAt"(ms), ...}}.
// Wir manipulieren ihn als Dictionary (JSONSerialization), damit unbekannte Felder erhalten bleiben.
//
// WICHTIG: Der Token-Endpoint sitzt hinter Cloudflare-Bot-Schutz (Error 1010) — ohne
// claude-code-User-Agent kommt ein 403 statt einer OAuth-Antwort. Ein 429 ist transient
// (Rate-Limit), NICHT „abgelaufen" — nur ein invalid_grant gilt als endgültig tot.

import Foundation

public enum ClaudeAuth {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let userAgent = "claude-code/2.1.173"
    static let oauthKey = "claudeAiOauth"

    // MARK: - Pure Blob-Helfer

    private static func root(_ blob: String) -> [String: Any]? {
        guard let data = blob.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func oauth(_ blob: String) -> [String: Any]? {
        root(blob)?[oauthKey] as? [String: Any]
    }

    public static func accessToken(in blob: String) -> String? {
        oauth(blob)?["accessToken"] as? String
    }

    public static func refreshToken(in blob: String) -> String? {
        oauth(blob)?["refreshToken"] as? String
    }

    public static func subscriptionType(in blob: String) -> String? {
        oauth(blob)?["subscriptionType"] as? String
    }

    public static func expiresAtMillis(in blob: String) -> Double? {
        (oauth(blob)?["expiresAt"] as? NSNumber)?.doubleValue
    }

    /// True, wenn der Access-Token abgelaufen ist (oder innerhalb von `leeway` Sekunden abläuft).
    public static func isExpired(_ blob: String, leeway: TimeInterval = 300, now: Date = Date()) -> Bool {
        guard let millis = expiresAtMillis(in: blob) else { return false }
        return millis / 1000 <= now.timeIntervalSince1970 + leeway
    }

    static func makeRefreshBody(refreshToken: String) -> Data {
        let payload: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    /// Merge der 200-Token-Response in den bestehenden Blob (unbekannte Felder bleiben erhalten).
    static func applyTokenResponse(into blob: String, responseBody: Data, now: Date = Date()) -> String? {
        guard var rootDict = root(blob),
            var oauthDict = rootDict[oauthKey] as? [String: Any],
            let response = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any]
        else { return nil }

        if let access = response["access_token"] as? String { oauthDict["accessToken"] = access }
        if let refresh = response["refresh_token"] as? String { oauthDict["refreshToken"] = refresh }
        if let expiresIn = (response["expires_in"] as? NSNumber)?.doubleValue {
            oauthDict["expiresAt"] = (now.timeIntervalSince1970 + expiresIn) * 1000
        }
        rootDict[oauthKey] = oauthDict

        guard let data = try? JSONSerialization.data(withJSONObject: rootDict),
            let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    // MARK: - Netzwerk

    /// Erneuert den Access-Token via Refresh-Token. Gibt den aktualisierten Blob zurück.
    public static func refresh(_ blob: String, http: HTTPClient, now: Date = Date()) async throws -> String {
        guard let token = refreshToken(in: blob) else { throw CredentialsExpiredError() }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.httpBody = makeRefreshBody(refreshToken: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let response = try await http.send(request)
        switch response.status {
        case 200:
            guard let updated = applyTokenResponse(into: blob, responseBody: response.body, now: now) else {
                throw TransientRefreshError(status: 200)
            }
            return updated
        case 400, 401:
            // Nur invalid_grant heißt „Refresh-Token endgültig tot". invalid_request ist ein
            // Client-/Parameter-Fehler (RFC 6749) und KEIN Beleg für einen toten Token —
            // sonst würde der User grundlos zum Re-Login gezwungen.
            let body = String(data: response.body, encoding: .utf8) ?? ""
            if body.contains("invalid_grant") {
                throw CredentialsExpiredError()
            }
            throw TransientRefreshError(status: response.status)
        default:
            throw TransientRefreshError(status: response.status)
        }
    }
}
