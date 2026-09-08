import AppKit
import SwiftUI

/// The macOS menu-bar app. A thin view layer: it holds platform concerns — the menu-bar
/// scene, the activation policy — and no forecast logic. Everything it renders comes from an
/// `Instrument` computed in `SprintPulseCore`.
@main
struct SprintPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var panel = PanelModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(panel: panel)
        } label: {
            Text(panel.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu-bar instrument, not a windowed app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }
}
