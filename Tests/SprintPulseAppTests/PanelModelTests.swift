import SprintPulseCore
import XCTest
@testable import SprintPulse

/// The panel's live path (#11), tested at the same seam the setup flow tests the credential:
/// the gateway is handed in, so the whole of what the app does around a read is exercisable
/// without a Jira, a VPN, or a network call.
///
/// What is checked here is the app's own business, because the domain's is checked in
/// `SprintPulseCoreTests` against the identical JSON shapes: *when* a live read happens, which
/// configuration reaches the gateway, what the panel shows when a Board reports two active
/// sprints or none, what a resolved identity matching nothing looks like, and what a failed
/// fetch leaves standing.
///
/// These cases decide live-versus-fixture by asking the Keychain whether a credential exists, so
/// they go through the real item — the same seam #10 tested, and no Jira credential is involved
/// either way. On a machine where the Keychain refuses to work, `skipUnlessKeychainWorks` stands
/// the lot down; that silence covers #11's ACs 4, 5, 7 and 8 (the Board remembered, the sprint
/// named, the fetch bound, the empty subject), so a green run here means the Keychain answered.
/// The gateway, the paging, the decoding and the forecast are all covered without it, in
/// `SprintPulseCoreTests`.
@MainActor
final class PanelModelTests: XCTestCase {
    let identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")
    let baseURL = "https://jira.example.com"
    let boardID = 172
    let token = "SENTINEL-9f3c-never-in-preferences"

    private let suiteName = "SprintPulseAppTests.PanelModel"
    private let credentials = JiraCredentialStore.testItem()
    private var defaults: UserDefaults!
    private var settings: JiraSettingsStore { JiraSettingsStore(defaults: defaults) }
    private var baselines: BaselineStore { BaselineStore(defaults: defaults) }

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

    /// A complete live configuration: the credential, the identity that came with it, and a
    /// Board (#11).
    private func configureLive(estimateFieldID: String? = nil) throws {
        try credentials.save(token)
        settings.baseURLString = baseURL
        settings.identity = identity
        settings.boardID = boardID
        settings.estimateFieldID = estimateFieldID
    }

    // MARK: - When a read happens (#11)

    /// A live Board is not read at launch, is read when the window opens, and is read again on
    /// Refresh — and by nothing else. The absence of a timer is the presence of a bound: the
    /// count below only ever moves when the Operator acts.
    func test_liveBoard_readsOnWindowOpen_andOnRefresh_andAtNoOtherTime() async throws {
        try configureLive()
        let reads = Reads()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)

        XCTAssertEqual(reads.count, 0, "launch issues no request — the fetch waits for the window")
        XCTAssertEqual(model.source, .live(boardID: boardID))
        XCTAssertEqual(model.content, .nothing, "and there is no reading to show until it arrives")

        await model.windowDidAppear()
        XCTAssertEqual(reads.count, 1)

        await model.refresh()
        XCTAssertEqual(reads.count, 2)

