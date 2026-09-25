import Foundation
import SprintPulseCore

/// Persists the Sprint Baseline across launches (#14 AC 2) and holds one per sprint (AC 4). The
/// domain only computes the next baseline; holding it is a platform concern, so it lives here in
/// the app.
///
/// `UserDefaults` is enough for a handful of small `Codable` values, and the read cache (#12) made
/// the same choice beside this one rather than inventing a second convention.
///
/// Filed by sprint id rather than one slot for the latest capture, because a Board can report two
/// sprints active at once (#11's prompt) and the Operator can name one then the other then the
/// first again. A single slot makes that sequence destructive: naming sprint B forgets when the app
/// first saw sprint A, so returning to A re-captures from that moment and A's Scope Delta restarts at
/// zero on a sprint that has visibly grown — the reset this ticket exists to prevent. The map costs
/// one entry per sprint ever observed, which for one Operator watching one Board is a few hundred
/// bytes, twenty-six times a year; nothing here is ever worth pruning, because nothing here is ever
/// wrong.
struct BaselineStore {
    /// Named rather than inlined, so the test that puts something that is not a Baseline into the
    /// slot is writing the same key this store reads (#12's lesson, repeated).
    static let defaultsKey = "sprint-baseline"

    private let defaults: UserDefaults
    private let key = Self.defaultsKey

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored Baseline of the sprint the app is looking at, or `nil` when nothing has been
    /// captured for it — which is the first-observation case, not a broken slot.
    func load(sprintID: Int) -> SprintBaseline? {
        baselines()[sprintID]
    }

    /// Files a Baseline under the sprint it names. `SprintBaseline.sprintID` is the key rather than
    /// an argument, because the two can only disagree by a caller's mistake, and `Forecast` returns
    /// the Baseline it just captured or kept — so the value always knows which sprint it is about.
    func save(_ baseline: SprintBaseline) {
        var stored = baselines()
        stored[baseline.sprintID] = baseline
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    /// Every Baseline the app holds, keyed by sprint. A slot that decodes as neither the map nor
    /// what was here before it was a map is read as empty: the consequence is a re-capture, which is
    /// a fresh first observation, not a wrong comparison.
    private func baselines() -> [Int: SprintBaseline] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        if let stored = try? JSONDecoder().decode([Int: SprintBaseline].self, from: data) {
            return stored
        }
        // One Baseline, unkeyed — the shape every install that ran before this change wrote. Filed
        // under the sprint it names rather than dropped, because dropping it is the reset #14 exists
        // to prevent, delivered by #14 itself: the Operator would relaunch into a sprint whose
        // Scope Delta reads 0 again. The next `save` rewrites the slot in the map shape.
        guard let sole = try? JSONDecoder().decode(SprintBaseline.self, from: data) else { return [:] }
        return [sole.sprintID: sole]
    }
}
