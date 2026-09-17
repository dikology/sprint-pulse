import Foundation
import Security

/// The credential half of the Jira connection: **one** macOS Keychain item holding the
/// Operator's Personal Access Token (#10).
///
/// The Keychain is the only place the token lives — not preferences, not the cache, not a
/// log, never a second copy. This type is the only code in the app that reads or writes it,
/// and the token reaches it only as a value from the setup form and leaves only as a value
/// handed to `JiraHTTPClient`'s initializer. There is no other credential source to fall
/// back to: an environment variable, a netrc file, or an inherited CLI token is never read,
/// so a missing item means "no credential", full stop.
///
/// The service and account are fixed constants of the production item; they are parameters
/// only so the tests exercise this exact code against a test item instead of overwriting the
/// Operator's real one.
struct JiraCredentialStore {
    enum CredentialError: Error, Equatable {
        /// The Keychain refused an operation. The OSStatus keeps its number — a locked
        /// keychain and a denied access are different problems for the Operator to see,
        /// and "could not store" is what makes an integration undebuggable.
        case keychainRefused(status: OSStatus)

        /// An item is there, but its value is not readable as a token. Named as itself
        /// rather than reported as a refusal with status 0: the thing to do is replace or
        /// remove the item, and both stay possible.
        case unreadableItem

        var message: String {
            switch self {
            case .keychainRefused(let status):
                return "The macOS Keychain refused this operation (status \(status)). Nothing was stored."
            case .unreadableItem:
                return "The stored Jira credential could not be read — its Keychain item holds something that is not a token. Replace it by configuring again, or remove it."
            }
        }
    }

    static let productionService = "dev.dikology.sprintpulse.jira"
    static let productionAccount = "personal-access-token"

    /// A store pointed at a dedicated test item, so the suite exercises this exact code
    /// without ever overwriting or deleting the Operator's real credential.
    static func testItem() -> JiraCredentialStore {
        JiraCredentialStore(service: "dev.dikology.sprintpulse.jira.tests")
    }

    private let service: String
    private let account: String

    init(service: String = Self.productionService, account: String = Self.productionAccount) {
        self.service = service
        self.account = account
    }

    /// The stored token, or `nil` when no credential exists — the condition that keeps
    /// fixture mode the default (#10).
    func read() throws -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            query([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]) as CFDictionary,
            &item
        )
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                throw CredentialError.unreadableItem
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialError.keychainRefused(status: status)
        }
    }

    /// Stores the token, replacing whatever was there — the item is keyed by service and
    /// account, so re-configuring updates the single item rather than stacking copies.
    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemAdd(
            query([
                kSecValueData as String: data,
                // Available after the first unlock of the login keychain: the instrument
                // reads at panel-open, which never precedes a login, and anything stricter
                // would fail on a machine that wakes from sleep.
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]) as CFDictionary,
            nil
        )
        switch status {
        case errSecSuccess: return
        case errSecDuplicateItem:
            let updated = SecItemUpdate(
                query([:]) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updated == errSecSuccess else {
                throw CredentialError.keychainRefused(status: updated)
            }
        default:
            throw CredentialError.keychainRefused(status: status)
        }
    }

    /// Removes the credential. Idempotent by design: revoking access locally must succeed
    /// whether or not an item is there — "nothing to remove" is still removed.
    func delete() throws {
        let status = SecItemDelete(query([:]) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychainRefused(status: status)
        }
    }

    /// How many items this store's identity has in the Keychain. The acceptance criterion is
    /// "a single item", so the tests count rather than infer it from one successful read.
    func countStoredItems() throws -> Int {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ] as CFDictionary,
            &item
        )
        switch status {
        case errSecSuccess: return (item as? [AnyHashable])?.count ?? 0
        case errSecItemNotFound: return 0
        default: throw CredentialError.keychainRefused(status: status)
        }
    }

    private func query(_ extras: [String: Any]) -> [String: Any] {
        var base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        for (key, value) in extras { base[key] = value }
        return base
    }
}
