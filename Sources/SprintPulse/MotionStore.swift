import Foundation

/// The one presentation preference the Operator gets to set: whether the notch's shape is allowed to
/// move (#22 AC 4).
///
/// It exists because "I find it distracting" is a different reason from an accessibility need, and
/// switching it on should not require changing a system setting that every other app reads too
/// (`docs/agents/product.md` → Presentation, motion, and accessibility). It is *independent* of Reduce
/// Motion rather than a mirror of it: `NotchHost` asks both and needs either to answer "instant".
///
/// Deliberately nothing else lives here. The morph is the only motion Sprint Pulse has in M1, so this
/// store holds one Bool; when M3's mascot needs its own switch, that is a different ask about a
/// different surface and does not belong in this key.
struct MotionStore {
    private let defaults: UserDefaults

    /// The key the preference is stored under. `false` — animate — is stored as *nothing*, the way
    /// `ReadMode.automatic` is: an absent key and "nobody asked" are one state, which keeps a fresh
    /// install's default from being a value somebody had to set. `MotionStoreTests` pins the string
    /// itself rather than this name, so a rename cannot quietly orphan an Operator's stored answer.
    private let animationDisabledKey = "notch-animation-disabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the Operator has asked for no animation. As with every store here the setter is
    /// `nonmutating`: the value is written straight through to the `UserDefaults` reference, so a
    /// handle held as a `let` can write it and every other reader sees it at once.
    var animationDisabled: Bool {
        get { defaults.bool(forKey: animationDisabledKey) }
        nonmutating set {
            if newValue {
                defaults.set(true, forKey: animationDisabledKey)
            } else {
                defaults.removeObject(forKey: animationDisabledKey)
            }
        }
    }
}
