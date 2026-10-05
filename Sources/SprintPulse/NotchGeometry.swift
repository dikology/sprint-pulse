import Foundation

/// Where the notch host puts its one window, as arithmetic rather than as AppKit calls (#19, #22).
///
/// The host has to answer three questions every time the screens change — which screen carries the
/// Glance, where on it the Glance hangs, and how far down that window goes when the Panel opens — and
/// all three are decidable from a description of the screens. `ScreenSurface` is that description: the
/// whole of what `NSScreen` is asked for, so a lid closing, an external display attaching, and a notch
/// of a different width are each one value here rather than a display configuration a test cannot make.
///
/// Since #22 the answer is two frames of *one* window rather than the frames of two windows: shut, the
/// window is the band; open, it is the band extended downward by the Panel's own height. The morph is
/// then only what the difference between those two rects can be — the bottom edge travelling — and
/// saying it as arithmetic is what lets a test falsify "one shape growing" at all.
///
/// Rects are in the Cocoa coordinate space `NSScreen.frame` already uses — origin at the bottom-left of
/// the main display, y increasing upwards — which is also the space `NSWindow` is positioned in. A
/// frame computed here goes to `setFrame(_:display:)` unchanged, and nothing in this file needs AppKit
/// to say what it means.
enum NotchGeometry {
    /// The screen the Glance belongs on: the one with a notch, and the main screen when none has
    /// one (#19).
    ///
    /// A notched screen wins even when another screen carries the menu bar, because the Glance is a
    /// band wrapped around an obstruction rather than a shape floating in clear space. Where several
    /// screens have one — a built-in display and a Studio Display's camera housing are both
    /// obstructions macOS reports the same way — the main one is the answer, so the choice is a rule
    /// rather than the order `NSScreen.screens` happens to report in.
    static func hostScreen(of surfaces: [ScreenSurface]) -> ScreenSurface? {
        surfaces.first { $0.isMain && $0.hasNotch }
            ?? surfaces.first(where: \.hasNotch)
            ?? surfaces.first(where: \.isMain)
            ?? surfaces.first
    }

    /// The one window's two frames on `surface`, given the Panel's measured size.
    ///
    /// The Glance is a band wrapped around the cutout, flush with the top edge of the screen, and the
    /// Panel is the same column continued downwards from its bottom edge — one shape, because the
    /// window holding it is one window (#22 AC 1). The two kinds of screen differ in exactly two
    /// things, which cutout the band wraps and what pins it sideways; the band's width is one
    /// arithmetic (`NotchMetrics.columnWidth`) and its top edge is `frame.maxY` on both.
    static func layout(on surface: ScreenSurface, panelSize: CGSize) -> NotchLayout {
        // The cutout: the hardware where there is any, and a nominal one of this Mac's measurements
        // where there is none, so the same band is drawn in the place a notch would have been (#25 AC 2).
        // ADR-0007 rejected keeping it below the menu bar the way M1.5 did — a black tab under the bar is
        // neither hardware nor system UI — and the cost it names, a long app menu reaching the centre and
        // meeting the band, is the one accepted.
        let cutout = surface.notch ?? CGRect(
            x: surface.frame.midX - NotchMetrics.nominalNotchWidth / 2,
            y: surface.frame.maxY - NotchMetrics.nominalNotchDepth,
            width: NotchMetrics.nominalNotchWidth,
            height: NotchMetrics.nominalNotchDepth
        )
        let column = NotchMetrics.columnWidth(notchWidth: cutout.width)
        // A real cutout pins the band's right edge a wing clear of the hardware, because that is where
        // the figure has to go. A nominal one has no hardware to keep clear, so the band is centred.
        let bandRight = surface.notch != nil
            ? cutout.maxX + NotchMetrics.bandFigureWing
            : surface.frame.midX + column / 2
        let band = placed(
            at: CGPoint(x: bandRight - column, y: surface.frame.maxY - cutout.height),
            size: CGSize(width: column, height: cutout.height),
            in: surface.frame
        )

        // The Panel's content hangs from the band's centre rather than from the cutout's, because the
        // band is the surface the Operator clicked. Where the cutout is wider than the content's own
        // column the two are no longer the same x — and now that the *window* is the band's column all
        // the way down, that difference is a margin of black beside the reading rather than a step in
        // the silhouette (#21's seam, which #22's one window retires along with its overlap).
        let panel = placed(
            at: CGPoint(
                x: band.midX - panelSize.width / 2,
                y: band.minY - panelSize.height
            ),
            size: panelSize,
            in: surface.frame
        )

        return NotchLayout(glance: band, panel: panel, atNotch: surface.notch != nil)
    }

    /// The rect of `size` resting on `origin` as its bottom-left corner, slid back inside `frame`.
    ///
    /// A bound, not a feature: a Glance clipped off the edge of its screen shows no number and has
    /// no way back, and where the screens are and how they are arranged is the Operator's to
    /// choose. Nothing else about the placement moves — the notch still decides both rects.
    private static func placed(at origin: CGPoint, size: CGSize, in frame: CGRect) -> CGRect {
        var rect = CGRect(origin: origin, size: size)
        let leftmost = max(frame.minX, frame.maxX - size.width)
        rect.origin.x = min(max(rect.origin.x, frame.minX), leftmost)
        rect.origin.y = max(min(rect.origin.y, frame.maxY - size.height), frame.minY)
        return rect
    }
}

