import Foundation
import SprintPulseCore

/// What the Operator has asked the panel to read (#15).
///
/// Named for `CONTEXT.md`'s **Fixture Mode**, and deliberately not `Source`: `PanelModel.Source`
/// is where the reading on screen actually came from, which is a fact about a read, while this is
/// an ask about the next one. They can disagree — a Board configured and a panel reading a scenario
/// — and collapsing them into one word is how that disagreement stops being visible.
///
/// An ask, not a fact about the connection: it says nothing about whether a credential exists,
/// only about what the Operator wants on screen while one does. Stored in preferences rather than
/// held in the panel, because the thing it is for — dropping back to a bundled scenario to
/// reproduce a bug — survives quitting the app and reopening it, and a mode that reset on relaunch
/// would put the Operator back on the live Board before the bug they came to catch had appeared.
enum ReadMode: String {
    /// Nobody asked, so the credential decides: the configured Board when the connection is
    /// complete, the bundled corpus while it is not (#10, #11). The default, and the reason first
    /// launch presents no authentication wall.
    case automatic
    /// The bundled corpus, whatever the credential holds (#15).
    case fixtures
}

/// The non-secret half of the Jira connection: the base URL and Board the Operator configured,
/// the sprint they named when the Board reported several, the Estimate field their instance keeps
/// its numbers in, the identity Jira resolved at setup (#10, #11), and which source the Operator
/// asked to be read (#15). All ordinary preferences — safe to store in `UserDefaults`, safe to
/// show on screen, safe to survive a credential removal (the URL is configuration, not a secret).
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
    private let readModeKey = "jira-read-mode"

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

    // MARK: - Which source the Operator asked to be read (#15)

    /// The Operator's own ask about what the panel reads, kept beside the rest of the connection
    /// rather than inside the panel, so dropping back to the corpus outlives a relaunch.
    ///
    /// `.automatic` is written as *nothing*: an absent key and an explicit "the credential decides"
    /// are one state, which is what keeps a fresh install's fixture default from being a value
    /// somebody had to set. A stored string that is not one of the two asks reads as no ask at
    /// all — preferences are user-editable, and the alternative is a panel reading nothing because
    /// of a word nobody should have typed into a plist.
    var readMode: ReadMode {
        get { defaults.string(forKey: readModeKey).flatMap(ReadMode.init(rawValue:)) ?? .automatic }
        nonmutating set {
            if newValue == .automatic {
                defaults.removeObject(forKey: readModeKey)
            } else {
                defaults.set(newValue.rawValue, forKey: readModeKey)
            }
        }
    }
}
