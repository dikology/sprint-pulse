import Foundation
import SprintPulseCore

/// The production `JiraTransport`: URLSession over the request the core client built.
///
/// It lives in the app because it *is* a platform concern — core defines the seam and reads
/// only status and body, the way it reads only values from the Keychain store (#2's split).
///
/// One shared **ephemeral** session, deliberately configured out of two things the default
/// session quietly carries: `URLCredentialStorage` (a challenge answered from stored
/// credentials would be a second credential source — #10 forbids the fallback, so the
/// storage is made structurally absent, not just unused) and the on-disk `URLCache` (a
/// cached `/myself` body is identity data written to disk — the token never is, and nothing
/// else is either). Ephemeral sessions must be invalidated or they leak, so the app holds
/// exactly one for its lifetime rather than minting one per request.
struct URLSessionJiraTransport: JiraTransport {
    static let shared = URLSessionJiraTransport(session: URLSession(configuration: .ephemeral))

    private let session: URLSession

    private init(session: URLSession) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> JiraHTTPResponse {
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            // Not HTTP at the end of an http(s) request — a response nothing can be read from.
            throw JiraClientError.malformedResponse
        }
        return JiraHTTPResponse(statusCode: http.statusCode, body: body)
    }
}
