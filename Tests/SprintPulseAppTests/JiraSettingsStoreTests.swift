import SprintPulseCore
import XCTest
@testable import SprintPulse

/// The non-secret half of the connection configuration (#10). The claim that the Personal
/// Access Token never lands here is pinned where it could happen — after a full setup — in
/// `JiraSetupModelTests`; this file pins what the store itself must do.
final class JiraSettingsStoreTests: XCTestCase {
    private let suiteName = "SprintPulseAppTests.JiraSettingsStore"
    private var defaults: UserDefaults!
    private var store: JiraSettingsStore { JiraSettingsStore(defaults: defaults) }

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func test_fresh_store_knows_noBaseURL_and_noIdentity() {
        XCTAssertNil(store.baseURLString)
        XCTAssertNil(store.identity)
    }

    func test_baseURL_roundTrips_andSettingItToNil_removesIt() {
        store.baseURLString = "https://jira.example.com"
        XCTAssertEqual(store.baseURLString, "https://jira.example.com")

        store.baseURLString = nil
        XCTAssertNil(store.baseURLString)
    }

    func test_identity_roundTrips_bothKeyAndName() {
        let identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")
        store.identity = identity
        XCTAssertEqual(store.identity, identity)
    }

    func test_clearIdentity_dropsIdentity_andKeepsBaseURL() {
        store.baseURLString = "https://jira.example.com"
        store.identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

        store.clearIdentity()

        XCTAssertNil(store.identity)
        XCTAssertEqual(store.baseURLString, "https://jira.example.com")
    }

    func test_unreadableIdentity_isNoIdentity_notAcrash() {
        // Preferences are user-editable files; a half-written value must read as "not set up
        // yet", the same as an absent one.
        defaults.set(Data("junk".utf8), forKey: "jira-identity")
        XCTAssertNil(store.identity)
    }

    // MARK: - The live read's configuration (#11)

    func test_fresh_store_knows_noBoard_noTrackedSprint_noEstimateField() {
        XCTAssertNil(store.boardID)
        XCTAssertNil(store.trackedSprintID)
        XCTAssertNil(store.estimateFieldID)
    }

    func test_boardID_roundTrips_andSettingItToNil_removesIt() {
        store.boardID = 172
        XCTAssertEqual(store.boardID, 172)

        store.boardID = nil
        XCTAssertNil(store.boardID)
    }

    func test_trackedSprintID_roundTrips_andSettingItToNil_removesIt() {
        store.trackedSprintID = 5311
        XCTAssertEqual(store.trackedSprintID, 5311)

        store.trackedSprintID = nil
        XCTAssertNil(store.trackedSprintID)
    }

    /// A remembered sprint choice is an answer about the Board it was given on. The same number
    /// names a different sprint elsewhere, so it goes with the Board rather than outliving it.
    func test_changingTheBoard_dropsTheRememberedSprint() {
        store.boardID = 172
        store.trackedSprintID = 5311

        store.boardID = 214
        XCTAssertNil(store.trackedSprintID, "the answer belonged to Board 172")

        store.boardID = 214
        XCTAssertEqual(store.boardID, 214)
    }

    func test_rememberingTheSameBoard_keepsTheSprintItWasAnsweredOn() {
        store.boardID = 172
        store.trackedSprintID = 5311

        store.boardID = 172

        XCTAssertEqual(store.trackedSprintID, 5311, "re-confirming the same Board is not a new question")
    }

    func test_estimateFieldID_roundTrips_andNilRestoresTheDefault() {
        store.estimateFieldID = "customfield_10007"
        XCTAssertEqual(store.estimateFieldID, "customfield_10007")

        store.estimateFieldID = nil
        XCTAssertNil(store.estimateFieldID, "absent means the documented default, decided by the reader")
    }

    func test_clearIdentity_leavesTheBoardTheEstimateField_andTheSprintChoice() {
        store.boardID = 172
        store.trackedSprintID = 5311
        store.estimateFieldID = "customfield_10007"
        store.identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

        store.clearIdentity()

        XCTAssertNil(store.identity)
        XCTAssertEqual(store.boardID, 172, "configuration outlives the credential it was made beside")
        XCTAssertEqual(store.trackedSprintID, 5311)
        XCTAssertEqual(store.estimateFieldID, "customfield_10007")
    }

    // MARK: - Which source the Operator asked to be read (#15)

    /// The default is the *absence* of an ask, not a stored value: fixture mode is what the app
    /// does while no credential exists (#10, #11), so a fresh install must not need to have been
    /// told. Writing `.automatic` away rather than storing it keeps "never asked" and "asked for
    /// the credential to decide" one state.
    func test_fresh_store_recordsNoSourceAsk_andThatMeansTheCredentialDecides() {
        XCTAssertEqual(store.readMode, .automatic)
        XCTAssertNil(
            defaults.object(forKey: "jira-read-mode"),
            "the default leaves nothing in preferences, so a fresh domain and a reset one are identical"
        )
    }

    func test_readMode_roundTrips_andChoosingAutomaticAgain_removesTheAsk() {
        store.readMode = .fixtures
        XCTAssertEqual(store.readMode, .fixtures)
        XCTAssertEqual(defaults.string(forKey: "jira-read-mode"), "fixtures")

        store.readMode = .automatic
        XCTAssertEqual(store.readMode, .automatic)
        XCTAssertNil(defaults.object(forKey: "jira-read-mode"))
    }

    /// Preferences are a user-editable file. A value that is not one of the two asks reads as
    /// "nobody asked", which is the credential's own rule (#10, #11) — the alternative is a panel
    /// that reads nothing at all because of a typo in a plist nobody should have opened.
    func test_anUnreadableSourceAsk_isNoAsk_notADeadPanel() {
        defaults.set("livish", forKey: "jira-read-mode")
        XCTAssertEqual(store.readMode, .automatic)
    }

    /// The ask is about which source is on screen, not about the connection, so revoking the
    /// credential does not cancel it: the Operator who pinned the corpus and then revoked access
    /// is still looking at the corpus, and the ask is inert rather than contradictory either way.
    func test_clearIdentity_leavesTheSourceAskAlone() {
        store.readMode = .fixtures
        store.identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

        store.clearIdentity()

        XCTAssertEqual(store.readMode, .fixtures)
    }
}
