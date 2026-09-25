import SprintPulseCore
import XCTest
@testable import SprintPulse

/// The Baseline slot itself (#14): what survives a relaunch, and under which sprint it is found.
/// The behaviour built on top of it — which sprint the panel reads a Baseline *for*, what a Scope
/// Delta measured against a stored one looks like — is `PanelModelTests`' business; this file is
/// only about the bytes in the slot and the id they are filed under.
final class BaselineStoreTests: XCTestCase {
    private let suiteName = "SprintPulseAppTests.BaselineStore"
    private var defaults: UserDefaults!
    private var store: BaselineStore { BaselineStore(defaults: defaults) }

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    /// A first-observation snapshot of the corpus's own walking-skeleton sprint: two of its Issues with the
    /// Estimates they carried when first seen, and one Unestimated Issue, which is in the Baseline
    /// as the gap it is rather than as a zero (invariant 2).
    private func baseline(sprintID: Int) -> SprintBaseline {
        SprintBaseline(
            sprintID: sprintID,
            capturedAt: isoDate("2026-09-01T09:03:11Z"),
            entries: [
                .init(key: "MOB-1201", estimate: 5),
                .init(key: "MOB-1202", estimate: 8),
                .init(key: "MOB-1203", estimate: nil),
            ]
        )
    }

    /// AC 2, at the seam where "survives quit and relaunch" is actually decidable: a second handle
    /// on the same defaults domain is what a relaunch means for a store this thin. The value has to
    /// be in the preferences, not in the object that wrote it.
    func test_aBaselineSurvivesTheStoreItWasWrittenTo() throws {
        let captured = baseline(sprintID: 5281)
        store.save(captured)

        let relaunched = BaselineStore(defaults: defaults)
        XCTAssertEqual(relaunched.load(sprintID: 5281), captured)
        XCTAssertEqual(
            relaunched.load(sprintID: 5281)?.points, 13,
            "the sum the Scope Delta subtracts from is reproducible from the stored entries"
        )
    }

    /// AC 4: a Baseline is held *per sprint*. A Board can report two sprints active at once (#11's
    /// prompt), and naming the second must not cost the first the moment the app saw it — a slot
    /// that holds one Baseline total would leave switching back with a fresh capture, so the
    /// Operator's Scope Delta silently restarts at zero on a sprint that has visibly grown.
    func test_eachSprintKeepsItsOwnBaseline() throws {
        let started = baseline(sprintID: 5281)
        let other = SprintBaseline(
            sprintID: 5282,
            capturedAt: isoDate("2026-09-14T08:15:00Z"),
            entries: [.init(key: "GRO-3001", estimate: 21)]
        )

        store.save(started)
        store.save(other)

        let relaunched = BaselineStore(defaults: defaults)
        XCTAssertEqual(relaunched.load(sprintID: 5281), started, "the sprint the Operator left still has its own first observation")
        XCTAssertEqual(relaunched.load(sprintID: 5282), other, "and the one they named last has its own")
    }

    /// A sprint the app has never seen has no Baseline, which is the first-observation case rather
    /// than a broken slot: the panel captures one from that moment and says which moment it was.
    func test_anUnseenSprintReadsAsHavingNoBaseline() throws {
        store.save(baseline(sprintID: 5281))

        XCTAssertNil(store.load(sprintID: 5282))
    }

    /// The shape this slot had before it was filed by sprint: one Baseline, no map. A running install
    /// has that blob on disk *now*, and reading it is the difference between the Operator keeping
    /// their sense of how the current sprint grew and the panel re-capturing from the moment this
    /// version first ran — which is #14's own failure, delivered by #14. The entry is filed under the
    /// sprint it names, so the next write takes the map shape with nothing lost.
    func test_aSlotWrittenBeforeTheBaselinesWereFiledBySprintIsStillRead() throws {
        let captured = baseline(sprintID: 5281)
        defaults.set(try JSONEncoder().encode(captured), forKey: BaselineStore.defaultsKey)

        XCTAssertEqual(store.load(sprintID: 5281), captured, "the first observation the app already had")
        XCTAssertNil(store.load(sprintID: 5282), "and no invented Baseline for a sprint it never saw")

        store.save(
            SprintBaseline(
                sprintID: 5282,
                capturedAt: isoDate("2026-09-14T08:15:00Z"),
                entries: [.init(key: "GRO-3001", estimate: 21)]
            )
        )
        XCTAssertEqual(store.load(sprintID: 5281), captured, "the second sprint's capture kept the first")
    }

    /// The consequence of the slot holding something that is not a Baseline — a hand-edited
    /// defaults entry, a blob a future version of this type wrote, a half-written save: the app has
    /// no Baseline and captures one, rather than comparing live Points against half a sprint.
    func test_garbageInTheSlotReadsAsNoBaselines() throws {
        store.save(baseline(sprintID: 5281))

        defaults.set(Data("{ \"5281\": { \"sprintID\"".utf8), forKey: BaselineStore.defaultsKey)
        XCTAssertNil(store.load(sprintID: 5281), "a truncated entry is not a Baseline")

        defaults.set(Data("not json at all".utf8), forKey: BaselineStore.defaultsKey)
        XCTAssertNil(store.load(sprintID: 5281), "and neither is a word")
    }
}

/// A calendar date from an ISO-8601 string, for naming the moment a Baseline claims it was taken
/// at — the same helper the cache's tests use, in a file that cannot see it.
private func isoDate(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}
