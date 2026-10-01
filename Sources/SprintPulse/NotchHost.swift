import Foundation

/// The notch host's own state (#19): which of its two surfaces is on screen, where both of them
/// belong on the screens there are right now, and what the Operator's one gesture on the Glance
/// costs.
///
/// It holds no window and reads no `NSScreen`. The AppKit layer (`NotchWindows`) supplies the
/// screens as `ScreenSurface` values, reports the Panel's measured size, and mirrors
/// `isPanelOpen` and `layout` into windows; everything the acceptance criteria can be falsified on
/// — that a click-open is exactly one live read, that closing is none, that launch is none, that the
/// Glance moves when the screens do — is decided here, where a test can ask it.
///
/// Why the read hangs on the click rather than on the window appearing: opening the Panel *is* the
/// ask (CONTEXT invariant 14), so the gesture and the read belong to one statement. The Panel's
/// SwiftUI view no longer reads anything on appear — with the menu-bar host gone the window stands
/// open between openings, so `onAppear` would fire once and then never again, which is both a
/// missed read and, once patched, a second read for one click.
@MainActor
final class NotchHost {
    private let panel: PanelModel

    /// Whether the Panel is open. The window layer mirrors this; nothing else decides it.
    private(set) var isPanelOpen = false

    /// Where the Glance and the Panel go, or `nil` when there is no screen to put them on. Read by
    /// the window layer after every gesture and every screen change; a `nil` is the instruction to
    /// leave the windows where they are rather than to move them to a zero rect.
    private(set) var layout: NotchLayout?

    /// How the Glance's context menu and the Panel's ⌘, reach the `Settings` scene. Installed by
    /// the Glance's own view, because the only route that works from a window this app draws is
    /// SwiftUI's `openSettings` environment action — `showSettingsWindow:` reports it handled and
    /// opens nothing (measured on macOS 26 while writing this).
    private var settingsOpener: (() -> Void)?

    private var surfaces: [ScreenSurface] = []
    private var panelSize = NotchMetrics.defaultPanelSize

    init(panel: PanelModel) {
        self.panel = panel
    }

    /// The Operator clicked the Glance: the Panel opens, and opening it is the live read (#11,
    /// invariant 14). A click while it is open closes it, which asks nothing of the Board — the
    /// Glance is one control with two states, not a control and a dismiss button.
    ///
    /// The read is issued here rather than in the window layer so that exactly one gesture owns it.
    /// Nothing about hovering is modelled at all: a cursor crossing the notch must not become a
    /// request (ADR-0006), and the guard against that growing later is in `NotchHostTests`.
    func glanceWasClicked() {
        if isPanelOpen {
            isPanelOpen = false
            return
        }
        isPanelOpen = true
        Task { await panel.windowDidAppear() }
    }

    /// Esc, or a click outside the Panel: it goes away, and neither is an ask of the Board.
    func panelWasDismissed() {
        isPanelOpen = false
    }

    /// The screens changed — the lid closing, an external display attaching, the main screen
    /// changing (#19) — so both windows belong somewhere else now.
    func screensDidChange(to surfaces: [ScreenSurface]) {
        self.surfaces = surfaces
        relayout()
    }

    /// The Panel's content reported its size. The top edge does not move: the Panel hangs from the
    /// notch, so a reading that gained a row grows downwards, the way a menu does.
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
