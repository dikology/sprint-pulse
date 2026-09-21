import XCTest
@testable import SprintPulseCore

final class SprintSnapshotTests: XCTestCase {
    /// The corpus's Operator, the identity every My Work assertion in this suite matches on.
    let identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

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

    /// My Work is one definition with two callers: `Forecast` sums over it and the app counts it
    /// to decide whether there is anything to forecast at all (#11). Both go through here, so a
    /// sub-task can never give a sprint a subject and an identity match cannot mean two different
    /// things on the same screen. Decoded from Jira's shape rather than built, the way every
    /// other test in this suite reaches these types.
    func test_myWork_excludesSubTasksAndMatchesTheResolvedIdentity() throws {
        let body = """
        [
          { "id": "1", "key": "A", "fields": { "summary": "mine",
              "issuetype": { "name": "Task", "subtask": false },
              "status": { "name": "In Progress" },
              "assignee": { "name": "new.username", "key": "JIRAUSER10500" } } },
          { "id": "2", "key": "B", "fields": { "summary": "my sub-task",
              "issuetype": { "name": "Sub-task", "subtask": true },
              "status": { "name": "In Progress" },
              "assignee": { "name": "new.username", "key": "JIRAUSER10500" } } },
          { "id": "3", "key": "C", "fields": { "summary": "mine under the old username",
              "issuetype": { "name": "Task", "subtask": false },
              "status": { "name": "In Progress" },
              "assignee": { "name": "old.username", "key": "JIRAUSER10500" } } },
          { "id": "4", "key": "D", "fields": { "summary": "same name, someone else",
              "issuetype": { "name": "Task", "subtask": false },
              "status": { "name": "In Progress" },
              "assignee": { "name": "dgimaletdinov", "key": "JIRAUSER99999" } } },
          { "id": "5", "key": "E", "fields": { "summary": "unassigned",
              "issuetype": { "name": "Task", "subtask": false },
              "status": { "name": "In Progress" }, "assignee": null } }
        ]
        """
        let issues = try JiraDecoding.decoder().decode([JiraIssue].self, from: Data(body.utf8))
        let snapshot = SprintSnapshot(sprint: sprint(id: 1, state: "active", name: "S"), issues: issues)

        XCTAssertEqual(
            snapshot.myWork(assignedTo: identity).map(\.key), ["A", "C", "D"],
            "key matches first (C, renamed since), name is the fallback (D); the sub-task (B) "
                + "and the unassigned (E) are not part of My Work whatever the assignee says"
        )
    }

    // MARK: - Naming the tracked sprint (#11)

    /// One active sprint is not a question, whatever the stored choice says. A Board that has
    /// settled down after a fortnight of overlap needs no prompting.
    func test_resolveTrackedSprint_withOneActiveSprint_neverAsks() throws {
        let response = envelope([
            sprint(id: 10, state: "closed", name: "Sprint 33"),
            sprint(id: 11, state: "active", name: "Sprint 34"),
        ])

        for chosen in [nil, 11, 10, 999] {
            let choice = SprintSnapshot.resolveTrackedSprint(in: response, chosenSprintID: chosen)
            XCTAssertEqual(choice, .tracked(response.values[1]), "stored choice \(String(describing: chosen))")
        }
    }

    func test_resolveTrackedSprint_withSeveralActiveSprints_asksTheOperator() throws {
        let response = envelope([
            sprint(id: 11, state: "active", name: "Team A"),
            sprint(id: 12, state: "active", name: "Team B"),
        ])

        let choice = SprintSnapshot.resolveTrackedSprint(in: response, chosenSprintID: nil)

        XCTAssertEqual(choice, .awaitingOperatorChoice([response.values[0], response.values[1]]))
    }

    /// The answer is remembered for the life of the sprint it names: the same active set read
    /// again asks nothing.
    func test_resolveTrackedSprint_honoursTheStoredChoiceWhileThatSprintIsActive() throws {
        let response = envelope([
            sprint(id: 11, state: "active", name: "Team A"),
            sprint(id: 12, state: "active", name: "Team B"),
        ])

        let choice = SprintSnapshot.resolveTrackedSprint(in: response, chosenSprintID: 12)

        XCTAssertEqual(choice, .tracked(response.values[1]))
    }

    /// The choice does not outlive its sprint. Once the named sprint is no longer active the
    /// Operator is asked again rather than the app guessing from the remaining candidates — and
    /// a Board with no active sprint at all is its own state, not a stale choice to resolve.
    func test_resolveTrackedSprint_aStaleChoiceIsReasked_neverInferred() throws {
        let response = envelope([
            sprint(id: 11, state: "active", name: "Team A"),
            sprint(id: 12, state: "active", name: "Team B"),
        ])
        XCTAssertEqual(
            SprintSnapshot.resolveTrackedSprint(in: response, chosenSprintID: 9),
            .awaitingOperatorChoice([response.values[0], response.values[1]]),
            "a closed sprint is not a subject to carry forward"
        )

        let noneActive = envelope([sprint(id: 9, state: "closed", name: "Team A")])
        XCTAssertEqual(
            SprintSnapshot.resolveTrackedSprint(in: noneActive, chosenSprintID: 9),
            .noActiveSprint
        )
    }

    // MARK: - Helpers

    private func envelope(_ sprints: [JiraSprint]) -> JiraSprintsResponse {
        JiraSprintsResponse(maxResults: 50, startAt: 0, isLast: true, values: sprints)
    }

    private func sprint(id: Int, state: String, name: String) -> JiraSprint {
        JiraSprint(id: id, state: state, name: name, startDate: nil, endDate: nil)
    }
}
