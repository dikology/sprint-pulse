import Foundation
import SprintPulseCore

/// The non-secret half of the Jira connection: the base URL and Board the Operator configured,
/// the sprint they named when the Board reported several, the Estimate field their instance keeps
/// its numbers in, and the identity Jira resolved at setup (#10, #11). All ordinary preferences —
/// safe to store in `UserDefaults`, safe to show on screen, safe to survive a credential removal
/// (the URL is configuration, not a secret).
///
/// The Personal Access Token is *not* stored here and this type has no way to store it: there
/// is no property, key, or writer that takes one. That is the shape of the acceptance
/// criterion "the token is never written to preferences" — the credential lives only in
/// `JiraCredentialStore`'s single Keychain item, and `JiraSetupModelTests` sweeps this
/// store's whole domain after a full setup to prove the token never lands here anyway.
struct JiraSettingsStore {
    private let defaults: UserDefaults
    private let baseURLKey = "jira-base-url"
    private let identityKey = "jira-identity"
    private let boardIDKey = "jira-board-id"
    private let trackedSprintIDKey = "jira-tracked-sprint-id"
    private let estimateFieldIDKey = "jira-estimate-field-id"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The configured Jira Data Center base URL, exactly as the Operator entered it.
    ///
    /// The setters are `nonmutating`: every value is written through to the `UserDefaults`
    /// reference, so a store held as a `let` by the setup flow can write it — the struct is
    /// a handle, not a buffer.
    var baseURLString: String? {
        get { defaults.string(forKey: baseURLKey) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: baseURLKey)
            } else {
                defaults.removeObject(forKey: baseURLKey)
            }
        }
    }

    /// The identity Jira resolved at credential setup — `key` and `name`, both, or nothing.
    /// Never typed by hand: a typed username is how a typo becomes a confidently empty
    /// forecast (#10).
    var identity: OperatorIdentity? {
        get {
            guard let data = defaults.data(forKey: identityKey),
                  let identity = try? JSONDecoder().decode(OperatorIdentity.self, from: data)
            else { return nil }
            return identity
        }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: identityKey)
            } else {
                defaults.removeObject(forKey: identityKey)
            }
        }
    }

    /// Drops everything but what the Operator would have to retype anyway: removing the
    /// credential clears the identity that came with it, and keeps the base URL.
    func clearIdentity() {
        defaults.removeObject(forKey: identityKey)
    }

    // MARK: - The live read's configuration (#11)

    /// The one Board Sprint Pulse watches, chosen once and remembered (CONTEXT "Board").
    ///
    /// An id rather than a name because the bounded call surface has no board listing to name one
    /// with: `/rest/agile/1.0/board/{boardId}/sprint` is asked by number, and asking for the
    /// Board list would be the fourth read operation M1 forbids (#2).
    ///
    /// Writing a different Board drops the remembered Active Sprint choice with it: an id is only
    /// an answer about the Board it was given on, and the same number names a different sprint
    /// somewhere else.
    var boardID: Int? {
        get { defaults.object(forKey: boardIDKey) as? Int }
        nonmutating set {
            if newValue != nil, newValue != boardID {
                defaults.removeObject(forKey: trackedSprintIDKey)
            }
            if let newValue {
                defaults.set(newValue, forKey: boardIDKey)
            } else {
                defaults.removeObject(forKey: boardIDKey)
            }
        }
    }

    /// The Active Sprint the Operator named when the Board reported several (#11).
    ///
    /// Not cleared when a sprint closes — `SprintSnapshot.resolveTrackedSprint` honours it only
    /// while the sprint it names is still active, which is the same span as "for the life of that
    /// sprint". It goes with the Board it was answered on (see `boardID`).
    var trackedSprintID: Int? {
        get { defaults.object(forKey: trackedSprintIDKey) as? Int }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: trackedSprintIDKey)
            } else {
                defaults.removeObject(forKey: trackedSprintIDKey)
            }
        }
    }

    /// Which custom field carries an Issue's Estimate on this instance. `nil` means
    /// `JiraDecoding.estimateFieldID`, the documented default — and on an instance where the
    /// points live under another id, the default decodes every Issue as Unestimated, which the
    /// instrument reads as a finished sprint. The field is configured once for that reason (#11).
    var estimateFieldID: String? {
        get { defaults.string(forKey: estimateFieldIDKey) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: estimateFieldIDKey)
            } else {
                defaults.removeObject(forKey: estimateFieldIDKey)
            }
        }
    }
}
