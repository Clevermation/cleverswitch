// Codex-CLI-Auth: auth.json-Blob, JWT-Identität, Token-Refresh.
//
// Blob-JSON (Datei ~/.codex/auth.json): {"tokens": {access_token, refresh_token, id_token,
// account_id}, "last_refresh", ...}. Identität + Plan stecken im id_token (JWT-Payload:
// `email` und `https://api.openai.com/auth`.chatgpt_plan_type / .chatgpt_account_id).

import Foundation

public enum CodexAuth {
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    static let authClaimKey = "https://api.openai.com/auth"

    // MARK: - JWT

    /// Dekodiert die Payload eines JWT ohne Signaturprüfung (nur lokale Identitäts-Anzeige).
    public static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    // MARK: - Blob-Helfer

    private static func root(_ blob: String) -> [String: Any]? {
        guard let data = blob.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func tokens(_ blob: String) -> [String: Any]? {
        root(blob)?["tokens"] as? [String: Any]
    }

    public static func accessToken(in blob: String) -> String? {
        tokens(blob)?["access_token"] as? String ?? root(blob)?["access_token"] as? String
    }

    public static func refreshToken(in blob: String) -> String? {
        tokens(blob)?["refresh_token"] as? String
    }

    /// ChatGPT-Account-ID (Header für den Usage-Endpoint).
    public static func accountID(in blob: String) -> String? {
        if let id = tokens(blob)?["account_id"] as? String { return id }
        guard let idToken = tokens(blob)?["id_token"] as? String,
            let payload = decodeJWTPayload(idToken),
            let auth = payload[authClaimKey] as? [String: Any]
        else { return nil }
        return auth["chatgpt_account_id"] as? String
    }

    public static func email(in blob: String) -> String? {
        guard let idToken = tokens(blob)?["id_token"] as? String,
            let payload = decodeJWTPayload(idToken)
        else { return nil }
        return payload["email"] as? String
    }

    public static func planType(in blob: String) -> String? {
        guard let idToken = tokens(blob)?["id_token"] as? String,
            let payload = decodeJWTPayload(idToken),
            let auth = payload[authClaimKey] as? [String: Any]
        else { return nil }
        return auth["chatgpt_plan_type"] as? String
    }

    /// Merge der Token-Response in den Blob (unbekannte Felder bleiben erhalten).
    static func applyTokenResponse(into blob: String, responseBody: Data, now: Date = Date()) -> String? {
        guard var rootDict = root(blob),
            let response = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any]
        else { return nil }
        var tokensDict = rootDict["tokens"] as? [String: Any] ?? [:]
        for key in ["access_token", "refresh_token", "id_token", "account_id"] {
            if let value = response[key] { tokensDict[key] = value }
        }
        rootDict["tokens"] = tokensDict
        rootDict["last_refresh"] = ISO8601DateFormatter().string(from: now)
        guard let data = try? JSONSerialization.data(withJSONObject: rootDict),
            let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    // MARK: - Netzwerk

    /// Erneuert den Access-Token via Refresh-Token (form-urlencoded, OpenAI-Auth).
    public static func refresh(_ blob: String, http: HTTPClient, now: Date = Date()) async throws -> String {
        guard let token = refreshToken(in: blob) else { throw CredentialsExpiredError() }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: token),
            URLQueryItem(name: "client_id", value: clientID),
        ]
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await http.send(request)
        switch response.status {
        case 200:
            guard let updated = applyTokenResponse(into: blob, responseBody: response.body, now: now) else {
                throw TransientRefreshError(status: 200)
            }
            return updated
        case 400, 401:
            let body = String(data: response.body, encoding: .utf8) ?? ""
            if body.contains("invalid_grant") || body.contains("already been used")
                || body.contains("token_invalidated")
            {
                throw CredentialsExpiredError()
            }
            throw TransientRefreshError(status: response.status)
        default:
            throw TransientRefreshError(status: response.status)
        }
    }
}
