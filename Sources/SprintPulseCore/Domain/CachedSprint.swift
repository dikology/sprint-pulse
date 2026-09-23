import Foundation

/// The last successful sprint read, held by the app and judged by the domain (#12).
///
/// A `SprintSnapshot` plus the two facts a snapshot cannot carry about itself: the Board it was
/// read from and the moment it was taken. Those are the whole of what makes a cached reading
/// honest — the Points in it are as correct as the day they were counted, and their age is the
/// one thing the reading cannot infer from its own contents.
///
/// **The app's own JSON, not a Jira response**, which is the line `SprintBaseline` draws (#8) for
/// the same reason twice over. A cached read has already been *interpreted*: its Estimates are the
/// Estimates, resolved from whichever custom field was configured when the read happened, so a
/// later change to that configuration cannot make the cache misread itself as a sprint with
/// nothing measured — the failure mode #11 names as the quietest one in the app. And because the
/// shape is the app's, there is no field in it a Personal Access Token could be parked in: the
/// credential reaches `JiraHTTPClient` as a value and goes nowhere else (#10), which
/// `SprintCacheStoreTests` checks by sweeping the stored bytes rather than by trusting this
/// paragraph.
///
/// `boardID` is kept because a Board makes a reading *whose* in the only sense that matters here: a
/// cached forecast shown under another Board's name would be a wrong number wearing a right face,
/// the same failure the tracked-sprint answer is scoped against for the same reason (#11). The
/// Operator's identity is deliberately **not** part of the entry — "whose work is this" is a
/// question `Forecast` answers at evaluation from the assignees in the data, and storing a key
/// beside it would only let the cache hold an identity that could go stale on its own.
public struct CachedSprint: Codable, Equatable, Sendable {
    /// A sprint as the cache holds it. `state` is kept because `resolveTrackedSprint` reads it: a
    /// cached sprint that lost its state on the way through storage would stop being an Active
    /// Sprint on the way back out.
    public struct Sprint: Codable, Equatable, Sendable {
        public let id: Int
        public let state: String
        public let name: String
        public let startDate: Date?
        public let endDate: Date?
    }

    /// An issue as the cache holds it — every field the decoded response carries, so the snapshot
    /// comes back out identical rather than approximately so. `CachedSprintTests` pins that.
    public struct Issue: Codable, Equatable, Sendable {
        public let id: String
        public let key: String
        public let summary: String
        public let issueTypeName: String
        public let subtask: Bool
        public let statusName: String
        public let assignee: Assignee?
        public let estimate: Double?
    }

    public struct Assignee: Codable, Equatable, Sendable {
        public let name: String?
        public let key: String?
        public let displayName: String?
    }

    public let boardID: Int

    /// The instant the read that produced this entry completed — the timestamp the acceptance
    /// criterion asks the cache be persisted *with*, and the one number `rule 1`'s stale-data
    /// trigger is computed against. `Instrument.readAt` carries the same instant onward.
    public let readAt: Date

    public let sprint: Sprint
    public let issues: [Issue]

    public init(boardID: Int, readAt: Date, snapshot: SprintSnapshot) {
        self.boardID = boardID
        self.readAt = readAt
        self.sprint = Sprint(
            id: snapshot.sprint.id,
            state: snapshot.sprint.state,
            name: snapshot.sprint.name,
            startDate: snapshot.sprint.startDate,
            endDate: snapshot.sprint.endDate
        )
        self.issues = snapshot.issues.map { issue in
            Issue(
                id: issue.id,
                key: issue.key,
                summary: issue.fields.summary,
                issueTypeName: issue.fields.issueType.name,
                subtask: issue.fields.issueType.subtask,
                statusName: issue.fields.status.name,
                assignee: issue.fields.assignee.map {
                    Assignee(name: $0.name, key: $0.key, displayName: $0.displayName)
                },
                estimate: issue.fields.estimate
            )
        }
    }

    /// The read as the domain takes it. `Forecast.evaluate` then runs on a cached sprint through
    /// the same code as on a live one — the same rule table, the same Caps, the same Scope Delta —
    /// and the only thing that differs is the moment it is told the data came from.
    public var snapshot: SprintSnapshot {
        SprintSnapshot(
            sprint: JiraSprint(
                id: sprint.id,
                state: sprint.state,
                name: sprint.name,
                startDate: sprint.startDate,
                endDate: sprint.endDate
            ),
            issues: issues.map { issue in
                JiraIssue(
                    id: issue.id,
                    key: issue.key,
                    fields: JiraIssueFields(
                        summary: issue.summary,
                        issueType: JiraIssueType(name: issue.issueTypeName, subtask: issue.subtask),
                        status: JiraStatus(name: issue.statusName),
                        assignee: issue.assignee.map {
                            JiraUser(name: $0.name, key: $0.key, displayName: $0.displayName)
                        },
                        estimate: issue.estimate
                    )
                )
            }
        )
    }
}
