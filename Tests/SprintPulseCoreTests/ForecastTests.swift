import XCTest
@testable import SprintPulseCore

final class ForecastTests: XCTestCase {
    /// The Operator, whose `key` matches the fixture assignees and whose `name` differs from
    /// their `key` so key-vs-name matching is actually exercised.
    let operatorIdentity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

    /// A pinned "today" inside the fixtures' sprint window.
    let now = isoDate("2026-09-08T12:00:00Z")

    /// Monday–Friday, pinned to UTC so `workingDaysRemaining` is deterministic regardless of the
    /// machine running the tests.
    let workingCalendar = WorkingCalendar(timeZone: TimeZone(identifier: "UTC")!)

    private func snapshot(_ fixture: String) async throws -> SprintSnapshot {
        let gateway = try FixtureJiraGateway.bundled(named: fixture)
        let sprint = try SprintSnapshot.selectActiveSprint(from: try await gateway.activeSprints())
        let issues = try await gateway.issues(inSprint: sprint.id)
        return SprintSnapshot(sprint: sprint, issues: issues.issues)
    }

    private func evaluate(_ fixture: String, baseline: SprintBaseline? = nil) async throws -> (instrument: Instrument, baseline: SprintBaseline) {
        Forecast.evaluate(
            snapshot: try await snapshot(fixture),
            identity: operatorIdentity,
            statusMap: .default,
            workingCalendar: workingCalendar,
            baseline: baseline,
            now: now
        )
    }

    // MARK: - The whole Instrument

    /// The acceptance test: construct the domain from a fixture and a fixed date, then assert
    /// on the whole `Instrument` in a single comparison.
    func test_evaluate_fromWalkingSkeletonFixture_producesTheWholeInstrument() async throws {
        let result = try await evaluate("walking-skeleton")

        XCTAssertEqual(
            result.instrument,
            Instrument(
                sprintName: "Mobile Platform Sprint 34",
                // MOB-1201 In Progress (5); MOB-1202, -1203 Open (8, unestimated).
                pointsByFlowState: [
                    .toDo: 8, .inProgress: 5, .inReview: 0, .onHold: 0, .done: 0, .dropped: 0,
                ],
                unestimatedCount: 1,
                unmappedStatuses: [],
                // Tue 09-08 (now) through Sat 09-12 (sprint end): Tue–Fri are Working Days,
                // Saturday is not.
                workingDaysRemaining: 4
            )
        )
    }

    func test_evaluate_excludesSubTasksAndOtherPeoplesWork() async throws {
        // MOB-1201 (5) + MOB-1202 (8) = 13 Actionable. MOB-1203 is unestimated.
        // MOB-1204 is a sub-task, MOB-1205 belongs to another assignee, MOB-1207 is
        // unassigned — none contribute.
        let result = try await evaluate("walking-skeleton")

        XCTAssertEqual(result.instrument.actionablePoints, 13)
        XCTAssertEqual(result.instrument.pointsRemaining, 13)
    }

    func test_evaluate_matchesTheOperatorByNameWhenKeyDiffers() async throws {
        let byName = OperatorIdentity(key: "JIRAUSER99999", name: "dgimaletdinov")
        let result = Forecast.evaluate(
            snapshot: try await snapshot("walking-skeleton"),
            identity: byName, statusMap: .default, workingCalendar: workingCalendar,
            baseline: nil, now: now
        )

        XCTAssertEqual(result.instrument.actionablePoints, 13)
    }

    // MARK: - Points per Flow State (all six)

    func test_evaluate_partitionsMyWorkAcrossAllSixFlowStates() async throws {
        let i = try await evaluate("all-flow-states").instrument

        XCTAssertEqual(i.points(.toDo), 5)        // AFS-1201 Open (3) + AFS-1202 Backlog (2)
        XCTAssertEqual(i.points(.inProgress), 5)  // AFS-1203 In Progress
        XCTAssertEqual(i.points(.inReview), 8)    // AFS-1204 In Review
        XCTAssertEqual(i.points(.onHold), 1)      // AFS-1205 Need Info
        XCTAssertEqual(i.points(.done), 13)       // AFS-1206 Done
        XCTAssertEqual(i.points(.dropped), 21)    // AFS-1207 Cancelled
    }

    func test_evaluate_showsActionableAndWaitingAsSeparateTotals() async throws {
        let i = try await evaluate("all-flow-states").instrument

        XCTAssertEqual(i.actionablePoints, 10)  // 5 + 5
        XCTAssertEqual(i.waitingPoints, 9)      // 8 + 1
    }

    func test_evaluate_droppedIsItsOwnFigureExcludedFromEveryRemainingTotalAndNeverCompleted() async throws {
        let i = try await evaluate("all-flow-states").instrument

        XCTAssertEqual(i.droppedPoints, 21)
        XCTAssertEqual(i.completedPoints, 13, "Dropped Points are never added to Completed")
        XCTAssertEqual(i.pointsRemaining, 19, "Dropped and Done are excluded from the remaining total")
        XCTAssertFalse(FlowState.actionable.contains(.dropped))
        XCTAssertFalse(FlowState.waiting.contains(.dropped))
    }

