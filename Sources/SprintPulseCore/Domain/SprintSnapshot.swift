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

    /// The Issues the forecast is computed over: task-level Issues assigned to `identity`
    /// (CONTEXT "My Work").
    ///
    /// One implementation of My Work, and it sits outside `Forecast`'s own call on purpose:
    /// `Forecast` sums over it, and the app reads its *size* off it to tell an emptied sprint
    /// apart from a sprint holding nothing that belongs to the Operator (#11). Both must agree,
    /// so neither gets its own copy of the two rules — a sub-task is not an Issue, and a match is
    /// `key` first with `name` only as fallback (`docs/agents/glossary.md` "Identity").
    public func myWork(assignedTo identity: OperatorIdentity) -> [JiraIssue] {
        issues.filter { !$0.fields.issueType.subtask && identity.matches($0.fields.assignee) }
    }

    public enum SelectionError: Error, Equatable {
        case noActiveSprint
        /// Several sprints are in the `active` state. The Operator names the tracked one (M1);
        /// Sprint Pulse never infers it.
        case ambiguousActiveSprint(names: [String])
    }

    /// Which sprint the instrument is tracking, as a value rather than as an exception.
    ///
    /// `selectActiveSprint` says what the *domain* can decide; this says what the *Operator*
    /// has to decide, which a thrown error cannot carry: the candidates to name one of
    /// (#11, CONTEXT "Active Sprint").
    public enum TrackedSprint: Equatable, Sendable {
        /// The sprint to read. Either the Board's only active one, or the one the Operator
        /// named when there were several.
        case tracked(JiraSprint)
        /// Nothing on the Board is active. The instrument has no sprint to read — its own state,
        /// not a failed fetch.
        case noActiveSprint
        /// More than one sprint is active and none of them is the stored choice, so the
        /// Operator must name the tracked one. Sprint Pulse never infers it from names, dates,
        /// or issue counts.
        case awaitingOperatorChoice([JiraSprint])

        /// The sprint, when there is one to read.
        public var sprint: JiraSprint? {
            if case .tracked(let sprint) = self { return sprint }
            return nil
        }
    }

    /// The Active Sprint to read, given what the Board reports and the choice the Operator made
    /// earlier. Pure — no I/O.
    ///
    /// `chosenSprintID` is the persisted answer to a previous prompt. It is honoured only while
    /// the sprint it names is still active: a closed sprint stops being a subject, so the next
    /// time the Board reports several active sprints the Operator is asked again, and a Board
    /// that has settled on one active sprint needs no asking (#11 — the choice is remembered
    /// "for the life of that sprint", which is the same span as the sprint's own `active` state).
    public static func resolveTrackedSprint(
        in response: JiraSprintsResponse, chosenSprintID: Int?
    ) -> TrackedSprint {
        let active = response.values.filter { $0.state == "active" }
        switch active.count {
        case 0: return .noActiveSprint
        case 1: return .tracked(active[0])
        default:
            if let chosenSprintID, let chosen = active.first(where: { $0.id == chosenSprintID }) {
                return .tracked(chosen)
            }
            return .awaitingOperatorChoice(active)
        }
    }

    /// The one Active Sprint in a `/board/{id}/sprint` envelope. Pure — no I/O. More than one
    /// sprint in the `active` state is an error, not a guess: the Operator names the tracked
    /// one (M1).
    ///
    /// The app resolves this first so it can fetch that sprint's issues by id. Where the caller
    /// can act on a prompt rather than fail on one, it calls
    /// `resolveTrackedSprint(in:chosenSprintID:)` and this is the shape it throws in
    /// (#11) — which is what the M0 corpus asserts against, one active sprint per scenario.
    public static func selectActiveSprint(from response: JiraSprintsResponse) throws -> JiraSprint {
        switch resolveTrackedSprint(in: response, chosenSprintID: nil) {
        case .tracked(let sprint): return sprint
        case .noActiveSprint: throw SelectionError.noActiveSprint
        case .awaitingOperatorChoice(let candidates):
            throw SelectionError.ambiguousActiveSprint(names: candidates.map(\.name))
        }
    }
}
