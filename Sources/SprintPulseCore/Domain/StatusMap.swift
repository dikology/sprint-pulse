import Foundation

/// The translation from Jira's status names to `FlowState`s. Jira status strings appear here
/// and nowhere else in the system (CONTEXT invariant 1).
///
/// A status with no entry is an `Unmapped Status`: its Issues enter no set, the status is
/// surfaced prominently, and Confidence is forced to `Unknown` (#6). A status is never mapped
/// by resemblance — matching is exact.
///
/// The map is the Operator's own, and #13 made it editable: `setting` and `removing` return a new
/// map rather than mutating one, because `default` is a shared value and an edit that reached it
/// would spread across every reading in the app. `Forecast.evaluate` takes the map as a value the
/// way it takes the identity and the baseline — the domain performs no I/O, and holding an edited
/// map across launches is the app's business (`StatusMapStore`).
public struct StatusMap: Equatable, Sendable {
    private let entries: [String: FlowState]

    public init(_ entries: [String: FlowState]) {
        self.entries = entries
    }

    /// The `FlowState` for a Jira status name, or `nil` when the status is unmapped.
    public func flowState(for jiraStatus: String) -> FlowState? {
        entries[jiraStatus]
    }

    /// The map with `jiraStatus` translated to `flowState` — a status the map never knew joined it,
    /// a status it knew changed its answer, and nothing else moved (#13).
    public func setting(_ jiraStatus: String, to flowState: FlowState) -> StatusMap {
        var edited = entries
        edited[jiraStatus] = flowState
        return StatusMap(edited)
    }

    /// The map without `jiraStatus`, which makes it an `Unmapped Status` again: removing an entry
    /// is a real edit with a real consequence — rule 1 comes back — and not a request to guess at
    /// what the status meant.
    public func removing(_ jiraStatus: String) -> StatusMap {
        guard entries[jiraStatus] != nil else { return self }
        var edited = entries
        edited.removeValue(forKey: jiraStatus)
        return StatusMap(edited)
    }

    /// The map as `(Jira status, Flow State)` pairs, sorted by Jira status, so the editor's rows
    /// stay in one order across launches rather than following `Dictionary`'s per-process ordering.
    /// The status names are reachable through this and nowhere else: #13 made the map the editor's
    /// own subject, and a row needs its pair whole.
    public var rows: [(jiraStatus: String, flowState: FlowState)] {
        entries.sorted { $0.key < $1.key }.map { (jiraStatus: $0.key, flowState: $0.value) }
    }

    /// The Status Map for the Operator's current workflow, from `docs/agents/product.md`, and the
    /// map an edit starts from on first launch. `Backlog` occurs on Issues inside an active sprint,
    /// not only outside one.
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

/// The map is a value the app persists (`StatusMapStore`) and hands back in, so it has to survive
/// being written to disk and read again. The shape on disk is the map itself — a JSON object of
/// `{ "Jira status": "FlowState" }` — because a translation table is the one thing in this system
/// worth being able to read with no code in front of it.
extension StatusMap: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([String: FlowState].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(entries)
    }
}
