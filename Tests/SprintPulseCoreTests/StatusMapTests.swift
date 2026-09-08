import XCTest
@testable import SprintPulseCore

final class StatusMapTests: XCTestCase {
    let map = StatusMap.default

    func test_default_isTheOperatorsWorkflowFromProductMd() {
        XCTAssertEqual(map.flowState(for: "Backlog"), .toDo)
        XCTAssertEqual(map.flowState(for: "Open"), .toDo)
        XCTAssertEqual(map.flowState(for: "Need Info"), .onHold)
        XCTAssertEqual(map.flowState(for: "In Progress"), .inProgress)
        XCTAssertEqual(map.flowState(for: "In Review"), .inReview)
        XCTAssertEqual(map.flowState(for: "Done"), .done)
        XCTAssertEqual(map.flowState(for: "Cancelled"), .dropped)
    }

    func test_unmappedStatus_returnsNil_neverBucketedByResemblance() {
        XCTAssertNil(map.flowState(for: "Blocked"))
        XCTAssertNil(map.flowState(for: "In review"), "matching is exact, not case-insensitive")
        XCTAssertNil(map.flowState(for: "Reviewing"), "no resemblance to 'In Review'")
        XCTAssertNil(map.flowState(for: ""))
    }

    func test_jiraStatuses_listsEveryKnownStatusSortedForTheReadOnlyDisplay() {
        XCTAssertEqual(
            map.jiraStatuses,
            ["Backlog", "Cancelled", "Done", "In Progress", "In Review", "Need Info", "Open"]
        )
    }

    func test_customMap_translatesADifferentWorkflow() {
        let custom = StatusMap(["To Do": .toDo, "Shipped": .done])
        XCTAssertEqual(custom.flowState(for: "Shipped"), .done)
        XCTAssertNil(custom.flowState(for: "Open"))
    }
}
