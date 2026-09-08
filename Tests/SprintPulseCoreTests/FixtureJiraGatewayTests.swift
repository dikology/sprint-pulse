import XCTest
@testable import SprintPulseCore

final class FixtureJiraGatewayTests: XCTestCase {
    func test_bundled_decodesTheActiveSprintsEnvelope() async throws {
        let gateway = try FixtureJiraGateway.bundled(named: "walking-skeleton")

        let response = try await gateway.activeSprints()

        XCTAssertEqual(response.values.count, 1)
        let sprint = try XCTUnwrap(response.values.first)
        XCTAssertEqual(sprint.id, 5281)
        XCTAssertEqual(sprint.name, "Mobile Platform Sprint 34")
        XCTAssertEqual(sprint.state, "active")
        XCTAssertEqual(sprint.startDate, ISO8601DateFormatter().date(from: "2026-09-01T09:00:00Z"))
        XCTAssertEqual(sprint.endDate, ISO8601DateFormatter().date(from: "2026-09-12T17:00:00Z"))
    }

    func test_bundled_decodesTheSprintIssuesInJiraShape() async throws {
        let gateway = try FixtureJiraGateway.bundled(named: "walking-skeleton")

        let response = try await gateway.issues(inSprint: 5281)

        XCTAssertEqual(response.total, 6)
        XCTAssertEqual(response.issues.count, 6)

        let byKey = Dictionary(uniqueKeysWithValues: response.issues.map { ($0.key, $0) })
        XCTAssertEqual(byKey["MOB-1201"]?.fields.estimate, 5)
        XCTAssertEqual(byKey["MOB-1201"]?.fields.assignee?.key, "JIRAUSER10500")
        XCTAssertEqual(byKey["MOB-1201"]?.fields.status.name, "In Progress")
        XCTAssertNil(byKey["MOB-1203"]?.fields.estimate, "an unsized issue is nil, never 0")
        XCTAssertEqual(byKey["MOB-1204"]?.fields.issueType.subtask, true)
        XCTAssertNil(byKey["MOB-1207"]?.fields.assignee)
    }

    func test_init_readsFromAnArbitraryDirectory() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try sprintsJSON.write(
            to: directory.appendingPathComponent("active-sprints.json"), atomically: true, encoding: .utf8
        )

        let gateway = FixtureJiraGateway(directory: directory)
        let response = try await gateway.activeSprints()

        XCTAssertEqual(response.values.first?.id, 42)
    }

    func test_activeSprints_throwsWhenFileMissing() async {
        let gateway = FixtureJiraGateway(
            directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        )

        do {
            _ = try await gateway.activeSprints()
            XCTFail("expected a fileNotReadable error")
        } catch let error as FixtureJiraGateway.FixtureError {
            guard case .fileNotReadable = error else { return XCTFail("wrong case: \(error)") }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private let sprintsJSON = """
    {
      "maxResults": 50, "startAt": 0, "isLast": true,
      "values": [
        { "id": 42, "state": "active", "name": "Temp Sprint" }
      ]
    }
    """
}
