import Foundation

/// The part of an HTTP response the live Jira client reads: a status code and a body.
///
/// Deliberately not `HTTPURLResponse` — the tests must be able to hand the client a response
/// without the network, and minting a URL-response object for a URL that was never fetched is
/// a ceremony with no assertion behind it.
public struct JiraHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// The single HTTP seam beneath the live Jira client.
///
/// A self-hosted instance is unreachable more often than it is reachable (#2), so the failure
/// path of this integration matters as much as the success path — and unlike a socket, a failure
/// must be *described*, not just thrown. The protocol exists so every state a fetch can end in
/// is exercisable without a Jira, a VPN, or a credential: production traffic goes through the
/// app's `URLSessionJiraTransport`, tests go through a stub that replays recorded responses
/// and errors. No test in this repository performs a real network call.
public protocol JiraTransport: Sendable {
    /// Sends the request and returns its status and body. Throws a `URLError` when the request
    /// never produced a response — the connection-level failures the client maps to distinct
    /// states (`unreachableHost`, `tlsFailure`).
    func send(_ request: URLRequest) async throws -> JiraHTTPResponse
}
