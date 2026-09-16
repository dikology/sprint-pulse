import Foundation

/// A Reading, as data: which rule of the Confidence table matched and which Caps fired.
///
/// This is the object the panel explains itself with (CONTEXT "Reading", "Explanation"). It is
/// deliberately not a sentence and not a table of strings — a sentence in the domain could not be
/// argued with past its own wording, and a string keyed by state would re-derive in the view what
/// the model already knows. The rule and the Caps *are* the Explanation; the view renders them
/// beside numbers already on screen.
public struct ConfidenceReading: Equatable, Sendable {
    /// The rule that matched, which fixes the uncapped state by definition.
    public let rule: ConfidenceRule

    /// Every Cap whose condition held, in declaration order — including Caps that found no band
    /// left to demote. This is why `state` can equal `uncappedState`: a Cap is a condition on the
    /// data, and whether it had anywhere to go is a separate fact (`demotions`).
    public let caps: [Cap]

    public init(rule: ConfidenceRule, caps: [Cap]) {
        self.rule = rule
        self.caps = caps
    }

    /// What the rule table said before any Cap — the answer with nothing demoted, which the panel
    /// shows only as the origin of a demotion.
    public var uncappedState: ConfidenceState { rule.state }

    /// The Confidence State to display: the table's answer walked down one band per fired Cap,
    /// stopping at the bottom of the scale.
    public var state: ConfidenceState { steppedDown().state }

    /// How many bands `state` sits below `uncappedState`: fewer than `caps.count` when a Cap
    /// reached `Off Track`, and zero when the answer is not a point on the scale at all. The
    /// panel names a demotion exactly when this is non-zero, so a demotion is never unexplained
    /// and a reading that was not demoted never claims to have been.
    public var demotions: Int { steppedDown().demotions }

    /// One walk of the scale behind both accessors, so the displayed state and the count of bands
    /// it fell cannot disagree about the route.
    private func steppedDown() -> (state: ConfidenceState, demotions: Int) {
        var state = uncappedState
        var demotions = 0
        while demotions < caps.count, let lower = state.demotedOneBand {
            state = lower
            demotions += 1
        }
        return (state, demotions)
    }
}

extension ConfidenceReading {
    /// The whole reading in one call: the nine-rule table first, then the Caps — the evaluation
    /// order `docs/agents/glossary.md` fixes, expressed by the sequence of these two calls rather
    /// than by a note beside them.
    public static func evaluate(
        unmappedStatusPresent: Bool,
        actionablePoints: Double,
        waitingPoints: Double,
        requiredRate: Double?,
        demonstratedRate: Double?,
        unestimatedCount: Int
    ) -> ConfidenceReading {
        let rule = ConfidenceRule.evaluate(
            unmappedStatusPresent: unmappedStatusPresent,
            actionablePoints: actionablePoints,
            waitingPoints: waitingPoints,
            requiredRate: requiredRate,
            demonstratedRate: demonstratedRate
        )
        let caps = Cap.fired(
            unestimatedCount: unestimatedCount,
            actionablePoints: actionablePoints,
            waitingPoints: waitingPoints
        )
        return ConfidenceReading(rule: rule, caps: caps)
    }
}
