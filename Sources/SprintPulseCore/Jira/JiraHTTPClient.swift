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
/// The whole of what Sprint Pulse can ask Jira for is the three public reads below, and the
/// bounded call surface is a claim about this type: `myself` (#10, credential setup only), the
/// active sprints on one Board, and one sprint's Issues (#11). The last two read *listings*, so
/// they repeat their own request until it closes — more requests, never a second kind of request.
/// `LiveJiraGateway` is the only caller of the sprint reads, and the panel is the only caller of
/// the gateway: a fetch happens on window open and on explicit refresh, and no timer anywhere in
/// the app reaches this file.
public struct JiraHTTPClient: Sendable {
    /// Held to the access level it is used at: nothing outside this type reads the configured
    /// URL back out of the client.
    private let baseURL: URL

    /// Held only to build the `Authorization` header. Never logged, never serialised: see
    /// `description`, and see the Keychain item for where it lives at rest.
    private let token: String
    private let transport: any JiraTransport

    /// The Agile listings are paged, 50 entries per request — Jira's own default. Paging is not
    /// a fourth operation: it is the same read, asked again for the next slice.
    static let pageSize = 50

    /// How far a listing is followed before the read is called off. The bound exists so that a
    /// server which never closes a page — a captive portal, a plugin that ignores `startAt` —
    /// cannot turn one panel open into an endless request loop. Crossing it is reported
    /// (`.incompleteRead`), never quietly truncated: forecasting the first 2 000 Issues of a
    /// 5 000-Issue sprint as though they were the sprint is the kind of confident wrong number
    /// this instrument exists to avoid.
    static let maxPages = 40

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

    // MARK: - The three reads (#2's bounded call surface for M1)

    /// Resolves the Operator's identity from `GET /rest/api/2/myself`, storing both `key` and
    /// `name` so assignee matching survives a username change (#10). The Operator is never
    /// asked to type their own username — a typo there yields a confident, empty forecast
    /// rather than an error, which is why this is the only way an identity enters the app.
    public func myself() async throws -> OperatorIdentity {
        let user: JiraUser = try await get(path: "rest/api/2/myself")
        guard let key = user.key, !key.isEmpty, let name = user.name, !name.isEmpty else {
            throw JiraClientError.malformedResponse
        }
        return OperatorIdentity(key: key, name: name)
    }

    /// `GET /rest/agile/1.0/board/{boardId}/sprint?state=active`, every page of it — the raw
    /// envelope, so a Board reporting two active sprints arrives as two and the Operator names
    /// the tracked one (#11). The instrument never reads a sprint that is not active, which is
    /// why `state=active` is part of the request rather than a filter applied afterwards.
    ///
    /// An empty page ends the walk even where `isLast` did not: the Board's envelope has no
    /// total to be short of, so a page that delivers nothing has nothing left to deliver. The
    /// paging bound still fails the read rather than returning a partial Board — a Board whose
    /// second active sprint went unread would forecast the wrong sprint in silence, which is the
    /// one outcome this instrument is not allowed.
    public func activeSprints(onBoard boardID: Int) async throws -> JiraSprintsResponse {
        var paging = Paging(pageSize: Self.pageSize, maxPages: Self.maxPages)
        var collected: [JiraSprint] = []

        while true {
            let page: JiraSprintsResponse = try await get(
                path: "rest/agile/1.0/board/\(boardID)/sprint",
                query: paging.query(extra: ["state": "active"])
            )
            collected.append(contentsOf: page.values)
            paging.didReceive(count: page.values.count)
            if page.isLast || page.values.isEmpty { break }
            if paging.outOfPages {
                throw JiraClientError.incompleteRead(received: collected.count, pages: paging.pages)
            }
        }

        // Whole by construction, or the read threw: the assembled envelope says so, whatever the
        // last page's own flag claimed. Nothing downstream reads it; `SprintSnapshot` reads
        // `values`.
        return JiraSprintsResponse(
            maxResults: paging.stitchedMaxResults, startAt: 0, isLast: true, values: collected
        )
    }

