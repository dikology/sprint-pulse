import Foundation
import SprintPulseCore

/// Owns the platform concerns the domain must not: reading the fixture through the gateway,
/// persisting the Sprint Baseline, and supplying "now". It calls `Forecast.evaluate` and
/// publishes the resulting `Instrument` for the panel to render.
@MainActor
final class PanelModel: ObservableObject {
    @Published private(set) var instrument: Instrument?
    @Published private(set) var loadError: Error?

    /// Resolved from `/rest/api/2/myself` in M1. Hard-coded to the fixture's Operator until then.
    private let identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")
    private let baselineStore = BaselineStore()

    init() {
        // Read the reading at launch so the menu-bar item shows the number without a click.
        Task { await load() }
    }

    var menuBarLabel: String {
        guard let instrument else { return "Sprint Pulse" }
        // A neutral marker until the mascot (M3); the number is the instrument.
        return "▲ \(Self.formatted(instrument.pointsRemaining))"
    }

    func load() async {
        do {
            let gateway = try FixtureJiraGateway.bundled(named: "walking-skeleton")
            let sprint = try SprintSnapshot.selectActiveSprint(from: try await gateway.activeSprints())
            let issues = try await gateway.issues(inSprint: sprint.id)
            let snapshot = SprintSnapshot(sprint: sprint, issues: issues.issues)

            let result = Forecast.evaluate(
                snapshot: snapshot,
                identity: identity,
                baseline: baselineStore.load(),
                now: Date()
            )
            baselineStore.save(result.baseline)
            instrument = result.instrument
            loadError = nil
        } catch {
            loadError = error
        }
    }

    static func formatted(_ points: Double) -> String {
        points == points.rounded()
            ? String(Int(points))
            : String(format: "%.1f", points)
    }
}
