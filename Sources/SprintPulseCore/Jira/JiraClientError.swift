import Foundation

/// How a live Jira request failed — one case per condition the Operator can act on.
///
/// A self-hosted instance behind a VPN fails in several different ways, and collapsing them
/// into "could not connect" makes the integration undebuggable (#10): an expired token says
/// *recreate the token*, a TLS rejection says *fix the certificate*, a 404 says *the base URL
/// points at the wrong place*. Each case therefore carries its own `message`, and no message
/// contains the Personal Access Token — errors are what the panel shows the Operator and what
/// a debug session echoes, and the token must survive neither (#2).
public enum JiraClientError: Error, Equatable {
    /// DNS failed or the host refused/dropped the connection — the instance is not there
    /// right now. Usually: the VPN is off.
    case unreachableHost(host: String)

    /// The TLS handshake was rejected. A certificate problem, never a token problem —
    /// the request carrying the token was never sent.
    case tlsFailure(host: String)

    /// 401 or 403: Jira knows the address and said no. The PAT is wrong or expired.
    case credentialRejected

    /// 404 on the configured path: the host answered, but not where the base URL points.
    /// A wrong base URL, or a disabled REST API.
    case pathNotFound(path: String)

    /// A 2xx whose body is not a response of the expected shape — including a well-formed
    /// JSON response missing what the caller needs, which Jira returns when a login method
    /// strips fields.
    case malformedResponse

    /// A status with no distinct reading (5xx, redirects exhausted, anything unlisted).
    /// Reported as itself rather than folded into one of the states above.
    case unexpectedStatus(code: Int)

    /// A connection-level failure that is neither an unreachable host nor a rejected
    /// certificate. Named by the system's own reason, so it is distinguishable from every
    /// state above instead of lying about which one it was.
    case connectionFailed(reason: String)

    /// No Personal Access Token was supplied. The app refuses the request rather than
    /// authenticating from any other source — an environment variable, a netrc file, or
    /// credentials inherited from a CLI (#10).
    case missingToken

    /// The configured base URL is not usable as a Jira Data Center root.
    case invalidBaseURL(detail: String)

    /// What the panel shows. Distinct per state by construction: one sentence each, naming
    /// what to do.
    public var message: String {
        switch self {
        case .unreachableHost(let host):
            return "Can't reach \(host). The instance may be down, or the VPN may not be connected."
        case .tlsFailure(let host):
            return "The HTTPS certificate for \(host) was rejected — a TLS problem, not a token problem. The request was never sent."
        case .credentialRejected:
            return "Jira rejected the Personal Access Token (401/403). If it expired, create a new one in your Jira profile. No other credential will be tried."
        case .pathNotFound(let path):
            return "The configured Jira answered, but has no API at \(path). The base URL may point at the wrong path, or the REST API may be disabled."
        case .malformedResponse:
            return "Jira answered, but the response could not be read as a Data Center response of the expected shape."
        case .unexpectedStatus(let code):
            return "Jira answered with status \(code). Nothing was stored from this response."
        case .connectionFailed(let reason):
            return "The connection to Jira failed: \(reason)"
        case .missingToken:
            return "No Personal Access Token is configured. Sprint Pulse authenticates only from the single Keychain item it stored itself — never from an environment variable, a netrc file, or any inherited credential."
        case .invalidBaseURL(let detail):
            return "That is not a usable Jira base URL: \(detail)"
        }
    }
}

extension JiraClientError {
    /// Maps a connection-level `URLError` — a failure that produced no response at all —
    /// onto its distinct state. The two families an Operator has to tell apart are "the
    /// instance is not reachable" (VPN off, DNS wrong, host down) and "reaching it was
    /// refused on TLS grounds" (untrusted certificate, expired certificate, hostname
    /// mismatch); everything else keeps its own name rather than joining either family.
    init(urlError: URLError, host: String) {
        switch urlError.code {
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .notConnectedToInternet, .timedOut:
            self = .unreachableHost(host: host)
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
             .clientCertificateRejected, .clientCertificateRequired:
            self = .tlsFailure(host: host)
        default:
            self = .connectionFailed(reason: urlError.localizedDescription)
        }
    }
}
