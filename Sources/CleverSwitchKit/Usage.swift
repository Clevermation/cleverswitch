// Claude-Usage: Abruf + Mapping der API-Antwort auf das neutrale AccountUsage-Modell.
//
// API liefert {"five_hour":{"utilization","resets_at"},"seven_day":{...}} -> session/weekly.

import Foundation

public enum UsageResult: Sendable {
    case ok(AccountUsage)
    case unauthorized  // 401 — Token (vor Ablauf) widerrufen
    case failed  // sonstiger Fehler / nicht parsebar
}

public enum ClaudeUsageAPI {
    public static let usageURL = URL(string: "https://api.anthropic.com/oauth/usage")!
    public static let userAgent = "claude-code/2.1.11"

    /// Mappt die Usage-Response auf AccountUsage (five_hour->session, seven_day->weekly).
    public static func mapUsage(responseBody: Data) -> AccountUsage? {
        guard let object = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any] else {
            return nil
        }
        var windows: [UsageWindow] = []
        if let window = window(from: object["five_hour"], key: UsageWindowKey.session) {
            windows.append(window)
        }
        if let window = window(from: object["seven_day"], key: UsageWindowKey.weekly) {
            windows.append(window)
        }
        guard !windows.isEmpty else { return nil }
        return AccountUsage(known: true, windows: windows)
    }

    private static func window(from raw: Any?, key: String) -> UsageWindow? {
        guard let dict = raw as? [String: Any],
            let utilization = (dict["utilization"] as? NSNumber)?.doubleValue
        else { return nil }
        return UsageWindow(key: key, usedPct: utilization, resetsAt: dict["resets_at"] as? String)
    }

    public static func fetch(accessToken: String, http: HTTPClient) async throws -> UsageResult {
        var request = URLRequest(url: usageURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let response = try await http.send(request)
        switch response.status {
        case 200:
            return mapUsage(responseBody: response.body).map(UsageResult.ok) ?? .failed
        case 401:
            return .unauthorized
        default:
            return .failed
        }
    }
}

public enum CodexUsageAPI {
    /// Primärer Endpoint + Fallback (ChatGPT-Backend).
    public static let usageURLs = [
        URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        URL(string: "https://chatgpt.com/backend-api/api/codex/usage")!,
    ]

    /// Mappt die Codex-Usage-Response: primary_window->session, secondary_window->weekly.
    /// `reset_at` ist ein Unix-Timestamp und wird als String übernommen.
    public static func mapUsage(responseBody: Data) -> AccountUsage? {
        guard let object = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any]
        else { return nil }
        if let error = object["error"] as? [String: Any], error["code"] as? String == "login_required" {
            return nil
        }
        guard let rateLimit = object["rate_limit"] as? [String: Any] else { return nil }

        var windows: [UsageWindow] = []
        for (rawKey, key) in [("primary_window", UsageWindowKey.session), ("secondary_window", UsageWindowKey.weekly)] {
            guard let window = rateLimit[rawKey] as? [String: Any],
                let usedPct = (window["used_percent"] as? NSNumber)?.doubleValue
            else { continue }
            // int64 statt double: vermeidet e-Notation bei großen Unix-Timestamps.
            let resetsAt = (window["reset_at"] as? NSNumber).map { String($0.int64Value) }
            windows.append(UsageWindow(key: key, usedPct: usedPct, resetsAt: resetsAt))
        }
        guard !windows.isEmpty else { return nil }
        return AccountUsage(known: true, windows: windows)
    }

    /// Live-Plan aus der Usage-Response (verlässlicher als der ggf. veraltete JWT-Claim).
    public static func planType(responseBody: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any]
        else { return nil }
        return object["plan_type"] as? String
    }

    public static func fetch(
        accessToken: String, accountID: String, http: HTTPClient
    ) async throws -> (result: UsageResult, planType: String?) {
        var sawUnauthorized = false
        for url in usageURLs {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")

            guard let response = try? await http.send(request) else { continue }
            switch response.status {
            case 200:
                if let usage = mapUsage(responseBody: response.body) {
                    return (.ok(usage), planType(responseBody: response.body))
                }
            case 401, 403:
                sawUnauthorized = true
            default:
                continue
            }
        }
        return (sawUnauthorized ? .unauthorized : .failed, nil)
    }
}
