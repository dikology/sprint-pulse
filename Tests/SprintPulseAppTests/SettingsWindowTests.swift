import SprintPulseCore
import XCTest
@testable import SprintPulse

/// The two model seams that sit underneath #17's move of configuration into a Settings window.
///
/// The window itself is a view and this repo carries no view tests by convention; what the move
/// *changes* below the views is here, and it is exactly the two things the acceptance criteria
/// can be falsified on:
///
/// - **AC 5, the Panel's source line.** With the scenario picker gone from the Panel, the one
///   line naming where a reading came from has to name the bundled scenario being read — the
///   picker's caption did that before, and a Panel reading `cap-both` while saying nothing is a
///   Panel that lost its provenance. The wording lives in `PanelModel` for the same reason
///   `dataAgeText` and `baselineCaption` do: panel wording worth having under test.
/// - **AC 3, invariant 14 across two windows.** The read that used to be triggered by a Board
///   remembered was wired in the Panel's own `onAppear` — fine while the form lived on the
///   Panel, wrong now that it lives in Settings, which can be the first window opened. The
///   wiring is `readsOnConfigurationChanges(of:)`, called once by the composition root, and each
///   trigger must cost exactly one live read: no timer, no fan-out, none on opening a window.
@MainActor
final class SettingsWindowTests: XCTestCase {
    let identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")
    let baseURL = "https://jira.example.com"
    let boardID = 172
    let token = "SENTINEL-9f3c-never-in-preferences"

    private let suiteName = "SprintPulseAppTests.SettingsWindow"
    private let credentials = JiraCredentialStore.testItem()
    private var defaults: UserDefaults!
    private var settings: JiraSettingsStore { JiraSettingsStore(defaults: defaults) }
    private var baselines: BaselineStore { BaselineStore(defaults: defaults) }
    private var cache: SprintCacheStore { SprintCacheStore(defaults: defaults) }
    private var statusMaps: StatusMapStore { StatusMapStore(defaults: defaults) }

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

    /// A complete live configuration except the Board: everything a live read needs once the
    /// Operator remembers one (#11).
    private func configureCredential() throws {
        try credentials.save(token)
        settings.baseURLString = baseURL
        settings.identity = identity
    }

    // MARK: - The source line names its reading (AC 5)

    /// The fresh install #17's AC 4 describes: no credential, the Panel reading a bundled
    /// scenario, and the scenario named on the Panel rather than only in the Settings picker
    /// that replaced the one the Panel used to carry.
    func test_sourceLine_onAFixtureRead_namesTheScenarioBeingRead() async throws {
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: Reads())
        await waitUntil { model.instrument != nil }

        XCTAssertEqual(model.sourceLine, "Fixture — walking-skeleton")

