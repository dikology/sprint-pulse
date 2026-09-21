import Foundation
import SprintPulseCore

/// The credential-setup flow (#10): the Operator names a Jira Data Center base URL and a
/// Personal Access Token, the app asks `/rest/api/2/myself` who that credential is, and only
/// a resolved identity is confirmed and persisted. #11 adds the rest of the connection's
/// configuration beside it — the one Board to watch and the custom field that carries Estimates —
/// which is remembered without a probe because it authenticates nothing.
///
/// Setup is atomic in the direction that matters: nothing — not the token, not the base URL,
/// not an identity — is stored *by the attempt* before Jira has answered. A failed probe
/// therefore leaves no half-configured credential behind, and fixture mode, the default
/// whenever no credential exists, is never left pointing at a live configuration that was
/// refused. A credential stored by an earlier, successful setup is untouched by a later
/// failure and stays removable — `hasStoredCredential` is what the panel renders the
/// removal control on, independent of this flow's state.
///
/// The `probe` is the same kind of seam the core client has under its transport: production
/// resolves identity through `JiraHTTPClient` over the app's URLSession adapter; tests hand
/// in a fake, so the whole flow is exercisable without a Jira, a VPN, or a credential — and
/// without a real network call ever being made from a test. This is not a credential-store
/// protocol: the token still reaches core as a plain value, and nothing but the app's own
/// Keychain item is a source of it (#2).
@MainActor
final class JiraSetupModel: ObservableObject {
    enum State: Equatable {
        /// No resolved identity to show. The panel reads fixtures; nothing is fetched live.
        case notConfigured
        /// A probe is in flight. Rendered as a plain line — the panel has no motion (#9).
        case connecting
        /// Setup completed: Jira resolved this Operator and the credential is stored.
        case resolved(OperatorIdentity)
        /// The last attempt failed, with the distinct message for its state (#10). The
        /// attempt persisted nothing.
        case failed(message: String)
    }

    @Published var baseURLText = ""
    /// Held in the view-model only between "typed" and "attempt answered", then cleared —
    /// whatever the outcome. Its only destinations are the probe call and, on success, the
    /// single Keychain item.
    @Published var tokenText = ""
    @Published private(set) var state: State = .notConfigured

    // MARK: - The Board and the Estimate field (#11)

    /// What the Operator typed for the Board: an id, or a board URL to take one from.
    @Published var boardText = ""

    /// What the Operator typed for the custom field carrying Estimates on their instance.
    @Published var estimateFieldText = ""

    /// Why the last Board or Estimate-field entry was refused. Deliberately not `state`: this
    /// flow's `state` is about the credential and the identity behind it, and a mistyped number
    /// says nothing about either.
    @Published private(set) var configurationProblem: String?

    /// Called whenever the connection's configuration changes — a Board or Estimate field
    /// remembered, a credential resolved or revoked — so the panel reads the connection the
    /// Operator now has. Each of those is something the Operator did, which makes the fetch that
    /// follows an explicit request like the Refresh button rather than a timer (#11's fetch
    /// rule), and it is what stops the panel claiming to read a Board whose credential was just
    /// removed.
    var onConfigurationChanged: (() -> Void)?

    /// Attempts identity resolution with the given configuration. Contract: `.success` only
    /// for a Jira-resolved identity, `.failure` with a distinct `JiraClientError` otherwise —
    /// including refusing to proceed without a token.
    typealias IdentityProbe = @Sendable (_ baseURL: URL, _ token: String) async -> Result<OperatorIdentity, JiraClientError>

    private let credentials: JiraCredentialStore
    private let settings: JiraSettingsStore
    private let probe: IdentityProbe

    init(
        credentials: JiraCredentialStore = JiraCredentialStore(),
        settings: JiraSettingsStore = JiraSettingsStore(),
        probe: @escaping IdentityProbe = JiraSetupModel.liveProbe
    ) {
        self.credentials = credentials
        self.settings = settings
        self.probe = probe
        hydrate()
    }

    /// Whether the Keychain holds a credential at all — the one condition that decides
    /// live-versus-fixture default (#10), and the one the removal control is shown on, so a
    /// stored token is never stranded by the flow's state. A Keychain that cannot answer
    /// counts as no credential, which falls back to fixtures — never to another source.
    /// Presence is counted, not read: nothing here needs the token's bytes.
    var hasStoredCredential: Bool {
        ((try? credentials.countStoredItems()) ?? 0) > 0
    }

    /// On launch the app restores the confirmed identity beside a stored credential, the base URL
    /// the Operator typed, and the Board and Estimate field remembered with them (#11).
    private func hydrate() {
        baseURLText = settings.baseURLString ?? ""
        boardText = settings.boardID.map(String.init) ?? ""
        estimateFieldText = settings.estimateFieldID ?? ""
        if hasStoredCredential, let identity = settings.identity, settings.baseURLString != nil {
            state = .resolved(identity)
        } else {
            state = .notConfigured
        }
    }