        // Then give any background polling the app might have had a chance to show itself: the
        // count has to still be 2, because nothing else asked (#11 — no timer, no polling).
        await wait(seconds: 0.05)
        XCTAssertEqual(reads.count, 2, "a live read happens on window open and on Refresh, and at no other time")
    }

    /// The other half of the default: with a credential but no Board, there is nothing to ask
    /// about, so the panel keeps reading fixtures and issues no request at all.
    func test_credentialWithoutABoard_isNotHalfALiveRead() async throws {
        try credentials.save(token)
        settings.baseURLString = baseURL
        settings.identity = identity
        let reads = Reads()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)

        XCTAssertEqual(model.source, .fixture(.walkingSkeleton))
        await model.windowDidAppear()
        await model.refresh()
        XCTAssertEqual(reads.count, 0, "fixtures cost no request, whatever the credential state is")
        XCTAssertTrue(model.hasStoredCredential, "#10's removal control still applies")
    }

    func test_fixtureRead_neverReachesTheGateway() async throws {
        let reads = Reads()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)

        for scenario in [FixtureScenario.walkingSkeleton, .severalAssignees, .noWorkAssigned] {
            model.scenario = scenario
            await waitUntil { model.content != .nothing }
        }
        XCTAssertEqual(reads.count, 0)
    }

    // MARK: - What the configuration reaches the gateway (#11)

    func test_liveRead_carriesTheBoardTheOperatorConfigured_andTheIdentityJiraResolved() async throws {
        try configureLive(estimateFieldID: "customfield_10007")
        let reads = Reads()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)

        await model.windowDidAppear()

        let configuration = try XCTUnwrap(reads.configurations.first)
        XCTAssertEqual(configuration.baseURL.absoluteString, baseURL)
        XCTAssertEqual(configuration.boardID, boardID)
        XCTAssertEqual(configuration.identity, identity, "resolved at setup, never typed (#10)")
        XCTAssertEqual(configuration.estimateFieldID, "customfield_10007")
        XCTAssertEqual(reads.tokens, [token], "the token travels as a value, from the one Keychain item")
    }

    func test_liveRead_withoutAnEstimateFieldConfigured_usesTheDocumentedDefault() async throws {
        try configureLive()
        let reads = Reads()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)

        await model.windowDidAppear()

        XCTAssertEqual(
            try XCTUnwrap(reads.configurations.first).estimateFieldID,
            JiraDecoding.estimateFieldID
        )
    }

    // MARK: - The reading, and the states that are not one

    func test_liveRead_forecastsMyWorkAndNamesTheSprint() async throws {
        try configureLive()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: Reads())

        await model.windowDidAppear()

        let instrument = try XCTUnwrap(model.instrument)
        XCTAssertEqual(instrument.sprintName, "Live Sprint 1")
        XCTAssertEqual(instrument.actionablePoints, 5)
        XCTAssertEqual(instrument.completedPoints, 8, " somebody else's 13 Points are not the Operator's")
        XCTAssertEqual(instrument.liveSprintPoints, 26)
        XCTAssertEqual(model.content, .forecast(instrument))
    }

    /// The state #11 exists for: the identity resolved, the Board answered, and nothing in the
    /// sprint belongs to that person. The forecast's own answer over an empty set is `Finished`,
    /// which would be a confident zero about a sprint that is full; the panel replaces the
    /// reading instead, and the menu bar declines to render a number for it.
    func test_liveRead_matchingNoIssues_isItsOwnState_notAConfidentZero() async throws {
        try configureLive()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: noneOfMine), into: Reads())

        await model.windowDidAppear()

        XCTAssertEqual(
            model.content,
            .noWorkAssigned(sprintName: "Live Sprint 1", teamScopePoints: 21),
            "the empty subject, named, with the sprint's own Points beside it"
        )
        XCTAssertNil(model.instrument, "no reading, so nothing to put a number on")
        XCTAssertEqual(model.menuBarLabel, "Sprint Pulse", "and no zero in the menu bar either")
        XCTAssertNil(model.readProblem, "this is a state, not a failure")
    }

    /// The same state through the fixture path, so it is reachable by clicking (#9) whatever the
    /// credential holds — and proof that fixture mode reads the corpus's Operator rather than the
    /// live one, or the picker would promise readings it cannot produce.
    func test_fixtureRead_ofTheNoWorkAssignedScenario_showsTheSameState() async throws {
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: Reads())
        model.scenario = .noWorkAssigned

        await waitUntil { model.content != .nothing }

        XCTAssertEqual(
            model.content,
            .noWorkAssigned(sprintName: "Mobile Platform Sprint 42", teamScopePoints: 21)
        )
        XCTAssertEqual(model.readingIdentity, OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov"))
    }

    // MARK: - Several active sprints (#11)

    /// Two active sprints, no stored choice: the prompt is the state, naming both candidates, and
    /// nothing is forecast until the Operator answers. Then the answer is persisted, so the next
    /// launch reads straight through.
    func test_twoActiveSprints_asksOnceAndRemembersTheAnswer() async throws {
        try configureLive()
        let reads = Reads()
        let model = makeModel(reading: .json(sprints: twoSprints, issues: myWork), into: reads)

        await model.windowDidAppear()

        let candidates = try XCTUnwrap(model.content.sprintCandidates)
        XCTAssertEqual(candidates.map(\.name), ["Mobile Platform Sprint 1", "Growth Sprint 2"])
        XCTAssertNil(model.instrument, "the app does not guess, so there is nothing to show")
        XCTAssertNil(settings.trackedSprintID)

        model.choose(trackedSprintID: 2)
        await waitUntil { model.instrument != nil }

        XCTAssertEqual(settings.trackedSprintID, 2, "remembered for the life of that sprint")
        XCTAssertEqual(try XCTUnwrap(model.instrument).sprintName, "Growth Sprint 2")

        // A relaunch over the same stored choice: the question is not asked twice.
        let reopened = makeModel(reading: .json(sprints: twoSprints, issues: myWork), into: reads)
        await reopened.windowDidAppear()
        XCTAssertEqual(try XCTUnwrap(reopened.instrument).sprintName, "Growth Sprint 2")
        XCTAssertNil(reopened.content.sprintCandidates)
    }

    /// The stored choice is honoured only while the sprint it names is active; a Board that has
    /// moved on is asked again rather than inferred about (#11).
    func test_aChoiceForASprintThatClosed_asksAgain() async throws {
        try configureLive()
        settings.trackedSprintID = 999
        let model = makeModel(reading: .json(sprints: twoSprints, issues: myWork), into: Reads())

        await model.windowDidAppear()

        XCTAssertEqual(model.content.sprintCandidates?.count, 2, "never the first candidate, never the shortest")
    }

    func test_noActiveSprint_isItsOwnState_notAFailedFetch() async throws {
        try configureLive()
        let model = makeModel(reading: .json(sprints: noSprints, issues: myWork), into: Reads())

        await model.windowDidAppear()

        XCTAssertEqual(model.content, .noActiveSprint)
        XCTAssertNil(model.readProblem, "a Board with nothing active is not a broken connection")
    }

    // MARK: - A fetch that failed (#11)

    /// Stale, not broken: the previous reading stays on the panel and the failure says which
    /// condition it was — #12 puts the age of that reading beside it.
    func test_failedFetch_leavesThePreviousReadingStanding_sayingWhatFailed() async throws {
        try configureLive()
        let box = GatewayBox(
            gateway: JSONGateway(sprints: oneSprint, issues: myWork, error: nil)
        )
        let model = PanelModel(
            settings: settings, credentials: credentials, baselineStore: baselines,
            liveGateway: { _, _ in box.gateway }
        )
        await model.windowDidAppear()
        let before = try XCTUnwrap(model.instrument)

        box.gateway = JSONGateway(sprints: "", issues: "", error: .unreachableHost(host: "jira.example.com"))
        await model.refresh()

        XCTAssertEqual(model.content, .forecast(before), "the reading survives the failed fetch")
        XCTAssertEqual(model.readProblem, JiraClientError.unreachableHost(host: "jira.example.com").message)
        XCTAssertFalse(try XCTUnwrap(model.readProblem).contains(token), "the message is showable")
    }

    func test_firstFetchFailing_showsTheFailureRatherThanAnEmptyReading() async throws {
        try configureLive()
        let model = PanelModel(
            settings: settings, credentials: credentials, baselineStore: baselines,
            liveGateway: { _, _ in
                JSONGateway(sprints: "", issues: "", error: .credentialRejected)
            }
        )

        await model.windowDidAppear()

        XCTAssertEqual(model.content, .nothing)
        XCTAssertEqual(model.readProblem, JiraClientError.credentialRejected.message)
    }

    /// The credential is what makes a read live (#10's rule), so its absence is not a failure to
    /// report — the panel goes back to fixtures and never builds a gateway. Nothing authenticates
    /// from another source: an environment variable, a netrc file, or an inherited CLI token is
    /// not a path this app can take, because there is no code that reads one.
    func test_noCredentialToRead_isNotAFailedFetch_itIsFixtureMode() async throws {
        // Configured in preferences, but no Keychain item beside it.
        settings.baseURLString = baseURL
        settings.identity = identity
        settings.boardID = boardID
        let reads = Reads()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)

        await model.windowDidAppear()
        await wait(seconds: 0.05)

        XCTAssertEqual(reads.count, 0, "no credential, so no gateway and no request")
        XCTAssertEqual(model.source, .fixture(model.scenario))
        XCTAssertNil(model.readProblem, "the fixture default is a reading, not an error")
        XCTAssertNotNil(model.instrument, "and the corpus's reading is on screen")
    }

    /// Browsing the corpus must not cost the Operator their own sprint's history: a fixture is an
    /// observation of somebody else's sprint, so it never writes the Baseline slot (#14 owns that
    /// slot; live reads write it, and a fixture click would otherwise restart Scope Delta to 0 on
    /// the next read of the real Board).
    func test_fixtureRead_doesNotOverwriteTheStoredBaseline() async throws {
        try configureLive()
        let reads = Reads()
        let live = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)
        await live.windowDidAppear()
        let stored = try XCTUnwrap(baselines.load())
        XCTAssertEqual(stored.sprintID, 1, "the live sprint's own Baseline, captured on first sight")

        try credentials.delete()  // back to fixtures, same preferences
        let browsing = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)
        browsing.scenario = .capBoth
        await waitUntil { browsing.instrument != nil }

        XCTAssertEqual(baselines.load(), stored, "the corpus left the Operator's Baseline alone")
    }

    /// An answer given while browsing the corpus is not the Operator's configuration. Persisting
    /// it would let a fixture's sprint id resolve the *live* Board's prompt, so a live sprint
    /// would be picked by a click made earlier about somebody else's sprint — #11's "the app
    /// never infers it", violated through the back of the settings store.
    func test_fixtureSprintChoice_isNeverPersistedIntoTheLiveConfiguration() async throws {
        let reads = Reads()
        let browsing = makeModel(reading: .json(sprints: twoSprints, issues: myWork), into: reads)

        // The corpus's own two-active-sprint Board, browsed with no credential configured.
        browsing.scenario = .twoActiveSprints
        await waitUntil { browsing.content.sprintCandidates != nil }

        browsing.choose(trackedSprintID: 5312)
        await waitUntil { browsing.instrument != nil }

        XCTAssertEqual(browsing.trackedSprintID, 5312, "honoured while that Board is the one on screen")
        XCTAssertNil(settings.trackedSprintID, "a fixture's sprint id is nobody's configuration")

        // Now configure the real connection and read a live Board that happens to report two
        // active sprints too: it has to be answered about itself.
        try configureLive()
        let live = makeModel(reading: .json(sprints: twoSprints, issues: myWork), into: reads)
        await live.windowDidAppear()

        XCTAssertNotNil(live.content.sprintCandidates, "a fixture's answer is not a live one")
        XCTAssertNil(live.instrument)
    }

    /// Revoking the credential has to reach the panel in the same breath, or it goes on claiming
    /// to read a Board the Operator no longer has access to (#11's header names the source).
    func test_revokingTheCredential_returnsThePanelToFixtures() async throws {
        try configureLive()
        let reads = Reads()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)
        await model.windowDidAppear()
        XCTAssertEqual(model.source, .live(boardID: boardID))

        // What the panel wires `setup.onConfigurationChanged` to: a read asked for by the
        // Operator's own action, which recomputes the source from what is configured now.
        try credentials.delete()
        await model.refresh()

        XCTAssertEqual(model.source, .fixture(model.scenario))
        XCTAssertNil(model.liveBoardID, "nothing on screen may still claim to be Live")
        XCTAssertNotNil(model.instrument, "the fixture reading replaces the revoked one")
    }

    /// The fallback sentence for an error the panel has no state for. Everything named keeps its
    /// own words (#10); this is the one route that echoes the error itself, so it is pinned
    /// rather than left to whatever a thrown type happens to describe itself as.
    func test_unnamedError_isStillDescribedAndStillShowable() async throws {
        struct Unnamed: Error {}
        try configureLive()
        let model = PanelModel(
            settings: settings, credentials: credentials, baselineStore: baselines,
            liveGateway: { _, _ in throw Unnamed() }
        )

        await model.windowDidAppear()

        XCTAssertEqual(model.content, .nothing, "an unnamed failure invents no reading")
        let problem = try XCTUnwrap(model.readProblem)
        XCTAssertFalse(problem.isEmpty, "and the panel still has a sentence to show")
        XCTAssertFalse(problem.contains(token))
    }

    // MARK: - Helpers

    private func makeModel(reading: Reading, into reads: Reads) -> PanelModel {
        PanelModel(
            settings: settings,
            credentials: credentials,
            baselineStore: baselines,
            liveGateway: { configuration, token in
                reads.record(configuration: configuration, token: token)
                return JSONGateway(
                    sprints: reading.sprints, issues: reading.issues, error: reading.error
                )
            }
        )
    }

    struct Reading: Sendable {
        var sprints: String
        var issues: String
        var error: JiraClientError? = nil

        /// Both reads answered with recorded Data Center envelopes.
        static func json(sprints: String, issues: String) -> Reading {
            Reading(sprints: sprints, issues: issues)
        }
    }

    /// Patience on the test's side, not the app's: `PanelModel` reads inside a `Task`, and there
    /// is no timer in the app to wait on (#11). Bounded, so a state that never arrives fails the
    /// test rather than hanging it.
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<50 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the panel never reached the state the test waited for")
    }

    private func wait(seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Counts the live reads and keeps what each was asked with.
    private final class Reads: @unchecked Sendable {
        private(set) var count = 0
        private(set) var configurations: [JiraLiveConfiguration] = []
        private(set) var tokens: [String] = []

        func record(configuration: JiraLiveConfiguration, token: String) {
            count += 1
            configurations.append(configuration)
            tokens.append(token)
        }
    }

    private final class GatewayBox: @unchecked Sendable {
        var gateway: any JiraGateway
        init(gateway: any JiraGateway) { self.gateway = gateway }
    }

    // MARK: - Recorded envelopes
    //
    // Small Jira-shaped envelopes: enough ignored fields to stay honest about the decode path
    // (`self`, `expand`, `statusCategory`), with the shapes the corpus tests cover in full.

    private let oneSprint = """
    { "maxResults": 50, "startAt": 0, "isLast": true,
      "values": [
        { "self": "https://jira.example.com/rest/agile/1.0/sprint/1", "id": 1, "state": "active",
          "name": "Live Sprint 1", "originBoardId": 172,
          "startDate": "2026-09-14T06:00:00.000+0000", "endDate": "2026-09-25T15:00:00.000+0000" }
      ] }
    """

    private let twoSprints = """
    { "maxResults": 50, "startAt": 0, "isLast": true,
      "values": [
        { "id": 1, "state": "active", "name": "Mobile Platform Sprint 1",
          "startDate": "2026-09-14T06:00:00.000+0000", "endDate": "2026-09-25T15:00:00.000+0000" },
        { "id": 2, "state": "active", "name": "Growth Sprint 2",
          "startDate": "2026-09-14T06:00:00.000+0000", "endDate": "2026-10-09T15:00:00.000+0000" },
        { "id": 3, "state": "future", "name": "Live Sprint 3", "startDate": null, "endDate": null }
      ] }
    """

    private let noSprints = """
    { "maxResults": 50, "startAt": 0, "isLast": true,
      "values": [
        { "id": 0, "state": "closed", "name": "Live Sprint 0",
          "startDate": "2026-09-01T06:00:00.000+0000", "endDate": "2026-09-12T15:00:00.000+0000" }
      ] }
    """

    /// Two Issues of the Operator's (5 Actionable, 8 Completed) and one of somebody else's.
    private let myWork = issuesJSON([
        ("L-1", "In Progress", 5, "dgimaletdinov", "JIRAUSER10500"),
        ("L-2", "Done", 8, "dgimaletdinov", "JIRAUSER10500"),
        ("L-3", "In Progress", 13, "aivanova", "JIRAUSER10877"),
    ])

    /// The same sprint with nothing in it that belongs to the Operator.
    private let noneOfMine = issuesJSON([
        ("L-1", "In Progress", 5, "aivanova", "JIRAUSER10877"),
        ("L-2", "Done", 8, "psokolov", "JIRAUSER11204"),
        ("L-3", "In Review", 8, "aivanova", "JIRAUSER10877"),
    ])
}