    /// `GET /rest/agile/1.0/sprint/{sprintId}/issue`, every page of it, decoded with the
    /// Operator's own Estimate field. Paging to the envelope's own `total` is what keeps
    /// Team Scope honest on a large sprint — a single 50-issue page would forecast a subset of
    /// the sprint as the sprint, and `total` is Jira's word for how many Issues there are.
    public func issues(
        inSprint sprintID: Int,
        estimateFieldID: String = JiraDecoding.estimateFieldID
    ) async throws -> JiraSprintIssuesResponse {
        var paging = Paging(pageSize: Self.pageSize, maxPages: Self.maxPages)
        var collected: [JiraIssue] = []
        var total = 0

        while true {
            let page: JiraSprintIssuesResponse = try await get(
                path: "rest/agile/1.0/sprint/\(sprintID)/issue",
                query: paging.query(),
                estimateFieldID: estimateFieldID
            )
            collected.append(contentsOf: page.issues)
            paging.didReceive(count: page.issues.count)
            total = page.total
            if collected.count >= total { break }
            // Jira promised more than it delivered, or the paging bound is reached. Either way
            // the sprint cannot be read whole, and a slice of it is not a smaller truth — it is
            // a wrong one.
            if page.issues.isEmpty || paging.outOfPages {
                throw JiraClientError.incompleteRead(received: collected.count, pages: paging.pages)
            }
        }

        return JiraSprintIssuesResponse(
            startAt: 0, maxResults: paging.stitchedMaxResults, total: total, issues: collected
        )
    }

    // MARK: - One request shape, one failure rule

    /// Sends one request and decodes its body, or throws what went wrong. Every read above goes
    /// through here, so a status, a socket, and a body mean the same thing whichever of the
    /// three was asked.
    private func get<T: Decodable>(
        path: String,
        query: [String: String] = [:],
        estimateFieldID: String = JiraDecoding.estimateFieldID
    ) async throws -> T {
        let request = try request(path: path, query: query)
        let response: JiraHTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as URLError {
            // A failure that never produced a response: unreachable host, refused TLS, or
            // something that keeps its own name. Never collapsed onto the others (#10).
            throw JiraClientError(urlError: error, host: baseURL.host ?? baseURL.absoluteString)
        }
        try Self.accept(response, for: request)

        do {
            return try JiraDecoding.decoder(estimateFieldID: estimateFieldID)
                .decode(T.self, from: response.body)
        } catch {
            throw JiraClientError.malformedResponse
        }
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
    ///
    /// Query items are sorted by name so the same read always produces the same URL — the
    /// bounded call surface is checkable by comparing requests, which is how its tests prove it.
    private func request(path: String, query: [String: String] = [:]) throws -> URLRequest {
        let base = baseURL.hasDirectoryPath
            ? baseURL
            : URL(string: baseURL.absoluteString + "/")!
        guard let resolved = URL(string: path, relativeTo: base) else {
            throw JiraClientError.invalidBaseURL(detail: "can't append \(path) to \(baseURL.absoluteString)")
        }
        var url = resolved
        if !query.isEmpty {
            guard var components = URLComponents(url: resolved, resolvingAgainstBaseURL: true) else {
                throw JiraClientError.invalidBaseURL(detail: "can't add parameters to \(resolved.absoluteString)")
            }
            components.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let parameterised = components.url else {
                throw JiraClientError.invalidBaseURL(detail: "can't add parameters to \(resolved.absoluteString)")
            }
            url = parameterised
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

/// How far into an Agile listing a read has got, and the bound past which it is called off
/// rather than truncated. Both listings walk the same way and differ only in what "closed"
/// means — `isLast` for the Board's sprints, `total` for a sprint's Issues — so the bookkeeping
/// is one type and the stop rule stays with each caller (#11).
private struct Paging {
    private(set) var startAt = 0
    private(set) var pages = 0
    let pageSize: Int
    let maxPages: Int

    /// The paging parameters, plus anything the listing filters on server-side.
    func query(extra: [String: String] = [:]) -> [String: String] {
        extra.merging(["maxResults": "\(pageSize)", "startAt": "\(startAt)"]) { _, new in new }
    }

    mutating func didReceive(count: Int) {
        pages += 1
        startAt += count
    }

    /// The paging bound is reached: the listing is not closing, and the read has to be named
    /// incomplete instead of quietly reporting a slice as the whole.
    var outOfPages: Bool { pages >= maxPages }

    /// What the assembled envelope reports as its own `maxResults`: the pages this read asked
    /// for, stitched. One expression for both listings so the two cannot drift apart.
    var stitchedMaxResults: Int { pages * pageSize }
}
