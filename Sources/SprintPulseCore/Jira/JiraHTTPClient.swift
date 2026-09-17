import Foundation

/// The live Jira Data Center client's HTTP layer: a configured base URL, one Personal Access
/// Token supplied as a value, and a transport behind which every request is testable without
/// a network (#2's testing decisions: no test performs a real call, none needs a Jira).
///
/// Authentication is Bearer with a PAT and nothing else: no Basic, no OAuth, no Jira Cloud.
/// This holds by construction — `Authorization: Bearer` is the only header this type can
/// produce, and the token arrives only as an argument, from the single Keychain item the app
/// layer stores. With no token the client refuses the request (`.missingToken`) rather than
/// falling back to any other credential source (#10).
///
/// #10 ships the one request that is about identity — `GET /rest/api/2/myself`, resolved once
/// at credential setup. The sprint reads join here in #11, keeping the bounded call surface
/// exactly three operations; nothing else may be added to this type without amending #2.
public struct JiraHTTPClient: Sendable {
    /// Held to the access level it is used at: nothing outside this type reads the configured
    /// URL back out of the client.
    private let baseURL: URL

    /// Held only to build the `Authorization` header. Never logged, never serialised: see
    /// `description`, and see the Keychain item for where it lives at rest.
    private let token: String
    private let transport: any JiraTransport

    /// Validates configuration rather than sending anything: an empty token or a base URL that
    /// is not a full http(s) URL is a setup mistake to show the Operator, not a network
    /// condition to map onto the failure states.
    public init(baseURL: URL, token: String, transport: any JiraTransport) throws {
        guard !token.isEmpty else { throw JiraClientError.missingToken }
        guard baseURL.scheme == "https" || baseURL.scheme == "http",
              let host = baseURL.host, !host.isEmpty else {
            throw JiraClientError.invalidBaseURL(detail: "expected a full http(s) URL with a host, got \(baseURL.absoluteString)")
        }
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    /// Resolves the Operator's identity from `GET /rest/api/2/myself`, storing both `key` and
    /// `name` so assignee matching survives a username change (#10). The Operator is never
    /// asked to type their own username — a typo there yields a confident, empty forecast
    /// rather than an error, which is why this is the only way an identity enters the app.
    public func myself() async throws -> OperatorIdentity {
        let request = try request(path: "rest/api/2/myself")
        let response: JiraHTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as URLError {
            // A failure that never produced a response: unreachable host, refused TLS, or
            // something that keeps its own name. Never collapsed onto the others (#10).
            throw JiraClientError(urlError: error, host: baseURL.host ?? baseURL.absoluteString)
        }
        try Self.accept(response, for: request)

        let user: JiraUser
        do {
            user = try JiraDecoding.decoder().decode(JiraUser.self, from: response.body)
        } catch {
            throw JiraClientError.malformedResponse
        }
        guard let key = user.key, !key.isEmpty, let name = user.name, !name.isEmpty else {
            throw JiraClientError.malformedResponse
        }
        return OperatorIdentity(key: key, name: name)
    }

    /// One HTTP response, one distinct state. 401/403 rejected the credential, 404 named a
    /// path that does not exist on the configured host, and every other status keeps its own
    /// number rather than borrowing one of those readings — 200 alone is readable, because
    /// 204 and friends carry no body to decode. This is the shared rule every request on
    /// this client fails through, the sprint reads included (#11).
    private static func accept(_ response: JiraHTTPResponse, for request: URLRequest) throws {
        switch response.statusCode {
        case 200: return
        case 401, 403: throw JiraClientError.credentialRejected
        case 404:
            throw JiraClientError.pathNotFound(path: request.url?.absoluteString ?? "<no url>")
        default: throw JiraClientError.unexpectedStatus(code: response.statusCode)
        }
    }

    /// Builds the one request shape this client knows: GET, absolute against the configured
    /// base URL, Bearer token. No other authentication is constructible from here.
    private func request(path: String) throws -> URLRequest {
        let base = baseURL.hasDirectoryPath
            ? baseURL
            : URL(string: baseURL.absoluteString + "/")!
        guard let url = URL(string: path, relativeTo: base) else {
            throw JiraClientError.invalidBaseURL(detail: "can't append \(path) to \(baseURL.absoluteString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Redacted by design. The default memberwise description of a struct would print the
    /// token into any log, crash report, or playground that ever echoes the client — so the
    /// type says what it is and hides what it authenticates with.
    public var description: String {
        "JiraHTTPClient(baseURL: \(baseURL.absoluteString), auth: Bearer ‹redacted›)"
    }
}

extension JiraHTTPClient: CustomStringConvertible {}
