import SwiftUI
import SprintPulseCore

/// The standard macOS Settings window (#17): everything the Panel used to hold as
/// configuration, moved out of a 280pt column into a window that has room for it.
///
/// Five things live here: the Jira connection (base URL, Personal Access Token, Verify,
/// removal, and the identity Jira resolved — #10), the Board and the Estimate field (#11),
/// the Status Map editor (#13), Fixture Mode — the scenario picker (#9) and the #15 switch onto
/// the corpus and back — and the "no animation" switch (#22), which is the Operator's own answer
/// to the notch's structural motion, beside the system's Reduce Motion rather than instead of it.
/// The Panel keeps the reading and Refresh, and one
/// exception: the `Unmapped Status` warning's inline Flow State menu, resolved where it is
/// seen. It is not duplicated here in a second affordance — both surfaces drive the model's
/// one writer, so a mapping made on either shows up on the other in the same breath.
///
/// **Opening this window triggers no live read** (invariant 14). Nothing here consults the
/// Board on appear; the reads happen in answer to what the Operator *does* in it — remember a
/// Board, resolve or revoke a credential, switch Fixture Mode — through the wiring the
/// composition root put in place of the Panel's old `onAppear`. The rules the moves preserved
/// are the Panel's own: no motion (a probe in flight is a plain line, not a spinner), nothing
/// conveyed by image or colour alone, and every failure named by its own distinct state.
///
/// The moved blocks shed the `.accessibilityElement(children: .contain)` they carried on the
/// Panel (#9's distinction: a form holds live controls a reader must reach, where the value
/// rows combine). That manual containment was the *panel column's* concern — a flat VStack of
/// combined rows and forms — and a grouped `Form` is the standard containment: every field,
/// menu and button is its own row, reached and named individually by VoiceOver, with each
/// `FlowStateMenu`'s accessible name carried by the title `.labelsHidden()` only hides
/// visually (#17's AC).
struct SettingsView: View {
    @ObservedObject var panel: PanelModel
    @ObservedObject var setup: JiraSetupModel
    /// Observed for one control: the "no animation" switch (#22) is the notch host's own preference,
    /// persisted through it, and the host is what answers whether the shape may move.
    @ObservedObject var host: NotchHost

