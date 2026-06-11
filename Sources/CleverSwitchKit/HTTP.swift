// Schmale HTTP-Abstraktion, damit Auth-/Usage-Logik gegen einen Fake testbar ist.

import Foundation

/// Antwort eines HTTP-Requests (Status + Rohdaten).
public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Versendet einen Request und liefert Status + Body.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// Echte Implementierung über `URLSession`.
///
/// Eigene Session mit Redirect-Wächter: bei einem Host-Wechsel wird der Redirect NICHT
/// gefolgt (würde sonst den `Authorization: Bearer`-Header an einen fremden Host tragen).
public final class LiveHTTPClient: HTTPClient {
    private let session: URLSession

    public init() {
        session = URLSession(
            configuration: .ephemeral, delegate: RedirectGuard(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, body: data)
    }

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            let sameHost = task.originalRequest?.url?.host == request.url?.host
            completionHandler(sameHost ? request : nil)
        }
    }
}
