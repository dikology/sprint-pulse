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
    private var motions: MotionStore { MotionStore(defaults: defaults) }

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

    private func makeHost(
        into reads: Reads,
        reduceMotion: @escaping () -> Bool = { false }
    ) -> (PanelModel, NotchHost) {
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
        return (panel, NotchHost(panel: panel, motion: motions, reduceMotion: reduceMotion))
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

    /// The host publishes the band that wraps the notch, not the surface that used to sit beside it:
    /// the frames the window layer moves its windows to are the wrapping ones (#25 AC 1).
    func test_theGlanceWrapsTheNotch_onANotchedScreen() throws {
        let (_, host) = makeHost(into: Reads())

        host.screensDidChange(to: [Self.builtIn])

        let layout = try XCTUnwrap(host.layout)
        XCTAssertTrue(layout.atNotch)
        XCTAssertEqual(
            layout.glance.minX, 758,
            "the band starts left of the cutout at x 771 rather than right of it at x 956"
        )
        XCTAssertEqual(layout.glance.maxY, 1_117, "flush with the top edge of this Mac's display")
    }

    /// AC 4, as the Operator meets it: the lid closes, the built-in display goes away with its
    /// notch, and only the external display is left. The Glance follows and takes the top-centre of
    /// that display — the same band, in the place a notch would have been.
    func test_theLidCloses_movingTheGlanceToTheTopCentreOfTheExternalDisplay() throws {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            notch: nil,
            isMain: false
        )
        let (_, host) = makeHost(into: Reads())

        host.screensDidChange(to: [Self.builtIn, external])
        XCTAssertEqual(host.layout?.atNotch, true, "with the lid open the notch hosts the Glance")

        // The lid closed: one screen left, and it carries the menu bar now.
        host.screensDidChange(to: [
            ScreenSurface(frame: external.frame, notch: nil, isMain: true),
        ])

        let layout = try XCTUnwrap(host.layout)
        XCTAssertFalse(layout.atNotch)
        XCTAssertEqual(layout.glance.midX, external.frame.midX, "centred on the only screen left")
        XCTAssertEqual(layout.glance.maxY, 1_080, "flush with its top edge, not under the menu bar")
        XCTAssertEqual(layout.panel.midX, external.frame.midX)
    }

    /// An external display attaching is the same event from the other side, and the Glance moves to
    /// the notch rather than staying where it was drawn.
    func test_anExternalDisplayAttaches_movingTheGlanceOntoTheNotch() throws {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            notch: nil,
            isMain: true
        )
        let (_, host) = makeHost(into: Reads())

        host.screensDidChange(to: [external])
        XCTAssertEqual(host.layout?.atNotch, false, "lid closed: top-centre of the external display")

        host.screensDidChange(to: [external, Self.builtIn])
        XCTAssertEqual(host.layout?.atNotch, true, "the lid is open again — the notch hosts it")
    }

    /// The window grows downward from the band, so when the Panel's content gains a row the top edge
    /// stays where the Operator saw it appear and only the bottom moves (#22 AC 5's other half: a
    /// reading arriving must not shove the shape around).
    func test_thePanelContentGrows_keepingItsTopEdgeAtTheNotch() throws {
        let (_, host) = makeHost(into: Reads())
        host.screensDidChange(to: [Self.builtIn])
        let topEdge = try XCTUnwrap(host.layout?.windowOpen.maxY)

        host.panelContentSizeChanged(CGSize(width: 280, height: 620))

        XCTAssertEqual(host.layout?.panel.height, 620)
        XCTAssertEqual(host.layout?.windowOpen.maxY, topEdge, "the top edge did not move")
        XCTAssertEqual(host.layout?.windowOpen.height, 652, "32 of band and 620 of reading")
    }

    /// No host screen means no placement rather than a window at the origin: mid-unplug, the AppKit
    /// layer is left with the frame it had instead of being handed a zero rect.
    func test_noScreens_leaveThePlacementUndecided() {
        let (_, host) = makeHost(into: Reads())
        host.screensDidChange(to: [Self.builtIn])

        host.screensDidChange(to: [])

        XCTAssertNil(host.layout, "and the previous placement is not the current one")
    }

    // MARK: - The band's figure while the Panel is open (#21 AC 3)

    /// ADR-0007 and `CONTEXT.md`'s "one number is shown once, under one name": the Panel states Points
    /// remaining, so while it is open the band states nothing. The marker stays either way — the band is
    /// one shape and one click target whatever it carries (#25 AC 4) — and the spoken form withdraws
    /// with the visible one, or VoiceOver would read a figure that is not there.
    func test_theBandWithdrawsItsFigure_whileThePanelIsOpen_andRestatesIt_whenItCloses() async throws {
        let reads = Reads()
        let (panel, host) = makeHost(into: reads)
        host.screensDidChange(to: [Self.builtIn])
        await waitUntil { panel.instrument != nil }

        XCTAssertEqual(host.glanceText, panel.glanceLabel, "closed: the band states the figure")
        XCTAssertEqual(host.glanceSpokenText, panel.glanceAccessibilityLabel)

        host.glanceWasClicked()
        XCTAssertEqual(
            host.glanceText, PanelModel.glanceMarker,
            "open: the marker alone, because the Panel is stating that figure now"
        )
        XCTAssertEqual(host.glanceSpokenText, "Sprint Pulse", "and nothing counted in the spoken form")

        host.panelWasDismissed()
        XCTAssertEqual(host.glanceText, panel.glanceLabel, "the figure returns with the closed Panel")
        XCTAssertEqual(reads.count, 0, "and none of this asked the Board anything — the corpus is on screen")
    }

    /// The withdrawal is a state of the surface, not of the reading: a band with no figure to withdraw
    /// looks the same with the Panel open or shut. Invariant 13 is not made an exception by #21's rule —
    /// `No Work Assigned` gives the band nothing to state before the click and nothing after it.
    func test_theBandShowsTheMarkerAlone_whenThereIsNoFigureToWithdraw() async throws {
        let (panel, host) = makeHost(into: Reads())
        panel.scenario = .noWorkAssigned
        await waitUntil { panel.content != .nothing }

        XCTAssertEqual(
            host.glanceText, PanelModel.glanceMarker,
            "an empty My Work gives the band no number, whatever the Panel's state"
        )

        host.glanceWasClicked()

        XCTAssertEqual(host.glanceText, PanelModel.glanceMarker, "and opening the Panel changes nothing")
        XCTAssertEqual(host.glanceSpokenText, "Sprint Pulse")
    }

    // MARK: - The morph (#22 AC 1, 3, 4)

    /// AC 1, as far as the host is asked to know it: the shape takes one short, fixed time to grow and
    /// the same time to shrink, and the number is ADR-0007's. It is stated as a literal because a test
    /// that read `NotchMetrics.structuralMorphDuration` back would pass with the morph set to four
    /// seconds, or to none at all.
    func test_theGlanceGrowsIntoThePanel_overOneShortMorph_inBothDirections() throws {
        let (_, host) = makeHost(into: Reads())

        XCTAssertEqual(host.morphDuration, 0.22, "220ms of structural motion, both ways")

        host.glanceWasClicked()
        XCTAssertEqual(host.morphDuration, 0.22, "and closing is the same morph, not a second animation")
    }

    /// AC 3: Reduce Motion makes it instant. The flag is read off the system through the closure the
    /// composition root handed in — the host reads no `NSWorkspace` itself, exactly as it reads no
    /// `NSScreen` — and read at the moment of the gesture, so a switch flipped mid-session is honoured
    /// by the next open without the app having to observe anything.
    func test_reduceMotionMakesOpenAndCloseInstant() throws {
        let (_, host) = makeHost(into: Reads(), reduceMotion: { true })

        XCTAssertEqual(host.morphDuration, 0, "instant, and not merely shorter")
    }

    /// AC 4: the Operator's own switch does the same thing, on its own and independently of the system's
    /// — "I find it distracting" is a different reason from an accessibility need. Both switches are
    /// exercised in both combinations because "independently of" is the half that breaks quietly when
    /// somebody reads one flag where the other belongs.
    func test_theNoAnimationPreferenceMakesTheMorphInstant_whateverReduceMotionSays() throws {
        let (_, systemAllowsMotion) = makeHost(into: Reads())
        systemAllowsMotion.animationDisabled = true
        XCTAssertEqual(systemAllowsMotion.morphDuration, 0, "the preference alone is enough")

        let (_, operatorAsks) = makeHost(into: Reads(), reduceMotion: { true })
        operatorAsks.animationDisabled = false
        XCTAssertEqual(operatorAsks.morphDuration, 0, "and Reduce Motion alone is enough")
    }

    /// AC 4's "persisted", asked of the host rather than of the store: a second host on the same
    /// preferences is what "the next launch still has no animation" means, and the write that makes it
    /// true is one line of `didSet` that a test which only ever checks the in-memory flag would not
    /// notice being deleted.
    func test_thePreferenceTheOperatorSet_isWhatTheNextLaunchReads() throws {
        let (_, first) = makeHost(into: Reads())
        first.animationDisabled = true

        let (_, relaunched) = makeHost(into: Reads())
        XCTAssertTrue(relaunched.animationDisabled)
        XCTAssertEqual(relaunched.morphDuration, 0, "and it is the launch's own answer, not a re-ask")
    }

    /// Invariant 14 applied to the new control: a preference is not an ask of the Board. The switch sits
    /// in Settings beside the ones that *are* asks (remembering a Board, revoking a credential), and the
    /// difference has to hold in the model rather than in the view's wording — a toggle that reloaded
    /// would mean every flick of the switch sent a request.
    func test_turningTheNoAnimationPreference_issuesNoRead() async throws {
        try configureLive()
        let reads = Reads()
        let (_, host) = makeHost(into: reads)

        host.animationDisabled = true
        host.animationDisabled = false
        await wait(seconds: 0.05)

        XCTAssertEqual(reads.count, 0, "a preference is not a request")
    }

    /// AC 2's second clause, and the reason the morph is the window layer's business rather than the
    /// read's: with a 220ms morph on its way, the click still owns the read outright. Nothing in the
    /// host can wait for an animation — it holds no clock and no window, which is what
    /// `SourceGuardTests` then checks from the other side.
    func test_theClickThatOpens_ownsTheRead_whileTheMorphIsRunning() async throws {
        try configureLive()
        let reads = Reads()
        let (panel, host) = makeHost(into: reads)
        XCTAssertEqual(host.morphDuration, 0.22, "the morph is on its way")

        host.glanceWasClicked()

        XCTAssertEqual(host.isPanelOpen, true, "the Panel is opening")
        await waitUntil { reads.count >= 1 }
        XCTAssertEqual(reads.count, 1, "and one click asked the Board once")
        await waitUntil { panel.instrument != nil }
    }

    /// AC 2's last clause: a close that interrupts an opening issues nothing. The host has no notion of
    /// a morph being in flight — the click decided the read the moment it landed — so interrupting is
    /// the same pair of calls it always was, and this pins that the first read is not repeated and the
    /// second gesture is not a fresh ask.
    func test_aCloseInterruptingAnOpening_issuesNoRead() async throws {
        try configureLive()
        let reads = Reads()
        let (_, host) = makeHost(into: reads)

        host.glanceWasClicked()
        host.panelWasDismissed()
        await wait(seconds: 0.1)

        XCTAssertEqual(host.isPanelOpen, false, "shut again before the shape ever finished growing")
        XCTAssertEqual(reads.count, 1, "the opening click's read, and nothing from the interrupting close")
    }

    // MARK: - Helpers

    /// This Mac's built-in display, as `NSScreen` reports it: a notch 185 wide and 32 deep, whose
    /// strip runs from y 1085 to the top of the screen at 1117.
    private static let builtIn = ScreenSurface(
        frame: CGRect(x: 0, y: 0, width: 1_728, height: 1_117),
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
