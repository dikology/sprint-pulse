import SwiftUI

/// The notch host's own shape: a rectangle rounded only where it meets air.
///
/// Hardware is flush with the top edge of the screen, so the corners that touch that edge stay square
/// and only the ones facing the desktop carry a radius. `RoundedRectangle` rounds all four, and the
/// per-corner initialiser is macOS 14 while this target still supports 13 (`Package.swift`), hence the
/// hand-built path.
///
/// The arcs are circular rather than continuous: at this radius the difference is a pixel of curvature
/// at the corner, and the shape is read as the notch, not as a card.
struct NotchShape: Shape {
    /// The corners that are rounded. Every other corner is square because it meets the top edge of the
    /// screen or another part of the same silhouette.
    struct Corners: OptionSet {
        let rawValue: Int
        static let topLeft = Corners(rawValue: 1 << 0)
        static let topRight = Corners(rawValue: 1 << 1)
        static let bottomRight = Corners(rawValue: 1 << 2)
        static let bottomLeft = Corners(rawValue: 1 << 3)
    }

    var corners: Corners = [.bottomLeft, .bottomRight]
    var radius: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        let r = min(radius, min(rect.width, rect.height) / 2)
        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)
        // Where the walk resumes after the top-left corner: on the top edge, one radius in.
        let afterTopLeft = CGPoint(x: rect.minX + r, y: rect.minY)

        var path = Path()
        path.move(to: corners.contains(.topLeft) ? afterTopLeft : topLeft)
        walk(to: topRight, rounding: .topRight, then: CGPoint(x: rect.maxX, y: rect.minY + r), r, in: &path)
        walk(to: bottomRight, rounding: .bottomRight, then: CGPoint(x: rect.maxX - r, y: rect.maxY), r, in: &path)
        walk(to: bottomLeft, rounding: .bottomLeft, then: CGPoint(x: rect.minX, y: rect.maxY - r), r, in: &path)
        walk(to: topLeft, rounding: .topLeft, then: afterTopLeft, r, in: &path)
        path.closeSubpath()
        return path
    }

    /// Runs the straight edge up to `corner`, then rounds that corner or squares it, as `corners` says.
    /// `then` is a point on the edge the corner gives way to, which is what an inscribed arc needs to
    /// leave the corner tangentially.
    private func walk(
        to corner: CGPoint,
        rounding flag: Corners,
        then: CGPoint,
        _ r: CGFloat,
        in path: inout Path
    ) {
        if corners.contains(flag) {
            path.addArc(tangent1End: corner, tangent2End: then, radius: r)
        } else {
            path.addLine(to: corner)
        }
    }
}

/// The notch host's own colours.
///
/// Both surfaces are the black of the cutout whatever the system appearance, because a light surface
/// cannot read as hardware (ADR-0007) — this is the one place that colour is named, so the band and
/// the Panel cannot drift apart about what black they are.
enum NotchPalette {
    static let surface = Color.black

    /// The figure on the band. Explicitly light rather than a semantic label colour: the band's own
    /// surface is this app's black, not a system surface, and the figure has to be legible on it in
    /// both appearances.
    static let figure = Color.white
}
