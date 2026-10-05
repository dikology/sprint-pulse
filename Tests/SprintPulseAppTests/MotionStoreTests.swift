import SprintPulseCore
import XCTest
@testable import SprintPulse

/// The "no animation" preference (#22 AC 4) — the bytes behind the switch, and nothing else. Whether
/// the preference actually makes the morph instant is `NotchHostTests`' business; this file is about
/// what survives quitting the app, which is the half of "persisted" a running test can reach.
final class MotionStoreTests: XCTestCase {
    private let suiteName = "SprintPulseAppTests.MotionStore"
    private var defaults: UserDefaults!
    private var store: MotionStore { MotionStore(defaults: defaults) }

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    /// Nobody asked, so the shape moves. The default is the *absence* of a preference rather than a
    /// value somebody had to write, which is what keeps a first launch animating without an Operator
    /// having discovered the switch exists.
    func test_nothingStoredYetTheMorphAnimates() throws {
        XCTAssertFalse(store.animationDisabled)
    }

    /// AC 4's "persisted", in the only sense available to a store this thin: a second handle on the
    /// same domain is what "across launches" means, so the value has to be in the defaults rather than
    /// in the object that wrote it.
    func test_thePreferenceSurvivesTheStoreItWasWrittenTo() throws {
        store.animationDisabled = true

        let relaunched = MotionStore(defaults: defaults)
        XCTAssertTrue(relaunched.animationDisabled, "an Operator who asked for no animation still has it")
    }

    /// Switching it back off is the *absence* of an ask, not a stored "off": the domain is left as
    /// first-launch as it was, so an Operator who toggles it twice and then reads their own plist sees
    /// nothing they have to reason about. The key is written as a literal rather than as
    /// `MotionStore`'s own constant — a test that reads the constant back stays green when somebody
    /// renames it, which is exactly when the stored preference would be orphaned.
    func test_turningThePreferenceBackOffStoresNothing() throws {
        store.animationDisabled = true
        store.animationDisabled = false

        XCTAssertFalse(store.animationDisabled)
        XCTAssertNil(
            defaults.object(forKey: "notch-animation-disabled"),
            "off is the default, and the default is stored as nothing"
        )
    }

    /// The key's name is the contract with a preference an Operator may have set months ago, so it is
    /// pinned from the other side too: written by hand under this name, the store has to read it.
    func test_thePreferenceIsReadFromTheKeyItWritesTo() throws {
        defaults.set(true, forKey: "notch-animation-disabled")

        XCTAssertTrue(store.animationDisabled)
    }

    /// A value that is not the preference — a hand-edited defaults entry, a word where a flag should be
    /// — is no ask, so the shape moves. The alternative is an Operator's plist typo freezing the notch
    /// into instant opens they never chose.
    func test_garbageInTheKeyReadsAsNoPreference() throws {
        defaults.set("distracting", forKey: "notch-animation-disabled")

        XCTAssertFalse(store.animationDisabled)
    }
}
