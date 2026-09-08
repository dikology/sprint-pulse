import Foundation

/// The Active Sprint and its issues at one moment, exactly as decoded from Jira Data Center.
/// The app fetches the two gateway envelopes and hands them here; the domain performs no I/O
/// of its own. `Forecast.evaluate` takes a `SprintSnapshot` as its gateway-response argument.
public struct SprintSnapshot: Equatable, Sendable {
    public let sprint: JiraSprint
    public let issues: [JiraIssue]

    public init(sprint: JiraSprint, issues: [JiraIssue]) {
        self.sprint = sprint
        self.issues = issues
    }

    public enum SelectionError: Error, Equatable {
        case noActiveSprint
        /// Several sprints are in the `active` state. The Operator names the tracked one (M1);
        /// Sprint Pulse never infers it.
        case ambiguousActiveSprint(names: [String])
    }

    /// The one Active Sprint in a `/board/{id}/sprint` envelope. Pure — no I/O. More than one
    /// sprint in the `active` state is an error, not a guess: the Operator names the tracked
    /// one (M1).
    ///
    /// The app resolves this first so it can fetch that sprint's issues by id.
    public static func selectActiveSprint(from response: JiraSprintsResponse) throws -> JiraSprint {
        let active = response.values.filter { $0.state == "active" }
        switch active.count {
        case 0: throw SelectionError.noActiveSprint
        case 1: return active[0]
        default: throw SelectionError.ambiguousActiveSprint(names: active.map(\.name))
        }
    }
}
