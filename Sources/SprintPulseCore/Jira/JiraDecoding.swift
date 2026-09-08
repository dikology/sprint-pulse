import Foundation

/// Builds a `JSONDecoder` configured for Jira Data Center responses.
public enum JiraDecoding {
    /// The custom field carrying an issue's story-point Estimate on the Operator's Jira
    /// installation. A per-instance setting in M1; a fixed default until then.
    public static let storyPointsFieldID = "customfield_10002"

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "Unrecognised Jira date: \(string)")
                )
            }
            return date
        }
        return decoder
    }

    /// Jira Data Center emits ISO-8601 with milliseconds and a numeric offset
    /// (`2026-09-01T09:00:00.000+0000`); some deployments use `Z`. Accept both.
    static func parseDate(_ string: String) -> Date? {
        for formatter in dateFormatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }

    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
         "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
         "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
         "yyyy-MM-dd'T'HH:mm:ssZ"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            return formatter
        }
    }()
}
