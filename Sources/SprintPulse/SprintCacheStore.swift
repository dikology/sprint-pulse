import Foundation
import SprintPulseCore

/// Persists the last successful sprint read across launches (#12), so closing the laptop costs
/// the Operator their reading rather than their whole panel.
///
/// One slot, holding one Board's read: `CONTEXT.md`'s Board is singular, and a second Board's
/// reading would be somebody else's sprint — which is why `CachedSprint` carries the id it came
/// from and `PanelModel` refuses an entry that names another.
///
/// `UserDefaults` is enough for one small `Codable` value, the same choice the Sprint Baseline
/// slot makes; the *decision* the cache is built around lives in core (`CachedSprint`), and this
/// type only holds bytes. Core stays free of I/O: it receives the cached read as a value and never
/// knows it was stored (#2's boundary).
///
/// A write that fails is silent, by the same convention as the Baseline's: the consequence is that
/// the next launch has nothing cached and says so, which is a missing reading rather than a wrong
/// one. What nothing here will do is overwrite a good entry with anything short of a read that
/// succeeded — the only call site of `save` sits past both envelopes being decoded and the tracked
/// sprint resolved (`PanelModel.loadLive`), so a failure at any earlier point never reaches it.
struct SprintCacheStore {
    /// Named rather than inlined, so the test that puts something that is not a cached read into
    /// the slot is writing the same key this store reads — a private literal in two files is how a
    /// corruption test ends up testing nothing.
    static let defaultsKey = "sprint-read"

    private let defaults: UserDefaults
    private let key = Self.defaultsKey

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CachedSprint? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedSprint.self, from: data)
    }

    func save(_ cached: CachedSprint) {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: key)
    }

    /// The raw persisted bytes, for the test that proves no credential is among them (#12's AC 9).
    /// Nothing in the app has a reason to read the cache this way, which is the point: the token
    /// has no destination here to be looked for in — `CachedSprint` has no property that could hold
    /// one, and this is the sweep that shows the slot stayed that way.
    func storedBytes() -> Data? {
        defaults.data(forKey: key)
    }
}
