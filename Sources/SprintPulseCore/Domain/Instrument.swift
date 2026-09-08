import Foundation

/// Everything the panel renders, as a single value.
///
/// The panel holds no forecast logic: it displays the fields of an `Instrument` and nothing
/// more. Each later M0 ticket widens this type — Points per Flow State (#4), Working Days
/// Remaining (#5), the rates and Confidence State (#6). The walking skeleton carries only the
/// total Points remaining.
public struct Instrument: Equatable, Sendable {
    /// The Active Sprint's name, for the panel header.
    public let sprintName: String

    /// Total Points remaining in My Work.
    ///
    /// Until Flow States land (#4) there is no way to tell a finished Issue from an open one,
    /// so every My Work Issue counts as remaining. Unestimated Issues contribute nothing —
    /// they are never coerced to zero-as-a-value.
    public let pointsRemaining: Double

    public init(sprintName: String, pointsRemaining: Double) {
        self.sprintName = sprintName
        self.pointsRemaining = pointsRemaining
    }
}
