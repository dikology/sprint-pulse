import SprintPulseCore
import XCTest
@testable import SprintPulse

/// The cache slot itself (#12): what survives a relaunch, and what does not. The behaviour built on
/// top of it — when the panel reaches for the drawer, what it shows when the drawer is empty — is
/// `PanelModelTests`' business; this file is only about the bytes in the slot.
final class SprintCacheStoreTests: XCTestCase {
    private let suiteName = "SprintPulseAppTests.SprintCacheStore"
    private var defaults: UserDefaults!
    private var store: SprintCacheStore { SprintCacheStore(defaults: defaults) }

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    /// A read of the corpus's own sprint, so the slot is exercised against the shapes the live
    /// gateway actually produces rather than against a hand-built approximation of them.
    private func cachedRead(boardID: Int = 172, readAt: Date = Date()) async throws -> CachedSprint {
        let gateway = try FixtureJiraGateway.bundled(.severalAssignees)
        let sprint = try SprintSnapshot.selectActiveSprint(from: try await gateway.activeSprints())
        let issues = try await gateway.issues(inSprint: sprint.id)
        return CachedSprint(
            boardID: boardID,
            readAt: readAt,
            snapshot: SprintSnapshot(sprint: sprint, issues: issues.issues)
        )
    }

    func test_nothingStoredYetTheSlotReadsAsEmptyRatherThanBroken() throws {
        XCTAssertNil(store.load())
        XCTAssertNil(store.storedBytes())
    }

    /// AC 1's second half — persisted, not merely remembered. A second handle on the same domain is
    /// what "across launches" means for a store this thin: the value has to be in the defaults, not
    /// in the object that wrote it.
    func test_anEntrySurvivesTheStoreItWasWrittenTo() async throws {
        let readAt = isoDate("2026-09-21T09:30:00Z")
        let cached = try await cachedRead(readAt: readAt)

        store.save(cached)

        let relaunched = SprintCacheStore(defaults: defaults)
        XCTAssertEqual(relaunched.load(), cached)
        XCTAssertEqual(relaunched.load()?.readAt, readAt, "to the microsecond, or the age line is rounding")
    }

    /// The consequence of the slot holding something that is not a cached read — a hand-edited
    /// defaults entry, a blob a future version of this type wrote, a half-written save: the panel
    /// has nothing cached and says so, rather than showing half a sprint.
    func test_garbageInTheSlotReadsAsNothingCached() async throws {
        store.save(try await cachedRead())

        defaults.set(Data("{ \"boardID\": 172".utf8), forKey: SprintCacheStore.defaultsKey)
        XCTAssertNil(store.load(), "a truncated entry is not a cached read")

        defaults.set(Data("not json at all".utf8), forKey: SprintCacheStore.defaultsKey)
        XCTAssertNil(store.load(), "and neither is a word")
    }

    /// One slot, and the newest read owns it. `boardID` is what makes the older entry harmless
    /// after the Operator points the app at another Board — `PanelModelTests` checks the refusal,
    /// this checks that the refusal has something to read.
    func test_theNewestReadReplacesTheOldOne() async throws {
        store.save(try await cachedRead(boardID: 172, readAt: isoDate("2026-09-21T09:00:00Z")))

        let newer = try await cachedRead(boardID: 999, readAt: isoDate("2026-09-21T10:00:00Z"))
        store.save(newer)

        let stored = try XCTUnwrap(store.load())
        XCTAssertEqual(stored.boardID, 999)
        XCTAssertEqual(stored.readAt, newer.readAt)
    }

    /// AC 9, at the seam where the bytes exist: the whole stored blob swept for anything a credential
    /// could have arrived as. The type has no property that could hold a token, which is the design;
    /// this is the check that the design is what actually got written — no `Authorization` header, no
    /// `Bearer` anything, and not Jira's envelope either, because a cached read holds what the read
    /// *concluded* (the Estimate, not `customfield_10055`) rather than what the server sent.
    func test_theStoredBytesHoldNoCredentialAndNoEnvelope() async throws {
        store.save(try await cachedRead(boardID: 172, readAt: isoDate("2026-09-21T09:30:00Z")))

        let bytes = try XCTUnwrap(store.storedBytes(), "the slot holds the read")
        let text = String(decoding: bytes, as: UTF8.self)
        for marker in ["Authorization", "Bearer", "token", "SENTINEL", "customfield", "expand", "statusCategory"] {
            XCTAssertFalse(text.contains(marker), "the cached bytes name \(marker)")
        }
        XCTAssertTrue(text.contains("SEA-2201"), "…while still holding the sprint itself")
    }
}

/// A calendar date from an ISO-8601 string, for naming the moment a cached read claims its data
/// was taken at — the same helper the core tests use, in a target that cannot see it.
private func isoDate(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}
