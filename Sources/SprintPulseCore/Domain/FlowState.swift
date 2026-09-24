import Foundation

/// Sprint Pulse's own vocabulary for where an Issue sits in the workflow. The vocabulary is
/// fixed and independent of any Jira installation (ADR-0002) — Jira's status strings reach a
/// Flow State only through the `StatusMap`.
///
/// `Codable` for one reason: the Status Map is persisted by the app (#13), and a `FlowState` is a
/// value inside it. The raw values are the names `docs/agents/glossary.md` uses, so what lands in
/// the preferences file reads in the domain's vocabulary rather than in somebody's storage format.
public enum FlowState: String, CaseIterable, Codable, Sendable {
    case toDo = "ToDo"
    case inProgress = "InProgress"
    /// Work that has left the Operator's hands for someone else's judgement but is not
    /// finished. A first-class state, never a synonym for `done`.
    case inReview = "InReview"
    case onHold = "OnHold"
    case done = "Done"
    /// Work removed from the sprint without being completed. Dropped Points leave the
    /// remaining total and are never credited as completed work.
    case dropped = "Dropped"

    /// Points the Operator's own effort can move. The forecast (#6) runs on these alone.
    public static let actionable: [FlowState] = [.toDo, .inProgress]

    /// Points that are unfinished but outside the Operator's control. Displayed alongside the
    /// forecast; never folded into it.
    public static let waiting: [FlowState] = [.inReview, .onHold]
}
