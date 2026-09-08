import Foundation

/// The translation from Jira's status names to `FlowState`s. Jira status strings appear here
/// and nowhere else in the system (CONTEXT invariant 1).
///
/// A status with no entry is an `Unmapped Status`: its Issues enter no set, the status is
/// surfaced prominently, and Confidence is forced to `Unknown` (#6). A status is never mapped
/// by resemblance — matching is exact.
///
/// The map is operator-editable, but the editor is M1. M0 ships the `default` map read-only,
/// and `Forecast.evaluate` takes the map as a value the way it takes the identity and the
/// baseline — the domain performs no I/O.
public struct StatusMap: Equatable, Sendable {
    private let entries: [String: FlowState]

    public init(_ entries: [String: FlowState]) {
        self.entries = entries
    }

    /// The `FlowState` for a Jira status name, or `nil` when the status is unmapped.
    public func flowState(for jiraStatus: String) -> FlowState? {
        entries[jiraStatus]
    }

    /// The Jira status names the map knows, for display of the read-only map (#4).
    public var jiraStatuses: [String] {
        entries.keys.sorted()
    }

    /// The map as `(Jira status, Flow State)` pairs, sorted by Jira status, for the read-only
    /// display in M0.
    public var rows: [(jiraStatus: String, flowState: FlowState)] {
        entries.sorted { $0.key < $1.key }.map { (jiraStatus: $0.key, flowState: $0.value) }
    }

    /// The Status Map for the Operator's current workflow, from `docs/agents/product.md`.
    /// `Backlog` occurs on Issues inside an active sprint, not only outside one.
    public static let `default` = StatusMap([
        "Backlog": .toDo,
        "Open": .toDo,
        "Need Info": .onHold,
        "In Progress": .inProgress,
        "In Review": .inReview,
        "Done": .done,
        "Cancelled": .dropped,
    ])
}
