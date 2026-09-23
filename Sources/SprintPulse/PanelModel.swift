import Foundation
import SprintPulseCore

/// Everything a live read needs, and nothing that authenticates it (#11). The Personal Access
/// Token is deliberately absent: this value reaches the gateway factory whole, is printed by the
/// tests, and must never carry a credential.
struct JiraLiveConfiguration: Equatable, Sendable {
    let baseURL: URL
    let identity: OperatorIdentity
    let boardID: Int
    /// Which custom field carries an Issue's Estimate on this instance — per-instance
    /// configuration, because the default would read somebody else's field as no Estimate at all.
    let estimateFieldID: String
}

/// Owns the platform concerns the domain must not: reaching the gateway (a bundled scenario on
/// disk, or one Board over HTTP), persisting the Sprint Baseline and the last successful read, and
/// supplying "now". It calls `Forecast.evaluate` and publishes the result for the panel to render.
///
/// Two sources, one protocol (#11): `FixtureJiraGateway` and `LiveJiraGateway` satisfy the same
/// `JiraGateway`, so everything below the gateway is the same code path producing the same
/// `Instrument`. Which one is in use is the Operator's business, not the domain's.
///
/// When a read happens (#11): a live fetch runs when the panel window opens, when the Operator
/// presses Refresh, and when they change the connection they want read — a Board remembered, a
/// credential resolved or revoked. There is no timer and no polling anywhere in the app, and no
/// live read at launch. A fixture read issues no request at all, which is why the picker can keep
/// loading on click.
///
/// What a read leaves on screen when it fails (#12): the last read that succeeded, with its age
/// against it. Being off the VPN is this milestone's ordinary condition, so the cache is not a
/// fallback for a broken app — it is what the panel shows, and the withdrawal to it is the reason
/// the panel is worth opening offline. Nothing here decides how old that reading is: the cache
/// carries the instant it was taken and `Forecast` judges it against `now`, which is rule 1 of the
/// evaluation order rather than a caption (#2's boundary, still holding).
@MainActor
final class PanelModel: ObservableObject {
    /// Where the panel's reading comes from, for the caption and for what a read is allowed to do.
    enum Source: Equatable {
        /// The bundled corpus, chosen by the picker. The reading whenever the app has no complete
        /// live configuration (#10, #11).
        case fixture(FixtureScenario)
        /// One Board, over HTTP — and the fetch that just filled this in succeeded.
        case live(boardID: Int)
        /// The same Board, but the reading on screen is the last one that got through, not the
        /// result of this read (#12). Refresh still belongs on the panel: the Operator is looking
        /// at a Board, and asking it again is the thing to do about an old answer.
        case cached(boardID: Int)
    }

    /// What the panel renders below the sprint name. One case per condition the Operator can
    /// actually meet, because "the fetch failed", "nothing is assigned to you", "which of these
    /// two sprints?" and "the Board has no active sprint" are four different sentences — and
    /// three of them are states, not errors (#11).
    enum Content: Equatable {
        /// The reading.
        case forecast(Instrument)

        /// The resolved identity matched no Issue in the Active Sprint — CONTEXT's **No Work
        /// Assigned**. The forecast's arithmetic is real over that empty set and answers
        /// `Finished`, which is exactly the confident zero this state exists to prevent: the
        /// sprint is not finished, it has no subject. The sprint's own Points come along so the
        /// emptiness can be read against something (CONTEXT invariant 10).
        case noWorkAssigned(sprintName: String, teamScopePoints: Double)

        /// More than one sprint is active and the Operator has not named the tracked one (#11).
        /// The prompt is the state — the app never picks by name, length, or envelope order.
        case namingActiveSprint([JiraSprint])

        /// Nothing on the Board is in the `active` state (#11). There is no sprint to read, and
        /// the Board is not broken.
        case noActiveSprint

        /// Nothing has been read in this session yet.
        case nothing
    }

    /// The corpus's Operator. Every fixture scenario is written against this identity, so fixture
    /// mode keeps its own whoever `/myself` resolved in live mode: clicking a scenario has to
    /// produce the reading the corpus audit pins, or the picker is lying (#9).
    private let fixtureIdentity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

