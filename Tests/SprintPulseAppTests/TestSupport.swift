import XCTest
import SprintPulseCore
@testable import SprintPulse

/// Shared ground for the app-layer tests that touch the real Keychain: they run actual
/// `SecItem` calls against the dedicated test item (`JiraCredentialStore.testItem()`), and
/// on a machine where the Keychain refuses to answer — headless CI without a login session —
/// they skip rather than silently pass. The skip is loud in the run log; an environment
/// without a Keychain can never *falsify* these, and the file says so rather than pretending.
///
/// `swift test` on the Operator's own machine — the environment this project targets —
/// executes them for real.
func skipUnlessKeychainWorks(_ store: JiraCredentialStore) throws {
    do {
        _ = try store.read()
    } catch JiraCredentialStore.CredentialError.keychainRefused(let status) {
        throw XCTSkip("macOS Keychain unavailable in this environment (status \(status))")
    }
}
