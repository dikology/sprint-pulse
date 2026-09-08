import XCTest
@testable import SprintPulseCore

final class SprintSnapshotTests: XCTestCase {
    func test_selectActiveSprint_returnsTheSoleActiveSprint() throws {
        let response = envelope([
            sprint(id: 10, state: "closed", name: "Sprint 33"),
            sprint(id: 11, state: "active", name: "Sprint 34"),
            sprint(id: 12, state: "future", name: "Sprint 35"),
        ])

        let selected = try SprintSnapshot.selectActiveSprint(from: response)

        XCTAssertEqual(selected.id, 11)
    }

    func test_selectActiveSprint_throwsWhenNoneActive() {
        let response = envelope([sprint(id: 10, state: "closed", name: "Sprint 33")])

        XCTAssertThrowsError(try SprintSnapshot.selectActiveSprint(from: response)) { error in
            XCTAssertEqual(error as? SprintSnapshot.SelectionError, .noActiveSprint)
        }
    }

    func test_selectActiveSprint_throwsRatherThanInferWhenSeveralActive() {
        let response = envelope([
            sprint(id: 11, state: "active", name: "Team A"),
            sprint(id: 12, state: "active", name: "Team B"),
        ])

        XCTAssertThrowsError(try SprintSnapshot.selectActiveSprint(from: response)) { error in
            XCTAssertEqual(
                error as? SprintSnapshot.SelectionError,
                .ambiguousActiveSprint(names: ["Team A", "Team B"])
            )
        }
    }

    // MARK: - Helpers

    private func envelope(_ sprints: [JiraSprint]) -> JiraSprintsResponse {
        JiraSprintsResponse(maxResults: 50, startAt: 0, isLast: true, values: sprints)
    }

    private func sprint(id: Int, state: String, name: String) -> JiraSprint {
        JiraSprint(id: id, state: state, name: name, startDate: nil, endDate: nil)
    }
}
