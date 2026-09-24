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

    /// The editor's rows (#13), sorted by status name: a set of menus that re-ordered itself between
    /// two launches would make the same status hard to find twice, and `Dictionary`'s ordering is
    /// per-process rather than stable. Each row carries its answer beside its name, because the menu
    /// has to open showing what the map currently says.
    func test_rows_listEveryMappedStatusSortedByNameWithItsAnswer() {
        XCTAssertEqual(
            map.rows.map(\.jiraStatus),
            ["Backlog", "Cancelled", "Done", "In Progress", "In Review", "Need Info", "Open"]
        )
        XCTAssertEqual(map.rows.map(\.flowState), [.toDo, .dropped, .done, .inProgress, .inReview, .onHold, .toDo])
    }

    func test_customMap_translatesADifferentWorkflow() {
        let custom = StatusMap(["To Do": .toDo, "Shipped": .done])
        XCTAssertEqual(custom.flowState(for: "Shipped"), .done)
        XCTAssertNil(custom.flowState(for: "Open"))
    }

    // MARK: - Editing the map (#13)

    /// The Operator's answer to an Unmapped Status: one more entry, and the status stops being
    /// unknown. `default` is a value, so editing it leaves the shipped map alone — an edit that
    /// mutated the shared static would spread across every reading in the app.
    func test_setting_addsAStatusTheMapDidNotKnow_andLeavesTheRestOfTheMapStanding() {
        let edited = map.setting("Blocked", to: .onHold)

        XCTAssertEqual(edited.flowState(for: "Blocked"), .onHold)
        XCTAssertEqual(edited.flowState(for: "In Progress"), .inProgress, "an edit is one entry, not a reset")
        XCTAssertEqual(edited.rows.count, map.rows.count + 1)
        XCTAssertNil(map.flowState(for: "Blocked"), "and the map that shipped is unchanged by editing it")
    }

    /// Re-mapping a status the Operator already translated is the same operation: a renamed column
    /// is corrected by writing over it, not by removing and re-adding.
    func test_setting_replacesTheFlowStateOfAStatusAlreadyInTheMap() {
        let edited = map.setting("In Review", to: .done)

        XCTAssertEqual(edited.flowState(for: "In Review"), .done)
        XCTAssertEqual(edited.rows.count, map.rows.count, "one status, one entry")
    }

    /// Every one of the six Flow States is a legal answer for any status — the editor offers
    /// `FlowState.allCases` and refuses none of them, `Dropped` included, because "this column
    /// means the work left my sprint" is the Operator's call to make (#13 AC 4).
    func test_setting_acceptsEveryFlowState_includingDropped() {
        for state in FlowState.allCases {
            let edited = StatusMap([:]).setting("QA Gate", to: state)
            XCTAssertEqual(edited.flowState(for: "QA Gate"), state)
        }
    }

    /// Removing an entry puts the status back to being Unmapped: the map is editable in both
    /// directions, and the consequence is the one rule 1 already describes rather than a guess
    /// about what the status used to mean.
    func test_removing_anEntry_leavesTheStatusUnmappedAgain() {
        let edited = map.removing("Need Info")

        XCTAssertNil(edited.flowState(for: "Need Info"))
        XCTAssertNil(edited.flowState(for: "Need INfo"), "matching is exact, before and after an edit")
        XCTAssertNotNil(edited.flowState(for: "Done"), "the rest of the map survives")
        XCTAssertEqual(map.flowState(for: "Need Info"), .onHold, "again: the shipped map is untouched")
    }

    func test_removing_aStatusTheMapNeverKnew_changesNothing() {
        XCTAssertEqual(map.removing("Blocked"), map)
    }
}
