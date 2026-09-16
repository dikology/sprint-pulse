import Foundation

/// A condition that demotes the displayed Confidence State by exactly one band (CONTEXT "Cap").
/// The two conditions are the table in `docs/agents/glossary.md` §Caps; CONTEXT invariant 5 and
/// the glossary both settle what a demotion may do to a state, which is `ConfidenceState`'s
/// business, not this file's.
///
/// Every condition is computed from numbers the panel already shows, so a Cap can be argued
/// with by hand (CONTEXT invariant 10).
public enum Cap: Sendable, Equatable {
    /// `U > 0` — an unknown amount of work remains, so the ratio is computed over an incomplete
    /// total.
    case unestimated
    /// `W / (A + W) > ConfidenceBands.waitingHeavy` — too much of the sprint sits in somebody
    /// else's queue to claim comfort.
    case waitingHeavy

    /// The Caps whose condition holds, in declaration order. A Cap appears at most once: it is
    /// a condition, not a rate, and firing twice would demote twice on the same evidence.
    public static func fired(
        unestimatedCount: Int,
        actionablePoints: Double,
        waitingPoints: Double
    ) -> [Cap] {
        var fired: [Cap] = []
        if unestimatedCount > 0 { fired.append(.unestimated) }

        // The share is taken over the remaining Points only — Done and Dropped work is in neither
        // the numerator nor the denominator. `A + W = 0` leaves the share undefined rather than
        // reading it as zero; that is the `Finished` state, which no Cap can demote anyway.
        let remaining = actionablePoints + waitingPoints
        if remaining > 0 && waitingPoints / remaining > ConfidenceBands.waitingHeavy {
            fired.append(.waitingHeavy)
        }

        return fired
    }
}
