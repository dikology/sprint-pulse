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
    /// A notched screen wins even when another screen carries the menu bar, because the Glance is
    /// shaped to sit beside an obstruction rather than float in clear space. Where several screens
    /// have one — a built-in display and a Studio Display's camera housing are both obstructions
    /// macOS reports the same way — the main one is the answer, so the choice is a rule rather than
    /// the order `NSScreen.screens` happens to report in.
    static func hostScreen(of surfaces: [ScreenSurface]) -> ScreenSurface? {
        surfaces.first { $0.isMain && $0.hasNotch }
            ?? surfaces.first(where: \.hasNotch)
            ?? surfaces.first(where: \.isMain)
            ?? surfaces.first
    }

    /// Both windows' frames on `surface`, given the Panel's measured size.
    static func layout(on surface: ScreenSurface, panelSize: CGSize) -> NotchLayout {
        guard let notch = surface.notch else {
            // Top-centre of a screen with no notch: below the menu bar rather than under it. The
            // Glance is no longer a menu-bar item, but covering the clock is still somebody else's
            // UI taken away.
            let glance = placed(
                at: CGPoint(
                    x: surface.frame.midX - NotchMetrics.glanceSize.width / 2,
                    y: surface.unobstructedTop - NotchMetrics.notchClearance
                        - NotchMetrics.glanceSize.height
                ),
                size: NotchMetrics.glanceSize,
                in: surface.frame
            )
            return NotchLayout(
                glance: glance,
                panel: placed(
                    at: CGPoint(
                        x: surface.frame.midX - panelSize.width / 2,
                        y: glance.minY - NotchMetrics.panelDrop - panelSize.height
                    ),
                    size: panelSize,
                    in: surface.frame
                ),
                atNotch: false
            )
        }

        // Beside the notch, centred on its strip: the same band of screen the menu bar occupies on
        // a notched Mac, which is where the Operator already looks for a figure this small.
        // The Panel opens from the notch's own bottom edge — "directly below the notch" — and is
        // centred on the notch rather than on the screen, because the notch is where the click came
        // from.
        return NotchLayout(
            glance: placed(
                at: CGPoint(
                    x: notch.maxX + NotchMetrics.notchClearance,
                    y: notch.midY - NotchMetrics.glanceSize.height / 2
                ),
                size: NotchMetrics.glanceSize,
                in: surface.frame
            ),
            panel: placed(
                at: CGPoint(
                    x: notch.midX - panelSize.width / 2,
                    y: notch.minY - NotchMetrics.panelDrop - panelSize.height
                ),
                size: panelSize,
                in: surface.frame
            ),
            atNotch: true
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
    /// The screen's full frame, in the global Cocoa space `NSScreen.frame` uses.
    var frame: CGRect
    /// The top of the part of the screen the menu bar leaves clear — `NSScreen.visibleFrame.maxY`.
    /// On a notched screen this is the bottom of the notch's strip, give or take a pixel; on a
    /// screen with no notch it is where a top-centre Glance may start.
    var unobstructedTop: CGFloat
    /// The notch and the camera housing as one rect, in the same space as `frame`; `nil` when the
    /// screen has neither.
    var notch: CGRect?
    /// Whether macOS draws the menu bar on this screen — the one the Glance falls back to.
    var isMain: Bool

    var hasNotch: Bool { notch != nil }
}

/// Where the two windows go.
struct NotchLayout: Equatable {
    var glance: CGRect
    var panel: CGRect
    /// `true` when these frames hang beside a notch; `false` when they are at the top-centre of a
    /// screen that has none.
    var atNotch: Bool
}

/// The host's own measurements: the two clearances and the Glance's fixed size.
enum NotchMetrics {
    /// The Glance keeps one size whatever the figure it carries: a surface that grew and shrank as
    /// Points were counted would move the click target under the cursor, and would move it again
    /// every evening. The width is the marker, a space, and the widest reading it must hold; the
    /// height is what the notch's strip leaves room for.
    static let glanceSize = CGSize(width: 82, height: 24)

    /// How far both surfaces keep from whatever obstructs the top of the screen: the notch on a
    /// notched Mac, the menu bar everywhere else.
    static let notchClearance: CGFloat = 8

    /// How far below the obstruction — or below the Glance, on a screen with no notch — the Panel's
    /// top edge sits.
    static let panelDrop: CGFloat = 6

    /// The size to place the Panel at before its content has reported one. The Panel is 280 wide by
    /// its own `.frame`, so only the height is a guess.
    static let defaultPanelSize = CGSize(width: 280, height: 340)
}
