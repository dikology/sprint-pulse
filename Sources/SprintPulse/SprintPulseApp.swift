import AppKit
import SwiftUI

/// The macOS menu-bar app. A thin view layer: it holds platform concerns — the menu-bar
/// scene, the Settings scene, the activation policy — and no forecast logic. Everything it
/// renders comes from an `Instrument` computed in `SprintPulseCore`.
///
/// Two scenes since #17: the `MenuBarExtra` keeps the reading and the two ways out, and the
/// standard Settings window holds the configuration the Panel used to carry. The composition
/// root is where the two models meet — the wiring that makes an act on the connection a live
/// read belongs here rather than to either window's `onAppear`, because Settings can be the
/// first window opened and invariant 14's triggers must not depend on which one was.
@main
struct SprintPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var panel: PanelModel
    @StateObject private var setup: JiraSetupModel

    init() {
        let panel = PanelModel()
        let setup = JiraSetupModel()
        panel.readsOnConfigurationChanges(of: setup)
        _panel = StateObject(wrappedValue: panel)
        _setup = StateObject(wrappedValue: setup)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(panel: panel)
        } label: {
            Text(panel.menuBarLabel)
                .accessibilityLabel(panel.menuBarAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)

        // Opening this window triggers no live read (invariant 14) — nothing in `SettingsView`
        // consults the Board on appear; the reads happen in answer to the acts the window holds.
        Settings {
            SettingsView(panel: panel, setup: setup)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu-bar instrument, not a windowed app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}
