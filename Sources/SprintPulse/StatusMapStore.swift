import Foundation
import SprintPulseCore

/// Persists the Operator's Status Map across launches (#13), so mapping an `Unmapped Status` fixes
/// the forecast for good rather than until the next window open.
///
/// The map is the Operator's own translation, and this is the only place it is stored: `Forecast`
/// keeps taking it as a value and core stays free of I/O (#2's boundary, the same one the Baseline
/// and the cache slot respect). One slot for one Board is enough — there is exactly one Board
/// (`CONTEXT.md`), and a map per Board would be a second question nobody has asked the Operator.
///
/// Two fallbacks, both deliberate:
///
/// - Nothing stored hands back `StatusMap.default`. A fresh install has a working map, the same way
///   it has a fixture reading rather than an authentication wall (#10, #11's default Estimate field).
/// - Bytes that are not a map hand back the same default. Preferences are a user-editable plist, and
///   `try?` is the whole defence — the same convention as a half-written identity (#10) and a
///   corrupt cache entry (#12). A slot that cannot answer costs the Operator a missing edit, never a
///   wrong translation.
///
/// A map the Operator emptied is *not* a missing slot: an entry of `{}` reads back empty, and every
/// status in it becomes Unmapped. That is an edit they made, and the store's job is to remember it.
///
/// A write that fails is silent, by the Baseline's and the cache's convention: the consequence is
/// that the next launch has the shipped map and says which statuses it does not know.
struct StatusMapStore {
    /// Named rather than inlined, so the tests that corrupt the slot and the one that sweeps every
    /// `jira-` preference for a credential are writing and reading this store's own key — a private
    /// literal in two files is how a sweep ends up testing nothing (#12's convention).
    static let defaultsKey = "jira-status-map"

    private let defaults: UserDefaults
    private let key = Self.defaultsKey

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> StatusMap {
        guard let data = defaults.data(forKey: key),
              let map = try? JSONDecoder().decode(StatusMap.self, from: data)
        else { return .default }
        return map
    }

    func save(_ map: StatusMap) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: key)
    }
}
