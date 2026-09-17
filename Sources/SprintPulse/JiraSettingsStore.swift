import Foundation
import SprintPulseCore

/// The non-secret half of the Jira connection: the base URL the Operator configured and the
/// identity Jira resolved at setup (#10). Both are ordinary preferences — safe to store in
/// `UserDefaults`, safe to show on screen, safe to survive a credential removal (the URL is
/// configuration, not a secret).
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
}
