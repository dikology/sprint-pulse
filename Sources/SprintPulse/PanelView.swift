import AppKit
import SwiftUI
import SprintPulseCore

/// The panel behind the menu-bar item. It renders the fields of an `Instrument` and holds no
/// forecast logic of its own. The walking skeleton shows one reading; later M0 tickets add
/// rows without changing this contract.
struct PanelView: View {
    @ObservedObject var panel: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let instrument = panel.instrument {
                Text(instrument.sprintName)
                    .font(.headline)

                HStack {
                    Text("Points remaining")
                    Spacer()
                    Text(PanelModel.formatted(instrument.pointsRemaining))
                        .font(.title3.monospacedDigit())
                        .bold()
                }
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
        .frame(width: 260)
    }
}
