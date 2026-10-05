import Foundation
import XCTest
@testable import SprintPulse

/// Where the notch host puts its one window, decided as arithmetic on a description of the screens
/// rather than as AppKit calls (#19, #21, #22).
///
/// Since #22 the decision is about a single rect that changes size, not two rects that have to be kept
/// aligned: the window is the band while the Panel is shut and the band extended downward while it is
/// open, so what the morph can do is stated here as the difference between two frames — the bottom edge
/// travels, and nothing else.
///
/// `ScreenSurface` is the whole of what the decision reads off `NSScreen` — the frame, the notch's own
/// rect, and which screen is the main one — so a lid closing, an external display attaching, and a notch
/// of a different width are all expressible here. The numbers below are this Machine's real ones where
/// they can be: the built-in display is 1728×1117 with a notch of 185×32 whose strip runs from y 1085 to
/// the screen's top at 1117, measured through `safeAreaInsets` and
/// `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`. Everything else is a screen the Operator's Mac can be
/// plugged into.
///
/// Frames are in the Cocoa coordinate space `NSScreen.frame` uses — origin at the bottom-left of the
/// main display, y increasing upwards — which is also `NSWindow`'s, so a frame computed here is
/// handed to `setFrame(_:display:)` unchanged.
final class NotchGeometryTests: XCTestCase {
    // MARK: - Which screen hosts the Glance

    /// The ticket's first clause: the Glance wraps the notch *on the screen that has one*.
    /// A notched built-in display wins over an external one that carries the menu bar, because the
    /// notch is where the Glance belongs and the menu bar is nobody's.
    func test_theHostScreen_isTheScreenWithANotch_evenWhenAnotherScreenIsMain() {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
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
            notch: nil,
            isMain: true
        )
        let second = ScreenSurface(
            frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
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
            notch: CGRect(x: 2499, y: 1085, width: 185, height: 32),
            isMain: false
        )