    /// The scenario the panel is reading. Every `FixtureScenario` is loadable by clicking
    /// (#9); the default is the corpus's front door, and first launch presents no
    /// authentication wall — in M0 there was nothing to authenticate against, and in M1 there is
    /// nothing to authenticate *until* a credential and a Board exist.
    @Published var scenario: FixtureScenario = .walkingSkeleton {
        didSet {
            guard oldValue != scenario else { return }
            // A different scenario is a different Board, and the sprint named on the old one is
            // not an answer about the new (#11).
            fixtureSprintChoice = nil
            Task { await load() }
        }
    }

    @Published private(set) var source: Source = .fixture(.walkingSkeleton)
    @Published private(set) var content: Content = .nothing

    /// The moment the data behind whatever is on screen was read, and which Board it was read from
    /// — `nil` and `nil` together when nothing on screen came from a fetch at all. The panel's age
    /// line has one source, and it is not the wall clock: a reading stays on screen for as long as
    /// the window is open, and a caption computed from "now minus then" would have to be re-timed
    /// to stay true — which this app never does, having no timer anywhere in it (#11). So the
    /// instant is carried and the view words it (#12's AC 3: the age is always visible).
    ///
    /// Both together answer one question — *where is this reading from* — and it is the question
    /// `source` cannot answer alone: a Board's cached read is that Board's, and neither the age line
    /// nor a "Cached — Board N" caption may be attached to a reading fetched from somewhere else. A
    /// fixture read leaves them `nil`, because a bundled scenario is not a fetch; the moment it
    /// pins for itself (#9) still reaches the reading as `Instrument.readAt`.
    @Published private(set) var dataReadAt: Date?
    @Published private(set) var dataBoardID: Int?

    /// The panel's line for a read that failed, held apart from `content` so a failure leaves the
    /// previous reading on screen: stale, not broken (#11), and #12 puts an age beside it.
    @Published private(set) var readProblem: String?

    /// The default map, displayed read-only in M0; the editor is #13.
    let statusMap = StatusMap.default
    /// Monday–Friday, no Non-Working Dates, displayed read-only in M0; the editor is #13.
    private let workingCalendar = WorkingCalendar.default

    private let settings: JiraSettingsStore
    private let credentials: JiraCredentialStore
    private let baselineStore: BaselineStore
    /// The last read that succeeded, so a Board that is unreachable tonight is not a panel with
    /// nothing on it (#12).
    private let cache: SprintCacheStore

    /// The answer to the active-sprint prompt while the panel is reading the corpus. Held in
    /// memory only: a fixture's sprint id is nobody's configuration, and persisting it would let
    /// an answer given while browsing scenarios resolve the *live* Board's prompt without the
    /// Operator ever naming a live sprint — the one thing #11 forbids.
    private var fixtureSprintChoice: Int?

    /// The seam beneath the live read, the same shape as `JiraSetupModel`'s probe (#10):
    /// production builds `LiveJiraGateway` over `JiraHTTPClient` and the app's URLSession
    /// adapter; a test hands in a gateway replaying recorded envelopes. So the whole fetch path —
    /// which Board the configuration reached, what happens on a second active sprint, what a
    /// failure leaves standing — is exercisable without a Jira, a VPN, or a credential, and
    /// without a real request ever being made from a test.
    typealias LiveGatewayFactory =
        @Sendable (_ configuration: JiraLiveConfiguration, _ token: String) async throws -> any JiraGateway

    private let liveGateway: LiveGatewayFactory

    init(
        settings: JiraSettingsStore = JiraSettingsStore(),
        credentials: JiraCredentialStore = JiraCredentialStore(),
        baselineStore: BaselineStore = BaselineStore(),
        cache: SprintCacheStore = SprintCacheStore(),
        liveGateway: @escaping LiveGatewayFactory = PanelModel.liveGateway
    ) {
        self.settings = settings
        self.credentials = credentials
        self.baselineStore = baselineStore
        self.cache = cache
        self.liveGateway = liveGateway

        if let configuration = liveConfiguration {
            // A live Board is not read at launch: the first fetch waits for the window to open
            // (#11). Nothing is read from the cache at launch either — the cache is what the panel
            // shows *when* the window opens, before the fetch has had a chance to fail (#12).
            // Fixtures are read at launch so the menu-bar item carries the number without
            // a click — a bundled file is not a request.
            source = .live(boardID: configuration.boardID)
        } else {
            Task { await load() }
        }
    }

