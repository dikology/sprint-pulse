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
}
