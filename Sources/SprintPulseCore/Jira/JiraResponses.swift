import Foundation

/// Decoded shapes of Jira **Data Center** REST responses.
///
/// These types are a faithful subset of what Jira Data Center returns from the Agile API
/// (`/rest/agile/1.0/`) and REST API v2 (`/rest/api/2/`). Unknown keys in the JSON are ignored,
/// so a fixture in the exact shape of a live response decodes identically — that is the seam
/// the `JiraGateway` protocol exists to hide.
///
/// The modelled fields are the ones the instrument reads now or in the next M0 tickets (Flow
/// States #4, Working Days #5). Everything else Jira sends is left unmodelled rather than
/// carried speculatively.

// MARK: - Sprints

/// The envelope returned by `/rest/agile/1.0/board/{boardId}/sprint`.
public struct JiraSprintsResponse: Decodable, Equatable, Sendable {
    public let maxResults: Int
    public let startAt: Int
    public let isLast: Bool
    public let values: [JiraSprint]
}

/// A Jira Agile sprint object. `startDate`/`endDate` feed Working Days Remaining (#5).
public struct JiraSprint: Decodable, Equatable, Sendable {
    public let id: Int
    public let state: String
    public let name: String
    public let startDate: Date?
    public let endDate: Date?
}

// MARK: - Issues

/// The envelope returned by `/rest/agile/1.0/sprint/{sprintId}/issue`.
public struct JiraSprintIssuesResponse: Decodable, Equatable, Sendable {
    public let startAt: Int
    public let maxResults: Int
    public let total: Int
    public let issues: [JiraIssue]
}

/// A Jira issue as returned inside a sprint's issue list.
public struct JiraIssue: Decodable, Equatable, Sendable {
    public let id: String
    public let key: String
    public let fields: JiraIssueFields
}

/// The `fields` object of a Jira issue.
///
/// The story-point value lives in an instance-specific custom field
/// (`JiraDecoding.storyPointsFieldID`).
public struct JiraIssueFields: Decodable, Equatable, Sendable {
    public let summary: String
    public let issueType: JiraIssueType
    public let status: JiraStatus
    public let assignee: JiraUser?
    /// The raw story-point value from the configured custom field. `nil` when the field is
    /// absent or null — an unsized issue, never a zero.
    public let estimate: Double?

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ stringValue: String) { self.stringValue = stringValue }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }

        static let summary = Key("summary")
        static let issuetype = Key("issuetype")
        static let status = Key("status")
        static let assignee = Key("assignee")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        issueType = try container.decode(JiraIssueType.self, forKey: .issuetype)
        status = try container.decode(JiraStatus.self, forKey: .status)
        assignee = try container.decodeIfPresent(JiraUser.self, forKey: .assignee)
        estimate = try container.decodeIfPresent(Double.self, forKey: Key(JiraDecoding.storyPointsFieldID))
    }
}

/// A Jira issue type. Sub-tasks are detail belonging to their parent, never Issues, and are
/// identified by `subtask` rather than by name.
public struct JiraIssueType: Decodable, Equatable, Sendable {
    public let name: String
    public let subtask: Bool
}

/// A Jira status. The status *name* is a Jira string; nothing outside a Status Map may
/// interpret it (CONTEXT invariant 1). The walking skeleton carries it without reading it;
/// the Status Map arrives in #4.
public struct JiraStatus: Decodable, Equatable, Sendable {
    public let name: String
}

/// A Jira Data Center user. Identified by `name` (mutable username) and `key` (stable across
/// renames) — not Jira Cloud's `accountId`.
public struct JiraUser: Decodable, Equatable, Sendable {
    public let name: String?
    public let key: String?
    public let displayName: String?
}
