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
                reading(instrument)
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
    private func reading(_ instrument: Instrument) -> some View {
        Text(instrument.sprintName)
            .font(.headline)

        HStack {
            Text("Working Days Remaining")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(instrument.workingDaysRemaining)")
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
                Text("Its Issues are excluded from every total until the status is mapped.")
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
}