    /// The reading to put a number on, when the state on screen is one. Derived from `content` so
    /// the menu-bar item and the panel cannot disagree about what was read — and so No Work
    /// Assigned, which is not a reading, contributes no zero to the menu bar (#11).
    var instrument: Instrument? {
        if case .forecast(let instrument) = content { return instrument }
        return nil
    }

    var menuBarLabel: String {
        guard let instrument else { return "Sprint Pulse" }
        // A neutral marker until the mascot (M3); the number is the instrument.
        return "▲ \(Self.formatted(instrument.pointsRemaining))"
    }

    /// The menu-bar item's spoken form: the marker is decorative and a bare number is not a
    /// sentence, so VoiceOver is given the figure in words — the instrument's entry point
    /// must be as legible as its panel (#9).
    ///
    /// Neither form carries the age (#12), and that is a decision rather than an omission: what the
    /// bar shows is Points remaining, which is exactly the figure AC 7 keeps on screen when data
    /// goes stale because it stays true of the sprint whenever it was counted. The thing that
    /// withdraws is Confidence, which the bar never claimed. Where a reading came from and when it
    /// was taken are the panel's to say, and the panel is one click away by design.
    var menuBarAccessibilityLabel: String {
        guard let instrument else { return "Sprint Pulse" }
        return "Sprint Pulse, \(Self.formatted(instrument.pointsRemaining)) Points remaining"
    }

    /// The Board the reading belongs to, whether it arrived from the fetch that just ran or from
    /// the one that last got through; `nil` while the panel is reading the corpus.
    ///
    /// One branch on `source` for everything the two connections do differently — the caption, the
    /// fixture picker, the Refresh control — so the view never asks the same question three times
    /// (#11). A cached read answers it the same way: it is still that Board's read, and asking the
    /// Board again is still what Refresh is for (#12).
    var boardID: Int? {
        switch source {
        case .fixture: return nil
        case .live(let boardID), .cached(let boardID): return boardID
        }
    }

    /// The Active Sprint the Operator named when the Board reported several, for the prompt's
    /// selection. `nil` until they answer it, and scoped to whichever source is being read (#11).
    var trackedSprintID: Int? {
        liveConfiguration == nil ? fixtureSprintChoice : settings.trackedSprintID
    }

    /// Whose work the reading on screen is about — the corpus's Operator in fixture mode, the
    /// identity Jira resolved in live mode. The panel names it (#11) because the two outcomes an
    /// identity can produce, No Work Assigned and a reading that looks fine, are told apart by
    /// nobody except the person whose name it matched.
    var readingIdentity: OperatorIdentity {
        liveConfiguration?.identity ?? fixtureIdentity
    }

    /// The configuration a live read needs: a stored credential, the base URL and identity that
    /// came with it, and a Board. Absent any one of them and the panel reads fixtures — a
    /// credential with no Board is not half a live read, it is a live read with nothing to ask
    /// about (#11).
    var liveConfiguration: JiraLiveConfiguration? {
        guard let identity = settings.identity,
              let baseURLString = settings.baseURLString,
              let baseURL = URL(string: baseURLString),
              let boardID = settings.boardID,
              hasStoredCredential
        else { return nil }
        return JiraLiveConfiguration(
            baseURL: baseURL,
            identity: identity,
            boardID: boardID,
            estimateFieldID: settings.estimateFieldID ?? JiraDecoding.estimateFieldID
        )
    }

    /// Whether the Keychain holds a credential at all (#10). Presence is counted, not read:
    /// nothing here needs the token's bytes.
    var hasStoredCredential: Bool {
        ((try? credentials.countStoredItems()) ?? 0) > 0
    }

    /// The panel window appeared: the first of the moments a live read happens (#11). A fixture
    /// panel is not re-read for it — the reading is already on screen and no request is waiting.
    func windowDidAppear() async {
        guard liveConfiguration != nil else { return }
        await load()
    }

    /// Refresh: the second of them (#11). Fixtures do not need it — choosing one is the ask,
    /// and it costs no request — so the control is shown only in live mode.
    func refresh() async {
        await load()
    }

