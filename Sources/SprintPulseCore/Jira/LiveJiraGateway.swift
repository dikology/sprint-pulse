import Foundation

/// The live `JiraGateway` (#11): one Board's active sprints and one sprint's Issues, read over
/// HTTP from Jira Data Center.
///
/// It returns the same raw response shapes `FixtureJiraGateway` returns, which is the whole
/// point of the protocol: `SprintPulseCore` cannot tell a live sprint from a directory of
/// JSON, so the forecast, the Caps, and the corpus all keep running untouched on real data
/// (#2). Nothing here interprets a status, chooses a sprint, or computes a number — the
/// Board's two active sprints arrive as two, and the Operator names the tracked one outside
/// this type.
///
/// The call surface is the two reads `JiraHTTPClient` exposes and nothing else, which is half
/// of M1's bound: three operations in the milestone, the third being `/rest/api/2/myself` at
/// credential setup. Both of these read a listing, so each pages its own request until the
/// listing closes — the same operation repeated, never a different endpoint. No write, no
/// search, no JQL, and nothing reaches Jira that the client cannot build.
public struct LiveJiraGateway: JiraGateway {
    private let client: JiraHTTPClient
    private let boardID: Int

    /// Which custom field carries the Estimate on this instance. A per-instance value, not an
    /// API constant: read the wrong field and every Issue arrives Unestimated, which the
    /// instrument reports as `Finished`, so the configuration belongs to the read the way the
    /// Board does (#11).
    private let estimateFieldID: String

    public init(
        client: JiraHTTPClient,
        boardID: Int,
        estimateFieldID: String = JiraDecoding.estimateFieldID
    ) {
        self.client = client
        self.boardID = boardID
        self.estimateFieldID = estimateFieldID
    }

    public func activeSprints() async throws -> JiraSprintsResponse {
        try await client.activeSprints(onBoard: boardID)
    }

    public func issues(inSprint sprintID: Int) async throws -> JiraSprintIssuesResponse {
        try await client.issues(inSprint: sprintID, estimateFieldID: estimateFieldID)
    }
}