    /// The production probe: build the client (which refuses an empty token or an unusable
    /// base URL before anything is sent) and resolve identity through it.
    static func liveProbe(baseURL: URL, token: String) async -> Result<OperatorIdentity, JiraClientError> {
        do {
            let client = try JiraHTTPClient(
                baseURL: baseURL, token: token, transport: URLSessionJiraTransport.shared
            )
            return .success(try await client.myself())
        } catch let error as JiraClientError {
            return .failure(error)
        } catch {
            // The client's surface throws only `JiraClientError`; reaching here means the
            // transport said something no state covers. Named, not folded.
            return .failure(.connectionFailed(reason: String(describing: error)))
        }
    }

    func connect() async {
        state = .connecting
        defer { tokenText = "" }  // the draft never outlives the attempt it belongs to

        let trimmedURL = baseURLText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmedURL) else {
            state = .failed(
                message: JiraClientError.invalidBaseURL(detail: "not a parseable URL: \(trimmedURL)").message
            )
            return
        }
        // A pasted PAT often arrives wearing a trailing newline; asking Jira with it attached
        // would report a *rejected token* for a valid credential, which is exactly the kind
        // of wrong-named failure #10 exists to prevent.
        let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch await probe(url, token) {
        case .failure(let error):
            state = .failed(message: error.message)

        case .success(let identity):
            do {
                try credentials.save(token)
            } catch let storeError as JiraCredentialStore.CredentialError {
                state = .failed(message: storeError.message)
                return
            } catch {
                state = .failed(message: "The credential could not be stored.")
                return
            }
            settings.baseURLString = url.absoluteString
            settings.identity = identity
            state = .resolved(identity)
            // The connection now resolves to a person, so a Board becomes readable. Where none is
            // configured this costs the panel a fixture re-read and no request (#11).
            onConfigurationChanged?()
        }
    }

    /// Removes the stored credential — the Operator revokes the app's access locally (#10). The
    /// identity resolved from it goes with the credential; the base URL, the Board and the
    /// Estimate field are configuration and stay, so configuring a fresh token does not mean
    /// retyping them.
    func removeCredential() {
        do {
            try credentials.delete()
        } catch let storeError as JiraCredentialStore.CredentialError {
            state = .failed(message: storeError.message)
            return
        } catch {
            state = .failed(message: "The credential could not be removed.")
            return
        }
        settings.clearIdentity()
        tokenText = ""
        state = .notConfigured
        // Revocation has to reach the panel in the same breath. Left alone it would go on showing
        // the last live reading under a "Live — Board N" header, claiming an access the Operator
        // has just taken away (#11).
        onConfigurationChanged?()
    }

    // MARK: - Remembering the Board and the Estimate field (#11)

    /// Remembers the one Board to watch. Validated before stored: a Board is read by number, and
    /// storing `nil` for an unparsable entry would leave the panel reading no Board at all while
    /// appearing configured.
    func saveBoard() {
        guard let boardID = Self.boardID(in: boardText) else {
            configurationProblem =
                "That is not a Board. Type its id, or paste its address — the number comes after \"boards/\" in https://jira.example.com/jira/software/projects/MP/boards/172"
            return
        }
        settings.boardID = boardID
        boardText = String(boardID)
        configurationProblem = nil
        onConfigurationChanged?()
    }

    /// Remembers which custom field carries an Issue's Estimate on this instance. Custom field ids
    /// are assigned in installation order, so there is nothing to infer it from: read the wrong
    /// field and every Issue arrives Unestimated, which the instrument reports as `Finished` —
    /// a whole sprint of work read as none. Empty restores the documented default.
    func saveEstimateField() {
        let entry = estimateFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty else {
            settings.estimateFieldID = nil
            configurationProblem = nil
            onConfigurationChanged?()
            return
        }
        let digits = entry.hasPrefix("customfield_")
            ? String(entry.dropFirst("customfield_".count))
            : entry
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else {
            configurationProblem =
                "An Estimate field is a custom field id: customfield_10007, or just its number, 10007."
            return
        }
        let fieldID = "customfield_\(digits)"
        settings.estimateFieldID = fieldID
        estimateFieldText = fieldID
        configurationProblem = nil
        onConfigurationChanged?()
    }

    /// The Board id in an entry: a bare number, or the number in a pasted board address — which is
    /// where an Operator reading it off their own browser will get it from. Both of the address
    /// shapes Data Center puts in that location bar are accepted: the project board path
    /// (`…/boards/172`) and the classic query parameter (`RapidBoard.jspa?rapidView=172`).
    ///
    /// Anything that is not a number at that position is refused rather than guessed at: `17abc`
    /// is a typo, not a Board whose id starts with 17.
    static func boardID(in entry: String) -> Int? {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["boards/", "rapidView="] {
            if let range = trimmed.range(of: marker) {
                return boardID(after: trimmed[range.upperBound...])
            }
        }
        return boardID(after: Substring(trimmed))
    }

    private static func boardID(after candidate: Substring) -> Int? {
        let digits = candidate.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let rest = candidate[digits.endIndex...]
        guard rest.isEmpty || "?/#&".contains(rest.first!) else { return nil }
        return Int(digits)
    }
}
