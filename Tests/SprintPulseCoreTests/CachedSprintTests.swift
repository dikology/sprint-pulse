import XCTest
@testable import SprintPulseCore

/// The cache's own value type (#12), tested where it lives: in the domain, as a value the app
/// hands back in. Two things have to be true of it and neither is obvious from reading it — the
/// snapshot comes back out *identical*, and no credential has anywhere in it to be stored.
final class CachedSprintTests: XCTestCase {
    let operatorIdentity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

    /// A real decoded read, from the corpus — not a hand-built snapshot, so the test says
    /// something about what the live gateway actually produces (#11's shapes).
    private func liveSnapshot() async throws -> SprintSnapshot {
        let gateway = try FixtureJiraGateway.bundled(.severalAssignees)
        let sprint = try SprintSnapshot.selectActiveSprint(from: try await gateway.activeSprints())
        let issues = try await gateway.issues(inSprint: sprint.id)
        return SprintSnapshot(sprint: sprint, issues: issues.issues)
    }

    func test_roundTripsThroughJSONIdentically() async throws {
        let snapshot = try await liveSnapshot()
        let readAt = isoDate("2026-09-21T09:30:00Z")
        let cached = CachedSprint(boardID: 172, readAt: readAt, snapshot: snapshot)

        let decoded = try JSONDecoder().decode(CachedSprint.self, from: try JSONEncoder().encode(cached))

        XCTAssertEqual(decoded, cached, "the slot holds the read, not an approximation of it")
        XCTAssertEqual(decoded.snapshot, snapshot, "and it hands back the same snapshot, sub-tasks and null assignees included")
        XCTAssertEqual(decoded.readAt, readAt, "to the microsecond: the panel's age line and rule 1 both read this instant")
        XCTAssertEqual(decoded.boardID, 172)
    }

    /// The cached read must produce the same forecast as the live one it stands in for — the
    /// equality the whole ticket rests on. The reading differs only in what it is allowed to
    /// conclude, and only when the moment it is judged at has moved past its own Working Day.
    func test_theCachedSnapshotForecastsTheSameReadingAsTheLiveOneDid() async throws {
        let snapshot = try await liveSnapshot()
        let moment = isoDate("2026-09-21T09:30:00Z")
        let cached = CachedSprint(boardID: 172, readAt: moment, snapshot: snapshot)

        let live = Forecast.evaluate(
            snapshot: snapshot, identity: operatorIdentity, statusMap: .default,
            workingCalendar: WorkingCalendar(timeZone: TimeZone(identifier: "UTC")!),
            baseline: nil, readAt: moment, now: moment
        ).instrument
        let fromCache = Forecast.evaluate(
            snapshot: cached.snapshot, identity: operatorIdentity, statusMap: .default,
            workingCalendar: WorkingCalendar(timeZone: TimeZone(identifier: "UTC")!),
            baseline: nil, readAt: cached.readAt, now: cached.readAt
        ).instrument

        XCTAssertEqual(fromCache, live, "the gateway boundary is the only thing that changed")
    }

    /// A cached read carries the assignee structure it was given: sub-tasks stay sub-tasks (they
    /// enter no total, invariant 8), unassigned Issues stay unassigned (nobody's work is not the
    /// Operator's), and an Issue with no Estimate stays Unestimated rather than becoming a zero
    /// (invariant 2). A cache that flattened any of those would quietly change the forecast.
    func test_theCachedSnapshotKeepsTheDistinctionsTheForecastDependsOn() async throws {
        let snapshot = try await liveSnapshot()
        let cached = try XCTUnwrap(
            JSONDecoder().decode(
                CachedSprint.self,
                from: try JSONEncoder().encode(CachedSprint(boardID: 172, readAt: Date(), snapshot: snapshot))
            )
        ).snapshot

        let restored = cached.issues
        XCTAssertEqual(restored.filter(\.fields.issueType.subtask).count,
                       snapshot.issues.filter { $0.fields.issueType.subtask }.count)
        XCTAssertEqual(restored.filter { $0.fields.assignee == nil }.count,
                       snapshot.issues.filter { $0.fields.assignee == nil }.count)
        XCTAssertEqual(restored.filter { $0.fields.estimate == nil }.count,
                       snapshot.issues.filter { $0.fields.estimate == nil }.count)
        XCTAssertEqual(
            cached.myWork(assignedTo: operatorIdentity).map(\.key),
            snapshot.myWork(assignedTo: operatorIdentity).map(\.key)
        )
    }
}
