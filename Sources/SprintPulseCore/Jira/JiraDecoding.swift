import Foundation

/// Builds a `JSONDecoder` configured for Jira Data Center responses.
public enum JiraDecoding {
    /// The custom field carrying an Issue's Estimate on the Operator's Jira installation. Custom
    /// field ids are assigned in installation order, so this is a per-instance value rather than
    /// a constant of the API (#11): read the wrong field and every Issue decodes with no
    /// Estimate, which the instrument reports as `Finished` — a confident zero built out of
    /// nothing. This is the *default*; the live read decodes with whatever the Operator
    /// configured, which is why the decoder is built per read rather than shared.
    ///
    /// Named for the domain concept (`CONTEXT.md` "Estimate", which explicitly avoids "story
    /// points") rather than for what one installation happens to call its field.
    public static let estimateFieldID = "customfield_10002"

    /// How the field id reaches `JiraIssueFields`, which decodes it by name and has no other way
    /// to be told. A `Decoder` carries no properties of its own, so the configuration travels in
    /// `userInfo`.
    static let estimateFieldIDInfoKey = CodingUserInfoKey(rawValue: "sprintPulse.estimateFieldID")!

    /// A decoder for Data Center envelopes, reading the Estimate from `estimateFieldID`.
    public static func decoder(estimateFieldID: String = JiraDecoding.estimateFieldID) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[estimateFieldIDInfoKey] = estimateFieldID
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            for formatter in [Self.fractionalSecondsUTC, Self.secondsUTC] {
                if let date = formatter.date(from: string) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognised Jira date: \(string)"
            )
        }
        return decoder
    }

    /// `yyyy-MM-dd'T'HH:mm:ss.SSSZ` — what `/rest/agile/1.0/` emits for sprint dates
    /// (`2026-09-01T09:00:00.000+0000`). `Z` in `DateFormatter` accepts the `+0000` form Data
    /// Center actually writes; `ISO8601DateFormatter` with `.withInternetDateTime` does not.
    private static let fractionalSecondsUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()

    /// The same without fractional seconds, which some endpoints emit.
    private static let secondsUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()
}
