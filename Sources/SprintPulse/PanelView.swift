import AppKit
import SwiftUI
import SprintPulseCore

/// The Panel: the expanded surface a click on the Glance opens, directly below the notch (#19). It
/// renders the fields of an `Instrument` and holds no forecast logic of its own. Every number shown
/// is reproducible by hand from the others on screen (CONTEXT invariant 10): the per-Flow-State rows
/// sum to the Actionable and Waiting totals.
///
/// Two properties of the whole panel are load-bearing (#9): it ships with no motion — no spinner,
/// no animating disclosure, nothing that loops and demands peripheral attention — and nothing
/// conveys meaning by image or colour alone, so every row reads usefully under VoiceOver.
///
/// Below the header sits one state of `PanelModel.Content` (#11): the reading, an empty My Work,
/// a sprint that has to be named, a Board with no active sprint, or nothing read yet. A failed
/// fetch is not one of them — it is a line beside whatever was last read, and the source line
/// above says whether that reading came from the Board or the cache, and how old its data was
/// when the line was drawn.
///
/// #17 took the configuration out: the connection, the Board and Estimate fields, the Status Map
/// editor, and the scenario picker are the Settings window's now. #18 took the prose out — no
/// caption annotates a figure, and the states the invariants require keep their wording only where
/// the wording *is* the state (`docs/agents/product.md`, Surfaces). #19 took the last two things
/// that were not the reading: Settings… and Quit, which the Glance's right-click carries now, and
/// the `onAppear` that used to read the Board when the window appeared — with the menu-bar host
/// gone, the window stands open between openings, so appear-with-a-read became either a missed read
/// or a second one for a single click. Opening the Panel is the read now, and `NotchHost` owns that
/// gesture.
///
/// What stays is the reading, Refresh, and the one exception — the `Unmapped Status` warning's Flow
/// State menu, resolved where it is met (#13's exception, the same `StatusMappingMenu` the Settings
/// editor carries).
struct PanelView: View {
    @ObservedObject var panel: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            readingSource

            content

