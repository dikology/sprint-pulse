import AppKit
import SwiftUI

/// The Glance: Sprint Pulse's collapsed surface, the black band that wraps the notch — or, on a screen
/// that has none, the same shape at the menu bar's centre where a notch would be (#25).
///
/// It carries one figure and nothing that can go stale or be demoted — Points remaining, worded by
/// `PanelModel.glanceLabel` so the Glance and the Panel cannot disagree about what was read. The figure
/// sits in the band's right wing, clear of the cutout, and the left wing stays empty: the Glance has one
/// figure to show, and an empty wing says so (`CONTEXT.md`, Glance; ADR-0007). The click that opens the
/// Panel belongs to the window layer (`NotchWindows`), which owns the window this view is hosted in; what
/// is left here is the thing the Operator looks at, and the accessibility of it.
///
/// Two properties of #9 still hold and are the reason for this view's shape: nothing loops or
/// animates, and the figure is a readable string rather than an image or a colour.
///
/// A borderless window is not reachable the way a menu-bar item is (ADR-0006's last Consequence), so the
/// whole band is one accessibility element whose spoken label is the sentence the figure stands in for
/// and whose press action is the click. That is what AC 5 is verified against.
struct GlanceView: View {
    @ObservedObject var panel: PanelModel
    let host: NotchHost

    /// The click, reached from the accessibility tree rather than the mouse: VoiceOver's press
    /// action on the Glance opens the Panel exactly as a click does, and asks the Board for the same
    /// one read. The window layer owns this closure because presenting the Panel is its business;
    /// the gesture and the read are the host's.
    let press: () -> Void

    var body: some View {
        Text(panel.glanceLabel)
            .font(.callout.bold().monospacedDigit())
            .foregroundStyle(NotchPalette.figure)
            // The figure sits at the right end of the band's wing, so it never overlaps the cutout.
            .padding(.trailing, NotchMetrics.bandFigureInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            // The band is hardware: the cutout's black, square against the top edge of the screen and
            // rounded where it meets the desktop. No system colour is in this surface at all, so the
            // shape is drawn by the view rather than being a window background with an edge (ADR-0007).
            .background(NotchShape().fill(NotchPalette.surface))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(panel.glanceAccessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { press() }
            .background(SettingsRoute(host: host))
    }
}

/// Reads SwiftUI's `openSettings` environment action out of the Glance's own view tree and installs it
/// on the host, which is the part of the app that gets asked to open Settings — from the Glance's
/// right-click and from the Panel's ⌘,.
private struct SettingsRoute: View {
    let host: NotchHost

    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsActionRoute(host: host)
        } else {
            LegacySettingsActionRoute(host: host)
        }
    }
}

/// The only route that works, and the reason this is a view rather than a call in AppKit: measured
/// on macOS 26 against the `Settings` scene #17 installed,
/// `NSApp.sendAction(Selector(("showSettingsWindow:")))` returns `true` and opens nothing, and
/// `showPreferencesWindow:` is refused outright. The environment action reaches the scene from a
/// window AppKit owns; the selector does not.
@available(macOS 14.0, *)
private struct SettingsActionRoute: View {
    let host: NotchHost
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                let action = openSettings
                host.install(settingsOpener: {
                    // An accessory app has no menu bar to put a window under, so it activates
                    // itself first: a Settings window behind the desktop is one nobody opened.
                    NSApp.activate(ignoringOtherApps: true)
                    action()
                })
            }
    }
}

/// macOS 13 has no environment action for Settings, so there the responder-chain selector is what
/// there is — the same split #17 found at the Panel's call site, now on the side that asks.
private struct LegacySettingsActionRoute: View {
    let host: NotchHost

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                host.install(settingsOpener: {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                })
            }
    }
}
