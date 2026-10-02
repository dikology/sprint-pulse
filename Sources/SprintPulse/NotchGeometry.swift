import Foundation

/// Where the notch host puts its two windows, as arithmetic rather than as AppKit calls (#19).
///
/// The host has to answer three questions every time the screens change — which screen carries the
/// Glance, where on it the Glance hangs, and where the Panel opens below it — and all three are
/// decidable from a description of the screens. `ScreenSurface` is that description: the whole of
/// what `NSScreen` is asked for, so a lid closing, an external display attaching, and a notch of a
/// different width are each one value here rather than a display configuration a test cannot make.
///
/// Rects are in the Cocoa coordinate space `NSScreen.frame` already uses — origin at the bottom-left
/// of the main display, y increasing upwards — which is also the space `NSWindow` is positioned in.
/// A frame computed here goes to `setFrame(_:display:)` unchanged, and nothing in this file needs
/// AppKit to say what it means.
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

    /// Both windows' frames on `surface`, given the Panel's measured size.
    ///
    /// The Glance is a band wrapped around the cutout, flush with the top edge of the screen, and the
    /// Panel hangs below that band's bottom edge. Which cutout is being wrapped is the only thing the
    /// two kinds of screen differ in, so the band's size is one arithmetic
    /// (`NotchMetrics.bandSize`) and its top edge is `frame.maxY` on both.
    static func layout(on surface: ScreenSurface, panelSize: CGSize) -> NotchLayout {
        let size: CGSize
        let band: CGRect
        let panelCentre: CGFloat
        if let notch = surface.notch {
            size = NotchMetrics.bandSize(notchWidth: notch.width, notchDepth: notch.height)
            band = placed(
                at: CGPoint(x: notch.minX - NotchMetrics.bandLeftWing, y: surface.frame.maxY - size.height),
                size: size,
                in: surface.frame
            )
            // The Panel is centred on the notch rather than on the screen, because the notch is where
            // the click came from.
            panelCentre = notch.midX
        } else {
            // #25 AC 2: on a screen with no cutout the same band is drawn where a notch would be — the
            // menu bar's own centre, flush with the top edge, from a nominal cutout of this Mac's
            // measurements. ADR-0007 rejected keeping it below the bar the way M1.5 did: a black tab
            // under the bar is neither hardware nor system UI, and the cost the ADR names — a long app
            // menu reaching the centre and meeting it — is the one accepted.
            size = NotchMetrics.bandSize(
                notchWidth: NotchMetrics.nominalNotchWidth,
                notchDepth: NotchMetrics.nominalNotchDepth
            )
            band = placed(
                at: CGPoint(x: surface.frame.midX - size.width / 2, y: surface.frame.maxY - size.height),
                size: size,
                in: surface.frame
            )
            panelCentre = surface.frame.midX
        }

        return NotchLayout(
            glance: band,
            panel: placed(
                at: CGPoint(
                    x: panelCentre - panelSize.width / 2,
                    y: band.minY - NotchMetrics.panelDrop - panelSize.height
                ),
                size: panelSize,
                in: surface.frame
            ),
            atNotch: surface.notch != nil
        )
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

/// Where the two windows go.
struct NotchLayout: Equatable {
    /// The Glance's band, wrapping the cutout and flush with the top edge of the screen.
    var glance: CGRect
    var panel: CGRect
    /// `true` when the band wraps a real cutout; `false` when it is drawn at the top-centre of a
    /// screen that has none.
    var atNotch: Bool
}

/// The host's own measurements: the band's two wings, the cutout a screen without one is given, and
/// the Panel's drop.
enum NotchMetrics {
    /// The band's left wing: how far the drawn shape reaches past the cutout so the hardware's own
    /// edge is inside it rather than beside it. Empty by design — the Glance has one figure, and it
    /// is in the right wing (`CONTEXT.md`, Glance; ADR-0007).
    static let bandLeftWing: CGFloat = 12

    /// The band's right wing: the room the widest figure the Glance may carry needs, clear of the
    /// cutout. A fixed width rather than a measurement of the text, so the band keeps one size
    /// whatever figure it carries.
    static let bandFigureWing: CGFloat = 82

    /// How far the figure sits in from the wing's outer edge — the band's own margin, so the number is
    /// never against the corner the band rounds.
    static let bandFigureInset: CGFloat = 12

    /// The cutout a screen with none is given, so the band is the same shape where a notch would be:
    /// this Mac's own measurements, which `NotchGeometryTests` pins against the real notch.
    static let nominalNotchWidth: CGFloat = 185
    static let nominalNotchDepth: CGFloat = 32

    /// The band's size for a cutout of the given width and depth: the cutout itself, `bandLeftWing` of
    /// margin on the left that makes the hardware disappear into the drawn shape, and
    /// `bandFigureWing` on the right for the figure.
    ///
    /// One size whatever the band carries (#25 AC 4): the width is a fixed wing, never a measurement of
    /// the text in it, so counting Points cannot move the click target under the cursor — or move it
    /// again every evening.
    static func bandSize(notchWidth: CGFloat, notchDepth: CGFloat) -> CGSize {
        CGSize(width: notchWidth + bandLeftWing + bandFigureWing, height: notchDepth)
    }

    /// The band to put the Glance window at before the screens have been read: the nominal cutout's
    /// shape, which is also the shape a screen with no notch is drawn.
    static let nominalBandSize = bandSize(
        notchWidth: nominalNotchWidth,
        notchDepth: nominalNotchDepth
    )

    /// How far below the band's bottom edge the Panel's top edge sits. #21 takes this to nothing so
    /// that the two surfaces read as one silhouette; until then the Panel is a separate window.
    static let panelDrop: CGFloat = 6

    /// The size to place the Panel at before its content has reported one. The Panel is 280 wide by
    /// its own `.frame`, so only the height is a guess.
    static let defaultPanelSize = CGSize(width: 280, height: 340)
}
