import Foundation
import SprintPulseCore

/// Owns the platform concerns the domain must not: reading the fixture through the gateway,
/// persisting the Sprint Baseline, and supplying "now". It calls `Forecast.evaluate` and
/// publishes the resulting `Instrument` for the panel to render.
///
/// In M0 the only data source is the fixture corpus (#9), so this also owns *which* scenario
/// is loaded: the picker sets `scenario`, and the reload follows here rather than in the view
/// — the panel renders state and never drives logic of its own.
@MainActor
final class PanelModel: ObservableObject {
    @Published private(set) var instrument: Instrument?
    @Published private(set) var loadError: Error?

    /// The scenario the panel is reading. Every `FixtureScenario` is loadable by clicking
    /// (#9); the default is the corpus's front door, and first launch presents no
    /// authentication wall — in M0 there is nothing to authenticate against.
    @Published var scenario: FixtureScenario = .walkingSkeleton {
        didSet {
            guard oldValue != scenario else { return }
            Task { await load() }
        }
    }

    /// Resolved from `/rest/api/2/myself` in M1. Hard-coded to the fixture's Operator until then.
    private let identity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")
    /// The default map, displayed read-only in M0; the editor is M1.
    let statusMap = StatusMap.default
    /// Monday–Friday, no Non-Working Dates, displayed read-only in M0; the editor is M1.
    private let workingCalendar = WorkingCalendar.default
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

    /// The menu-bar item's spoken form: the marker is decorative and a bare number is not a
    /// sentence, so VoiceOver is given the figure in words — the instrument's entry point
    /// must be as legible as its panel (#9).
    var menuBarAccessibilityLabel: String {
        guard let instrument else { return "Sprint Pulse" }
        return "Sprint Pulse, \(Self.formatted(instrument.pointsRemaining)) Points remaining"
    }


    func load() async {
        do {
            let gateway = try FixtureJiraGateway.bundled(scenario)
            let sprint = try SprintSnapshot.selectActiveSprint(from: try await gateway.activeSprints())
            let issues = try await gateway.issues(inSprint: sprint.id)
            let snapshot = SprintSnapshot(sprint: sprint, issues: issues.issues)

            // A scenario is a frozen observation, so it carries its own "now" (#9): every
            // fixture pins the moment it was written to be read at, and evaluating it against
            // the wall clock would walk Working Days past the fixture's sprint end — Required
            // Rates hollowing out to no reading, bands drifting away from the states the
            // picker's names promise. The wall clock is only the fallback for a directory
            // without a pin; `FixtureCorpusTests` requires every bundled scenario to carry one.
            let moment = try FixtureJiraGateway.pinnedNow(scenario) ?? Date()

            // A scenario that bundles its day-one `baseline.json` (the Scope Delta fixtures,
            // #8) *is* its stored Baseline: otherwise the picker could load scope-growth and
            // watch the instrument capture the baseline from the live fixture itself, reading
            // Delta 0 forever — the one movement the scenario exists to show. Every other
            // scenario falls back to the app's own persisted Baseline, exactly as live mode
            // will; a stale one from another sprint re-captures on mismatch, which is
            // `Forecast`'s existing rule.
            let stored = try FixtureJiraGateway.bundledBaseline(scenario)
                ?? baselineStore.load()

            let result = Forecast.evaluate(
                snapshot: snapshot,
                identity: identity,
                statusMap: statusMap,
                workingCalendar: workingCalendar,
                baseline: stored,
                now: moment
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
