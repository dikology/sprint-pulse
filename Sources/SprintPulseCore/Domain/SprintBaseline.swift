import Foundation

/// A snapshot of the Active Sprint's Issues and Estimates, taken the first time Sprint Pulse
/// observes the sprint as active.
///
/// It exists to explain change — the Scope Delta (#4+) is measured against it — never to be
/// forecast against. The walking skeleton captures and persists it but does not yet display
/// anything derived from it.
///
/// The snapshot is over the whole sprint (Team Scope), not just My Work: scope can move
/// through issues that are not the Operator's.
public struct SprintBaseline: Equatable, Sendable, Codable {
    /// One Issue as it stood when the baseline was taken.
    public struct Entry: Equatable, Sendable, Codable {
        public let key: String
        /// The Estimate at snapshot time. `nil` for an Unestimated Issue.
        public let estimate: Double?

        public init(key: String, estimate: Double?) {
            self.key = key
            self.estimate = estimate
        }
    }

    public let sprintID: Int
    public let capturedAt: Date
    public let entries: [Entry]

    public init(sprintID: Int, capturedAt: Date, entries: [Entry]) {
        self.sprintID = sprintID
        self.capturedAt = capturedAt
        self.entries = entries
    }
}
