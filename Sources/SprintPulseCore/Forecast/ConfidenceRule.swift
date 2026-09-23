import Foundation

/// Which of the nine rules in `docs/agents/glossary.md` matched — the answer's own provenance,
/// carried as data beside the answer itself.
///
/// One case per numbered rule, and the state follows from the rule by definition (`state` below).
/// That is why `ConfidenceReading` stores the rule rather than storing the band state beside it:
/// an Explanation is generated from the same fact the number was, so the two cannot disagree.
///
/// Rule 1 is the exception to one-case-per-rule, and deliberately so: it has two triggers in
/// `docs/agents/glossary.md` — an Unmapped Status, and data that predates the current Working
/// Day — which answer the same state (`Unknown`) for two reasons the Operator can do two different
/// things about. M0 could only reach the first; #12 added a cache that can go stale, and with it
/// the second case, so the Reading says which one withdrew the forecast rather than leaving the
/// panel to infer it from a timestamp.
public enum ConfidenceRule: Sendable, Equatable {
    /// Rule 1 — an Issue of My Work sits in an Unmapped Status, so its Points are in no total.
    case unmappedStatus
    /// Rule 1, its stale-data trigger (#12) — the data behind the reading was read before the
    /// current Working Day. Every Points total still stands; the comparison between the rates is
    /// no longer today's, and a stale burn rate is worse than none.
    case dataPredatesWorkingDay
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
        case .dataPredatesWorkingDay: return .unknown
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
    ///
    /// Where rule 1's two triggers both hold, the Unmapped Status is the one the Reading names:
    /// the status is the thing the Operator can go and map, and a stale cache resolves itself on
    /// the next read that gets through.
    public static func evaluate(
        unmappedStatusPresent: Bool,
        dataPredatesWorkingDay: Bool,
        actionablePoints: Double,
        waitingPoints: Double,
        requiredRate: Double?,
        demonstratedRate: Double?
    ) -> ConfidenceRule {
        if unmappedStatusPresent { return .unmappedStatus }                            // Rule 1
        if dataPredatesWorkingDay { return .dataPredatesWorkingDay }                   // Rule 1
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
