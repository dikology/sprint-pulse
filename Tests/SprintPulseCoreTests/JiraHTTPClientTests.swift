import XCTest
@testable import SprintPulseCore

/// The identity half of the live integration (#10), tested at the transport seam — the
/// gateway boundary M1's testing decisions fixed for HTTP: recorded response bodies and
/// stubbed transport, no real network call, no Jira, no VPN, no credential required to run.
///
/// The response bodies are transcribed in the shape Jira Data Center emits from
/// `/rest/api/2/myself`, including the fields the model ignores — a decoding bug should
/// surface as a wrong identity here, the same style the fixture corpus uses for sprint reads.
///
/// #11's two sprint reads live on this type too and are tested in `LiveJiraGatewayTests`, at the
/// gateway boundary the protocol draws. They fail through the same `accept` rule asserted here,
/// which is why one set of failure states covers three operations.
final class JiraHTTPClientTests: XCTestCase {
    /// An opaque stand-in for a real PAT: what the token asserts about here is that it only
    /// ever travels in the `Authorization` header, never in a message or a description.
    let token = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY"

    func test_myself_resolvesIdentity_fromTheDataCenterResponse() async throws {
        let transport = StubJiraTransport(statusCode: 200, body: Self.myselfBody)
        let client = try JiraHTTPClient(
            baseURL: URL(string: "https://jira.example.com")!, token: token, transport: transport
        )

        let identity = try await client.myself()

        XCTAssertEqual(identity, OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov"))
    }

    func test_myself_asksWithBearerToken_andNoOtherAuth() async throws {
        let transport = StubJiraTransport(statusCode: 200, body: Self.myselfBody)
        let client = try JiraHTTPClient(
            baseURL: URL(string: "https://jira.example.com")!, token: token, transport: transport
        )
        _ = try await client.myself()

        let request = try XCTUnwrap(transport.requests.only)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://jira.example.com/rest/api/2/myself")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
    }

    // MARK: - Failure states are distinguished, not collapsed (#10)

    func test_myself_rejectedToken_isCredentialRejected_401and403() async throws {
        for code in [401, 403] {
            let error = await expectClientError(StubJiraTransport(statusCode: code, body: ""))
            XCTAssertEqual(error, .credentialRejected, "status \(code)")
        }
    }

    func test_myself_missingPath_isPathNotFound_namingTheFullURL() async throws {
        let error = await expectClientError(StubJiraTransport(statusCode: 404, body: "Whoops — there's nothing here"))
        XCTAssertEqual(
            error,
            .pathNotFound(path: "https://jira.example.com/rest/api/2/myself"),
            "404 must name where it looked, so a wrong base URL is visible"
        )
    }

    func test_myself_baseUrlWithContextPath_404namesTheFullConfiguredPath() async throws {
        let error = await expectClientError(
            StubJiraTransport(statusCode: 404, body: ""),
            baseURL: URL(string: "https://jira.example.com/wrong/prefix")!
        )
        XCTAssertEqual(
            error,
            .pathNotFound(path: "https://jira.example.com/wrong/prefix/rest/api/2/myself")
        )
    }

    func test_myself_aStatusWithNoDistinctReading_keepsItsOwnNumber() async throws {
        let error = await expectClientError(StubJiraTransport(statusCode: 500, body: "Internal Server Error"))
        XCTAssertEqual(error, .unexpectedStatus(code: 500))
    }

    func test_myself_hostDownOrVpnOff_isUnreachableHost() async throws {
        // The codes a self-hosted instance behind a VPN actually produces: unknown name,
        // refused connection, a dropped link, no route, a blackholed timeout.
        for code in [URLError.Code.cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                     .notConnectedToInternet, .timedOut] {
            let error = await expectClientError(StubJiraTransport(error: URLError(code)))
            XCTAssertEqual(error, .unreachableHost(host: "jira.example.com"), "\(code.rawValue)")
        }
    }

    func test_myself_tlsRejection_isTLSTrouble_neverFoldedIntoUnreachable() async throws {
        // A corporate CA missing from the trust store and an expired certificate look alike
        // to the socket and must not look alike to the Operator ("not a token problem").
        for code in [URLError.Code.secureConnectionFailed, .serverCertificateUntrusted,
                     .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot] {
            let error = await expectClientError(StubJiraTransport(error: URLError(code)))
            XCTAssertEqual(error, .tlsFailure(host: "jira.example.com"), "\(code.rawValue)")
        }
    }

    func test_myself_otherConnectionFailure_isNamed_notBorrowedFromAnotherState() async throws {
        let error = await expectClientError(StubJiraTransport(error: URLError(.userAuthenticationRequired)))
        guard case .connectionFailed = error else {
            return XCTFail("expected connectionFailed, got \(String(describing: error))")
        }
    }

    func test_myself_bodyThatIsNotJSON_isMalformedResponse() async throws {
        let error = await expectClientError(
            StubJiraTransport(statusCode: 200, body: "<html><body>Login page</body></html>")
        )
        XCTAssertEqual(error, .malformedResponse)
    }

    func test_myself_responseWithoutKeyOrName_isMalformedResponse() async throws {
        // A 200 that carries a user minus what identity needs (some SSO-filtered responses
        // do exactly this) must never resolve to a half identity.
        let bodies = [
            #"{"name": "dgimaletdinov"}"#,
            #"{"key": "JIRAUSER10500"}"#,
            #"{"name": "", "key": "JIRAUSER10500"}"#,
        ]
        for body in bodies {
            let error = await expectClientError(StubJiraTransport(statusCode: 200, body: body))
            XCTAssertEqual(error, .malformedResponse, body)
        }
    }

    // MARK: - Messages

    /// Every distinct state, once. The acceptance criterion is that they do not collapse, so
    /// both message properties are asserted over this one list rather than re-typed per test.
    static let allStates: [JiraClientError] = [
        .unreachableHost(host: "jira.example.com"),
        .tlsFailure(host: "jira.example.com"),
        .credentialRejected,
        .pathNotFound(path: "https://jira.example.com/rest/api/2/myself"),
        .malformedResponse,
        .unexpectedStatus(code: 503),
        .incompleteRead(received: 50, pages: 40),
        .connectionFailed(reason: "proxy asked for authentication"),
        .missingToken,
        .invalidBaseURL(detail: "not http(s)"),
    ]

    func test_messages_arePairwiseDistinct() {
        for a in Self.allStates {
            for b in Self.allStates where a != b {
                XCTAssertNotEqual(a.message, b.message, "\(a) and \(b) would collapse on the panel")
            }
        }
    }

    func test_noErrorMessageCarriesTheToken() throws {
        for error in Self.allStates {
            XCTAssertFalse(error.message.contains(token), "\(error) leaked the token")
            XCTAssertFalse(String(describing: error).contains(token), "\(error) leaked the token")
        }

        // And not via the client's own reflection: the memberwise description of a struct
        // would otherwise print the token into any log that echoes it.
        let client = try client(
            with: StubJiraTransport(statusCode: 200, body: Self.myselfBody),
            baseURL: URL(string: "https://jira.example.com")!
        )
        XCTAssertFalse(String(describing: client).contains(token), "description leaked the token")
    }

    func test_clientConfigurationRefusesWithoutAToken_orWithANonHttpBaseURL() {
        // Refusing here is AC #5: no token means no live request — never a fallback to some
        // other credential source.
        XCTAssertThrowsError(
            try JiraHTTPClient(
                baseURL: URL(string: "https://jira.example.com")!, token: "",
                transport: StubJiraTransport(statusCode: 200, body: "{}")
            )
        ) { XCTAssertEqual($0 as? JiraClientError, .missingToken) }

        for bad in ["ftp://jira.example.com", "jira.example.com", "https://"] {
            let url = URL(string: bad)!
            XCTAssertThrowsError(
                try JiraHTTPClient(
                    baseURL: url, token: token,
                    transport: StubJiraTransport(statusCode: 200, body: "{}")
                ),
                bad
            ) { error in
                guard case .invalidBaseURL = error as? JiraClientError else {
                    return XCTFail("\(bad): expected invalidBaseURL, got \(String(describing: error))")
                }
            }
        }
    }

    func test_myself_trailingSlashInBaseURL_neverDoublesThePath() async throws {
        let transport = StubJiraTransport(statusCode: 200, body: Self.myselfBody)
        _ = try await client(
            with: transport, baseURL: URL(string: "https://jira.example.com/jira/")!
        ).myself()

        XCTAssertEqual(
            try XCTUnwrap(transport.requests.only).url?.absoluteString,
            "https://jira.example.com/jira/rest/api/2/myself"
        )
    }

    // MARK: - Helpers

    private func client(
        with transport: StubJiraTransport, baseURL: URL = URL(string: "https://jira.example.com")!
    ) throws -> JiraHTTPClient {
        try JiraHTTPClient(baseURL: baseURL, token: token, transport: transport)
    }

    /// Runs `myself()` against the stub and hands back the `JiraClientError` it must throw —
    /// a wrong error type is a failure too, since the panel renders `JiraClientError.message`.
    private func expectClientError(
        _ transport: StubJiraTransport,
        baseURL: URL = URL(string: "https://jira.example.com")!,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> JiraClientError? {
        do {
            _ = try await client(with: transport, baseURL: baseURL).myself()
            XCTFail("expected a JiraClientError", file: file, line: line)
            return nil
        } catch let error as JiraClientError {
            return error
        } catch {
            XCTFail("expected JiraClientError, got \(error)", file: file, line: line)
            return nil
        }
    }

    /// A captured-shape `/rest/api/2/myself` body: `key` and `name` as Data Center emits them,
    /// plus the Cloud-era `accountId` (null here) and the metadata fields the model ignores.
    static let myselfBody = """
    {
      "self": "https://jira.example.com/rest/api/2/user?username=dgimaletdinov",
      "name": "dgimaletdinov",
      "key": "JIRAUSER10500",
      "accountId": null,
      "emailAddress": "denis@example.com",
      "avatarUrls": {
        "48x48": "https://jira.example.com/secure/useravatar?ownerId=JIRAUSER10500&avatarId=10452",
        "24x24": "https://jira.example.com/secure/useravatar?size=small&ownerId=JIRAUSER10500&avatarId=10452"
      },
      "displayName": "Denis Gimaletdinov",
      "active": true,
      "timeZone": "Europe/Moscow",
      "locale": { "locale": "en_GB", "systemLocale": "en_US" },
      "expand": "locale,groups,applicationRoles,editMetadata"
    }
    """
}

/// Replays one canned result per request and records the requests, so the assertions are
/// about what the client asked for and what it made of the answer — nothing else.
final class StubJiraTransport: JiraTransport, @unchecked Sendable {
    private let result: Result<JiraHTTPResponse, Error>
    private(set) var requests: [URLRequest] = []

    init(result: Result<JiraHTTPResponse, Error>) {
        self.result = result
    }

    convenience init(statusCode: Int, body: String) {
        self.init(result: .success(
            JiraHTTPResponse(statusCode: statusCode, body: Data(body.utf8))
        ))
    }

    convenience init(error: Error) {
        self.init(result: .failure(error))
    }

    func send(_ request: URLRequest) async throws -> JiraHTTPResponse {
        requests.append(request)
        return try result.get()
    }
}

private extension Array {
    /// The element, when there is exactly one — so "asked once" and "asked with what" are
    /// one assertion that fails loudly on a double-send or an empty client.
    var only: Element? { count == 1 ? self[0] : nil }
}
