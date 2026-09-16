import AppKit
import SwiftUI
import SprintPulseCore

/// The panel behind the menu-bar item. It renders the fields of an `Instrument` and holds no
/// forecast logic of its own. Every number shown is reproducible by hand from the others on
/// screen (CONTEXT invariant 10): the per-Flow-State rows sum to the Actionable and Waiting
/// totals.
struct PanelView: View {
    @ObservedObject var panel: PanelModel
    @State private var statusMapExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                ProgressView().controlSize(.small)
            }

            Divider()

            Button("Quit Sprint Pulse") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280)
    }

    @ViewBuilder
    private func forecast(_ instrument: Instrument) -> some View {
        Text(instrument.sprintName)
            .font(.headline)

        HStack {
            Text("Confidence")
                .font(.subheadline.bold())
            Spacer()
            Text(label(for: instrument.confidenceState))
                .font(.subheadline.bold())
        }

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

        HStack {
            Text("Required Rate")
                .foregroundStyle(.secondary)
            Spacer()
            Text(rate(instrument.requiredRate))
                .font(.callout.monospacedDigit())
        }
        .font(.callout)

        HStack {
            Text("Demonstrated Rate")
                .foregroundStyle(.secondary)
            Spacer()
            Text(rate(instrument.demonstratedRate))
                .font(.callout.monospacedDigit())
        }
        .font(.callout)

        // An Unmapped Status is surfaced prominently, naming the status. Its Issues are in no
        // set below.
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

        // The scope figures (#8): what the sprint holds now, what it held when first observed,
        // and the difference. Both operands sit beside the Delta so it stays reproducible by
        // hand (invariant 10), and they are sprint-wide by design — scope moves through Issues
        // that are not the Operator's.
        pointsRow("Live Sprint Points", instrument.liveSprintPoints)
        pointsRow("Baseline Points", instrument.baselinePoints)
        HStack {
            Text("Scope Delta")
                .foregroundStyle(.secondary)
            Spacer()
            Text(scopeDelta(instrument.scopeDelta))
                .font(.callout.monospacedDigit())
        }
        .font(.callout)

        Divider()

        DisclosureGroup("Status Map (read-only)", isExpanded: $statusMapExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(panel.statusMap.rows, id: \.jiraStatus) { entry in
                    HStack {
                        Text(entry.jiraStatus)
                        Spacer()
                        Text(label(for: entry.flowState)).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
            .padding(.top, 2)
        }
        .font(.caption)
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
                Spacer()
                Text(PanelModel.formatted(subtotal))
                    .font(.body.monospacedDigit())
                    .bold()
            }
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
        return String(format: "%.2f/day", rate)
    }
}
