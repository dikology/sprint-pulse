import XCTest
import SprintPulseCore
@testable import SprintPulse

/// The setup flow (#10) at its own seam: the identity probe is injected the way the core
/// client injects its transport, so the whole flow — persistence atomicity, confirmation,
/// revocation, and the "the token appears in exactly one place" claim — runs without a Jira,
/// a VPN, or a network call. The probe doubles honour the real contract: they only answer
/// with a resolved identity or a `JiraClientError`, exactly like `JiraHTTPClient.myself()`.
@MainActor
final class JiraSetupModelTests: XCTestCase {
    /// A token that must never be findable anywhere except the test Keychain item: every
    /// failure and preference assertion below searches for this string and demands absence.
    let sentinel = "SENTINEL-9f3c-never-in-preferences"

    let identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")
    let baseURL = "https://jira.example.com"

    private let suiteName = "SprintPulseAppTests.JiraSetupModel"
    private let credentials = JiraCredentialStore.testItem()
    private var defaults: UserDefaults!
    private var settings: JiraSettingsStore { JiraSettingsStore(defaults: defaults) }

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        try skipUnlessKeychainWorks(credentials)
        try credentials.delete()
    }

    override func tearDown() {
        try? credentials.delete()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - Successful setup

    func test_connect_withAResolvedIdentity_storesTheTokenAndConfirmsWhoItIs() async throws {
        let model = makeModel(probe: .success(identity))
        model.baseURLText = baseURL
        model.tokenText = sentinel

        await model.connect()

        XCTAssertEqual(model.state, .resolved(identity), "the resolved identity is confirmed back")
        XCTAssertEqual(try credentials.read(), sentinel, "the token's only resting place is the item")
        XCTAssertEqual(settings.identity, identity, "both key and name, stored")
        XCTAssertEqual(settings.baseURLString, baseURL)
        XCTAssertEqual(model.tokenText, "", "the draft never outlives the attempt")
    }

    func test_theTokenIsWrittenNowhereElse_preferencesHoldNothingLikeIt() async throws {
        let model = makeModel(probe: .success(identity))
        model.baseURLText = baseURL
        model.tokenText = sentinel
        await model.connect()

        // A sweep of the whole suite's stored state — the settings store is innocent by
        // construction, but the flow is where a leak would be authored, so the claim is
        // tested at the flow.
        for (key, value) in defaults.dictionaryRepresentation() {
            let rendered = String(describing: value)
            XCTAssertFalse(rendered.contains(sentinel), "preferences key \(key) holds the token")
        }
    }

    func test_connect_trimsAPastedToken_beforeAskingJira() async throws {
        // Pasted PATs arrive wearing trailing newlines; asking with one attached reports a
        // rejected token for a valid credential — a wrong-named failure (#10).
        let recorder = ProbeRecorder(result: .success(identity))
        let model = JiraSetupModel(
            credentials: credentials, settings: settings, probe: recorder.probe
        )
        model.baseURLText = baseURL
        model.tokenText = "\n\(sentinel)\n"

        await model.connect()

        XCTAssertEqual(recorder.lastToken, sentinel, "the probe asks with the trimmed token")
        XCTAssertEqual(try credentials.read(), sentinel, "and stores the trimmed token")
    }

    // MARK: - Failed setup persists nothing

    func test_connect_withARejectedToken_persistsNothingAndSaysWhichFailureItWas() async throws {
        let model = makeModel(probe: .failure(.credentialRejected))
        model.baseURLText = baseURL
        model.tokenText = sentinel

        await model.connect()

        let message = try XCTUnwrap(model.state.failureMessage)
        XCTAssertEqual(message, JiraClientError.credentialRejected.message)
        XCTAssertFalse(message.contains(sentinel))
        XCTAssertNil(try credentials.read(), "a refused setup leaves no credential behind")
        XCTAssertNil(settings.identity)
        XCTAssertNil(settings.baseURLString, "fixture mode is the default again — nothing exists")
        XCTAssertEqual(model.tokenText, "")
    }

    func test_connect_eachDistinctFailure_showsItsOwnMessageVerbatim() async throws {
        let failures: [JiraClientError] = [
            .unreachableHost(host: "jira.example.com"),
            .tlsFailure(host: "jira.example.com"),
            .pathNotFound(path: "\(baseURL)/rest/api/2/myself"),
            .malformedResponse,
        ]
        for failure in failures {
            defaults.removePersistentDomain(forName: suiteName)
            try credentials.delete()
            let model = makeModel(probe: .failure(failure))
            model.baseURLText = baseURL
            model.tokenText = sentinel

            await model.connect()

            XCTAssertEqual(
                model.state.failureMessage, failure.message,
                "\(failure): the flow renders the state's own message, untouched"
            )
            XCTAssertNil(try credentials.read(), "\(failure)")
        }
    }

    func test_connect_withNoBaseURLTyped_neverProbes() async throws {
        let recorder = ProbeRecorder(result: .success(identity))
        let model = JiraSetupModel(
            credentials: credentials, settings: settings, probe: recorder.probe
        )
        model.tokenText = sentinel

        await model.connect()

        XCTAssertFalse(recorder.called, "nothing is sent without a configured base URL")
        XCTAssertEqual(
            model.state.failureMessage,
            JiraClientError.invalidBaseURL(detail: "not a parseable URL: ").message
        )
        XCTAssertNil(try credentials.read())
    }

    // MARK: - Launch and revocation

    func test_launch_withAStoredCredential_resumesConfirmed() async throws {
        try credentials.save(sentinel)
        settings.baseURLString = baseURL
        settings.identity = identity

        let model = makeModel(probe: .failure(.malformedResponse))  // must never be needed

        XCTAssertEqual(model.state, .resolved(identity))
    }

    func test_launch_withNoCredential_isNotConfigured_soFixturesStayDefault() async throws {
        let model = makeModel(probe: .failure(.malformedResponse))
        XCTAssertEqual(model.state, .notConfigured)
        XCTAssertFalse(model.hasStoredCredential)
    }

    func test_hasStoredCredential_seesAnItemTheFlowDidNotResolve() async throws {
        // A token with no identity beside it (prefs wiped, item kept) still counts as a
        // credential: the flow state is notConfigured, and the panel's removal control is
        // shown on presence rather than on state, so the item is never stranded.
        try credentials.save(sentinel)

        let model = makeModel(probe: .failure(.malformedResponse))

        XCTAssertEqual(model.state, .notConfigured)
        XCTAssertTrue(model.hasStoredCredential)
    }

    func test_removeCredential_deletesTheItemAndTheIdentity_andKeepsTheBaseURL() async throws {
        let model = makeModel(probe: .success(identity))
        model.baseURLText = baseURL
        model.tokenText = sentinel
        await model.connect()

        model.removeCredential()

        XCTAssertNil(try credentials.read())
        XCTAssertEqual(try credentials.countStoredItems(), 0)
        XCTAssertNil(settings.identity)
        XCTAssertEqual(settings.baseURLString, baseURL, "the URL is configuration, not a secret")
        XCTAssertEqual(model.state, .notConfigured, "fixtures are the default again, without deleting anything else")
    }

    // MARK: - Helpers

    /// A model over a probe double with a fixed verdict. The doubles stand in for
    /// `JiraHTTPClient.myself()` — including its refusal to proceed without a token, which
    /// `JiraHTTPClientTests` pins against the real client.
    private func makeModel(probe result: Result<OperatorIdentity, JiraClientError>) -> JiraSetupModel {
        JiraSetupModel(
            credentials: credentials,
            settings: settings,
            probe: { _, token in
                token.isEmpty
                    ? .failure(.missingToken)
                    : result
            }
        )
    }
}

private extension JiraSetupModel.State {
    /// The message the panel would render, when the state is a failure.
    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// A probe double that also answers "was it called at all" and "with which token".
private final class ProbeRecorder: @unchecked Sendable {
    private let result: Result<OperatorIdentity, JiraClientError>
    private(set) var called = false
    private(set) var lastToken: String?

    init(result: Result<OperatorIdentity, JiraClientError>) {
        self.result = result
    }

    var probe: JiraSetupModel.IdentityProbe {
        { [self] _, token in
            called = true
            lastToken = token
            return result
        }
    }
}