            if let readProblem = panel.readProblem {
                problemLine(readProblem)
            }
        }
        .padding(12)
        .frame(width: 280)
        // The window this is drawn in is borderless and transparent, so the card is the view's own:
        // a standard window background with an edge, so the Panel reads as one surface rather than
        // as loose text over whatever is behind it. The corner radius is what the window's shadow
        // follows.
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor)))
    }

    /// What the panel is reading and how old its data is — one line (#18) — and the one control
    /// that asks for a fresh live read. Since #17 this is the whole chrome above the reading;
    /// since #18 that chrome is a single stated fact, because the instrument states and does not
    /// annotate itself. Refresh belongs only to a Board read: a fixture costs no request and
    /// choosing one is the ask.
    @ViewBuilder
    private var readingSource: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The model words it: provenance and age are panel wording worth having under test,
            // and stating the age needs the clock only the model owns (#11).
            Text(panel.sourceLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if panel.boardID != nil {
                Button("Refresh") {
                    Task { await panel.refresh() }
                }
            }
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
                // The Board the state was reached on — the one fact the heading cannot be read
                // without once a Board can change under the panel. What the state means is
                // CONTEXT's to say; the Panel states it (#18).
                if let boardID = panel.boardID {
                    Text("Board \(boardID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
    /// on screen above it, which is the difference between stale and broken. #12 gave that
    /// reading an age and a "Cached" label and #18 joined them into the source line above; off
    /// the VPN this line is the *least* interesting thing on the panel, because the numbers
    /// above it are still the ones the Operator came for.
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
    /// to prevent, so the reading is replaced rather than annotated — replaced, since #18, by the
    /// heading and the identity the work was looked for under, and nothing in between. Team Scope
    /// stays: it is the one figure that lets the Operator tell "the sprint is full and none of it
    /// is mine" from "the sprint is empty" (invariant 10).
    @ViewBuilder
    private func noWorkAssigned(sprintName: String, teamScopePoints: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sprintName)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("No work assigned")
                .font(.subheadline.bold())
                .accessibilityAddTraits(.isHeader)
            // The identity the resolved read matched no Issue against (#18's reduction). Whether
            // that identity is plausible is the Operator's judgement — which is why #11 put it on
            // screen at all; the sentence saying so is what #18 took away.
            Text(panel.readingIdentity.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
            pointsRow("Team Scope", teamScopePoints)
                .foregroundStyle(.secondary)
        }
    }

    /// The prompt #11 exists for: several active sprints, and the app will not pick one. The
    /// answer is the Operator's and is remembered for the life of the sprint they name, so the
    /// question is asked once per sprint rather than every time the Panel opens.
    @ViewBuilder
    private func activeSprintPrompt(_ candidates: [JiraSprint]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which sprint is being tracked?")
                .font(.subheadline.bold())
                .accessibilityAddTraits(.isHeader)
            // The one fact the question is asked on, stated; what the answer means for the app
            // ("remembered for the life of that sprint") is CONTEXT's "Active Sprint", not the
            // Panel's to repeat (#18).
            Text("This Board reports \(candidates.count) sprints in the active state.")
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
        // somewhere else. The icon and colour emphasise it; the words carry it (#9) — and since
        // #18 they carry only the status, because exclusion-and-recompute is the domain's rule
        // (CONTEXT "Unmapped Status"), not a sentence the Panel repeats.
        if !instrument.unmappedStatuses.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Label("Unmapped status", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
                ForEach(instrument.unmappedStatuses, id: \.self) { jiraStatus in
                    HStack {
                        Text(jiraStatus)
                            .font(.caption)
                            .textSelection(.enabled)
                        Spacer()
                        StatusMappingMenu(
                            panel: panel, jiraStatus: jiraStatus,
                            emptySelectionLabel: "Choose a Flow State"
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

        // The CONTEXT term, stated bare. The parenthesised scope this row used to carry was the
        // only label-plus-figure pair measured to overflow the Panel's 280pt column (#18's
        // no-truncation AC), and where the count sits is what the Actionable and Waiting
        // sections above already show — the figure states, it does not annotate itself.
        row("Unestimated", "\(instrument.unestimatedCount) issue\(instrument.unestimatedCount == 1 ? "" : "s")")

        // The scope figures (#8): what the sprint holds now, what it held when first observed,
        // and the difference. Both operands sit beside the Delta so it stays reproducible by
        // hand (invariant 10), and they are sprint-wide by design — scope moves through Issues
        // that are not the Operator's.
        //
        // The live operand is also the Team Scope total (#9): every Issue in the sprint,
        // regardless of assignee. It is one number with one row, not a second figure to
        // reconcile, and it is deliberately the dimmest thing on the panel — context, never a
        // reading. No forecast, Confidence State, or rate is ever attached to team scope
        // (ADR-0001, CONTEXT invariant 6); #18 took the disclaimer beside it out, because the
        // honest way to show a rule the Panel never breaks is the bare total itself — named for
        // what it counts, dimmed, carrying no rate.
        pointsRow("Team Scope", instrument.liveSprintPoints)
            .foregroundStyle(.secondary)
        // Which moment that figure belongs to (#14 AC 6), as a suffix on the row itself (#18):
        // Points and capture day stated together — `26 · 8 Sep 2026` — worded by the model, for
        // the reason the source line is: panel wording worth having under test.
        row("Baseline Points", panel.baselineRowValue(for: instrument))
        row("Scope Delta", scopeDelta(instrument.scopeDelta))
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
                pointsRow(state.displayName, instrument.points(state), indented: true)
            }
        }
    }

    /// A count of Working Days, labelled: the plain integer is the unit the rates divide by,
    /// shown unreduced rather than as a fraction of the sprint.
    @ViewBuilder
    private func daysRow(_ label: String, _ days: Int) -> some View {
        row(label, "\(days)")
    }

    @ViewBuilder
    private func pointsRow(_ label: String, _ points: Double, indented: Bool = false) -> some View {
        row(label, PanelModel.formatted(points), indented: indented)
    }

    /// The Panel's one row shape: a secondary label, a Spacer, and the figure right-aligned in
    /// monospaced digits — where the figure is words rather than a number, the model has already
    /// worded it (`baselineRowValue`), because panel wording belongs under test. Combined for
    /// VoiceOver like every other row, so the value travels in the row's spoken form (#9).
    @ViewBuilder
    private func row(_ label: String, _ value: String, indented: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospacedDigit())
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
