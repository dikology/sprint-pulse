import Foundation

/// A `JiraGateway` that reads Jira Data Center response JSON from a directory on disk.
///
/// The JSON is in the exact shape of live responses, so the domain cannot distinguish this
/// from the live client. Fixture mode is the default whenever no credential exists.
///
/// A fixture directory contains:
/// - `active-sprints.json` — a `/rest/agile/1.0/board/{id}/sprint` envelope
/// - `sprint-issues.json` — a `/rest/agile/1.0/sprint/{id}/issue` envelope
public struct FixtureJiraGateway: JiraGateway {
    public enum FixtureError: Error, Equatable {
        case fileNotReadable(String)
    }

    private let directory: URL

    /// Reads fixtures from an arbitrary directory.
    public init(directory: URL) {
        self.directory = directory
    }

    /// Reads a fixture set bundled with `SprintPulseCore` (its test corpus), by directory name.
    public static func bundled(named name: String) throws -> FixtureJiraGateway {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw FixtureError.fileNotReadable("Fixtures")
        }
        return FixtureJiraGateway(directory: fixtures.appendingPathComponent(name, isDirectory: true))
    }

    public func activeSprints() async throws -> JiraSprintsResponse {
        try load("active-sprints.json")
    }

    public func issues(inSprint sprintID: Int) async throws -> JiraSprintIssuesResponse {
        // The fixture models a single sprint, so `sprintID` selects nothing here. A live
        // gateway reads the id.
        try load("sprint-issues.json")
    }

    private func load<T: Decodable>(_ filename: String) throws -> T {
        let url = directory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else {
            throw FixtureError.fileNotReadable(url.path)
        }
        return try JiraDecoding.decoder().decode(T.self, from: data)
    }
}
