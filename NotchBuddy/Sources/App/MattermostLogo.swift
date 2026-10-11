import SwiftUI

/// Mattermost's mark: a ring opening at the top with a blade hanging inside it,
/// its tip pointing out through the opening.
///
/// Drawn rather than shipped as an image, for the reasons given on
/// `ClickMassaLogo`. Every ratio was measured off the published artwork at
/// 512 px, relative to the ring's outer radius; that artwork is not in this
/// repository, so these numbers are the only record of it.
///
/// Three things the measuring turned up, none of them guessable:
///
/// The ring's two circles are *not* concentric. The inner one sits up and to
/// the right of the outer, which is what makes the stroke taper — 79 px at the
/// bottom against 23 at the top, on a 391 px mark. A constant-width ring is the
/// obvious reading of the shape and it is the wrong one.
///
/// The blade's bulb is concentric with that inner circle, so the whole mark is
/// built on two centres rather than three.
///
/// The opening is not a wedge. It is the blade's own outline expanded by a
/// margin, which is why its edges are neither radial nor parallel: measured at
/// two radii, the left edge sits 56.0 and 55.8 px off the blade's tangent. So
/// it is cut here the way it was drawn — by subtracting a fattened blade —
/// rather than by approximating the result with arcs that would only agree with
/// the artwork at the radius they were fitted to.
struct MattermostLogo: View {
    var side: CGFloat
    /// Forces the ink. Left nil, the mark follows the surrounding appearance.
    var tint: Color? = nil

    @Environment(\.colorScheme) private var scheme

    /// The mark comes both ways, and both are the logo: Mattermost's blue on a
    /// pale ground, or knocked out white on that same blue -- which is how the
    /// artwork this was measured from is drawn. So it inverts rather than
    /// picking one and living with it, because neither survives both
    /// backgrounds: the blue is near-black against the island's #0E0F11 disc,
    /// about 1.9:1, and the white disappears into a light Settings window.
    ///
    /// The island's buttons are near-black whatever the system is set to, so
    /// they ask for the dark reading explicitly rather than inheriting it.
    static let onLight = Color(hex: "#28427B")
    static let onDark  = Color(hex: "#FFFFFF")

    private var ink: Color { tint ?? (scheme == .dark ? Self.onDark : Self.onLight) }

    var body: some View {
        MattermostMark()
            .fill(ink)
            .frame(width: side, height: side)
            // The mark never mirrors: the opening is at the top right, and a
            // flipped logo is the wrong logo.
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// The mark as one filled path.
struct MattermostMark: Shape {
    // Fractions of the outer radius, measured off the 512 px artwork.
    static let innerCentre = CGSize(width: 0.0409, height: -0.1381)
    static let innerRadius: CGFloat = 0.7391
    /// The bulb very nearly shares the inner circle's centre, but not quite --
    /// measured 3 px apart on a 391 px mark, which is small enough to look like
    /// rounding and large enough to lean the blade visibly if it is collapsed.
    static let bulbCentre = CGSize(width: 0.0563, height: -0.1458)
    static let bulbRadius:  CGFloat = 0.2864
    /// Bulb centre to the blade's furthest point.
    static let tipReach:    CGFloat = 0.8031
    static let tipRadius:   CGFloat = 0.0510
    /// Which way the blade points, and so where the ring opens.
    static let axis = Angle.degrees(287.7)
    /// How far the opening stands off the blade. Tuned against the artwork's
    /// own gap rather than measured off one edge: at this value the opening
    /// lands within 0.3 deg of the published one at every radius checked.
    static let margin: CGFloat = 0.2500

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let outer = CGPoint(x: rect.midX, y: rect.midY)
        let inner = CGPoint(x: outer.x + r * Self.innerCentre.width,
                            y: outer.y + r * Self.innerCentre.height)

        func circle(_ c: CGPoint, _ rad: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad,
                                   width: rad * 2, height: rad * 2))
        }

        let ring = circle(outer, r)
            .subtracting(circle(inner, r * Self.innerRadius))
        let bulb = CGPoint(x: outer.x + r * Self.bulbCentre.width,
                           y: outer.y + r * Self.bulbCentre.height)
        let blade = Self.blade(centre: bulb, r: r)
        // The fattened blade: the outline pushed out by `margin` all round.
        let clearance = blade
            .strokedPath(StrokeStyle(lineWidth: r * Self.margin * 2,
                                     lineCap: .round, lineJoin: .round))
            .union(blade)

        return ring.subtracting(clearance).union(blade)
    }

    /// The blade: the hull of the bulb and a small circle at the tip, joined by
    /// their outer tangents. Giving the tip a radius rather than a point is
    /// what the artwork shows, and it keeps the blade from going to a needle on
    /// the island's 34 pt buttons.
    static func blade(centre: CGPoint, r: CGFloat) -> Path {
        let r1 = r * bulbRadius
        let r2 = r * tipRadius
        let d  = r * tipReach - r2          // centre to centre
        let phi = CGFloat(axis.radians)
        let tip = CGPoint(x: centre.x + d * cos(phi), y: centre.y + d * sin(phi))
        // Where the outer tangents leave each circle. The contact angle is
        // acos((r1 - r2) / d): the radii at the two contact points are parallel,
        // which falls out of (T2 - T1) . (cos b, sin b) == 0. Using 90 + asin
        // instead of 90 - asin is the same number mirrored, and it walks the
        // contact points round the back of the bulb and starves the blade.
        let off = acos((r1 - r2) / d)

        var p = Path()
        p.addArc(center: centre, radius: r1,
                 startAngle: .radians(Double(phi + off)),
                 endAngle: .radians(Double(phi - off + 2 * .pi)),
                 clockwise: false)
        p.addArc(center: tip, radius: r2,
                 startAngle: .radians(Double(phi - off)),
                 endAngle: .radians(Double(phi + off)),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}