        model.scenario = .capBoth
        await waitUntil { model.source == .fixture(.capBoth) && model.instrument != nil }
        XCTAssertEqual(
            model.sourceLine, "Fixture — cap-both",
            "the line follows the picker's choice into the new window and stays on the Panel"
        )
    }

    /// The live and cached branches of the same line — one vocabulary for the caption, so the
    /// Panel cannot say "Live" over a corpus reading or hide the Board behind the move.
    func test_sourceLine_onABoardRead_namesTheBoardAndTheIdentity() async throws {
        try configureCredential()
        settings.boardID = boardID
        let reads = Reads()
        let model = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)

        await model.windowDidAppear()

        XCTAssertEqual(model.source, .live(boardID: boardID))
        XCTAssertEqual(model.sourceLine, "Live — Board 172, as dgimaletdinov")
    }

    func test_sourceLine_onACachedRead_saysCached() async throws {
        try configureCredential()
        settings.boardID = boardID
        let online = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: Reads())
        await online.windowDidAppear()

        let offline = makeModel(
            reading: Reading(sprints: "", issues: "", error: .unreachableHost(host: "jira.example.com")),
            into: Reads()
        )
        await offline.windowDidAppear()

        XCTAssertEqual(offline.source, .cached(boardID: boardID))
        XCTAssertEqual(offline.sourceLine, "Cached — Board 172, as dgimaletdinov")
    }

    // MARK: - Invariant 14 across two windows (AC 3)

    /// The case the move creates and the old view-level wiring could not meet: Settings can be
    /// the first window opened, so a Board remembered there must reach the Panel whether or not
    /// the Panel has ever appeared — exactly one live read, on the Operator's act.
    func test_rememberingABoard_triggersExactlyOneLiveRead_withThePanelNeverOpened() async throws {
        try configureCredential()
        let reads = Reads()
        let panel = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)
        let setup = makeSetup()
        panel.readsOnConfigurationChanges(of: setup)

        // Let the read the launch scheduled land before the act: with no Board configured, that
        // is a fixture read, and AC 4's fresh install is on screen. A load still in flight when
        // the Board arrives would decide what it is at run time — the #15 gate's rule — and the
        // test would be counting two reads for one act that production's ordering cannot reach.
        await waitUntil { panel.instrument != nil }
        XCTAssertEqual(reads.count, 0, "the wiring itself asks nothing of the Board")

        setup.boardText = "172"
        setup.saveBoard()

        await waitUntil { reads.count >= 1 }
        await wait(seconds: 0.05)
        XCTAssertEqual(reads.count, 1, "remembering a Board is one read, not a fan-out")
        XCTAssertEqual(panel.source, .live(boardID: boardID))
        XCTAssertEqual(reads.configurations.first?.boardID, boardID)
    }

    /// The other half: a refused entry is not an act on the connection and costs no read.
    func test_refusingABoardEntry_triggersNoRead() async throws {
        try configureCredential()
        let reads = Reads()
        let panel = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)
        let setup = makeSetup()
        panel.readsOnConfigurationChanges(of: setup)

        setup.boardText = "172abc"
        setup.saveBoard()
        await wait(seconds: 0.05)

        XCTAssertNotNil(setup.configurationProblem)
        XCTAssertEqual(reads.count, 0, "nothing was remembered, so nothing is asked")
    }

    /// Revoking a credential from Settings reaches the Panel in the same breath (#11) — and the
    /// read it triggers is a fixture re-read, so no request goes out for a Board that no longer
    /// has access to one.
    func test_revokingACredential_returnsThePanelToFixtures_withNoFurtherRequest() async throws {
        try configureCredential()
        settings.boardID = boardID
        let reads = Reads()
        let panel = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)
        let setup = makeSetup()
        panel.readsOnConfigurationChanges(of: setup)

        await panel.windowDidAppear()
        XCTAssertEqual(reads.count, 1)

        setup.removeCredential()

        await waitUntil { panel.source == .fixture(panel.scenario) }
        await wait(seconds: 0.05)
        XCTAssertEqual(reads.count, 1, "the revocation costs no second request")
        XCTAssertNotNil(panel.instrument, "and the corpus replaces the reading the access went with")
        XCTAssertEqual(
            panel.sourceLine, "Fixture — walking-skeleton",
            "with the Board gone, the source line is still the Panel's only provenance"
        )
    }

    /// Both directions of the #15 switch, now operated from Settings: onto the corpus costs no
    /// request, back onto the Board is the one live read the Operator asked for.
    func test_theFixtureModeSwitch_readsWithTheStandingRule() async throws {
        try configureCredential()
        settings.boardID = boardID
        let reads = Reads()
        let panel = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)
        let setup = makeSetup()
        panel.readsOnConfigurationChanges(of: setup)

        await panel.windowDidAppear()
        XCTAssertEqual(reads.count, 1)

        panel.switchToFixtures()
        await waitUntil { panel.source == .fixture(panel.scenario) }
        await wait(seconds: 0.05)
        XCTAssertEqual(reads.count, 1, "dropping onto the corpus issues no request")
        XCTAssertEqual(panel.sourceLine, "Fixture — walking-skeleton")

        panel.switchToBoard()
        await waitUntil { reads.count >= 2 }
        await wait(seconds: 0.05)
        XCTAssertEqual(reads.count, 2, "asking for the Board again is exactly one live read")
        XCTAssertEqual(panel.sourceLine, "Live — Board 172, as dgimaletdinov")
    }

    /// The failure the move creates, closed in the model rather than by the picker's
    /// `.disabled()`: choosing a scenario while a live Board is being read must not issue a
    /// live read — invariant 14's list has no "corpus choice with the Board standing" on it.
    /// HEAD made this structurally unreachable (the picker did not render during a Board read);
    /// Settings renders it always, so the guard has to be real.
    func test_choosingAScenario_whileTheBoardIsBeingRead_issuesNoLiveRead() async throws {
        try configureCredential()
        settings.boardID = boardID
        let reads = Reads()
        let panel = makeModel(reading: .json(sprints: oneSprint, issues: myWork), into: reads)

        await panel.windowDidAppear()
        XCTAssertEqual(reads.count, 1)

        panel.scenario = .capBoth
        await wait(seconds: 0.05)
        XCTAssertEqual(reads.count, 1, "a scenario click is not a read of the Board")
        XCTAssertEqual(panel.source, .live(boardID: boardID), "and the Board reading stands")

        // Stored, not dropped: switching onto the corpus finds the choice already waiting.
        panel.switchToFixtures()
        await waitUntil { panel.source == .fixture(.capBoth) && panel.instrument != nil }
        await wait(seconds: 0.05)
        XCTAssertEqual(reads.count, 1, "and the switch onto the corpus still costs none")
        XCTAssertEqual(panel.sourceLine, "Fixture — cap-both")
    }

    // MARK: - Helpers

    private func makeSetup() -> JiraSetupModel {
        JiraSetupModel(
            credentials: credentials,
            settings: settings,
            probe: { _, askedToken in
                askedToken.isEmpty ? .failure(.missingToken) : .success(self.identity)
            }
        )
    }

    private func makeModel(reading: Reading, into reads: Reads) -> PanelModel {
        PanelModel(
            settings: settings,
            credentials: credentials,
            baselineStore: baselines,
            cache: cache,
            statusMaps: statusMaps,
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

        static func json(sprints: String, issues: String) -> Reading {
            Reading(sprints: sprints, issues: issues)
        }
    }

    /// Patience on the test's side, not the app's: reads land inside `Task`s, and the app has no
    /// timer to wait on (#11). Bounded, so a state that never arrives fails rather than hangs.
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

    // MARK: - Recorded envelopes
    //
    /// The same shapes `PanelModelTests` replays: one active sprint, two Issues of the
    /// Operator's and one of somebody else's.
    private let oneSprint = """
    { "maxResults": 50, "startAt": 0, "isLast": true,
      "values": [
        { "id": 1, "state": "active", "name": "Live Sprint 1", "originBoardId": 172,
          "startDate": "2026-09-14T06:00:00.000+0000", "endDate": "2026-09-25T15:00:00.000+0000" }
      ] }
    """

    private let myWork = issuesJSON([
        ("L-1", "In Progress", 5, "dgimaletdinov", "JIRAUSER10500"),
        ("L-2", "Done", 8, "dgimaletdinov", "JIRAUSER10500"),
        ("L-3", "In Progress", 13, "aivanova", "JIRAUSER10877"),
    ])
}

private func issuesJSON(
    _ issues: [(issue: String, status: String, points: Double, name: String, key: String)]
) -> String {
    let body = issues.enumerated().map { offset, issue -> String in
        """
        { "id": "97\(100 + offset)", "key": "\(issue.issue)",
          "fields": {
            "summary": "\(issue.issue)",
            "issuetype": { "name": "Task", "subtask": false, "id": "10001" },
            "status": { "name": "\(issue.status)", "id": "3" },
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

/// A `JiraGateway` double decoding the recorded envelopes through the public decoder, the same
/// seam `PanelModelTests` reads the live path at.
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
        return try JiraDecoding.decoder().decode(
            JiraSprintIssuesResponse.self, from: Data(issues.utf8)
        )
    }
}
