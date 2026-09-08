import Foundation

/// Who the forecast is about, supplied to the domain as a value.
///
/// Jira Data Center identifies users by `name` (mutable username) and `key` (stable across
/// renames). Assignee matching is on `key`, falling back to `name`, so a username change does
/// not empty the forecast. In M1 this is resolved once from `/rest/api/2/myself`; the walking
/// skeleton passes it in directly.
public struct OperatorIdentity: Equatable, Sendable {
    public let key: String
    public let name: String

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }

    /// Whether the given Jira user is the Operator.
    public func matches(_ user: JiraUser?) -> Bool {
        guard let user else { return false }
        if let userKey = user.key, userKey == key { return true }
        if let userName = user.name, userName == name { return true }
        return false
    }
}
