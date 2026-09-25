import AppKit
import SwiftUI
import SprintPulseCore

/// The panel behind the menu-bar item. It renders the fields of an `Instrument` and holds no
/// forecast logic of its own. Every number shown is reproducible by hand from the others on
/// screen (CONTEXT invariant 10): the per-Flow-State rows sum to the Actionable and Waiting
/// totals.
///
/// Two properties of the whole panel are load-bearing (#9): it ships with no motion — no spinner,
/// no animating disclosure, nothing that loops and demands peripheral attention — and nothing
/// conveys meaning by image or colour alone, so every row reads usefully under VoiceOver.
///
/// Below the header sits one state of `PanelModel.Content` (#11): the reading, an empty My Work,
/// a sprint that has to be named, a Board with no active sprint, or nothing read yet. A failed
/// fetch is not one of them — it is a line beside whatever was last read, and since #12 the caption
/// above it says whether that was the Board a moment ago or the cache, and when the data behind it
/// was taken.
struct PanelView: View {
    @ObservedObject var panel: PanelModel
    @ObservedObject var setup: JiraSetupModel
    @State private var statusMapExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            readingSource

            content

            if let readProblem = panel.readProblem {
                problemLine(readProblem)
            }

            // The Status Map is configuration, not a figure in the reading: it belongs beside the
            // Board and the Estimate field, editable whether or not there is a reading to show —
            // an `Unmapped Status` is exactly the case where the Operator arrives here from a
            // warning, and a Board that will not answer is no reason they cannot fix the map.
            statusMapEditor

            Divider()

            jiraConnection

            Divider()