        XCTAssertEqual(NotchGeometry.hostScreen(of: [other, Self.builtIn]), Self.builtIn)
    }

    // MARK: - Wrapping a notch

    /// AC 1: the Glance is the notch's own strip widened into a band, flush with the top edge of the
    /// screen, so the cutout disappears into it instead of standing next to a floating shape. The
    /// figure's wing is the constant and the empty left wing absorbs the rest — the band has one figure
    /// to show (`CONTEXT.md`, Glance), so the left wing stays empty.
    func test_layout_wrappingANotch_putsTheBandFlushWithTheTopEdge() throws {
        let layout = NotchGeometry.layout(on: Self.builtIn, panelSize: Self.panelSize)
        let notch = try XCTUnwrap(Self.builtIn.notch)

        XCTAssertTrue(layout.atNotch, "the band is at the notch, not at the top-centre")
        XCTAssertEqual(layout.glance.maxY, 1_117, "flush with the top edge of the screen")
        XCTAssertEqual(layout.glance.minY, notch.minY, "and down to the notch's own bottom edge")
        XCTAssertEqual(layout.glance.maxX, 1_038, "the figure's 82 right of the cutout's edge at x 956")
        XCTAssertEqual(layout.glance.minX, 758, "…and the empty wing takes the rest: 13pt left of x 771")
        XCTAssertEqual(layout.glance.width, 280, "the Panel's own column, which is what makes the two one shape")
    }

    // MARK: - One window, two frames (#22)

    /// AC 1: while the Panel is shut the window *is* the band — one rect, the Glance's own shape,
    /// flush with the top edge of the screen. The numbers are worked out by hand from this Mac's
    /// display (1728×1117, a notch 185 wide and 32 deep at x 771) and the Panel's 280pt column, not
    /// recomputed from the arithmetic under test.
    func test_theWindowIsTheBand_whileThePanelIsShut() throws {
        let layout = NotchGeometry.layout(on: Self.builtIn, panelSize: Self.panelSize)

        XCTAssertEqual(layout.windowClosed, CGRect(x: 758, y: 1_085, width: 280, height: 32))
    }

    /// AC 1's other half, and the whole of what the morph is allowed to do: the open window is the
    /// same column with its bottom edge moved down by the Panel's height. x, width and the top edge are
    /// shared by the two frames, so AppKit's interpolation between them can only travel the bottom —
    /// one shape growing, with nothing else on the Panel able to move.
    ///
    /// The Panel's content starts exactly at the band's bottom edge: the 1pt of overlap #21 needed to
    /// hide the seam between two windows has no seam left to hide, and went with them.
    func test_theWindowGrowsIntoThePanel_travellingOnlyItsBottomEdge() throws {
        let layout = NotchGeometry.layout(on: Self.builtIn, panelSize: Self.panelSize)

        XCTAssertEqual(layout.windowOpen, CGRect(x: 758, y: 745, width: 280, height: 372))
        XCTAssertEqual(layout.windowOpen.minX, layout.windowClosed.minX, "the same left edge")
        XCTAssertEqual(layout.windowOpen.maxX, layout.windowClosed.maxX, "the same right edge")
        XCTAssertEqual(layout.windowOpen.maxY, layout.windowClosed.maxY, "and the same top edge")
        XCTAssertEqual(layout.panel.maxY, layout.glance.minY, "the content starts at the band's bottom")
    }

    /// AC 3's fourth screen, and the reason the band is arithmetic rather than a screenshot: a notch of
    /// a different width. The figure's wing and the minimum margin are constants and the middle is
    /// whatever the hardware is, so a wider cutout widens the band and both keep their room.
    ///
    /// This is where #21's silhouette used to step: the Panel's content is a fixed 280, so a 310 band
    /// overhung it by 15pt at the join. With one window the step is gone — the *window* is the band's
    /// width all the way down and the content is centred inside it.
    func test_layout_aCutoutWiderThanThePanel_growsTheWindowAndCentresTheContentInIt() throws {
        let studio = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
            notch: CGRect(x: 1_170, y: 1_408, width: 220, height: 32),
            isMain: true
        )
        let layout = NotchGeometry.layout(on: studio, panelSize: Self.panelSize)

        XCTAssertEqual(layout.glance.width, 310, "220 of cutout, 8 of margin, 82 of figure")
        XCTAssertEqual(layout.glance.maxX, 1_472, "the figure's wing keeps its room")
        XCTAssertEqual(layout.glance.minX, 1_162, "and the margin keeps its minimum")
        XCTAssertEqual(layout.glance.maxY, 1_440, "flush with the top edge of this display")
        XCTAssertEqual(layout.glance.height, 32, "and the cutout's own depth")
        XCTAssertEqual(layout.windowOpen.width, 310, "one column the whole way down — no step")
        XCTAssertEqual(layout.windowOpen, CGRect(x: 1_162, y: 1_068, width: 310, height: 372))
        XCTAssertEqual(layout.panel.midX, layout.glance.midX, "the content hangs from the band's centre")
        XCTAssertEqual(layout.panel.width, 280, "at its own width, inside the wider column")
    }

    /// AC 5: the window keeps its top edge when its content grows a row — the edge it shares with the
    /// band is fixed, so only the bottom moves, and the shape never detaches from the notch.
    func test_thePanelContentGrows_downwardsFromAnEdgeThatDoesNotMove() {
        let shortRead = NotchGeometry.layout(on: Self.builtIn, panelSize: CGSize(width: 280, height: 340))
        let tallRead = NotchGeometry.layout(on: Self.builtIn, panelSize: CGSize(width: 280, height: 620))

        XCTAssertEqual(tallRead.windowOpen.maxY, shortRead.windowOpen.maxY, "the top edge did not move")
        XCTAssertEqual(tallRead.windowOpen.minY, shortRead.windowOpen.minY - 280, "the bottom went down")
        XCTAssertEqual(tallRead.windowOpen.height, 652, "32 of band and 620 of Panel")
        XCTAssertEqual(tallRead.windowClosed, shortRead.windowClosed, "and the band is where it was")
    }

    /// AC 4: the band keeps one size whatever figure it carries. The reading is not an input to the
    /// band at all — a Panel that gained a row moves the window's own bottom edge, never the Glance's
    /// rect — so counting Points cannot move the click target out from under the cursor.
    func test_theBandKeepsOneSize_whateverTheReadingGrewTo() {
        let short = NotchGeometry.layout(on: Self.builtIn, panelSize: CGSize(width: 280, height: 340))
        let tall = NotchGeometry.layout(on: Self.builtIn, panelSize: CGSize(width: 280, height: 620))

        XCTAssertEqual(short.glance, tall.glance, "one band, whatever the reading below it")
        XCTAssertEqual(short.windowClosed, tall.windowClosed, "and one window while it is shut")
    }

    /// One bound rather than a feature: nothing the host draws may leave the screen that hosts it.
    /// A Glance clipped off the edge is a Glance showing no number with no way back, and a screen
    /// arranged with an offset origin or a notch near an edge is the Operator's to arrange, not the
    /// app's to be surprised by.
    func test_layout_keepsTheWindowInsideTheScreen_thatHostsIt() {
        let offset = ScreenSurface(
            frame: CGRect(x: -1_728, y: 0, width: 300, height: 700),
            notch: CGRect(x: -1_670, y: 668, width: 185, height: 32),
            isMain: false
        )
        let layout = NotchGeometry.layout(on: offset, panelSize: CGSize(width: 280, height: 400))

        for rect in [layout.glance, layout.panel, layout.windowClosed, layout.windowOpen] {
            XCTAssertGreaterThanOrEqual(rect.minX, offset.frame.minX, "\(rect) left of its screen")
            XCTAssertLessThanOrEqual(rect.maxX, offset.frame.maxX, "\(rect) off the right edge")
            XCTAssertGreaterThanOrEqual(rect.minY, offset.frame.minY, "\(rect) below its screen")
        }
    }

    // MARK: - The same band on a screen with no notch

    /// AC 2: on a screen with no cutout the Glance draws the same shape where a notch would be —
    /// flush with the top edge at the menu bar's centre. ADR-0007 rejected keeping it below the menu
    /// bar the way M1.5 did: a black tab under the bar is neither hardware nor system UI, and the
    /// cost (a long app menu can reach the centre and meet it) is the one the ADR accepts.
    func test_layout_noNotch_drawsTheSameBandFlushWithTheTopEdgeAndCentred() throws {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            notch: nil,
            isMain: true
        )
        let layout = NotchGeometry.layout(on: external, panelSize: Self.panelSize)

        XCTAssertFalse(layout.atNotch)
        XCTAssertEqual(layout.glance.maxY, 1_080, "flush with the top edge, where a notch would be")
        XCTAssertEqual(layout.glance.midX, 960, "at the menu bar's centre")
        XCTAssertEqual(
            layout.glance.size, CGSize(width: 280, height: 32),
            "the same shape this Mac's notch gets, from a nominal cutout"
        )
        XCTAssertEqual(
            layout.glance.size, NotchGeometry.layout(on: Self.builtIn, panelSize: Self.panelSize).glance.size,
            "the same shape whatever the screen has in it"
        )
    }

    /// With no notch to hang from the window grows the same way: the same shared edge and the same
    /// column, because the morph is one shape either way (#22 AC 1).
    func test_layout_topCentre_growsTheWindowDownFromTheBand() {
        let external = ScreenSurface(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            notch: nil,
            isMain: true
        )
        let layout = NotchGeometry.layout(on: external, panelSize: Self.panelSize)

        XCTAssertEqual(layout.windowClosed, CGRect(x: 820, y: 1_048, width: 280, height: 32))
        XCTAssertEqual(layout.windowOpen, CGRect(x: 820, y: 708, width: 280, height: 372))
        XCTAssertEqual(layout.windowOpen.midX, external.frame.midX)
    }

    // MARK: - Screens

    /// This Mac's built-in display, as measured from `NSScreen` on it.
    static let builtIn = ScreenSurface(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        notch: CGRect(x: 771, y: 1085, width: 185, height: 32),
        isMain: true
    )

    /// The Panel's own column, which `PanelView` fixes at 280 wide.
    static let panelSize = CGSize(width: 280, height: 340)
}