    /// The Operator named the sprint being tracked (#11). In live mode the answer is persisted
    /// for the life of that sprint — `SprintSnapshot.resolveTrackedSprint` stops honouring the id
    /// once it is no longer active. In fixture mode it is held for the length of the browsing
    /// session and nothing longer. Either way this is the only way a sprint id enters the app:
    /// nothing is ever inferred.
    func choose(trackedSprintID: Int) {
        if liveConfiguration != nil {
            settings.trackedSprintID = trackedSprintID
        } else {
            fixtureSprintChoice = trackedSprintID
        }
        Task { await load() }
    }

    /// Reads the configured source. Both branches go through the same gateway protocol, the same
    /// snapshot resolution, and the same `Forecast.evaluate`.
    ///
    /// A live read *begins* with the cached one (#12), before the request is made: off the VPN a
    /// fetch can spend its whole timeout discovering that there is nothing to reach, and the
    /// Operator who opened the panel came for the answer rather than for the news about the
    /// connection. What the request then does is replace it — or leave it standing, with the
    /// failure named beside it. `loadLive` claims `.live` for itself once the Board has answered,
    /// so the caption never says "Live" over a reading the fetch has not produced yet.
    func load() async {
        if let configuration = liveConfiguration {
            showCachedRead(of: configuration)
            await read { try await self.loadLive(configuration) }
        } else {
            source = .fixture(scenario)
            dataReadAt = nil
            dataBoardID = nil
            await read { try await self.loadFixture() }
        }
    }

    // MARK: - The two reads

    /// One read's worth of work, with the failure rule wrapped around it: a throw names what
    /// failed and leaves `content` standing, which is the difference between stale and broken
    /// (#11). What is standing when a live read fails is by then the cached read — `load` put it
    /// there before asking — so the failure adds a sentence and takes nothing away.
    ///
    /// Both sources come through here so neither can invent its own error handling.
    private func read(_ fetch: @MainActor () async throws -> Void) async {
        do {
            try await fetch()
            readProblem = nil
        } catch {
            readProblem = Self.describe(error)
        }
    }

    private func loadFixture() async throws {
        let gateway = try FixtureJiraGateway.bundled(scenario)
        // The same choice the live read honours: a fixture Board can report two active sprints as
        // readily as a real one, and answering that prompt is what makes the reading appear (#11).
        guard let snapshot = try await snapshot(from: gateway, chosenSprintID: fixtureSprintChoice) else {
            // The scenario's Board reported two active sprints awaiting an answer, or none:
            // `snapshot` has already published the state that says so.
            return
        }

        // A scenario is a frozen observation, so it carries its own "now" (#9): every
        // fixture pins the moment it was written to be read at, and evaluating it against
        // the wall clock would walk Working Days past the fixture's sprint end — Required
        // Rates hollowing out to no reading, bands drifting away from the states the
        // picker's names promise. The wall clock is only the fallback for a directory
        // without a pin; `FixtureCorpusTests` requires every bundled scenario to carry one.
        let moment = try FixtureJiraGateway.pinnedNow(scenario) ?? Date()

        // A scenario that bundles its day-one `baseline.json` (the Scope Delta fixtures, #8)
        // *is* its stored Baseline: otherwise the picker could load scope-growth and watch
        // the instrument capture the baseline from the live fixture itself, reading Delta 0
        // forever — the one movement the scenario exists to show. Every other scenario falls
        // back to the app's own persisted Baseline, exactly as live mode does; a stale one
        // from another sprint re-captures on mismatch, which is `Forecast`'s existing rule.
        let stored = try FixtureJiraGateway.bundledBaseline(scenario) ?? baselineStore.load()

        // A scenario that is about the cache (#12) carries the moment its own data was taken beside
        // the moment it is observed at, which is the only thing separating the corpus's two
        // cached-read scenarios. Every other scenario is a fresh observation, where the two
        // instants are the same one — and neither is ever the wall clock, which is what lets the
        // picker promise a state and produce it on any machine, on any day.
        let readAt = try FixtureJiraGateway.bundledReadAt(scenario) ?? moment

        apply(
            Forecast.evaluate(
                snapshot: snapshot,
                identity: fixtureIdentity,
                statusMap: statusMap,
                workingCalendar: workingCalendar,
                baseline: stored,
                readAt: readAt,
                now: moment
            ),
            snapshot: snapshot,
            // A fixture is an observation of somebody else's sprint, so it does not write the
            // app's Baseline slot: clicking through the corpus would otherwise destroy the
            // day-one snapshot of the Operator's own real sprint and restart its Scope Delta
            // (#14 owns what the Baseline persists across).
            persistingBaseline: false
        )
    }

