import AppKit
import SwiftUI

/// The notch app: a thin view layer that holds the platform concerns — the one window at the notch,
/// the Settings scene, the activation policy — and no forecast logic. Everything either surface
/// renders comes from an `Instrument` computed in `SprintPulseCore`.
///
/// Since #19 the app draws its own window and there is no scene for it: a notch surface has to be
/// borderless, non-activating, positioned from `safeAreaInsets`, and above the menu bar, which no
/// SwiftUI scene of #13's or #17's vintage offers. What is left for SwiftUI to own is the standard
/// `Settings` window #17 moved the configuration into, and the composition root below — where the
/// models meet. That wiring belongs here rather than to either surface's `onAppear` because Settings
/// can be the first window opened, and invariant 14's triggers must not depend on which one was.
///
/// A click on the Glance opens the Panel, and opening the Panel is the live read. Hovering is not a
/// thing this app can be asked about: ADR-0006 refuses it, and `NotchHostTests` fails anything that
/// grows a cursor-tracking path.
@main
struct SprintPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Opening this window triggers no live read (invariant 14) — nothing in `SettingsView`
        // consults the Board on appear; the reads happen in answer to the acts the window holds.
        Settings {
            SettingsView(panel: delegate.panel, setup: delegate.setup, host: delegate.host)
        }
    }
}

/// The composition root, and the owner of the notch window.
///
/// It is the delegate rather than the `App` struct because the window is AppKit's and the models have
/// to exist before either surface is drawn: `@StateObject` cannot reach a window, and a delegate
/// cannot be handed a model created after it. So the models are made here, in the one order that has
/// them meet before anything is drawn — the Panel's, the setup flow's, the host that turns a click
/// into a read and decides how long the shape takes, and the window that moves to where the host says.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel: PanelModel
    let setup: JiraSetupModel
    let host: NotchHost
    private var window: NotchWindow?

    override init() {
        panel = PanelModel()
        setup = JiraSetupModel()
        // Reduce Motion is read off the system here rather than inside `NotchHost` for the same reason
        // the screens are read here rather than inside it: the host decides, and decides from values
        // handed to it, so a test can hand it a system that says either thing.
        host = NotchHost(
            panel: panel,
            motion: MotionStore(),
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        )
        super.init()
        panel.readsOnConfigurationChanges(of: setup)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A notch instrument, not a windowed app: no Dock icon (#19's first AC, and #9's since M0).
        NSApp.setActivationPolicy(.accessory)

        let window = NotchWindow(panel: panel, host: host)
        self.window = window
        window.start()
    }
}
