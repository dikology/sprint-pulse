import XCTest
@testable import SprintPulseCore

final class OperatorIdentityTests: XCTestCase {
    let identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

    func test_matches_onKey() {
        let user = JiraUser(name: "someone-else", key: "JIRAUSER10500", displayName: "Denis")
        XCTAssertTrue(identity.matches(user))
    }

    func test_matches_fallsBackToName_whenKeyIsAbsentOrDifferent() {
        let renamed = JiraUser(name: "dgimaletdinov", key: "JIRAUSER77777", displayName: "Denis")
        XCTAssertTrue(identity.matches(renamed))

        let noKey = JiraUser(name: "dgimaletdinov", key: nil, displayName: "Denis")
        XCTAssertTrue(identity.matches(noKey))
    }

    func test_matches_isFalse_forOtherPeopleAndForUnassigned() {
        let other = JiraUser(name: "aivanova", key: "JIRAUSER10877", displayName: "Anna")
        XCTAssertFalse(identity.matches(other))
        XCTAssertFalse(identity.matches(nil))
    }
}
