import SprintPulseCore
import XCTest
@testable import SprintPulse

/// The notch host's own state (#19), tested at the same seam `PanelModel` is tested at: the host is
/// the thing that turns a click into a read, so invariant 14's counts are answered here rather than
/// in a view that cannot be run.
///
/// `NotchHost` holds no window and reads no `NSScreen` — it is handed the screens as `ScreenSurface`
/// values and publishes the frames the AppKit layer positions itself by. What that leaves testable
/// is the part the acceptance criteria are about: that opening the Panel is one live read and
/// nothing else is, that closing asks nothing, that a click while it is open closes it, and that the
/// Glance moves when the screens do.
///
/// Live reads are counted through the same injected gateway `PanelModelTests` uses, with the corpus
/// behind it: this file is about how often a read happens, not about what it says.
@MainActor
final class NotchHostTests: XCTestCase {
    private let identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")
    private let boardID = 172
    private let token = "SENTINEL-9f3c-never-in-preferences"

    private let suiteName = "SprintPulseAppTests.NotchHost"
    private let credentials = JiraCredentialStore.testItem()
    private var defaults: UserDefaults!
    private var settings: JiraSettingsStore { JiraSettingsStore(defaults: defaults) }
    private var baselines: BaselineStore { BaselineStore(defaults: defaults) }
    private var cache: SprintCacheStore { SprintCacheStore(defaults: defaults) }
    private var statusMaps: StatusMapStore { StatusMapStore(defaults: defaults) }

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        try skipUnlessKeychainWorks(credentials)
        try credentials.delete()
    }

    override func tearDown() {
        try? credentials.delete()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    /// A complete live configuration, so a read is a fetch rather than a bundled file.
    private func configureLive() throws {
        try credentials.save(token)
        settings.baseURLString = "https://jira.example.com"
        settings.identity = identity
        settings.boardID = boardID
    }

    private func makeHost(into reads: Reads) -> (PanelModel, NotchHost) {
        let panel = PanelModel(
            settings: settings,
            credentials: credentials,
            baselineStore: baselines,
            cache: cache,
            statusMaps: statusMaps,
            liveGateway: { configuration, token in
                reads.record(configuration: configuration, token: token)
                return corpusGateway()
            }
        )
        return (panel, NotchHost(panel: panel))
    }

    // MARK: - A click is the read (AC 2, invariant 14)

    /// Opening the Panel is the live read (invariant 14), so exactly one read happens per
    /// click-open — and the click is what issues it, not the window appearing on screen.
    func test_aClickOnTheGlance_opensThePanel_withExactlyOneLiveRead() async throws {
        try configureLive()
        let reads = Reads()
        let (panel, host) = makeHost(into: reads)

        host.glanceWasClicked()

        XCTAssertEqual(host.isPanelOpen, true, "the Panel opened before the read had arrived")
        await waitUntil { reads.count >= 1 }
        await wait(seconds: 0.05)
        XCTAssertEqual(reads.count, 1, "one click, one read")
        await waitUntil { panel.instrument != nil }
        XCTAssertEqual(reads.count, 1, "and the read that landed issued no second one")
    }

    /// Closing and reopening issues one more, because opening the Panel *is* the ask.
    func test_reopeningThePanel_issuesOneMoreRead() async throws {
        try configureLive()
        let reads = Reads()
        let (panel, host) = makeHost(into: reads)

        host.glanceWasClicked()
        await waitUntil { panel.instrument != nil }
        host.panelWasDismissed()
        XCTAssertEqual(reads.count, 1, "closing the Panel asks nothing of the Board")

        host.glanceWasClicked()
        await wait(seconds: 0.05)
        XCTAssertEqual(reads.count, 2, "reopening is a fresh ask, so a fresh read")
    }

    /// The other half of the same gesture: a click while the Panel is open closes it and costs
    /// nothing. Without it the Glance would need a second way out, and a second read.
    func test_aSecondClick_whileThePanelIsOpen_closesIt_withoutARead() async throws {
        try configureLive()
        let reads = Reads()
        let (panel, host) = makeHost(into: reads)

        host.glanceWasClicked()
        await waitUntil { panel.instrument != nil }
        host.glanceWasClicked()

        XCTAssertEqual(host.isPanelOpen, false)
        XCTAssertEqual(reads.count, 1, "the second click closed, and closing reads nothing")
    }

    /// Launching the app issues no live read (#11, invariant 14): drawing the Glance is not an ask
    /// of the Board, and the host stands ready before the Operator has clicked anything.
    func test_drawingTheGlance_atLaunchAsksNothingOfTheBoard() async throws {
        try configureLive()
        let reads = Reads()
        let (panel, host) = makeHost(into: reads)
        host.screensDidChange(to: [Self.builtIn])

        XCTAssertEqual(reads.count, 0, "no click, no read")
        XCTAssertEqual(host.isPanelOpen, false, "the Panel opens when the Operator opens it")
        XCTAssertNotNil(
            panel.liveConfiguration,
            "and this is a Board the app could read — it simply has not been asked to"
        )
    }

    /// Esc and a click outside close the Panel, and neither is an ask of the Board.
    func test_dismissingThePanel_closesItAndIssuesNoRead() async throws {
        try configureLive()
        let reads = Reads()
        let (panel, host) = makeHost(into: reads)

        host.glanceWasClicked()
        await waitUntil { panel.instrument != nil }
        host.panelWasDismissed()
        host.panelWasDismissed()

        XCTAssertEqual(host.isPanelOpen, false)
        XCTAssertEqual(reads.count, 1, "dismissing, even twice, reads nothing")
    }

    /// A click while the corpus is what is on screen opens the Panel and sends no request: a
    /// bundled scenario is a file, not a fetch (#15).
    func test_aClickWhileTheCorpusIsBeingRead_opensThePanel_andSendsNoRequest() async throws {
        let reads = Reads()
        let (_, host) = makeHost(into: reads)

        host.glanceWasClicked()
        await wait(seconds: 0.05)

        XCTAssertEqual(host.isPanelOpen, true, "the Panel opens whatever the source is")
        XCTAssertEqual(reads.count, 0, "and nothing was fetched to do it")
    }

    // MARK: - Following the screens (AC 4)

    /// The Glance belongs beside the notch on the screen that has one.
    func test_theGlanceIsPlacedBesideTheNotch_onANotchedScreen() throws {
        let (_, host) = makeHost(into: Reads())

        host.screensDidChange(to: [Self.builtIn])

        let layout = try XCTUnwrap(host.layout)
        XCTAssertTrue(layout.atNotch)
        XCTAssertEqual(
            layout.glance.minX, 956 + NotchMetrics.notchClearance,
            "the notch's right edge on this Mac is x 956"
        )
        XCTAssertEqual(layout.glance.midY, 1_101, "centred on the strip from y 1085 to 1117")
    }

    /// AC 4, as the Operator meets it: the lid closes, the built-in display goes away with its
    /// notch, and only the external display is left. The Glance follows and takes the top-centre of
    /// that display — the same rule that puts it there on a Mac that never had a notch.
    func test_theLidCloses_movingTheGlanceToTheTopCentreOfTheExternalDisplay() throws {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            unobstructedTop: 1_055,
            notch: nil,
            isMain: false
        )
        let (_, host) = makeHost(into: Reads())

        host.screensDidChange(to: [Self.builtIn, external])
        XCTAssertEqual(host.layout?.atNotch, true, "with the lid open the notch hosts the Glance")

        // The lid closed: one screen left, and it carries the menu bar now.
        host.screensDidChange(to: [
            ScreenSurface(
                frame: external.frame,
                unobstructedTop: external.unobstructedTop,
                notch: nil,
                isMain: true
            ),
        ])

        let layout = try XCTUnwrap(host.layout)
        XCTAssertFalse(layout.atNotch)
        XCTAssertEqual(layout.glance.midX, external.frame.midX, "centred on the only screen left")
        XCTAssertEqual(layout.panel.midX, external.frame.midX)
    }

    /// An external display attaching is the same event from the other side, and the Glance moves to
    /// the notch rather than staying where it was drawn.
    func test_anExternalDisplayAttaches_movingTheGlanceOntoTheNotch() throws {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            unobstructedTop: 1_055,
            notch: nil,
            isMain: true
        )
        let (_, host) = makeHost(into: Reads())

        host.screensDidChange(to: [external])
        XCTAssertEqual(host.layout?.atNotch, false, "lid closed: top-centre of the external display")

        host.screensDidChange(to: [external, Self.builtIn])
        XCTAssertEqual(host.layout?.atNotch, true, "the lid is open again — the notch hosts it")
    }

    /// The Panel hangs from the notch's bottom edge, so when its content grows the top edge stays
    /// where the Operator saw it appear and only the bottom moves.
    func test_thePanelContentGrows_keepingItsTopEdgeAtTheNotch() throws {
        let (_, host) = makeHost(into: Reads())
        host.screensDidChange(to: [Self.builtIn])
        let topEdge = try XCTUnwrap(host.layout?.panel.maxY)

        host.panelContentSizeChanged(CGSize(width: 280, height: 620))

        XCTAssertEqual(host.layout?.panel.height, 620)
        XCTAssertEqual(host.layout?.panel.maxY, topEdge, "the top edge did not move")
    }

    /// No host screen means no placement rather than a window at the origin: mid-unplug, the AppKit
    /// layer is left with the frames it had instead of being handed a zero rect.
    func test_noScreens_leaveThePlacementUndecided() {
        let (_, host) = makeHost(into: Reads())
        host.screensDidChange(to: [Self.builtIn])

        host.screensDidChange(to: [])

        XCTAssertNil(host.layout, "and the previous placement is not the current one")
    }

    // MARK: - Helpers

    /// This Mac's built-in display, as `NSScreen` reports it: a notch 185 wide and 32 deep, whose
    /// strip runs from y 1085 to the top of the screen at 1117.
    private static let builtIn = ScreenSurface(
        frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
        unobstructedTop: 1_084,
        notch: CGRect(x: 771, y: 1_085, width: 185, height: 32),
        isMain: true
    )

    /// Patience on the test's side: reads land inside `Task`s and the app has no timer to wait on
    /// (#11). Bounded, so a state that never arrives fails rather than hangs.
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<50 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("the host never reached the state the test waited for")
    }

    private func wait(seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Counts the live reads and keeps what each was asked with.
    private final class Reads: @unchecked Sendable {
        private(set) var count = 0
        private(set) var configurations: [JiraLiveConfiguration] = []

        func record(configuration: JiraLiveConfiguration, token: String) {
            count += 1
            configurations.append(configuration)
        }
    }
}

/// The corpus behind the injected gateway. Any scenario holding one active sprint with work in it
/// will do: these tests count reads, they never judge a reading. File-level so the `@Sendable`
/// gateway factory captures no test case along with it.
private func corpusGateway() -> any JiraGateway {
    try! FixtureJiraGateway.bundled(.severalAssignees)
}
