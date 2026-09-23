import Foundation

/// Everything the panel renders, as a single value.
///
/// The panel holds no forecast logic: it displays the fields of an `Instrument` and nothing
/// more. Each M0 ticket widened this type — Flow States and Points per Flow State (#4), Working
/// Days Remaining (#5), the rates and Confidence State (#6), the `ConfidenceReading` that
/// explains them (#7), and the Scope Delta against the Sprint Baseline (#8). #11 widened the
/// gateway's implementations and no field of the model at all; #12 added the two the cache needs,
/// which are facts about *when the data was read* rather than about the sprint.
///
/// The one thing the panel needs that is not in here — whether My Work has any subject — it asks
/// `SprintSnapshot.myWork(assignedTo:)` for, the same call the forecast sums over.
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

    /// The named Confidence State to display — the band rules demoted by whatever Caps fired.
    /// Derived from `reading`, never stored beside it, so the number and its Explanation cannot
    /// drift apart.
    public var confidenceState: ConfidenceState { reading.state }

    /// The structured basis of the displayed state: which rule matched and which Caps fired
    /// (CONTEXT "Reading", #7). The panel renders its one-line Explanation from this and
    /// re-derives no arithmetic of its own — a forecast that cannot be argued with is a score to
    /// be trusted, which is the failure `docs/agents/product.md` exists to avoid.
    public let reading: ConfidenceReading

    /// Points over the live Active Sprint: every task-level Issue currently in it, regardless
    /// of assignee (Team Scope — scope can move through Issues the Operator does not own).
    /// The same population the Sprint Baseline snapshots, so the two are commensurable (#8).
    public let liveSprintPoints: Double

    /// Points as the Sprint Baseline recorded them: the first observation of this sprint, or
    /// equal to `liveSprintPoints` when this is it. Forecast input: never (CONTEXT invariant 9).
    public let baselinePoints: Double

    /// `Scope Delta` — live sprint Points minus Sprint Baseline Points (CONTEXT "Scope Delta").
    /// Positive is added scope, negative is work dropped out of the sprint; the two must read
    /// differently on the panel, and neither is the `Dropped` Flow State, whose Points leave the
    /// remaining total without moving this figure (#8).
    public var scopeDelta: Double { liveSprintPoints - baselinePoints }

    /// The moment the data behind this reading was taken (#12). A reading carries it so the panel
    /// can say how old its own numbers are instead of letting a cached sprint present as a current
    /// one — the age is a fact about the data, not something the view infers from a clock.
    ///
    /// For a fixture this is the moment the scenario pins in its own `now.json` (#9): a scenario
    /// *is* an observation taken then.
    public let readAt: Date

    /// Whether that data predates the current Working Day — the judgement behind rule 1's
    /// stale-data trigger (#12), carried beside the reading it produced.
    ///
    /// `Instrument.reading.rule` already names the trigger when it fires, and names the Unmapped
    /// Status first when both hold. This is the data's own fact, independent of which rule won:
    /// Points read yesterday are yesterday's Points whether or not something else withdrew the
    /// forecast too.
    public let predatesCurrentWorkingDay: Bool

    public init(
        sprintName: String,
        pointsByFlowState: [FlowState: Double],
        unestimatedCount: Int,
        unmappedStatuses: [String],
        workingDaysRemaining: Int,
        workingDaysElapsed: Int,
        requiredRate: Double?,
        demonstratedRate: Double?,
        reading: ConfidenceReading,
        liveSprintPoints: Double,
        baselinePoints: Double,
        readAt: Date,
        predatesCurrentWorkingDay: Bool
    ) {
        self.sprintName = sprintName
        self.pointsByFlowState = pointsByFlowState
        self.unestimatedCount = unestimatedCount
        self.unmappedStatuses = unmappedStatuses
        self.workingDaysRemaining = workingDaysRemaining
        self.workingDaysElapsed = workingDaysElapsed
        self.requiredRate = requiredRate
        self.demonstratedRate = demonstratedRate
        self.reading = reading
        self.liveSprintPoints = liveSprintPoints
        self.baselinePoints = baselinePoints
        self.readAt = readAt
        self.predatesCurrentWorkingDay = predatesCurrentWorkingDay
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