    private func loadLive(_ configuration: JiraLiveConfiguration) async throws {
        // The token is read at the moment of the request and passed as a value: never held on
        // this model, never in preferences, never in a description (#10). Its absence is a
        // refusal, and the refusal is named — not a fallback to another credential source.
        guard let token = try credentials.read(), !token.isEmpty else {
            throw JiraClientError.missingToken
        }
        let gateway = try await liveGateway(configuration, token)
        let fetched = try await snapshot(
            from: gateway, chosenSprintID: settings.trackedSprintID
        )
        // The Board answered, so anything now on screen came out of this fetch and the caption may
        // say "Live" again (#11, #12).
        source = .live(boardID: configuration.boardID)
        dataBoardID = configuration.boardID
        guard let snapshot = fetched else {
            // Two active sprints awaiting a name, or none active at all: `snapshot` has already
            // published the state that says so (#11). Both replace what is on screen — they are
            // about the Board having changed, not about a read that failed.
            dataReadAt = Date()
            return
        }

        // One instant for the moment the data arrived and the moment it is judged at: a live read
        // is fresh by definition, and `readAt` is the timestamp the cache persists (AC 1) and the
        // panel ages against (AC 3). `now` stays an argument to the domain either way (#2); only a
        // fixture pins one, because only a fixture is a frozen observation.
        let readAt = Date()
        dataReadAt = readAt

        // The only place the cache is written, and it sits past the point where anything could have
        // thrown: both envelopes decoded, every page of both listings arrived, the tracked sprint
        // resolved. A refused Board, a truncated page, and a response that is not a response leave
        // the last good read exactly as it was (AC 8) — which is the read already on screen, since
        // `showCachedRead` put it there before this request was made.
        cache.save(CachedSprint(boardID: configuration.boardID, readAt: readAt, snapshot: snapshot))

        apply(
            Forecast.evaluate(
                snapshot: snapshot,
                identity: configuration.identity,
                statusMap: statusMap,
                workingCalendar: workingCalendar,
                baseline: baselineStore.load(),
                readAt: readAt,
                now: readAt
            ),
            snapshot: snapshot,
            persistingBaseline: true
        )
    }

    // MARK: - The cached read (#12)

    /// This Board's last successful read, put on screen before its request is made and labelled
    /// for what it is (AC 2, AC 4).
    ///
    /// Three situations, told apart by what the app can actually know: which Board the reading on
    /// screen came from (`dataBoardID`), and which Board the cache slot belongs to.
    ///
    /// 1. The cache holds a read of *this* Board — re-evaluated against the current moment, so the
    ///    Working Day it predates is judged now rather than left at whatever was decided when it was
    ///    fetched. This is the relaunch-off-the-VPN case and the panel-open-before-the-timeout one.
    /// 2. The slot holds nothing (nothing has got through yet, it belongs to another Board, or the
    ///    write failed) but this Board's reading is already on screen from earlier in the session —
    ///    #11's rule stands, it keeps displaying, and it did not come from this fetch either.
    /// 3. Neither. What is on screen belongs to another Board or to the corpus, and no caption of
    ///    this Board's may be put on it: a bundled scenario's Points are not this sprint's cached
    ///    read any more than another Board's would be. The panel has read nothing, and the request
    ///    about to be made will either say something or fail and be named.
    ///
    /// A state that is not a reading — the active-sprint prompt, a Board with nothing active — is
    /// left alone in every case. Those are answers the Board gave to a read that *succeeded*; a
    /// cached forecast is older information about the same Board, and the app does not forecast a
    /// sprint the Operator has not named (#11) any more eagerly because a newer read has not
    /// arrived yet.
    private func showCachedRead(of configuration: JiraLiveConfiguration) {
        switch content {
        case .namingActiveSprint, .noActiveSprint:
            return

        case .forecast, .noWorkAssigned, .nothing:
            if let cached = cache.load(), cached.boardID == configuration.boardID {
                dataReadAt = cached.readAt
                dataBoardID = configuration.boardID
                apply(
                    Forecast.evaluate(
                        snapshot: cached.snapshot,
                        identity: configuration.identity,
                        statusMap: statusMap,
                        workingCalendar: workingCalendar,
                        baseline: baselineStore.load(),
                        readAt: cached.readAt,
                        now: Date()
                    ),
                    snapshot: cached.snapshot,
                    // A cached read re-captures nothing. The Baseline slot belongs to the first
                    // moment the app saw this sprint, and `readAt` is not that moment — writing it
                    // here would let a stale read reset the Operator's Scope Delta to zero (#14).
                    persistingBaseline: false
                )
                source = .cached(boardID: configuration.boardID)
                return
            }

            if dataBoardID == configuration.boardID {
                source = .cached(boardID: configuration.boardID)
                return
            }

            content = .nothing
            dataReadAt = nil
            dataBoardID = nil
            source = .live(boardID: configuration.boardID)
        }
    }

