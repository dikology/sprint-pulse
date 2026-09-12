import Foundation

/// Everything the panel renders, as a single value.
///
/// The panel holds no forecast logic: it displays the fields of an `Instrument` and nothing
/// more. Each M0 ticket widens this type — Flow States and Points per Flow State (#4), Working
/// Days Remaining (#5), the rates and Confidence State (#6). Caps and a structured explanation
/// (#7) widen it further.
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

    /// `WDE` — Working Days Elapsed: Working Days in `[sprintStart, today]`, inclusive of today.
    /// `0` before the sprint has started.
    public let workingDaysElapsed: Int

    /// `R` — Required Rate: `A ÷ WDR`, what the Operator must burn per day to finish. `nil` when
    /// `WDR = 0`. Shown on the panel even while Confidence is `Unknown` — the earliest days of a
    /// sprint still tell the Operator something.
    public let requiredRate: Double?

    /// `D` — Demonstrated Rate: `C ÷ WDE`, the observed rate at which the Operator has been
    /// completing Points. `nil` before `WDE ≥ 2` or while `C = 0`.
    public let demonstratedRate: Double?

    /// The named Confidence State, evaluated by the nine-rule table in
    /// `docs/agents/glossary.md`.
    public let confidenceState: ConfidenceState

    public init(
        sprintName: String,
        pointsByFlowState: [FlowState: Double],
        unestimatedCount: Int,
        unmappedStatuses: [String],
        workingDaysRemaining: Int,
        workingDaysElapsed: Int,
        requiredRate: Double?,
        demonstratedRate: Double?,
        confidenceState: ConfidenceState
    ) {
        self.sprintName = sprintName
        self.pointsByFlowState = pointsByFlowState
        self.unestimatedCount = unestimatedCount
        self.unmappedStatuses = unmappedStatuses
        self.workingDaysRemaining = workingDaysRemaining
        self.workingDaysElapsed = workingDaysElapsed
        self.requiredRate = requiredRate
        self.demonstratedRate = demonstratedRate
        self.confidenceState = confidenceState
    }

    /// Points in one Flow State. `0` for an absent or wholly-unestimated set.
    public func points(_ state: FlowState) -> Double {
        pointsByFlowState[state] ?? 0
    }

    /// `A` — Points the Operator's own effort can move (`ToDo` + `InProgress`).
    public var actionablePoints: Double {
        Self.sum(FlowState.actionable, of: pointsByFlowState)
    }

    /// `W` — Points unfinished but outside the Operator's control (`InReview` + `OnHold`).
    public var waitingPoints: Double {
        Self.sum(FlowState.waiting, of: pointsByFlowState)
    }

    /// The one place `A` and `W` are summed from a per-Flow-State totals dictionary. `Forecast`
    /// needs `A` and `W` to compute the rates before an `Instrument` exists to ask, so it calls
    /// this directly rather than restating the formula.
    static func sum(_ states: [FlowState], of pointsByFlowState: [FlowState: Double]) -> Double {
        states.reduce(0) { $0 + (pointsByFlowState[$1] ?? 0) }
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
