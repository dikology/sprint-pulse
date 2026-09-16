import Foundation

/// A `JiraGateway` that reads Jira Data Center response JSON from a directory on disk.
///
/// The JSON is in the exact shape of live responses, so the domain cannot distinguish this
/// from the live client. Fixture mode is the default whenever no credential exists.
///
/// A fixture directory contains:
/// - `active-sprints.json` — a `/rest/agile/1.0/board/{id}/sprint` envelope
/// - `sprint-issues.json` — a `/rest/agile/1.0/sprint/{id}/issue` envelope
/// - optionally `baseline.json` — the scenario's stored Sprint Baseline, the app's own
///   `SprintBaseline` JSON (not a Jira response)
/// - `now.json` — the scenario's pinned moment, the date it is read at: a fixture is a
///   frozen observation, and the second seam's value belongs to the scenario, not the clock
///   of the machine doing the reading (#9)
public struct FixtureJiraGateway: JiraGateway {
    public enum FixtureError: Error, Equatable {
        case fileNotReadable(String)
        case fileMalformed(String)
    }

    private let directory: URL

    /// Reads fixtures from an arbitrary directory.
    public init(directory: URL) {
        self.directory = directory
    }

    /// Reads a fixture set bundled with `SprintPulseCore` (its test corpus), by directory name.
    public static func bundled(named name: String) throws -> FixtureJiraGateway {
        FixtureJiraGateway(directory: try bundledDirectory(named: name))
    }

    /// The bundled directory for a fixture set, so the scenario's own files — the day-one
    /// `baseline.json` of a Scope Delta scenario, its pinned `now.json` — can be read beside
    /// the Jira envelopes. The gateway protocol covers Jira's responses only; neither file
    /// passes through it — both reach the domain as arguments to the pure transformation,
    /// exactly as the stored Baseline and the clock do (#8, #9).
    private static func bundledDirectory(named name: String) throws -> URL {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw FixtureError.fileNotReadable("Fixtures")
        }
        return fixtures.appendingPathComponent(name, isDirectory: true)
    }

    /// The scenario's stored Sprint Baseline, for the fixtures that bundle a `baseline.json`
    /// — the Scope Delta scenarios, whose day-one snapshot is part of the scenario. `nil`
    /// for first-observation scenarios, which have witnessed no movement. This is the same
    /// value the app would load from its own persistence in live mode, supplied by the
    /// fixture instead.
    public static func bundledBaseline(named name: String) throws -> SprintBaseline? {
        let url = try bundledDirectory(named: name).appendingPathComponent("baseline.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SprintBaseline.self, from: data)
    }

    /// The moment a scenario claims to be observed at — the `now.json` of its directory, an
    /// ISO-8601 string in the app's own format, never part of a Jira envelope. A fixture read
    /// on a later day is not the same observation: its Working Days move, its rates move, and
    /// its Confidence State drifts out of the band the scenario's name promises (#9). Every
    /// bundled scenario pins one; `FixtureCorpusTests` walks the corpus against that
    /// promise.
    public static func pinnedNow(named name: String) throws -> Date? {
        let url = try bundledDirectory(named: name).appendingPathComponent("now.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let string = try? JSONDecoder().decode(String.self, from: data),
              let date = ISO8601DateFormatter().date(from: string) else {
            throw FixtureError.fileMalformed(url.path)
        }
        return date
    }

    /// Every scenario directory in the bundled corpus. The picker and the corpus audit read
    /// the corpus through here, so a fixture added without a `FixtureScenario` case — or a
    /// case whose fixture has gone missing — is visible rather than silent.
    public static func corpusScenarioNames() throws -> Set<String> {
        guard let fixtures = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw FixtureError.fileNotReadable("Fixtures")
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: fixtures, includingPropertiesForKeys: [.isDirectoryKey], options: []
        )
        return Set(entries.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return nil
            }
            return url.lastPathComponent
        })
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
