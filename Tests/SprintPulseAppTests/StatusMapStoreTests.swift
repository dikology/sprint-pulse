import SprintPulseCore
import XCTest
@testable import SprintPulse

/// The Status Map's own slot (#13). The map is the one piece of configuration the Operator edits
/// in answer to a reading rather than in answer to a connection: an `Unmapped Status` is the reason
/// it exists, and the edit is worthless if the next launch forgets it.
///
/// What is pinned here is the store's own business — that a fresh install has a working map, that
/// an edit survives the process, and that bytes which are not a map are treated as no map rather
/// than as a crash. The consequence of an edit (the forecast coming back) is `PanelModelTests`'
/// subject, because that is where the read lives.
final class StatusMapStoreTests: XCTestCase {
    private let suiteName = "SprintPulseAppTests.StatusMapStore"
    private var defaults: UserDefaults!
    private var store: StatusMapStore { StatusMapStore(defaults: defaults) }

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    /// An Operator who has never opened the editor still has a map — the one from
    /// `docs/agents/product.md`. An empty slot reading as an empty map would make every fixture
    /// and every live sprint an `Unmapped Status` on first launch, which is the opposite of the
    /// default this app ships with everywhere else (#10's fixture default, #11's default Estimate
    /// field).
    func test_fresh_store_handsOverTheDefaultMap() {
        XCTAssertEqual(store.load(), StatusMap.default)
    }

    /// AC 1's second word: *persisted*. Both directions of an edit — a status added and a status
    /// taken away — outliving the store that made them, which is the same as outliving the app.
    func test_anEditedMap_comesBack_fromAFreshStore() {
        let edited = StatusMap.default
            .setting("Blocked", to: .onHold)
            .removing("Need Info")
        store.save(edited)

        let relaunched = StatusMapStore(defaults: defaults).load()

        XCTAssertEqual(relaunched, edited)
        XCTAssertEqual(relaunched.flowState(for: "Blocked"), .onHold)
        XCTAssertNil(relaunched.flowState(for: "Need Info"), "a removal is remembered too")
    }

    /// Every one of the six Flow States round-trips, `Dropped` included (#13 AC 4) — a persisted
    /// map that silently lost the states the editor refuses to lose would be a worse surprise on
    /// the second launch than the first.
    func test_everyFlowState_roundTrips() {
        for state in FlowState.allCases {
            let map = StatusMap(["QA Gate": state])
            store.save(map)
            XCTAssertEqual(store.load(), map, "\(state.rawValue) did not survive the slot")
        }
    }

    /// A status name is matched exactly, so the slot must not chew on it: a trailing space the
    /// Operator pasted, and a name with punctuation, come back as they went in.
    func test_statusNames_roundTripExactly() {
        let map = StatusMap(["Needs: Info (dev)": .onHold, "In Progress ": .inProgress])
        store.save(map)

        XCTAssertEqual(store.load(), map)
        XCTAssertEqual(store.load().flowState(for: "In Progress "), .inProgress, "the map is exact, storage included")
    }

    /// Preferences are a user-editable plist. Bytes that are not a map read as *no map* — the
    /// default — which is the same fallback as a half-written identity in #10 and a corrupt cache
    /// entry in #12: a slot that cannot answer costs the Operator a missing edit, never a wrong
    /// translation and never a crash.
    func test_bytesThatAreNotAMap_areTheDefaultMap_notACrash() {
        defaults.set(Data("junk".utf8), forKey: StatusMapStore.defaultsKey)
        XCTAssertEqual(store.load(), StatusMap.default)

        // Shape-right, content-wrong: valid JSON, not a `[status: Flow State]` dictionary.
        defaults.set(Data(#"["In Progress"]"#.utf8), forKey: StatusMapStore.defaultsKey)
        XCTAssertEqual(store.load(), StatusMap.default)

        // A dictionary whose values name no Flow State the model knows.
        defaults.set(
            Data(#"{"In Progress":"Shipped"}"#.utf8), forKey: StatusMapStore.defaultsKey
        )
        XCTAssertEqual(store.load(), StatusMap.default)
    }

    /// #12's AC 9 sweeps every preference the app writes for the credential, and it does so by
    /// key prefix. A slot outside that prefix would be an unsearched drawer, so the name is pinned
    /// rather than assumed: the Status Map is Jira-facing configuration, and it is swept with the
    /// rest of it.
    func test_theSlotIsInsideThePrefixTheCredentialSweepSearches() {
        XCTAssertTrue(StatusMapStore.defaultsKey.hasPrefix("jira-"), StatusMapStore.defaultsKey)
    }

    /// A slot holding a map with nothing in it is *not* an empty slot. An Operator who removes
    /// every entry has made a statement — "nothing in my workflow is translated yet" — and the
    /// honest reading of that is every status Unmapped, `Unknown` on every reading, until they say
    /// otherwise. Falling back to the shipped default here would answer an edit the Operator made
    /// with a guess about what they meant.
    func test_anEmptyMap_isRememberedAsEmpty_notAsTheDefault() {
        store.save(StatusMap([:]))

        XCTAssertEqual(store.load(), StatusMap([:]))
        XCTAssertNotEqual(store.load(), StatusMap.default)
    }

    /// An edit written by one store is a value, not a mutation of a shared default: after the
    /// Operator's map is saved, `StatusMap.default` is still the map that shipped. Nothing in the
    /// app may rewrite it — that is how one Operator's guess at a status would become everybody's.
    func test_savingAnEdit_leavesTheShippedDefaultAlone() {
        store.save(StatusMap.default.setting("Blocked", to: .done))

        XCTAssertNil(StatusMap.default.flowState(for: "Blocked"))
        XCTAssertEqual(StatusMapStore(defaults: defaults).load().flowState(for: "Blocked"), .done)
    }
}
