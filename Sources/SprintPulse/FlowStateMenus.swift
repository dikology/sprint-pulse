import SwiftUI
import SprintPulseCore

/// The app's label for a Flow State. Display text is a view concern; the domain enum carries
/// only the vocabulary.
///
/// An extension in the view layer rather than a `PanelView` private method because #17 gave two
/// views the same menus — the Panel's `Unmapped Status` warning and the Settings editor — and one
/// list is what keeps a row's menu, the add row's, and the figure rows from drifting apart (#13).
extension FlowState {
    var displayName: String {
        switch self {
        case .toDo: return "To Do"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .onHold: return "On Hold"
        case .done: return "Done"
        case .dropped: return "Dropped"
        }
    }
}

/// A menu over the six Flow States. The `nil` case is labelled differently in the places it
/// appears — "Not mapped" on a row that is in the map, "Choose a Flow State" on a draft that is
/// not yet one — because an unchosen draft and a deliberate removal are two different acts, and
/// the second one has a consequence the editor must not soft-pedal (#13).
///
/// `FlowState.allCases` is the whole vocabulary, which is what makes every status mappable to
/// every state, `Dropped` included (#13 AC 4).
struct FlowStateMenu: View {
    let title: String
    @Binding var selection: FlowState?
    let emptySelectionLabel: String

    var body: some View {
        Picker(title, selection: $selection) {
            Text(emptySelectionLabel).tag(nil as FlowState?)
            ForEach(FlowState.allCases, id: \.self) { state in
                Text(state.displayName).tag(state as FlowState?)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

/// The same menu for one named status, read out of the map and written back through the model's
/// one writer. Both the Panel's `Unmapped Status` warning and the editor's own rows need it — the
/// first to be resolvable where it is met, the second to be correctable afterwards — and the two
/// must not disagree about what picking does (#13). They cannot: `setMapping` is the only writer,
/// the map is published, and a mapping made on either surface shows up on the other in the same
/// breath (#17's exception to configuration leaving the Panel).
struct StatusMappingMenu: View {
    @ObservedObject var panel: PanelModel
    let jiraStatus: String
    let emptySelectionLabel: String

    var body: some View {
        FlowStateMenu(
            title: "Flow State for \(jiraStatus)",
            selection: Binding<FlowState?>(
                get: { panel.statusMap.flowState(for: jiraStatus) },
                set: { panel.setMapping(jiraStatus: jiraStatus, to: $0) }
            ),
            emptySelectionLabel: emptySelectionLabel
        )
    }
}