/// An issue listing in Data Center's shape — `expand` echoed per issue, a `statusCategory`, the
/// sprint field carrying Greenhopper's own `toString` — with the Estimates in the field the
/// documented default reads.
private func issuesJSON(
    _ issues: [(issue: String, status: String, points: Double, name: String, key: String)]
) -> String {
    let body = issues.enumerated().map { offset, issue -> String in
        """
        { "id": "97\(100 + offset)", "key": "\(issue.issue)",
          "expand": "operations,versionedRepresentations,editmeta,changelog,renderedFields",
          "fields": {
            "summary": "\(issue.issue)",
            "issuetype": { "name": "Task", "subtask": false, "id": "10001" },
            "status": { "name": "\(issue.status)", "id": "3",
              "statusCategory": { "id": 4, "key": "indeterminate", "name": "In Progress" } },
            "assignee": { "name": "\(issue.name)", "key": "\(issue.key)", "displayName": "\(issue.name)", "active": true },
            "customfield_10002": \(issue.points),
            "customfield_10004": ["com.atlassian.greenhopper.service.sprint.Sprint[id=1]"] } }
        """
    }.joined(separator: ",\n      ")
    return """
    { "expand": "schema,names", "startAt": 0, "maxResults": 50, "total": \(issues.count),
      "issues": [
        \(body)
      ] }
    """
}

/// A `JiraGateway` double that decodes recorded Data Center envelopes through the same public
/// decoder the live gateway uses, so the panel is tested against Jira's shapes rather than
/// against types it cannot build from outside the core module.
private struct JSONGateway: JiraGateway {
    let sprints: String
    let issues: String
    let error: JiraClientError?

    func activeSprints() async throws -> JiraSprintsResponse {
        if let error { throw error }
        return try JiraDecoding.decoder().decode(
            JiraSprintsResponse.self, from: Data(sprints.utf8)
        )
    }

    func issues(inSprint sprintID: Int) async throws -> JiraSprintIssuesResponse {
        if let error { throw error }
        let response = try JiraDecoding.decoder().decode(
            JiraSprintIssuesResponse.self, from: Data(issues.utf8)
        )
        return response
    }
}

private extension PanelModel.Content {
    /// The candidates, when the state is the prompt (#11).
    var sprintCandidates: [JiraSprint]? {
        if case .namingActiveSprint(let candidates) = self { return candidates }
        return nil
    }
}
