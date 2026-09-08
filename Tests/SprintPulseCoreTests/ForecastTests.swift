import XCTest
@testable import SprintPulseCore

final class ForecastTests: XCTestCase {
    /// The Operator, whose `key` matches the fixture assignees and whose `name` differs from
    /// their `key` so key-vs-name matching is actually exercised.
    let operatorIdentity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

    /// A pinned "today" inside Mobile Platform Sprint 34.
    let now = isoDate("2026-09-08T12:00:00Z")

    private func loadWalkingSkeletonSnapshot() async throws -> SprintSnapshot {
        let gateway = try FixtureJiraGateway.bundled(named: "walking-skeleton")
        let sprint = try SprintSnapshot.selectActiveSprint(from: try await gateway.activeSprints())
        let issues = try await gateway.issues(inSprint: sprint.id)
        return SprintSnapshot(sprint: sprint, issues: issues.issues)
    }

    /// The acceptance test: construct the domain from a fixture and a fixed date, then assert
    /// on the whole `Instrument` in a single comparison.
    func test_evaluate_fromFixture_producesTheWholeInstrument() async throws {
        let snapshot = try await loadWalkingSkeletonSnapshot()

        let result = Forecast.evaluate(
            snapshot: snapshot,
            identity: operatorIdentity,
            baseline: nil,
            now: now
        )

        XCTAssertEqual(
            result.instrument,
            Instrument(sprintName: "Mobile Platform Sprint 34", pointsRemaining: 13)
        )
    }

    func test_evaluate_excludesSubTasksAndOtherPeoplesWork() async throws {
        // MOB-1201 (5) + MOB-1202 (8) + MOB-1203 (unestimated) = 13.
        // MOB-1204 is a sub-task, MOB-1205 belongs to another assignee, MOB-1207 is
        // unassigned — none contribute.
        let snapshot = try await loadWalkingSkeletonSnapshot()

        let result = Forecast.evaluate(
            snapshot: snapshot, identity: operatorIdentity, baseline: nil, now: now
        )

        XCTAssertEqual(result.instrument.pointsRemaining, 13)
    }

    func test_evaluate_matchesTheOperatorByNameWhenKeyDiffers() async throws {
        // An identity whose key matches nobody but whose name matches the fixture assignees.
        let byName = OperatorIdentity(key: "JIRAUSER99999", name: "dgimaletdinov")
        let snapshot = try await loadWalkingSkeletonSnapshot()

        let result = Forecast.evaluate(
            snapshot: snapshot, identity: byName, baseline: nil, now: now
        )

        XCTAssertEqual(result.instrument.pointsRemaining, 13)
    }

    func test_evaluate_capturesTheBaselineOnFirstObservation() async throws {
        let snapshot = try await loadWalkingSkeletonSnapshot()

        let result = Forecast.evaluate(
            snapshot: snapshot, identity: operatorIdentity, baseline: nil, now: now
        )

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
        let snapshot = try await loadWalkingSkeletonSnapshot()
        let existing = SprintBaseline(
            sprintID: 5281,
            capturedAt: isoDate("2026-09-01T09:03:11Z"),
            entries: [.init(key: "MOB-1201", estimate: 3)]
        )

        let result = Forecast.evaluate(
            snapshot: snapshot, identity: operatorIdentity, baseline: existing, now: now
        )

        XCTAssertEqual(result.baseline, existing)
    }

    func test_evaluate_recapturesTheBaselineWhenTheSprintChanges() async throws {
        let snapshot = try await loadWalkingSkeletonSnapshot()
        let staleFromAnotherSprint = SprintBaseline(
            sprintID: 4999,
            capturedAt: isoDate("2026-08-01T09:00:00Z"),
            entries: []
        )

        let result = Forecast.evaluate(
            snapshot: snapshot, identity: operatorIdentity, baseline: staleFromAnotherSprint, now: now
        )

        XCTAssertEqual(result.baseline.sprintID, 5281)
        XCTAssertEqual(result.baseline.capturedAt, now)
    }
}

/// A calendar date from an ISO-8601 string, for pinning "today" and baseline timestamps.
func isoDate(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}
