import Foundation
import SprintPulseCore

/// Persists the Sprint Baseline across launches. The domain only computes the next baseline;
/// holding it is a platform concern, so it lives here in the app.
///
/// `UserDefaults` is enough for one small `Codable` value; M1 revisits storage alongside the
/// cache.
struct BaselineStore {
    private let defaults: UserDefaults
    private let key = "sprint-baseline"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SprintBaseline? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SprintBaseline.self, from: data)
    }

    func save(_ baseline: SprintBaseline) {
        guard let data = try? JSONEncoder().encode(baseline) else { return }
        defaults.set(data, forKey: key)
    }
}
