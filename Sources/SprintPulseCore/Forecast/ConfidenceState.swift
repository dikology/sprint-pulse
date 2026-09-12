import Foundation

/// The relationship between Demonstrated Rate and Required Rate, expressed on a named scale
/// (CONTEXT "Confidence State"). A stated comparison of two visible numbers, never a percentage
/// or a probability.
public enum ConfidenceState: Sendable, Equatable {
    /// Too little is known to say anything: fewer than two elapsed Working Days, zero Completed
    /// Points, or any Unmapped Status present. (A stale cache also forces this in M1, once a
    /// cache exists to go stale.) Always preferred to a guess.
    case unknown
    case offTrack
    case tight
    case onTrack
    case noSweat
    /// No Actionable Points remain but Waiting Points do — finished with everything that is the
    /// Operator's own to do, without the sprint itself being finished.
    case handsOff
    /// Neither Actionable nor Waiting Points remain: every Issue of My Work has reached `Done`
    /// or `Dropped`.
    case finished
}

/// The band boundaries on the `Demonstrated Rate ÷ Required Rate` ratio, kept in exactly one
/// place because they are expected to need calibration (`docs/agents/glossary.md`).
public enum ConfidenceBands {
    public static let noSweat = 1.25
    public static let onTrack = 1.00
    public static let tight = 0.75
}

extension ConfidenceState {
    /// The nine-rule evaluation table from `docs/agents/glossary.md`, in the specified order,
    /// first match winning. **That table is normative: this is a direct transcription, not a
    /// re-derivation, and the order must not change.**
    ///
    /// Rules 1–5 make the function total: by the time a Required Rate ÷ Demonstrated Rate ratio
    /// is taken, `actionablePoints > 0` (rules 2–3 ruled out zero) and `workingDaysRemaining > 0`
    /// (rule 5 ruled out zero), so the Required Rate is defined and positive; `workingDaysElapsed
    /// ≥ 2` and `completedPoints > 0` (rule 4), so the Demonstrated Rate is defined. No `A/0` or
    /// `C/0` is ever reached.
    public static func evaluate(
        unmappedStatusPresent: Bool,
        actionablePoints: Double,
        waitingPoints: Double,
        completedPoints: Double,
        workingDaysElapsed: Int,
        workingDaysRemaining: Int
    ) -> ConfidenceState {
        if unmappedStatusPresent { return .unknown }                                   // Rule 1
        if actionablePoints == 0 && waitingPoints == 0 { return .finished }             // Rule 2
        if actionablePoints == 0 && waitingPoints > 0 { return .handsOff }              // Rule 3
        if workingDaysElapsed < 2 || completedPoints == 0 { return .unknown }           // Rule 4
        if workingDaysRemaining == 0 { return .offTrack }                              // Rule 5

        let requiredRate = actionablePoints / Double(workingDaysRemaining)
        let demonstratedRate = completedPoints / Double(workingDaysElapsed)
        let ratio = demonstratedRate / requiredRate

        if ratio >= ConfidenceBands.noSweat { return .noSweat }                        // Rule 6
        if ratio >= ConfidenceBands.onTrack { return .onTrack }                        // Rule 7
        if ratio >= ConfidenceBands.tight { return .tight }                            // Rule 8
        return .offTrack                                                              // Rule 9
    }
}
