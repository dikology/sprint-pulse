import Foundation

/// The single seam between Sprint Pulse and Jira.
///
/// Every implementation returns raw decoded Jira Data Center response shapes and nothing
/// derived — `SprintPulseCore` cannot tell a fixture implementation from a live one (ADR-0005).
/// Turning the responses into a `SprintSnapshot` (which includes choosing the Active Sprint)
/// happens outside the gateway. The live client arrives in M1; the walking skeleton ships only
/// `FixtureJiraGateway`.
public protocol JiraGateway: Sendable {
    /// The sprints on the Board in the `active` state — the raw
    /// `/rest/agile/1.0/board/{boardId}/sprint?state=active` envelope.
    func activeSprints() async throws -> JiraSprintsResponse

    /// The issues of the given sprint — the raw `/rest/agile/1.0/sprint/{sprintId}/issue`
    /// envelope.
    func issues(inSprint sprintID: Int) async throws -> JiraSprintIssuesResponse
}