    /// The gateway call both sources go through: read the Board's active sprints, resolve which
    /// one is tracked, then read that sprint's Issues.
    ///
    /// Returns `nil` after publishing a state that is not a reading — the prompt, or no active
    /// sprint — which is why the resolution happens here rather than in the callers: both sources
    /// have to meet the same two non-answers, and a fixture Board can report two active sprints
    /// as readily as a live one (#11).
    private func snapshot(
        from gateway: any JiraGateway, chosenSprintID: Int?
    ) async throws -> SprintSnapshot? {
        let choice = SprintSnapshot.resolveTrackedSprint(
            in: try await gateway.activeSprints(), chosenSprintID: chosenSprintID
        )
        switch choice {
        case .tracked(let sprint):
            let issues = try await gateway.issues(inSprint: sprint.id)
            return SprintSnapshot(sprint: sprint, issues: issues.issues)
        case .noActiveSprint:
            content = .noActiveSprint
            return nil
        case .awaitingOperatorChoice(let candidates):
            content = .namingActiveSprint(candidates)
            return nil
        }
    }

    /// The one place that decides whether a reading is a reading or an empty subject (#11). The
    /// forecast's rules are untouched by it: rule 2 really does answer `Finished` over an empty
    /// My Work, and `all-dropped` proves that is the right word for a sprint whose work is done.
    /// The question "is there any My Work at all" is asked of `SprintSnapshot.myWork` — the same
    /// definition the forecast summed over — so the two can never disagree about what My Work is.
    private func apply(
        _ result: (instrument: Instrument, baseline: SprintBaseline),
        snapshot: SprintSnapshot,
        persistingBaseline: Bool
    ) {
        if persistingBaseline { baselineStore.save(result.baseline) }

        if snapshot.myWork(assignedTo: readingIdentity).isEmpty {
            content = .noWorkAssigned(
                sprintName: result.instrument.sprintName,
                teamScopePoints: result.instrument.liveSprintPoints
            )
        } else {
            content = .forecast(result.instrument)
        }
    }

    /// One sentence for a read that failed, from a vocabulary the panel does not extend: the
    /// client's states carry their own distinct messages (#10), a Keychain refusal carries its
    /// own, and a fixture that is not where it should be says which file. Anything else keeps its
    /// own description too — this is a personal instrument and an unexplained screen is worse
    /// than a verbose one — but it is the fallthrough, not the rule, and it is pinned by a test.
    private static func describe(_ error: Error) -> String {
        switch error {
        case let clientError as JiraClientError: return clientError.message
        case let storeError as JiraCredentialStore.CredentialError: return storeError.message
        case let fixtureError as FixtureJiraGateway.FixtureError:
            return "The bundled scenario could not be read: \(fixtureError)."
        default: return String(describing: error)
        }
    }

    /// The production gateway: the configured base URL, Board, identity, and Estimate field, over
    /// `JiraHTTPClient` and the app's URLSession adapter. The token arrives as a value from the
    /// single Keychain item and goes no further than this call — no credential, no request
    /// (#10's refusal rather than a fallback).
    static func liveGateway(
        configuration: JiraLiveConfiguration, token: String
    ) async throws -> any JiraGateway {
        let client = try JiraHTTPClient(
            baseURL: configuration.baseURL, token: token, transport: URLSessionJiraTransport.shared
        )
        return LiveJiraGateway(
            client: client,
            boardID: configuration.boardID,
            estimateFieldID: configuration.estimateFieldID
        )
    }

    static func formatted(_ points: Double) -> String {
        points == points.rounded()
            ? String(Int(points))
            : String(format: "%.1f", points)
    }
}
