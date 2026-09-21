import Foundation

/// The single seam between Sprint Pulse and Jira.
///
/// Every implementation returns raw decoded Jira Data Center response shapes and nothing
/// derived — `SprintPulseCore` cannot tell a fixture implementation from a live one (ADR-0005).
/// Turning the responses into a `SprintSnapshot` (which includes choosing the Active Sprint)
/// happens outside the gateway. `FixtureJiraGateway` reads the corpus from disk;
/// `LiveJiraGateway` reads one Board over HTTP (#11), and both are the same two operations
/// because the milestone's bound says the instrument can ask Jira for exactly those two plus
/// identity at setup.
public protocol JiraGateway: Sendable {
    /// The sprints on the Board in the `active` state — the raw
    /// `/rest/agile/1.0/board/{boardId}/sprint?state=active` envelope, whole however many pages
    /// of the listing it took to assemble.
    func activeSprints() async throws -> JiraSprintsResponse

    /// The issues of the given sprint — the raw `/rest/agile/1.0/sprint/{sprintId}/issue`
    /// envelope, every page of it. A single page would read 50 Issues as the sprint.
    func issues(inSprint sprintID: Int) async throws -> JiraSprintIssuesResponse
}
