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
        var changes = 0
        model.onConfigurationChanged = { changes += 1 }
        model.baseURLText = baseURL
        model.tokenText = sentinel
        await model.connect()
        XCTAssertEqual(changes, 1, "a resolved credential makes a Board readable — the panel is told")

        model.removeCredential()
        XCTAssertEqual(changes, 2, "and revoking it is heard in the same breath, not at next refresh (#11)")

        XCTAssertNil(try credentials.read())
        XCTAssertEqual(try credentials.countStoredItems(), 0)
        XCTAssertNil(settings.identity)
        XCTAssertEqual(settings.baseURLString, baseURL, "the URL is configuration, not a secret")
        XCTAssertEqual(model.state, .notConfigured, "fixtures are the default again, without deleting anything else")
    }

    // MARK: - The Board and the Estimate field (#11)

    /// The Board is the Operator's configuration, remembered once, and read off the Board's own
    /// address when it is pasted — no probe, because remembering a number authenticates nothing.
    func test_saveBoard_acceptsAnId_orABoardURL_andRemembersIt() throws {
        for (entry, expected) in [
            ("172", 172),
            ("  172  ", 172),
            ("https://jira.example.com/jira/software/projects/MP/boards/172", 172),
            ("https://jira.example.com/secure/RapidBoard.jspa?rapidView=172", 172),
            (".../boards/172?selectedIssue=MOB-1201", 172),
        ] {
            defaults.removePersistentDomain(forName: suiteName)
            let model = makeModel(probe: .success(identity))
            model.boardText = entry

            model.saveBoard()

            XCTAssertEqual(settings.boardID, expected, entry)
            XCTAssertNil(model.configurationProblem, entry)
        }
    }

    /// A mistyped Board is refused and *not* stored: a Board of `nil` alongside a configured
    /// credential would leave the panel reading fixtures while the Operator believes it reads their
    /// sprint (#11's "remembered once" only means something if what is remembered is valid).
    func test_saveBoard_refusesWhatIsNotABoard_andStoresNothing() throws {
        for entry in ["Mobile Platform", "172abc", "17 2", "boards/"] {
            defaults.removePersistentDomain(forName: suiteName)
            let model = makeModel(probe: .success(identity))
            var remembered = 0
            model.onConfigurationChanged = { remembered += 1 }
            model.boardText = entry

            model.saveBoard()

            XCTAssertNil(settings.boardID, entry)
            XCTAssertNotNil(model.configurationProblem, entry)
            XCTAssertEqual(remembered, 0, "\(entry): a refused entry asks the panel for nothing")
        }
    }

    func test_saveBoard_firesTheRememberedCallback_soThePanelReadsIt() throws {
        let model = makeModel(probe: .success(identity))
        var remembered = 0
        model.onConfigurationChanged = { remembered += 1 }
        model.boardText = "172"

        model.saveBoard()

        XCTAssertEqual(remembered, 1, "saving a Board is an explicit request to read it (#11)")
    }

    /// The Estimate field is per-instance, and an Operator who finds it will write the id in one
    /// of the two forms Jira shows it in. Both arrive at the same stored value.
    func test_saveEstimateField_normalisesEitherForm() throws {
        for entry in ["customfield_10007", "10007", " customfield_10007 "] {
            defaults.removePersistentDomain(forName: suiteName)
            let model = makeModel(probe: .success(identity))
            model.estimateFieldText = entry

            model.saveEstimateField()

            XCTAssertEqual(settings.estimateFieldID, "customfield_10007", entry)
            XCTAssertEqual(model.estimateFieldText, "customfield_10007", "the field shows what was stored")
            XCTAssertNil(model.configurationProblem, entry)
        }
    }

    func test_saveEstimateField_emptyRestoresTheDefault() throws {
        let model = makeModel(probe: .success(identity))
        model.estimateFieldText = ""

        model.saveEstimateField()

        XCTAssertNil(settings.estimateFieldID, "absent means the documented default, decided by the reader")
        XCTAssertNil(model.configurationProblem)
    }

    func test_saveEstimateField_refusesSomethingThatIsNotACustomFieldId() throws {
        for entry in ["Story Points", "customfield_", "abc123"] {
            defaults.removePersistentDomain(forName: suiteName)
            let model = makeModel(probe: .success(identity))
            model.estimateFieldText = entry

            model.saveEstimateField()

            XCTAssertNil(settings.estimateFieldID, entry)
            XCTAssertNotNil(model.configurationProblem, entry)
        }
    }

    /// Launch restores the Board and the Estimate field beside the credential, so "configured
    /// once" survives a quit (#11).
    func test_launch_restoresTheBoardAndTheEstimateField() throws {
        try credentials.save(sentinel)
        settings.baseURLString = baseURL
        settings.identity = identity
        settings.boardID = 172
        settings.estimateFieldID = "customfield_10007"

        let model = makeModel(probe: .failure(.malformedResponse))

        XCTAssertEqual(model.boardText, "172")
        XCTAssertEqual(model.estimateFieldText, "customfield_10007")
    }

    /// Removing the credential is the Operator revoking access, not re-doing configuration: the
    /// Board and the Estimate field are kept for the next token, exactly as the base URL is.
    func test_removeCredential_keepsTheBoardAndEstimateField() async throws {
        let model = makeModel(probe: .success(identity))
        model.baseURLText = baseURL
        model.tokenText = sentinel
        await model.connect()
        model.boardText = "172"
        model.saveBoard()
        model.estimateFieldText = "10007"
        model.saveEstimateField()

        model.removeCredential()

        XCTAssertEqual(settings.boardID, 172)
        XCTAssertEqual(settings.estimateFieldID, "customfield_10007")
        XCTAssertEqual(settings.trackedSprintID, nil)
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
