import Foundation

/// Everything the panel renders, as a single value.
///
/// The panel holds no forecast logic: it displays the fields of an `Instrument` and nothing
/// more. Each M0 ticket widens this type — Flow States and Points per Flow State (#4), Working
/// Days Remaining (#5), the rates and Confidence State (#6).
public struct Instrument: Equatable, Sendable {
    /// The Active Sprint's name, for the panel header.
    public let sprintName: String

    /// Points summed per Flow State across My Work. Every Flow State has an entry, `0` when the
    /// set is empty or holds only Unestimated Issues. An Unestimated Issue contributes nothing
    /// — it is never coerced to zero-as-a-value (CONTEXT invariant 2); its magnitude shows up
    /// only in `unestimatedCount`.
    public let pointsByFlowState: [FlowState: Double]

    /// The count of Unestimated Issues sitting in the Actionable or Waiting sets. This is a
    /// count of Issues, not a sum of Points, because its whole purpose is to express an unknown
    /// magnitude. Unestimated Issues that are `Done` or `Dropped` are not counted — they can no
    /// longer affect the outcome.
    public let unestimatedCount: Int

    /// Jira statuses on My Work Issues with no Status Map entry, sorted, each named exactly
    /// once. The Issues behind them are in no set. Empty in the ordinary case; when non-empty
    /// the panel surfaces it prominently and Confidence is forced to `Unknown` (#6).
    public let unmappedStatuses: [String]

    /// `WDR` — Working Days Remaining: Working Days in `[today, sprintEnd]`, inclusive of today,
    /// counted against the Operator's configured working pattern rather than a naive weekday
    /// count. `0` once the sprint has ended.
    public let workingDaysRemaining: Int

    public init(
        sprintName: String,
        pointsByFlowState: [FlowState: Double],
        unestimatedCount: Int,
        unmappedStatuses: [String],
        workingDaysRemaining: Int
    ) {
        self.sprintName = sprintName
        self.pointsByFlowState = pointsByFlowState
        self.unestimatedCount = unestimatedCount
        self.unmappedStatuses = unmappedStatuses
        self.workingDaysRemaining = workingDaysRemaining
    }

    /// Points in one Flow State. `0` for an absent or wholly-unestimated set.
    public func points(_ state: FlowState) -> Double {
        pointsByFlowState[state] ?? 0
    }

    /// `A` — Points the Operator's own effort can move (`ToDo` + `InProgress`).
    public var actionablePoints: Double {
        FlowState.actionable.reduce(0) { $0 + points($1) }
    }

    /// `W` — Points unfinished but outside the Operator's control (`InReview` + `OnHold`).
    public var waitingPoints: Double {
        FlowState.waiting.reduce(0) { $0 + points($1) }
    }

    /// `C` — Completed Points. Dropped work is never added here.
    public var completedPoints: Double {
        points(.done)
    }

    /// `X` — Dropped Points. Shown as its own figure and excluded from every remaining total.
    public var droppedPoints: Double {
        points(.dropped)
    }

    /// Points not yet finished and not shed: Actionable + Waiting. `Done` and `Dropped` are
    /// excluded from every remaining total.
    public var pointsRemaining: Double {
        actionablePoints + waitingPoints
    }
}
