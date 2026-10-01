import Foundation
import XCTest
@testable import SprintPulse

/// Where the notch host puts its two windows, decided as arithmetic on a description of the
/// screens rather than as AppKit calls (#19).
///
/// `ScreenSurface` is the whole of what the decision reads off `NSScreen` — the frame, the top of
/// the area the menu bar leaves clear, the notch's own rect, and which screen is the main one — so
/// a lid closing, an external display attaching, and a notch of a different width are all
/// expressible here. The numbers below are this Machine's real ones where they can be: the built-in
/// display is 1728×1117 with a notch of 185×32 whose strip runs from y 1085 to the screen's top at
/// 1117, measured through `safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`.
/// Everything else is a screen the Operator's Mac can be plugged into.
///
/// Frames are in the Cocoa coordinate space `NSScreen.frame` uses — origin at the bottom-left of the
/// main display, y increasing upwards — which is also `NSWindow`'s, so a frame computed here is
/// handed to `setFrame(_:display:)` unchanged.
final class NotchGeometryTests: XCTestCase {
    // MARK: - Which screen hosts the Glance

    /// The ticket's first clause: the Glance goes beside the notch *on the screen that has one*.
    /// A notched built-in display wins over an external one that carries the menu bar, because the
    /// notch is where the Glance belongs and the menu bar is nobody's.
    func test_theHostScreen_isTheScreenWithANotch_evenWhenAnotherScreenIsMain() {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            unobstructedTop: 1055,
            notch: nil,
            isMain: true
        )
        let surfaces = [external, Self.builtIn]

        XCTAssertEqual(NotchGeometry.hostScreen(of: surfaces), Self.builtIn)
    }

    /// The fallback, which is the lid-closed case seen from the other side: with no notch anywhere,
    /// the main screen hosts the Glance at its top-centre.
    func test_theHostScreen_isTheMainScreen_whenNoScreenHasANotch() {
        let main = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            unobstructedTop: 1055,
            notch: nil,
            isMain: true
        )
        let second = ScreenSurface(
            frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
            unobstructedTop: 1415,
            notch: nil,
            isMain: false
        )

        XCTAssertEqual(NotchGeometry.hostScreen(of: [second, main]), main)
    }

    /// Several screens can carry a notch (a built-in display and a Studio Display's camera housing
    /// are both obstructions macOS reports the same way). The main one wins so the choice is
    /// deterministic rather than whatever order `NSScreen.screens` happens to report.
    func test_theHostScreen_prefersTheMainScreen_whenSeveralScreensHaveNotches() {
        let other = ScreenSurface(
            frame: CGRect(x: 1728, y: 0, width: 1728, height: 1117),
            unobstructedTop: 1084,
            notch: CGRect(x: 2499, y: 1085, width: 185, height: 32),
            isMain: false
        )

        XCTAssertEqual(NotchGeometry.hostScreen(of: [other, Self.builtIn]), Self.builtIn)
    }

    // MARK: - Beside a notch

    /// The Glance hangs beside the notch, clear of it and vertically centred on the notch's own
    /// strip — it is a notch surface, not a menu-bar item, and the AC is that it sits clear of the
    /// notch and the camera housing.
    func test_layout_besideANotch_putsTheGlanceToTheRightOfItAndCentredOnTheStrip() {
        let layout = NotchGeometry.layout(on: Self.builtIn, panelSize: Self.panelSize)

        XCTAssertTrue(layout.atNotch, "the Glance is at the notch, not at the top-centre")
        XCTAssertEqual(layout.glance.size, NotchMetrics.glanceSize)
        XCTAssertEqual(
            layout.glance.minX,
            Self.builtIn.notch!.maxX + NotchMetrics.notchClearance,
            "one clearance away from the notch's right edge"
        )
        XCTAssertEqual(layout.glance.midY, Self.builtIn.notch!.midY, "centred on the notch's strip")
        XCTAssertLessThanOrEqual(layout.glance.maxY, Self.builtIn.frame.maxY, "inside the screen")
    }

    /// "Opens directly below the notch": the Panel's top edge is under the notch's bottom edge, and
    /// it is centred on the notch rather than on the screen — the notch is where the Operator looked
    /// from.
    func test_layout_besideANotch_hangsThePanelFromTheNotchsBottomEdge() {
        let layout = NotchGeometry.layout(on: Self.builtIn, panelSize: Self.panelSize)

        XCTAssertEqual(layout.panel.maxY, Self.builtIn.notch!.minY - NotchMetrics.panelDrop)
        XCTAssertEqual(layout.panel.midX, Self.builtIn.notch!.midX)
        XCTAssertEqual(layout.panel.size, Self.panelSize, "the size the content reported")
    }

    /// One bound rather than a feature: nothing the host draws may leave the screen that hosts it.
    /// A Glance clipped off the edge is a Glance showing no number with no way back, and a screen
    /// arranged with an offset origin or a notch near an edge is the Operator's to arrange, not the
    /// app's to be surprised by.
    func test_layout_keepsBothSurfacesInsideTheScreen_thatHostsThem() {
        let offset = ScreenSurface(
            frame: CGRect(x: -1_728, y: 0, width: 300, height: 700),
            unobstructedTop: 667,
            notch: CGRect(x: -1_670, y: 668, width: 185, height: 32),
            isMain: false
        )
        let layout = NotchGeometry.layout(on: offset, panelSize: CGSize(width: 280, height: 400))

        for rect in [layout.glance, layout.panel] {
            XCTAssertGreaterThanOrEqual(rect.minX, offset.frame.minX, "\(rect) left of its screen")
            XCTAssertLessThanOrEqual(rect.maxX, offset.frame.maxX, "\(rect) off the right edge")
            XCTAssertGreaterThanOrEqual(rect.minY, offset.frame.minY, "\(rect) below its screen")
        }
    }

    // MARK: - Top-centre of a screen with no notch

    /// The fallback position, and the one the Operator sees with the lid closed: centred on the
    /// screen's own width, and *below* the menu bar rather than under it — the Glance is not a
    /// menu-bar item any more, but it still has no business covering the clock.
    func test_layout_topCentre_centresTheGlanceBelowTheMenuBar() {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            unobstructedTop: 1055,
            notch: nil,
            isMain: true
        )
        let layout = NotchGeometry.layout(on: external, panelSize: Self.panelSize)

        XCTAssertFalse(layout.atNotch)
        XCTAssertEqual(layout.glance.midX, external.frame.midX)
        XCTAssertEqual(layout.glance.maxY, external.unobstructedTop - NotchMetrics.notchClearance)
        XCTAssertEqual(layout.glance.size, NotchMetrics.glanceSize)
    }

    /// With no notch to hang from, the Panel drops from the Glance the Operator clicked.
    func test_layout_topCentre_hangsThePanelFromTheGlance() {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            unobstructedTop: 1055,
            notch: nil,
            isMain: true
        )
        let layout = NotchGeometry.layout(on: external, panelSize: Self.panelSize)

        XCTAssertEqual(layout.panel.maxY, layout.glance.minY - NotchMetrics.panelDrop)
        XCTAssertEqual(layout.panel.midX, external.frame.midX)
    }

    // MARK: - Screens

    /// This Mac's built-in display, as measured from `NSScreen` on it.
    static let builtIn = ScreenSurface(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        unobstructedTop: 1084,
        notch: CGRect(x: 771, y: 1085, width: 185, height: 32),
        isMain: true
    )

    /// The Panel's own column, which `PanelView` fixes at 280 wide.
    static let panelSize = CGSize(width: 280, height: 340)
}
