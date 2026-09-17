import XCTest
import Security
import SprintPulseCore
@testable import SprintPulse

/// The single Keychain item (#10). These tests exercise the real `SecItem` calls — the
/// wrapper is a handful of Foundation calls with policy all the way down, and a policy that
/// is never executed is not verified — against a dedicated test item, never the Operator's
/// production one. See `TestSupport.swift` for the skip discipline.
final class JiraCredentialStoreTests: XCTestCase {
    private let store = JiraCredentialStore.testItem()

    override func setUpWithError() throws {
        try skipUnlessKeychainWorks(store)
        try store.delete()
    }

    override func tearDownWithError() throws {
        try? store.delete()
    }

    func test_read_withNoItemStored_isNil() throws {
        XCTAssertNil(try store.read())
    }

    func test_save_thenRead_roundTripsTheToken() throws {
        try store.save("MDEyMzQ1Njc4OWFiY2RlZg")
        XCTAssertEqual(try store.read(), "MDEyMzQ1Njc4OWFiY2RlZg")
    }

    func test_saveTwice_isOneItem_holdingTheLatestToken() throws {
        try store.save("first-token")
        try store.save("second-token")

        XCTAssertEqual(try store.read(), "second-token")
        XCTAssertEqual(try store.countStoredItems(), 1, "re-configuring must update, not stack")
    }

    func test_delete_removesTheItem_andAlreadyGone_stillCountsAsRemoved() throws {
        try store.save("a-token")
        try store.delete()
        XCTAssertNil(try store.read())
        XCTAssertEqual(try store.countStoredItems(), 0)

        try store.delete()  // revoking access locally must not fail on "nothing to remove"
    }

    func test_anItemThatIsNotAToken_readsAsUnreadable_notAsStatusZero() throws {
        // Preferences are user-editable; so is the Keychain. A value that is not a UTF-8
        // token must name itself, because the Operator's next move — replace it, or remove
        // it — is different from retrying a refused operation.
        let status = SecItemAdd(
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "dev.dikology.sprintpulse.jira.tests",
                kSecAttrAccount as String: "personal-access-token",
                kSecValueData as String: Data([0xFF, 0xFE, 0xFF]),
            ] as CFDictionary,
            nil
        )
        XCTAssertEqual(status, errSecSuccess, "the fixture item itself")

        XCTAssertThrowsError(try store.read()) { error in
            XCTAssertEqual(
                error as? JiraCredentialStore.CredentialError,
                .unreadableItem
            )
        }
        // Both next moves stay possible from here:
        try store.save("replacement")
        XCTAssertEqual(try store.read(), "replacement")
    }
}
