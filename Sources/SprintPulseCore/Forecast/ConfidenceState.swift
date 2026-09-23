import Foundation

/// The relationship between Demonstrated Rate and Required Rate, expressed on a named scale
/// (CONTEXT "Confidence State"). A stated comparison of two visible numbers, never a percentage
/// or a probability.
///
/// The `unknown`, `handsOff` and `finished` cases are named answers rather than bands: a Cap
/// never demotes them, because there is no lower band to move to (`demotedOneBand`).
public enum ConfidenceState: Sendable, Equatable {
    /// Too little is known to say anything: fewer than two elapsed Working Days, zero Completed
    /// Points, an Unmapped Status present, or data read before the current Working Day (#12).
    /// Always preferred to a guess.
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

/// The boundaries of the Confidence scale, kept in exactly one place because they are expected
/// to need calibration (`docs/agents/glossary.md`).
///
/// The first three are the band boundaries on the `Demonstrated Rate ÷ Required Rate` ratio; the
/// fourth is the Waiting-heavy Cap's boundary, which lives here for the same reason and is named
/// by the same mechanism — a reader checking a displayed demotion by hand finds every threshold
/// the Reading used in one file.
public enum ConfidenceBands {
    public static let noSweat = 1.25
    public static let onTrack = 1.00
    public static let tight = 0.75
    /// A Waiting share above this fraction of the remaining Points caps Confidence by one band.
    /// Strict: exactly this value does not fire.
    public static let waitingHeavy = 0.40
}

extension ConfidenceState {
    /// The band one place lower along `No Sweat → On Track → Tight → Off Track` — the path a Cap
    /// walks a Reading down (glossary §Caps).
    ///
    /// `nil` where there is nowhere lower to go: the bottom band, and the three named answers
    /// (`Unknown`, `Hands Off`, `Finished`) that are not points on the scale at all. A Cap never
    /// promotes (CONTEXT invariant 5), which is why this is a one-way step rather than an index
    /// into an ordered list of states — `ConfidenceState` deliberately has no ordering.
    public var demotedOneBand: ConfidenceState? {
        switch self {
        case .noSweat: return .onTrack
        case .onTrack: return .tight
        case .tight: return .offTrack
        case .offTrack, .unknown, .handsOff, .finished: return nil
        }
    }
}
