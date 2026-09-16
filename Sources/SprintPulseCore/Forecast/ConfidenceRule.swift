import Foundation

/// Which of the nine rules in `docs/agents/glossary.md` matched — the answer's own provenance,
/// carried as data beside the answer itself.
///
/// One case per numbered rule, and the state follows from the rule by definition (`state` below).
/// That is why `ConfidenceReading` stores the rule rather than storing the band state beside it:
/// an Explanation is generated from the same fact the number was, so the two cannot disagree.
///
/// # The stale-data trigger
///
/// Rule 1 has two triggers in the glossary: an Unmapped Status, and a cache that predates the
/// current Working Day. Only the first is reachable in M0, which reads fixtures and has no cache
/// to go stale. M1 adds the second, and with it either a case here or a payload on this one.
public enum ConfidenceRule: Sendable, Equatable {
    /// Rule 1 — an Issue of My Work sits in an Unmapped Status, so its Points are in no total.
    case unmappedStatus
    /// Rule 2 — `A = 0` and `W = 0`: no Actionable and no Waiting Points remain.
    case nothingRemaining
    /// Rule 3 — `A = 0` and `W > 0`: nothing the Operator's own effort can move remains.
    case nothingActionableRemaining
    /// Rule 4 — `WDE < 2` or `C = 0`: the Demonstrated Rate is unmeasurable, which is not the
    /// same as measured low.
    case insufficientHistory
    /// Rule 5 — `WDR = 0` while Actionable Points remain: no Working Day left to burn them.
    case workingDaysExhausted
    /// Rule 6 — `ratio ≥ 1.25`.
    case ratioNoSweat
    /// Rule 7 — `1.00 ≤ ratio < 1.25`.
    case ratioOnTrack
    /// Rule 8 — `0.75 ≤ ratio < 1.00`.
    case ratioTight
    /// Rule 9 — `ratio < 0.75`.
    case ratioOffTrack

    /// The Confidence State this rule names — the third column of the glossary table.
    public var state: ConfidenceState {
        switch self {
        case .unmappedStatus: return .unknown
        case .nothingRemaining: return .finished
        case .nothingActionableRemaining: return .handsOff
        case .insufficientHistory: return .unknown
        case .workingDaysExhausted: return .offTrack
        case .ratioNoSweat: return .noSweat
        case .ratioOnTrack: return .onTrack
        case .ratioTight: return .tight
        case .ratioOffTrack: return .offTrack
        }
    }
}

extension ConfidenceRule {
    /// The nine-rule evaluation table from `docs/agents/glossary.md`, in the specified order,
    /// first match winning. **That table is normative: this is a direct transcription, not a
    /// re-derivation, and the order must not change.**
    ///
    /// Rules 1–5 make the function total: `requiredRate` and `demonstratedRate` are `nil` under
    /// exactly the conditions rules 4–5 check for (see `Forecast.evaluate`, the sole place either
    /// division is performed), so by the time the ratio is taken both are defined and the
    /// `Required Rate` is positive. No `A/0` or `C/0` is ever reached.
    ///
    /// Caps are consulted nowhere in this function: they are evaluated *after* the band rules,
    /// never before (`ConfidenceReading.evaluate`). That order is what lets an unsized Issue or a
    /// full review queue demote a Reading without ever suppressing one — an unmapped status still
    /// yields `Unknown` rather than a capped guess, and `Hands Off` is still `Hands Off`.
    public static func evaluate(
        unmappedStatusPresent: Bool,
        actionablePoints: Double,
        waitingPoints: Double,
        requiredRate: Double?,
        demonstratedRate: Double?
    ) -> ConfidenceRule {
        if unmappedStatusPresent { return .unmappedStatus }                            // Rule 1
        if actionablePoints == 0 && waitingPoints == 0 { return .nothingRemaining }    // Rule 2
        if actionablePoints == 0 && waitingPoints > 0 { return .nothingActionableRemaining }  // Rule 3
        guard let demonstratedRate else { return .insufficientHistory }                // Rule 4
        guard let requiredRate else { return .workingDaysExhausted }                   // Rule 5

        let ratio = demonstratedRate / requiredRate

        if ratio >= ConfidenceBands.noSweat { return .ratioNoSweat }                   // Rule 6
        if ratio >= ConfidenceBands.onTrack { return .ratioOnTrack }                   // Rule 7
        if ratio >= ConfidenceBands.tight { return .ratioTight }                       // Rule 8
        return .ratioOffTrack                                                          // Rule 9
    }
}
