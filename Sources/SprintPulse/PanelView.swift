import AppKit
import SwiftUI
import SprintPulseCore

/// The panel behind the menu-bar item. It renders the fields of an `Instrument` and holds no
/// forecast logic of its own. Every number shown is reproducible by hand from the others on
/// screen (CONTEXT invariant 10): the per-Flow-State rows sum to the Actionable and Waiting
/// totals.
///
/// Two properties of the whole panel are load-bearing (#9): it ships with no motion — no
/// spinner, no animating disclosure, nothing that loops and demands peripheral attention —
/// and nothing conveys meaning by image or colour alone, so every row reads usefully under
/// VoiceOver.
struct PanelView: View {
    @ObservedObject var panel: PanelModel
    @ObservedObject var setup: JiraSetupModel
    @State private var statusMapExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            scenarioPicker

            if let instrument = panel.instrument {
                forecast(instrument)
            } else if let loadError = panel.loadError {
                Text("Could not read the fixture")
                    .font(.headline)
                Text(String(describing: loadError))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                // Static text, not a spinner: an indeterminate `ProgressView` loops, and M0
                // ships with no motion at all. This state lasts one fixture read on first
                // launch, not a watchable interval.
                Text("Reading the fixture")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
    }

    /// The corpus browser (#9): every state the instrument can reach is one click away. The
    /// entries are `FixtureScenario.allCases`, which `FixtureCorpusTests` pins to the corpus
    /// directories in both directions — a fixture the picker cannot load, or a picker entry
    /// with no fixture, fails the suite rather than surfacing as a dead option.
    @ViewBuilder
    private var scenarioPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker("Fixture scenario", selection: $panel.scenario) {
                ForEach(FixtureScenario.allCases) { scenario in
                    Text(title(for: scenario)).tag(scenario)
                }
            }
            .pickerStyle(.menu)
            // What the panel itself knows: the reading in front of the Operator came from the
            // bundled corpus, not a live sprint. Fixtures remain the default whenever no
            // credential exists (#10) — and in M1 the panel keeps reading them even once one
            // does, until the live sprint reads land behind the same gateway (#11).
            Text("Fixture mode — the panel is reading a bundled scenario, not a live sprint.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The credential setup (#10): a Jira Data Center base URL and a Personal Access Token,
    /// resolved against `/rest/api/2/myself` and confirmed back to the Operator before
    /// anything is stored. The rules are the panel's existing ones — no motion (a probe in
    /// flight is a plain line, not a spinner), no meaning carried by colour alone, and every
    /// failure named by its own distinct state rather than "could not connect".
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
                Text("The panel still reads bundled fixtures; live reads follow the Board configuration.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

        // An Unmapped Status is surfaced prominently, naming the status. Its Issues are in no
        // set below. The warning reads as one utterance — the icon and colour emphasise it,
        // the words carry it (#9).
        if !instrument.unmappedStatuses.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label("Unmapped status", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                Text(instrument.unmappedStatuses.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Its Issues are excluded from the forecast totals until the status is mapped.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
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
        HStack {
            Text("Scope Delta")
                .foregroundStyle(.secondary)
            Spacer()
            Text(scopeDelta(instrument.scopeDelta))
                .font(.callout.monospacedDigit())
        }
        .font(.callout)
        .accessibilityElement(children: .combine)

        Divider()

        // A plain button rather than a `DisclosureGroup`: the system disclosure animates its
        // rows open, and M0 ships with no motion at all (#9). The state lives in the row's
        // visibility — spelled out below, because a collapsed chevron rotating into an
        // upward one is exactly the kind of meaning an image alone must not carry.
        Button {
            statusMapExpanded.toggle()
        } label: {
            HStack {
                Text("Status Map (read-only)")
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
            VStack(alignment: .leading, spacing: 2) {
                ForEach(panel.statusMap.rows, id: \.jiraStatus) { entry in
                    HStack {
                        Text(entry.jiraStatus)
                        Spacer()
                        Text(label(for: entry.flowState)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.caption)
            .padding(.top, 2)
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