            Button("Quit Sprint Pulse") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280)
        // The window opening is one of the two moments a live read happens (#11); the other is
        // the Refresh button. Nothing here polls, and while the panel is reading the corpus this
        // asks for nothing — a fixture is a file, not a request.
        .onAppear {
            // One piece of wiring between the two models: remembering the Board or the Estimate
            // field is the Operator asking for it to be read, which makes the fetch that follows
            // an explicit request like Refresh (#11). Idempotent, because this runs on every
            // open.
            setup.onConfigurationChanged = { Task { await panel.refresh() } }
            Task { await panel.windowDidAppear() }
        }
    }

    /// What the panel is reading, when its data was read, and the one control that asks for a fresh
    /// live read.
    @ViewBuilder
    private var readingSource: some View {
        if let boardID = panel.boardID {
            VStack(alignment: .leading, spacing: 4) {
                // The Board and the identity are named because a live reading is the one thing on
                // this panel the Operator cannot reproduce from a fixture: they need to see which
                // Board was asked, and as whom (#11). The first word says whether the answer came
                // off it just now or survived the walk from the train (#12), and it comes first
                // because that is the question an Operator asks of a number before they ask
                // anything else of it.
                Text(sourceCaption(boardID))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Refresh") {
                    Task { await panel.refresh() }
                }
                // The other direction #15 opens: the Board is reachable, and the Operator can
                // still say "put me on a scenario instead". Beside Refresh rather than below the
                // fold, because the reason to want it is usually this reading on this screen.
                if panel.canSwitchToFixtures {
                    Button("Read fixtures instead") {
                        panel.switchToFixtures()
                    }
                }
                dataAgeLine
                Text("Reads when this window opens and on Refresh. Never on a timer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            scenarioPicker
        }
    }

    private func sourceCaption(_ boardID: Int) -> String {
        let read = "Board \(boardID), as \(panel.readingIdentity.name)"
        switch panel.source {
        case .fixture:
            // Unreachable: a fixture read has no Board, which is what `panel.boardID` is for. The
            // words are here rather than a `default:` so the caption's vocabulary stays one list.
            return "Fixture — \(read)"
        case .live:
            return "Live — \(read)"
        case .cached:
            return "Cached — \(read)"
        }
    }

    /// How old the data on screen is (#12 AC 3: always visible, not only to whoever happens to
    /// read the panel at the right moment).
    ///
    /// The sentence is `PanelModel.dataAgeText`'s, not this view's: stating an age needs a clock,
    /// and the clock is the platform concern the model exists to own (#11). It is also the only
    /// comparison anywhere between the domain and the screen, which makes it the one piece of panel
    /// wording worth having under test — a view function would not be.
    @ViewBuilder
    private var dataAgeLine: some View {
        if let age = panel.dataAgeText {
            Text(age)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch panel.content {
        case .forecast(let instrument):
            forecast(instrument)

        case .noWorkAssigned(let sprintName, let teamScopePoints):
            noWorkAssigned(sprintName: sprintName, teamScopePoints: teamScopePoints)

        case .namingActiveSprint(let candidates):
            activeSprintPrompt(candidates)

        case .noActiveSprint:
            VStack(alignment: .leading, spacing: 4) {
                Text("No active sprint")
                    .font(.subheadline.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("The Board reports no sprint in the active state, so there is nothing to read. Sprint Pulse waits for one to start rather than forecasting the last closed sprint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .nothing:
            // Static text, not a spinner: an indeterminate `ProgressView` loops, and the panel
            // ships with no motion at all (#9). In live mode this lasts from opening the window
            // to the read arriving — and since #12 the cached read usually arrives first, so this
            // line is what shows when there is nothing cached either. In fixture mode, from
            // launch to the first read.
            Text(panel.boardID == nil
                 ? "Reading the fixture"
                 : "Reading your Board")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// A read that failed, beside whatever was last read (#11). The sentence comes from the
    /// model — the panel holds no failure vocabulary of its own — and the previous reading stays
    /// on screen above it, which is the difference between stale and broken. #12 gave that reading
    /// an age and a "Cached" caption: off the VPN this line is the *least* interesting thing on the
    /// panel, because the numbers above it are still the ones the Operator came for.
    @ViewBuilder
    private func problemLine(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    /// The empty subject, as its own state (#11). The forecast ran over an empty My Work and
    /// answered `Finished`; showing that answer here would be the confident zero this state exists
    /// to prevent, so the reading is replaced rather than annotated. Team Scope stays: it is the
    /// one figure that lets the Operator tell "the sprint is full and none of it is mine" from
    /// "the sprint is empty".
    @ViewBuilder
    private func noWorkAssigned(sprintName: String, teamScopePoints: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sprintName)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("No work assigned")
                .font(.subheadline.bold())
                .accessibilityAddTraits(.isHeader)
            Text("No Issue in this sprint is assigned to \(panel.readingIdentity.name), the identity Jira resolved, so there is no forecast to make — and this is not the same as having finished. Check the identity and the Board above.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            pointsRow("Team Scope", teamScopePoints)
                .foregroundStyle(.secondary)
            Text("Every Issue in the sprint, not only yours. No forecast is computed over team scope.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The prompt #11 exists for: several active sprints, and the app will not pick one. The
    /// answer is the Operator's and is remembered for the life of the sprint they name, so the
    /// question is asked once per sprint rather than every time the window opens.
    @ViewBuilder
    private func activeSprintPrompt(_ candidates: [JiraSprint]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which sprint is being tracked?")
                .font(.subheadline.bold())
                .accessibilityAddTraits(.isHeader)
            Text("This Board reports \(candidates.count) sprints in the active state. Sprint Pulse forecasts one sprint and does not choose which. The answer is remembered for the life of the sprint you name.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(
                "Tracked sprint",
                selection: Binding<Int?>(
                    get: { panel.trackedSprintID },
                    set: { if let chosen = $0 { panel.choose(trackedSprintID: chosen) } }
                )
            ) {
                Text("Choose a sprint").tag(nil as Int?)
                ForEach(candidates, id: \.id) { sprint in
                    Text(trackedSprintTitle(sprint)).tag(sprint.id as Int?)
                }
            }
            .pickerStyle(.menu)
        }
        // `.contain`, not `.combine`: the prompt carries a live control the reader has to reach.
        .accessibilityElement(children: .contain)
    }

    /// A candidate sprint in the Board's own words, plus the one figure that tells two overlapping
    /// cadences apart: when each ends. Sprint names are display text, not Jira *status* strings —
    /// nothing outside the Status Map reads them (CONTEXT invariant 1).
    private func trackedSprintTitle(_ sprint: JiraSprint) -> String {
        let end = sprint.endDate.map(Self.sprintDateFormatter.string(from:)) ?? "no end date"
        return "\(sprint.name) — ends \(end)"
    }

    /// A sprint end date to the day: the prompt's job is to distinguish two sprints, not to show
    /// a timestamp.
    private static let sprintDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    /// The corpus browser (#9): every state the instrument can reach is one click away. The
    /// entries are `FixtureScenario.allCases`, which `FixtureCorpusTests` pins to the corpus
    /// directories in both directions — a fixture the picker cannot load, or a picker entry
    /// with no fixture, fails the suite rather than surfacing as a dead option.
    ///
    /// Since #15 this is also where fixture mode can be *entered on purpose* while a live Board
    /// stands, so the same block carries the way out: the control that goes back to the Board is
    /// shown whenever a Board is configured, whether or not it is what is being read. A panel
    /// dropped into the corpus with no visible way back is a panel that has eaten its credential,
    /// which is the exact thing this ticket exists to make untrue.
    @ViewBuilder
    private var scenarioPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker("Fixture scenario", selection: $panel.scenario) {
                ForEach(FixtureScenario.allCases) { scenario in
                    Text(title(for: scenario)).tag(scenario)
                }
            }
            .pickerStyle(.menu)
            fixtureModeNote
        }
    }

    /// Why the panel is reading a scenario, and what would make it stop. Three states, because #15
    /// made "am I here because I asked, or because there is nothing else?" a question the panel can
    /// genuinely answer three ways — and the promise each sentence makes has to be one the app will
    /// keep. With no ask stored, configuring a Board does replace the reading. With an ask stored
    /// and a Board standing, the way out is the control beside this note, not the connection. With
    /// an ask stored and no Board — the credential revoked since, which the mode survives — there is
    /// nothing to switch back to *yet*, and copy promising otherwise would be the panel refusing to
    /// do the one thing it just said it would.
    @ViewBuilder
    private var fixtureModeNote: some View {
        if panel.readMode == .fixtures {
            if let boardID = panel.configuredBoardID {
                note("Fixture mode — you asked the panel to read a bundled scenario. Your credential and Board \(boardID) are untouched, and the readings below are not your sprint.")
                Button("Read Board \(boardID)") {
                    panel.switchToBoard()
                }
            } else {
                note("Fixture mode — you asked the panel to read a bundled scenario, and no Board is configured to switch back to. Configuring one below puts that choice on this panel.")
            }
        } else {
            note("Fixture mode — the panel is reading a bundled scenario, not a live sprint. Configuring a Board below replaces this reading.")
        }
    }

    /// A secondary sentence in the panel's established shape: small, dimmed, allowed to wrap. Every
    /// explanation here is a sentence rather than a label, and the three fixture-mode states above
    /// are one sentence each by design.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The credential setup (#10) and the rest of the connection's configuration (#11): the one
    /// Board to watch and the custom field that carries Estimates. The rules are the panel's
    /// existing ones — no motion (a probe in flight is a plain line, not a spinner), no meaning
    /// carried by colour alone, and every failure named by its own distinct state rather than
    /// "could not connect".
    ///
    /// The token field is a `SecureField` and the draft is cleared the moment the attempt
    /// ends; the only place the token outlives the attempt is the single Keychain item, on a
    /// resolved identity and never otherwise. Removal is offered on `hasStoredCredential`,
    /// not on the flow's state: a token in the Keychain is never left with no way to revoke
    /// it from the panel.
    @ViewBuilder
    private var jiraConnection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Jira connection")
                .font(.subheadline.bold())
                .accessibilityAddTraits(.isHeader)

            switch setup.state {
            case .resolved(let identity):
                // The confirmation the Operator asked for: who the app thinks they are, in
                // both identifiers it matched on. Never a paraphrase, never a guess.
                Text("Identity confirmed: \(identity.name) — key \(identity.key).")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                boardConfiguration
                Button("Remove credential") {
                    setup.removeCredential()
                }

            case .notConfigured:
                connectionForm(connecting: false, failure: nil)

            case .connecting:
                connectionForm(connecting: true, failure: nil)

            case .failed(let message):
                connectionForm(connecting: false, failure: message)
            }
        }
        // `.contain`, not the value rows' `.combine`: a form is a set of live controls the
        // reader must reach individually — the combine that suits "label: figure" rows would
        // swallow the fields.
        .accessibilityElement(children: .contain)
    }

    /// The Board and Estimate fields (#11): configured once, remembered thereafter.
    ///
    /// The Board is typed rather than picked from a list because M1's bounded call surface has no
    /// board listing to ask for — three read operations, and a fourth would be a change to #2
    /// rather than an implementation detail (#11).
    ///
    /// Named off `configuredBoardID`, not `boardID`: this block states what the connection *is*,
    /// and since #15 the two come apart — a Board can be configured while the panel is reading a
    /// bundled scenario, and saying "no Board configured" over a stored Board 172 would be a
    /// sentence about the reading that does not belong in the configuration.
    @ViewBuilder
    private var boardConfiguration: some View {
        if let boardID = panel.configuredBoardID {
            // Configuration, not a claim about the last request: whether the reading on screen came
            // off the Board just now, out of the cache, or out of a scenario the Operator asked for
            // is the caption's sentence to say (#12, #15).
            Text("Board \(boardID) configured.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("No Board configured — the panel is reading fixtures.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        TextField("Board — id, or its URL (…/boards/172)", text: $setup.boardText)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Board id or URL")

        Button("Remember this Board") {
            setup.saveBoard()
        }

        TextField("Estimate field — e.g. customfield_10007", text: $setup.estimateFieldText)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Estimate custom field id")

        Button("Remember this Estimate field") {
            setup.saveEstimateField()
        }

        // Why the field is on the panel at all: custom field ids differ per instance, and read
        // the wrong one and every Issue arrives Unestimated — which the instrument reports as
        // a finished sprint. The failure is quiet, so the hint has to say where to look.
        Text("If every Points figure reads 0 for a sprint that clearly has Estimates, this field is the wrong custom field for your instance.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if let problem = setup.configurationProblem {
            Text(problem)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    /// The setup form, shared by every state that is not a confirmed identity. The removal
    /// control joins it whenever a credential is actually stored — an earlier setup's token
    /// must stay revocable even when the flow itself is mid-attempt or showing a failure.
    @ViewBuilder
    private func connectionForm(connecting: Bool, failure: String?) -> some View {
        TextField(
            "Jira base URL — https://jira.example.com",
            text: $setup.baseURLText
        )
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel("Jira base URL")

        SecureField("Personal Access Token", text: $setup.tokenText)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Personal Access Token")
            .disabled(connecting)

        Button("Verify credential") {
            Task { await setup.connect() }
        }
        .disabled(connecting)

        if connecting {
            // A line, not a spinner. It lasts one `/myself` request over a VPN that may be
            // down — which is exactly the case the failure message below distinguishes.
            Text("Asking Jira who this credential belongs to…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if let failure {
            Text(failure)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }

        if setup.hasStoredCredential {
            Button("Remove credential") {
                setup.removeCredential()
            }
        }
    }

    @ViewBuilder
    private func forecast(_ instrument: Instrument) -> some View {
        Text(instrument.sprintName)
            .font(.headline)
            .accessibilityAddTraits(.isHeader)

        HStack {
            Text("Confidence")
                .font(.subheadline.bold())
            Spacer()
            Text(label(for: instrument.confidenceState))
                .font(.subheadline.bold())
        }
        .accessibilityElement(children: .combine)

        // The Reading explains itself. A forecast that cannot be argued with is a score to be
        // trusted, which is the failure this project exists to avoid (`docs/agents/product.md`).
        Text(explanation(for: instrument))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        daysRow("Working Days Remaining", instrument.workingDaysRemaining)
        // Both rates' denominators on screen: Required Rate is Actionable Points over the
        // remaining days, Demonstrated Rate Completed Points over the elapsed ones, and neither
        // is reproducible by hand without the day count it was divided by (invariant 10).
        daysRow("Working Days Elapsed", instrument.workingDaysElapsed)

        rateRow("Required Rate", instrument.requiredRate)
        rateRow("Demonstrated Rate", instrument.demonstratedRate)

        // An Unmapped Status is surfaced prominently and named exactly — in Jira's own spelling, so
        // the Operator can see which column to look at. Its Issues are in no set below. #13 gave the
        // warning the other half of what it needs: the status arrives with a menu beside it, so
        // encountering one is a condition to resolve here rather than a fact to go and act on
        // somewhere else. The icon and colour emphasise it; the words carry it (#9).
        if !instrument.unmappedStatuses.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label("Unmapped status", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                Text("Its Issues are excluded from the forecast totals until the status is mapped. Choose what each one means and the reading above is recomputed — no request, no Refresh.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(instrument.unmappedStatuses, id: \.self) { jiraStatus in
                    HStack {
                        Text(jiraStatus)
                            .font(.caption)
                            .textSelection(.enabled)
                        Spacer()
                        mappingMenu(
                            jiraStatus, emptySelectionLabel: "Choose a Flow State"
                        )
                    }
                }
            }
            // `.contain`: this block now holds a control per status, and a reader has to be able to
            // reach each one — combining them would swallow the menus (#9).
            .accessibilityElement(children: .contain)
        }

        flowSection("Actionable", states: FlowState.actionable, instrument: instrument)
        flowSection("Waiting", states: FlowState.waiting, instrument: instrument)

        Divider()

        pointsRow("Completed", instrument.completedPoints)
        pointsRow("Dropped", instrument.droppedPoints)

        HStack {
            Text("Unestimated (Actionable / Waiting)")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(instrument.unestimatedCount) issue\(instrument.unestimatedCount == 1 ? "" : "s")")
                .font(.callout.monospacedDigit())
        }
        .font(.callout)
        .accessibilityElement(children: .combine)

        // The scope figures (#8): what the sprint holds now, what it held when first observed,
        // and the difference. Both operands sit beside the Delta so it stays reproducible by
        // hand (invariant 10), and they are sprint-wide by design — scope moves through Issues
        // that are not the Operator's.
        //
        // The live operand is also the Team Scope total (#9): every Issue in the sprint,
        // regardless of assignee. It is one number with one row, not a second figure to
        // reconcile, and it is deliberately the dimmest thing on the panel — context, never a
        // reading. No forecast, Confidence State, or rate is ever attached to team scope
        // (ADR-0001, CONTEXT invariant 6); the honest way to show that is a bare total with
        // the disclaimer beside it, and nothing else.
        pointsRow("Team Scope", instrument.liveSprintPoints)
            .foregroundStyle(.secondary)
        Text("Every Issue in the sprint, not only yours. No forecast is computed over team scope.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        pointsRow("Baseline Points", instrument.baselinePoints)
        // Which moment that figure belongs to (#14 AC 6). The sentence is the model's, for the same
        // reason the age line is: it is panel wording worth having under test, and a view function
        // would not be. Without it a `0` Delta reads as "this sprint has never grown" when all the
        // app knows is that it has not grown *since the day it arrived*.
        if let caption = panel.baselineCaption {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Text("Scope Delta")
                .foregroundStyle(.secondary)
            Spacer()
            Text(scopeDelta(instrument.scopeDelta))
                .font(.callout.monospacedDigit())
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The Status Map editor (#13)

    /// The map, editable: the only place in Sprint Pulse where a Jira status name is *translated*
    /// into a Flow State (ADR-0002, CONTEXT invariant 1) — a status name surfaces anywhere else only
    /// as the data of an `Unmapped Status`, which is what sends the Operator here.
    ///
    /// A row's menu holds all six Flow States plus "Not mapped", so any status can be sent to any
    /// state — `Dropped` included, which is the mapping ADR-0002 names as the one that corrupts the
    /// instrument quietly and is nonetheless the Operator's to make — and taking a status out of the
    /// map is the same control rather than a second affordance. There is no Save button: a pick is
    /// written through and the reading above is judged again in the same breath, which is what
    /// "mapping a status restores the forecast" means on screen (#13 AC 3).
    ///
    /// The disclosure is a plain button rather than a `DisclosureGroup` because the system one
    /// animates its rows open, and the panel ships with no motion at all (#9). The state lives in
    /// the rows' visibility, spelled out in `accessibilityValue`, because a chevron that rotates is
    /// exactly the meaning an image alone must not carry.
    @ViewBuilder
    private var statusMapEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                statusMapExpanded.toggle()
            } label: {
                HStack {
                    Text("Status Map")
                    Spacer()
                    Image(systemName: statusMapExpanded ? "chevron.up" : "chevron.down")
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.caption)
            .accessibilityValue(statusMapExpanded ? "expanded" : "collapsed")

            if statusMapExpanded {
                Text("Jira status names live here and nowhere else in Sprint Pulse. A change takes effect on the reading above at once — no Refresh, and no request to Jira.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if panel.statusMap.rows.isEmpty {
                    // An emptied map is the Operator's own edit, and its consequence is every status
                    // Unmapped. The panel says which map is in use whatever the reason (#13).
                    Text("The map is empty, so every status Jira reports is an Unmapped Status until a row is added.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(panel.statusMap.rows, id: \.jiraStatus) { row in
                        HStack {
                            Text(row.jiraStatus)
                                .textSelection(.enabled)
                            Spacer()
                            mappingMenu(
                                row.jiraStatus, emptySelectionLabel: "Not mapped"
                            )
                        }
                    }
                }
                .font(.caption)

                TextField("Another status — exactly as Jira spells it", text: $panel.newStatusText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Jira status to add to the map")

                HStack {
                    flowStateMenu(
                        "Flow State for the status being added",
                        selection: $panel.newStatusFlowState,
                        emptySelectionLabel: "Choose a Flow State"
                    )
                    Button("Add to the map") {
                        panel.addStatusToMap()
                    }
                }

                if let problem = panel.statusMapProblem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        // `.contain`, not the value rows' `.combine`: every row here is a control the reader has to
        // reach on their own — the same distinction the Jira connection form draws (#9).
        .accessibilityElement(children: .contain)
    }

    /// A menu over the six Flow States. The `nil` case is labelled differently in the two places it
    /// appears — "Not mapped" on a row that is in the map, "Choose a Flow State" on a draft that is
    /// not yet one — because an unchosen draft and a deliberate removal are two different acts, and
    /// the second one has a consequence the panel must not soft-pedal.
    private func flowStateMenu(
        _ name: String, selection: Binding<FlowState?>, emptySelectionLabel: String
    ) -> some View {
        Picker(name, selection: selection) {
            Text(emptySelectionLabel).tag(nil as FlowState?)
            flowStateOptions
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    /// The same menu for one named status, read out of the map and written back through the model's
    /// one writer. Both the `Unmapped Status` warning and the map's own rows need it — the first to
    /// be resolvable where it is met, the second to be correctable afterwards — and the two must not
    /// disagree about what picking does (#13).
    private func mappingMenu(_ jiraStatus: String, emptySelectionLabel: String) -> some View {
        flowStateMenu(
            "Flow State for \(jiraStatus)",
            selection: Binding<FlowState?>(
                get: { panel.statusMap.flowState(for: jiraStatus) },
                set: { panel.setMapping(jiraStatus: jiraStatus, to: $0) }
            ),
            emptySelectionLabel: emptySelectionLabel
        )
    }

    /// The six Flow States, in the domain's own order and in the panel's words. One list, so a
    /// row's menu and the add row's cannot drift apart — and `FlowState.allCases` is the whole
    /// vocabulary, which is what makes every status mappable to every state, `Dropped` included
    /// (#13 AC 4).
    @ViewBuilder
    private var flowStateOptions: some View {
        ForEach(FlowState.allCases, id: \.self) { state in
            Text(label(for: state)).tag(state as FlowState?)
        }
    }

    /// One Flow-State group — its subtotal and a row per state. The subtotal is the sum of the
    /// rows beneath it, so the reader can check it by hand.
    @ViewBuilder
    private func flowSection(
        _ title: String, states: [FlowState], instrument: Instrument
    ) -> some View {
        let subtotal = states.reduce(0.0) { $0 + instrument.points($1) }
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).bold()
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(PanelModel.formatted(subtotal))
                    .font(.body.monospacedDigit())
                    .bold()
            }
            .accessibilityElement(children: .combine)
            ForEach(states, id: \.self) { state in
                pointsRow(label(for: state), instrument.points(state), indented: true)
            }
        }
    }

    /// A count of Working Days, labelled. Plain integer: the day is the unit the rates divide by,
    /// so it is shown unreduced rather than as a fraction of the sprint.
    @ViewBuilder
    private func daysRow(_ label: String, _ days: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("\(days)").font(.callout.monospacedDigit())
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func pointsRow(_ label: String, _ points: Double, indented: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(PanelModel.formatted(points)).font(.callout.monospacedDigit())
        }
        .font(.callout)
        .padding(.leading, indented ? 12 : 0)
        .accessibilityElement(children: .combine)
    }

    /// A rate row. The spoken label is written out rather than left to the on-screen glyphs:
    /// `—` is a hedge a screen reader reads as punctuation, and "3.25/day" is a fraction, not
    /// the rate it names — the same figures, said as sentences (#9).
    private func rateRow(_ label: String, _ value: Double?) -> some View {
        let spoken = value.map { rateText($0) + " Points per day" } ?? "no reading yet"
        return HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(rate(value))
                .font(.callout.monospacedDigit())
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(spoken)")
    }

    /// The panel's label for a Flow State. Display text is a view concern; the domain enum
    /// carries only the vocabulary.
    private func label(for state: FlowState) -> String {
        switch state {
        case .toDo: return "To Do"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .onHold: return "On Hold"
        case .done: return "Done"
        case .dropped: return "Dropped"
        }
    }

    /// The panel's label for a Confidence State. Confidence is a named state, never a
    /// percentage or a probability — the view renders exactly that string.
    private func label(for state: ConfidenceState) -> String {
        switch state {
        case .unknown: return "Unknown"
        case .offTrack: return "Off Track"
        case .tight: return "Tight"
        case .onTrack: return "On Track"
        case .noSweat: return "No Sweat"
        case .handsOff: return "Hands Off"
        case .finished: return "Finished"
        }
    }

    /// The picker's name for a fixture scenario: what the Operator will see if they click it,
    /// in the panel's own vocabulary. Display text stays in the view — `FixtureScenario`
    /// carries only the corpus (the #9 convention, as with every `label(for:)` here).
    private func title(for scenario: FixtureScenario) -> String {
        switch scenario {
        case .walkingSkeleton: return "Walking Skeleton — first observation"
        case .confidenceColdStart: return "Unknown — one Working Day elapsed"
        case .confidenceZeroCompleted: return "Unknown — nothing Completed yet"
        case .unmappedStatus: return "Unknown — Unmapped Status present"
        case .confidenceOffTrack: return "Off Track — behind the Required Rate"
        case .confidenceDaysExhausted: return "Off Track — no Working Days Remaining"
        case .confidenceTight: return "Tight — ratio at 0.75"
        case .confidenceOnTrack: return "On Track — ratio at 1.00"
        case .confidenceNoSweat: return "No Sweat — ratio at 1.25"
        case .confidenceHandsOff: return "Hands Off — only Waiting Points remain"
        case .confidenceFinished: return "Finished — nothing left to move"
        case .capUnestimated: return "Unestimated Cap firing alone"
        case .capWaitingHeavy: return "Waiting-heavy Cap firing alone"
        case .capBoth: return "Both Caps firing — two bands lost"
        case .capAtBottom: return "Caps firing at the bottom of the scale"
        case .capHandsOff: return "Caps against Hands Off — nothing demoted"
        case .capUnknown: return "Caps against Unknown — nothing demoted"
        case .scopeGrowth: return "Scope — 34 Points added mid-sprint"
        case .scopeShrink: return "Scope — 8 Points removed mid-sprint"
        case .baselineColdStart: return "Scope — cold start, Delta 0"
        case .allDropped: return "A sprint entirely Dropped"
        case .allFlowStates: return "Every Flow State in one sprint"
        case .unestimatedAcrossStates: return "Unestimated Issues across Actionable and Waiting"
        case .subtasksWithEstimates: return "Sub-tasks with Estimates, ignored"
        case .twoActiveSprints: return "Two active sprints — the Board asks which one is tracked"
        case .severalAssignees: return "Several assignees — My Work forecast, the rest context"
        case .noWorkAssigned: return "No work assigned — the forecast has no subject"
        case .cacheWithinWorkingDay: return "Cached — read earlier in the Working Day, the forecast stands"
        case .cachePredatesWorkingDay: return "Cached — read on an earlier Working Day, Confidence withdrawn"
        }
    }

    /// The one-line account of a Reading: the rule that matched, and — only when a Cap actually
    /// moved the state — where it came from and which Caps did it.
    ///
    /// Generated entirely from `Instrument.reading` plus figures the panel already shows, so the
    /// sentence can be checked against the numbers above it (CONTEXT invariant 10). The view does
    /// no arithmetic of its own beyond formatting: it quotes the Waiting and Actionable subtotals
    /// rather than recomputing a share the domain already took.
    ///
    /// Caps that found nowhere to demote are absent from this line by design: `demotions` is the
    /// only authority on whether the state moved, so a demotion is never unexplained and a
    /// Reading that stands where the table left it never claims to have been capped.
    private func explanation(for instrument: Instrument) -> String {
        let reading = instrument.reading
        let ruleClause = switch reading.rule {
        case .unmappedStatus:
            "Confidence withdraws: an Unmapped Status leaves its Issues outside every total."
        case .dataPredatesWorkingDay:
            "Confidence withdraws: this data predates the current Working Day — the Points stand, the comparison between them does not."
        case .nothingRemaining:
            "No Actionable or Waiting Points remain."
        case .nothingActionableRemaining:
            "Nothing you can move remains — \(PanelModel.formatted(instrument.waitingPoints)) Waiting Points are in someone else's hands."
        case .insufficientHistory:
            "Confidence withdraws — nothing to compare yet: \(workingDays(instrument.workingDaysElapsed)) elapsed, \(PanelModel.formatted(instrument.completedPoints)) Points completed."
        case .workingDaysExhausted:
            "\(PanelModel.formatted(instrument.actionablePoints)) Actionable Points remain and no Working Days do."
        case .ratioNoSweat, .ratioOnTrack, .ratioTight, .ratioOffTrack:
            "Demonstrated \(rate(instrument.demonstratedRate)) against Required \(rate(instrument.requiredRate))."
        }

        guard reading.demotions > 0 else { return ruleClause }
        let caps = reading.caps.map { capPhrase($0, instrument: instrument) }.joined(separator: "; ")
        let bands = reading.demotions == 1 ? "one band" : "\(reading.demotions) bands"
        let from = label(for: reading.uncappedState)
        let to = label(for: reading.state)
        return "\(ruleClause) Capped \(bands) from \(from) to \(to): \(caps)."
    }

    /// "3 Working Days", or "1 Working Day" — the count reads as prose inside the Explanation.
    private func workingDays(_ count: Int) -> String {
        "\(count) Working Day\(count == 1 ? "" : "s")"
    }

    /// A fired Cap as the reader checks it: the figures on screen behind the condition, named
    /// rather than re-derived.
    private func capPhrase(_ cap: Cap, instrument: Instrument) -> String {
        switch cap {
        case .unestimated:
            let count = instrument.unestimatedCount
            return "\(count) unsized issue\(count == 1 ? "" : "s")"
        case .waitingHeavy:
            // The two subtotals the reader sees labelled on screen, not the share between them:
            // the addition and the comparison to the line are theirs to do, not the panel's to
            // re-compute (invariant 10).
            let percent = Int(ConfidenceBands.waitingHeavy * 100)
            let waiting = PanelModel.formatted(instrument.waitingPoints)
            let actionable = PanelModel.formatted(instrument.actionablePoints)
            return "\(waiting) Waiting against \(actionable) Actionable Points, over the \(percent)% line"
        }
    }

    /// A Scope Delta signed with the words that say what moved: "+34 added" is scope entering
    /// the sprint, "-8 removed" is work dropped out of it, and `0` is a sprint of the same
    /// shape as when it was first observed. The sign alone never carries the reading — and
    /// neither figure is the Dropped row above, which counts work cancelled where it stood
    /// without the sprint changing shape at all (#8).
    private func scopeDelta(_ delta: Double) -> String {
        guard delta != 0 else { return "0" }
        let points = PanelModel.formatted(abs(delta))
        return delta > 0 ? "+\(points) added" : "-\(points) removed"
    }

    /// `—` for an undefined rate rather than `0` or blank, so the reader never mistakes "not
    /// yet knowable" for "nothing to do."
    ///
    /// Rates get their own two-decimal formatting rather than `PanelModel.formatted` (Points'
    /// formatter): one decimal place is too coarse to reproduce the band boundaries (`0.75`,
    /// `1.00`, `1.25`) by hand — `String(format: "%.1f", 1.25)` rounds to `"1.2"`, which reads
    /// back into the wrong band.
    private func rate(_ rate: Double?) -> String {
        guard let rate else { return "—" }
        return "\(rateText(rate))/day"
    }

    /// The two-decimal rule behind both the displayed rate and its spoken form — one place,
    /// because the reader reproducing the band boundaries against either must get the same
    /// figure (invariant 10).
    private func rateText(_ rate: Double) -> String {
        String(format: "%.2f", rate)
    }
}