/// A screen as the notch host reads it off `NSScreen`.
struct ScreenSurface: Equatable {
    /// The screen's full frame, in the global Cocoa space `NSScreen.frame` uses. Its top edge is
    /// where the Glance's band rests (#25), which is why the band needs nothing here but the frame:
    /// `visibleFrame` — the area the menu bar leaves clear — is no longer consulted, because the
    /// Glance is drawn where a notch would be, over the bar rather than under it.
    var frame: CGRect
    /// The notch and the camera housing as one rect, in the same space as `frame`; `nil` when the
    /// screen has neither.
    var notch: CGRect?
    /// Whether macOS draws the menu bar on this screen — the one the Glance falls back to.
    var isMain: Bool

    var hasNotch: Bool { notch != nil }
}

/// The one window's geometry: the band, the Panel's content inside it, and the two frames the window
/// is moved between.
struct NotchLayout: Equatable {
    /// The Glance's band — the cutout's strip widened into a column, flush with the top edge of the
    /// screen. Also the click target, the figure's home, and the whole window while the Panel is shut.
    var glance: CGRect

    /// Where the Panel's content sits *inside* the window once it has grown: the measured content,
    /// centred in the band's column and starting at the band's bottom edge.
    var panel: CGRect

    /// `true` when the band wraps a real cutout; `false` when it is drawn at the top-centre of a
    /// screen that has none.
    var atNotch: Bool

    /// The window's frame with the Panel shut.
    var windowClosed: CGRect { glance }

    /// The window's frame with the Panel open: the same column, its bottom edge moved down to the
    /// content's. The union is exact rather than a bounding-box approximation because the content is
    /// centred inside the band's column and abuts its bottom edge — so the only thing the two frames
    /// disagree about is where the bottom is.
    var windowOpen: CGRect { glance.union(panel) }
}

/// The host's own measurements: the band's wings, the cutout a screen without one is given, the
/// Panel's column, and how long its one shape takes to grow.
enum NotchMetrics {
    /// The Panel's own column — the width `PanelView` fixes its content at, and the width the band
    /// grows to so that the two surfaces share one silhouette (#21 AC 2). One number in one place
    /// because the two surfaces disagreeing about it *is* the seam.
    static let panelContentWidth: CGFloat = 280

    /// The band's left wing: the *least* margin the drawn shape keeps past the cutout's edge so the
    /// hardware is inside it rather than beside it. The empty wing absorbs whatever the Panel's column
    /// leaves over, which is why this is a minimum rather than the margin this Mac actually gets.
    static let bandLeftWing: CGFloat = 8

    /// The band's right wing: the room the widest figure the Glance may carry needs, clear of the
    /// cutout. A fixed width rather than a measurement of the text, so the band keeps one size
    /// whatever figure it carries.
    static let bandFigureWing: CGFloat = 82

    /// How far the figure sits in from the wing's outer edge — the band's own margin, so the number is
    /// never against the corner the band rounds.
    static let bandFigureInset: CGFloat = 12

    /// The room the figure is allowed to draw in: the wing less its margin. The Glance's text is given
    /// exactly this width, so a reading wider than the wing is bounded by the wing — the figure can
    /// never run leftwards over the cutout it is supposed to sit clear of (#25 AC 1).
    static let bandFigureRoom = bandFigureWing - bandFigureInset

    /// The cutout a screen with none is given, so the band is the same shape where a notch would be:
    /// this Mac's own measurements, which `NotchGeometryTests` pins against the real notch.
    static let nominalNotchWidth: CGFloat = 185
    static let nominalNotchDepth: CGFloat = 32

    /// The band's width for a cutout of the given width: enough column for the cutout, the figure's
    /// wing, and the minimum margin — and never less than the Panel's own column, because the two
    /// surfaces are one shape (#21 AC 2). A cutout wider than the Panel grows the band rather than
    /// clipping the figure's wing, and since #22 grows the window with it, so the reading simply gets
    /// more black beside it.
    static func columnWidth(notchWidth: CGFloat) -> CGFloat {
        max(panelContentWidth, notchWidth + bandLeftWing + bandFigureWing)
    }

    /// The band to put the window at before the screens have been read: the nominal cutout's shape,
    /// which is also the shape a screen with no notch is drawn.
    static let nominalBandSize = CGSize(
        width: columnWidth(notchWidth: nominalNotchWidth),
        height: nominalNotchDepth
    )

    /// The radius of every corner that meets air. One constant because the window is one shape: its
    /// top corners are square against the top edge of the screen and its bottom corners are the only
    /// rounded ones, in both states and at every frame of the morph between them.
    static let cornerRadius: CGFloat = 8

    /// How long the shape takes to grow and shrink: ADR-0007's short structural motion, identical every
    /// time and carrying no information. `NotchHost` answers with `0` — an instant open and close — for
    /// Reduce Motion and for the Operator's own "no animation" preference.
    static let structuralMorphDuration: TimeInterval = 0.22

    /// The size to place the Panel's content at before it has reported one. The width is the Panel's
    /// own column, so only the height is a guess.
    static let defaultPanelSize = CGSize(width: panelContentWidth, height: 340)
}