    // MARK: - Unmapped Status

    func test_evaluate_surfacesUnmappedStatusesEachNamedOnceAndExcludesTheirIssues() async throws {
        let i = try await evaluate("unmapped-status").instrument

        // "Blocked" (UMS-1303, -1306) and "Escalated" (UMS-1305) are absent from the map.
        XCTAssertEqual(i.unmappedStatuses, ["Blocked", "Escalated"])
        // Their Issues are in no set: only UMS-1301 (5) and UMS-1302 (3) reach Actionable,
        // only UMS-1304 (2) reaches Waiting. The 8 + 1 behind "Blocked" is nowhere.
        XCTAssertEqual(i.actionablePoints, 8)
        XCTAssertEqual(i.waitingPoints, 2)
        XCTAssertEqual(i.pointsRemaining, 10)
    }

    func test_evaluate_noUnmappedStatusesForAWorkflowThatFitsTheDefaultMap() async throws {
        let i = try await evaluate("all-flow-states").instrument
        XCTAssertEqual(i.unmappedStatuses, [])
    }

    // MARK: - Unestimated Issues

    func test_evaluate_countsUnestimatedIssuesOnlyInActionableOrWaitingAndNeverAsPoints() async throws {
        let i = try await evaluate("unestimated-across-states").instrument

        // UNE-1401 ToDo, UNE-1402 InProgress, UNE-1403 InReview — three unsized Issues in
        // Actionable ∪ Waiting.
        XCTAssertEqual(i.unestimatedCount, 3)
        // UNE-1405 Done and UNE-1406 Dropped are also unsized but are not counted.
        // The unsized Issues add nothing: only UNE-1407 (5) and UNE-1404 (3) are Points.
        XCTAssertEqual(i.points(.toDo), 5)
        XCTAssertEqual(i.points(.inProgress), 0)
        XCTAssertEqual(i.points(.inReview), 0)
        XCTAssertEqual(i.points(.onHold), 3)
        XCTAssertEqual(i.points(.done), 0)
        XCTAssertEqual(i.points(.dropped), 0)
    }

    // MARK: - Sub-task estimates

    func test_evaluate_ignoresSubTaskEstimatesEntirelyRatherThanRollingThemUp() async throws {
        let i = try await evaluate("subtasks-with-estimates").instrument

        // Only the two task-level Issues count: SUB-1504 Open (2), SUB-1501 In Progress (5).
        // The sub-tasks carry 8 + 13 + 3 that must appear nowhere.
        XCTAssertEqual(i.points(.toDo), 2)
        XCTAssertEqual(i.points(.inProgress), 5)
        XCTAssertEqual(i.points(.inReview), 0)
        XCTAssertEqual(i.actionablePoints, 7)
        XCTAssertEqual(i.waitingPoints, 0)
        XCTAssertEqual(i.unestimatedCount, 0)
    }

    // MARK: - Sprint Baseline

    func test_evaluate_capturesTheBaselineOnFirstObservation() async throws {
        let result = try await evaluate("walking-skeleton")

        XCTAssertEqual(result.baseline.sprintID, 5281)
        XCTAssertEqual(result.baseline.capturedAt, now)
        // Whole sprint, task-level only: MOB-1201, -1202, -1203, -1205, -1207. Not the sub-task.
        XCTAssertEqual(
            result.baseline.entries.sorted { $0.key < $1.key },
            [
                .init(key: "MOB-1201", estimate: 5),
                .init(key: "MOB-1202", estimate: 8),
                .init(key: "MOB-1203", estimate: nil),
                .init(key: "MOB-1205", estimate: 13),
                .init(key: "MOB-1207", estimate: 2),
            ]
        )
    }

    func test_evaluate_keepsAnExistingBaselineForTheSameSprint() async throws {
        let existing = SprintBaseline(
            sprintID: 5281,
            capturedAt: isoDate("2026-09-01T09:03:11Z"),
            entries: [.init(key: "MOB-1201", estimate: 3)]
        )

        let result = try await evaluate("walking-skeleton", baseline: existing)

        XCTAssertEqual(result.baseline, existing)
    }

    func test_evaluate_recapturesTheBaselineWhenTheSprintChanges() async throws {
        let staleFromAnotherSprint = SprintBaseline(
            sprintID: 4999,
            capturedAt: isoDate("2026-08-01T09:00:00Z"),
            entries: []
        )

        let result = try await evaluate("walking-skeleton", baseline: staleFromAnotherSprint)

        XCTAssertEqual(result.baseline.sprintID, 5281)
        XCTAssertEqual(result.baseline.capturedAt, now)
    }
}

/// A calendar date from an ISO-8601 string, for pinning "today" and baseline timestamps.
func isoDate(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}
