import Combine
import Foundation

/// The notch host's own state (#19): which of its two surfaces is on screen, where the window that
/// draws both of them belongs on the screens there are right now, how long its shape takes to change
/// between them (#22), what the Operator's one gesture on the Glance costs, and what the Glance is
/// therefore allowed to say (#21).
///
/// It holds no window and reads no `NSScreen`. The AppKit layer (`NotchWindow`) supplies the screens as
/// `ScreenSurface` values, reports the Panel's measured size, and moves the one window between
/// `layout`'s two frames; everything the acceptance criteria can be falsified on — that a click-open is
/// exactly one live read, that closing is none, that launch is none, that the Glance moves when the
/// screens do, that the morph is short and can be switched off — is decided here, where a test can ask
/// it.
///
/// Why the read hangs on the click rather than on the window appearing: opening the Panel *is* the ask
/// (CONTEXT invariant 14), so the gesture and the read belong to one statement. Since #22 there is a
/// second reason, and it is the one an Operator can see: the window now takes 220ms to grow, and a read
/// issued once the shape had landed would answer the click a fifth of a second late.
@MainActor
final class NotchHost: ObservableObject {
    private let panel: PanelModel

    /// Where the Operator's "no animation" preference is kept, so the next open reads what the switch
    /// was set to rather than what it was set to at launch.
    private let motion: MotionStore

    /// The system's own answer for Reduce Motion, reached through a closure because this type reads no
    /// AppKit — the same reason it reads no `NSScreen`. The composition root hands in
    /// `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`; a test hands in a constant.
    private let reduceMotion: () -> Bool

    /// Whether the Panel is open. The window layer mirrors this; nothing else decides it. Published
    /// because the band's own wording depends on it: `GlanceView` is the other reader.
    @Published private(set) var isPanelOpen = false

    /// The Operator's "no animation" preference (#22 AC 4), persisted. Published because Settings
    /// renders the switch; read at the moment of each gesture rather than observed, because the next
    /// open is the only thing that has to change.
    @Published var animationDisabled: Bool {
        didSet {
            guard animationDisabled != oldValue else { return }
            motion.animationDisabled = animationDisabled
        }
    }

    /// Where the window goes, or `nil` when there is no screen to put it on. Read by the window layer
    /// after every gesture and every screen change; a `nil` is the instruction to leave the window where
    /// it is rather than to move it to a zero rect.
    private(set) var layout: NotchLayout?

    /// How the Glance's context menu and the Panel's ⌘, reach the `Settings` scene. Installed by
    /// the Glance's own view, because the only route that works from a window this app draws is
    /// SwiftUI's `openSettings` environment action — `showSettingsWindow:` reports it handled and
    /// opens nothing (measured on macOS 26 while writing this).
    private var settingsOpener: (() -> Void)?

    private var surfaces: [ScreenSurface] = []
    private var panelSize = NotchMetrics.defaultPanelSize

    init(
        panel: PanelModel,
        motion: MotionStore,
        reduceMotion: @escaping () -> Bool
    ) {
        self.panel = panel
        self.motion = motion
        self.reduceMotion = reduceMotion
        self.animationDisabled = motion.animationDisabled
    }

    /// What the band states: the figure, or the marker alone while the Panel is open.
    ///
    /// The Panel shows Points remaining among its own figures, so a band that went on stating it would
    /// show one number twice (`CONTEXT.md`, Live Sprint Points; ADR-0007). The withdrawal lives here
    /// because it is a state of the surface, not of the reading — `PanelModel` still words the figure,
    /// and nothing about the reading changes when the Panel opens.
    var glanceText: String { isPanelOpen ? PanelModel.glanceMarker : panel.glanceLabel }

    /// The same withdrawal in the spoken form: a reader must not be handed a figure the band is not
    /// showing (#9's rule that every figure is said as a sentence, applied to one that is absent).
    var glanceSpokenText: String {
        isPanelOpen ? PanelModel.glanceSpokenName : panel.glanceAccessibilityLabel
    }

    /// How long the window takes to grow into the Panel, or to shrink back to the band: ADR-0007's short
    /// structural motion, and `0` — an instant open and close — when either switch says so.
    ///
    /// A duration rather than a flag because the window layer's only question is *over how long*, and
    /// zero is that answer without a second branch to keep in step with it. Reduce Motion is asked here,
    /// at the gesture, rather than subscribed to: it is a system setting the Operator can change at any
    /// moment, and the next click reading it fresh is both cheaper and more honest than an observer that
    /// has to be remembered when it changes.
    var morphDuration: TimeInterval {
        animationDisabled || reduceMotion() ? 0 : NotchMetrics.structuralMorphDuration
    }

    /// The Operator clicked the Glance: the Panel opens, and opening it is the live read (#11,
    /// invariant 14). A click while it is open closes it, which asks nothing of the Board — the
    /// Glance is one control with two states, not a control and a dismiss button.
    ///
    /// The read is issued here rather than in the window layer so that exactly one gesture owns it, and
    /// it is issued before anything about the window is decided: the morph is the window's business and
    /// the ask is the click's, and #22's AC is that the first does not wait for the second. Nothing
    /// about hovering is modelled at all: a cursor crossing the notch must not become a request
    /// (ADR-0006), and the guard against that growing later is in `NotchHostTests`.
    func glanceWasClicked() {
        if isPanelOpen {
            isPanelOpen = false
            return
        }
        isPanelOpen = true
        Task { await panel.windowDidAppear() }
    }

    /// Esc, or a click outside the Panel: it goes away, and neither is an ask of the Board. A close that
    /// interrupts an opening is the same call — the read already happened on the click that started it,
    /// and nothing here knows or cares that a morph is in flight (#22 AC 2).
    func panelWasDismissed() {
        isPanelOpen = false
    }

    /// The screens changed — the lid closing, an external display attaching, the main screen
    /// changing (#19) — so the window belongs somewhere else now.
    func screensDidChange(to surfaces: [ScreenSurface]) {
        self.surfaces = surfaces
        relayout()
    }

    /// The Panel's content reported its size. The top edge does not move: the window grows downward
    /// from the band, so a reading that gained a row lengthens the shape, the way a menu does.
    func panelContentSizeChanged(_ size: CGSize) {
        guard size != panelSize else { return }
        panelSize = size
        relayout()
    }

    /// The Glance's context menu and the Panel's ⌘, both ask for the Settings window through here.
    func openSettings() {
        settingsOpener?()
    }

    func install(settingsOpener: @escaping () -> Void) {
        self.settingsOpener = settingsOpener
    }

    private func relayout() {
        guard let host = NotchGeometry.hostScreen(of: surfaces) else {
            layout = nil
            return
        }
        layout = NotchGeometry.layout(on: host, panelSize: panelSize)
    }
}