    var body: some View {
        Form {
            jiraConnectionSection
            statusMapSection
            fixtureModeSection
            motionSection
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    // MARK: - The Jira connection (#10, #11)

    /// The credential setup (#10) and the rest of the connection's configuration (#11): the
    /// one Board to watch and the custom field that carries Estimates. The token field is a
    /// `SecureField` and the draft is cleared the moment the attempt ends; the only place the
    /// token outlives the attempt is the single Keychain item, on a resolved identity and never
    /// otherwise. Removal is offered on `hasStoredCredential`, not on the flow's state: a token
    /// in the Keychain is never left with no way to revoke it.
    @ViewBuilder
    private var jiraConnectionSection: some View {
        Section(header: Text("Jira connection")) {
            switch setup.state {
            case .resolved(let identity):
                // The confirmation the Operator asked for: who the app thinks they are, in
                // both identifiers it matched on. Never a paraphrase, never a guess.
                Text("Identity confirmed: \(identity.name) — key \(identity.key).")
                boardAndEstimateFields
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
    private var boardAndEstimateFields: some View {
        if let boardID = panel.configuredBoardID {
            // Configuration, not a claim about the last request: whether the reading on screen
            // came off the Board just now, out of the cache, or out of a scenario the Operator
            // asked for is the Panel's source line to say (#12, #15).
            Text("Board \(boardID) configured.")
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

        // Why the field exists at all: custom field ids differ per instance, and read the wrong
        // one and every Issue arrives Unestimated — which the instrument reports as a finished
        // sprint. The failure is quiet, so the hint has to say where to look.
        Text("If every Points figure reads 0 for a sprint that clearly has Estimates, this field is the wrong custom field for your instance.")
            .font(.caption)
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

    // MARK: - The Status Map editor (#13)

    /// The map, editable: the only place in Sprint Pulse where a Jira status name is *translated*
    /// into a Flow State (ADR-0002, CONTEXT invariant 1) — a status name surfaces anywhere else only
    /// as the data of an `Unmapped Status`, which is what sends the Operator here.
    ///
    /// A row's menu holds all six Flow States plus "Not mapped", so any status can be sent to any
    /// state — `Dropped` included, which is the mapping ADR-0002 names as the one that corrupts the
    /// instrument quietly and is nonetheless the Operator's to make — and taking a status out of the
    /// map is the same control rather than a second affordance. There is no Save button: a pick is
    /// written through and the Panel's reading is judged again in the same breath, which is what
    /// "mapping a status restores the forecast" means (#13 AC 3).
    ///
    /// The editor left the Panel's cramped column and gained room: no disclosure any more, the
    /// rows are simply there. The menus are the same `StatusMappingMenu` the Panel's warning
    /// carries, so the two surfaces cannot disagree about what picking does (#17).
    @ViewBuilder
    private var statusMapSection: some View {
        Section(header: Text("Status Map")) {
            Text("Jira status names live here and nowhere else in Sprint Pulse. A change takes effect on the Panel's reading at once — no Refresh, and no request to Jira.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if panel.statusMap.rows.isEmpty {
                // An emptied map is the Operator's own edit, and its consequence is every status
                // Unmapped. The editor says which map is in use whatever the reason (#13).
                Text("The map is empty, so every status Jira reports is an Unmapped Status until a row is added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(panel.statusMap.rows, id: \.jiraStatus) { row in
                HStack {
                    Text(row.jiraStatus)
                        .textSelection(.enabled)
                    Spacer()
                    StatusMappingMenu(
                        panel: panel, jiraStatus: row.jiraStatus, emptySelectionLabel: "Not mapped"
                    )
                }
            }

            TextField("Another status — exactly as Jira spells it", text: $panel.newStatusText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Jira status to add to the map")

            HStack {
                FlowStateMenu(
                    title: "Flow State for the status being added",
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

    // MARK: - Fixture Mode (#9, #15)

    /// The corpus browser (#9): every state the instrument can reach is one choice away, and the
    /// #15 switch that puts the Panel onto the corpus with a live Board standing — or back onto
    /// that Board — beside it. The entries are `FixtureScenario.allCases`, which
    /// `FixtureCorpusTests` pins to the corpus directories in both directions — a fixture the
    /// picker cannot load, or a picker entry with no fixture, fails the suite rather than
    /// surfacing as a dead option.
    ///
    /// The picker is disabled while the Panel is reading a live Board, and that is invariant 14
    /// rather than a nicety: with a complete connection, one scenario click would have issued an
    /// unasked live read. The model refuses that outright — `scenario`'s `didSet` reloads only
    /// when the corpus is what is being read (#17) — and the disabled control is the window's way
    /// of saying so: a pick that changed nothing on screen would be a control that lies. "Read
    /// fixtures instead" first — then the picker answers which scenario, and choosing one costs
    /// no request, because a fixture is a file.
    @ViewBuilder
    private var fixtureModeSection: some View {
        Section(header: Text("Fixture mode")) {
            Picker("Fixture scenario", selection: $panel.scenario) {
                ForEach(FixtureScenario.allCases) { scenario in
                    Text(title(for: scenario)).tag(scenario)
                }
            }
            .pickerStyle(.menu)
            .disabled(panel.canSwitchToFixtures)

            fixtureModeNote
        }
    }

    /// Why the Panel is reading a scenario — or why the picker is quiet — and what would change
    /// it. #15 made "am I here because I asked, or because there is nothing else?" a question the
    /// surface can genuinely answer several ways, and the promise each sentence makes has to be
    /// one the app will keep. With no ask stored, configuring a Board does replace the reading.
    /// With an ask stored and a Board standing, the way out is the button beside this note, not
    /// the connection. With an ask stored and no Board — the credential revoked since, which the
    /// mode survives — there is nothing to switch back to *yet*, and copy promising otherwise
    /// would be the window refusing to do the one thing it just said it would.
    @ViewBuilder
    private var fixtureModeNote: some View {
        if panel.canSwitchToFixtures, let boardID = panel.configuredBoardID {
            note("The Panel is reading Board \(boardID). Choosing a scenario is disabled while it is — \"Read fixtures instead\" first, and the picker then says which.")
            Button("Read fixtures instead") {
                panel.switchToFixtures()
            }
        } else if panel.readMode == .fixtures {
            if let boardID = panel.configuredBoardID {
                note("Fixture mode — you asked the Panel to read a bundled scenario. Your credential and Board \(boardID) are untouched, and the readings on the Panel are not your sprint.")
                Button("Read Board \(boardID)") {
                    panel.switchToBoard()
                }
            } else {
                note("Fixture mode — you asked the Panel to read a bundled scenario, and no Board is configured to switch back to. Configuring one in the Jira connection above puts that choice on the Panel.")
            }
        } else {
            note("Fixture mode — the Panel is reading a bundled scenario, not a live sprint, because there is no complete connection to read. Configuring one in the Jira connection above replaces this reading.")
        }
    }

    // MARK: - Motion (#22)

    /// The Operator's own switch on the notch's structural motion, which since #22 is what carries the
    /// Panel open and shut: the shape grows and shrinks, identical every time, saying nothing about the
    /// reading.
    ///
    /// It sits beside Reduce Motion rather than behind it, because "I find it distracting" is a
    /// different reason from an accessibility need and should not require changing a system setting
    /// every other app on the Mac reads too (`docs/agents/product.md` → Presentation, motion, and
    /// accessibility). Either switch on its own is enough — `NotchHost.morphDuration` asks both — and
    /// what this row does is persist the ask, which is the half of AC 4 that outlives the session.
    @ViewBuilder
    private var motionSection: some View {
        Section(header: Text("Motion")) {
            Toggle("No animation", isOn: $host.animationDisabled)

            note("Opening and closing the Panel is Sprint Pulse's structural motion: the band grows into the Panel and back, the same short way every time, carrying nothing about your sprint. Switching it off makes both instant. Reduce Motion in System Settings does the same for every app; this switch is yours alone, and either one is enough.")
        }
    }

    /// A secondary sentence in the app's established shape: small, dimmed, allowed to wrap.
    /// Every explanation here is a sentence rather than a label, and the fixture-mode states
    /// above are one sentence each by design.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The picker's name for a fixture scenario: what the Operator will see if they choose it,
    /// in the app's own vocabulary. Display text stays in the view — `FixtureScenario` carries
    /// only the corpus (the #9 convention, as with every display label here).
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
}
