import SwiftUI

// MARK: - The chat tab's mark

/// The speech bubble with sparkles that opens the chat.
///
/// Drawn rather than an asset, like every other mark in the app: the island is
/// one black panel, and a PNG with an edge of its own shows the moment the
/// scale is not 1:1.
///
/// Measured off the reference art on a 400 × 357 grid, which is the art's own
/// bounding box, and scaled to whatever frame it is given — so the numbers here
/// are the drawing, and nothing re-derives them.
struct ChatSparkleShape: Shape {

    /// The art's own box. Everything below is in these units.
    static let designSize = CGSize(width: 400, height: 357)

    // The bubble, as a rounded rectangle with a tail hung off its bottom-left.
    static let bubble = CGRect(x: 0, y: 50, width: 341, height: 252)
    static let bubbleRadius: CGFloat = 52
    /// The tail's vertical left edge, the corner its two edges would meet in,
    /// and where its slope rejoins the bubble. `tailBottom` is below the box on
    /// purpose: it is the corner the rounding cuts off, not where the ink ends.
    static let tailX: CGFloat = 82
    static let tailBottom: CGFloat = 375
    static let tailJoin: CGFloat = 163
    static let tailRadius: CGFloat = 14

    // The two sparkles: one punched out of the bubble, one over its corner with
    // the bubble cut away around it.
    static let innerCentre = CGPoint(x: 170, y: 172)
    static let innerRadius: CGFloat = 63
    static let outerCentre = CGPoint(x: 324, y: 76)
    static let outerRadius: CGFloat = 75
    /// How much black is left between the bubble and the sparkle crossing it.
    static let gap: CGFloat = 15
    /// How far the cubic's controls sit from each tip, as a fraction of the
    /// radius: how deeply the star's sides are cut in.
    static let waist: CGFloat = 0.54
    /// The tips are not points. As a fraction of the radius.
    static let tipRounding: CGFloat = 0.125

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / Self.designSize.width, rect.height / Self.designSize.height)
        let dx = rect.minX + (rect.width - Self.designSize.width * s) / 2
        let dy = rect.minY + (rect.height - Self.designSize.height * s) / 2

        let inner = Self.sparkle(centre: Self.innerCentre, radius: Self.innerRadius)
        let outer = Self.sparkle(centre: Self.outerCentre, radius: Self.outerRadius)

        let glyph = Self.body
            .subtracting(inner)
            .subtracting(Self.grown(outer, by: Self.gap))
            .union(outer)

        return glyph.applying(CGAffineTransform(scaleX: s, y: s)
            .concatenating(CGAffineTransform(translationX: dx, y: dy)))
    }

    /// Bubble plus tail, before anything is taken out of it.
    ///
    /// A union rather than a second subpath: the tail is wound the other way
    /// round, and under the non-zero rule the overlap cancelled — the bubble
    /// came out with a triangular hole where the two met.
    static var body: Path {
        let bubblePath = Path(roundedRect: bubble,
                              cornerSize: CGSize(width: bubbleRadius, height: bubbleRadius),
                              style: .continuous)
        var tail = Path()
        // Starts inside the bubble, so the union leaves no seam along the join.
        tail.move(to: CGPoint(x: tailX, y: bubble.midY))
        tail.addArc(tangent1End: CGPoint(x: tailX, y: tailBottom),
                    tangent2End: CGPoint(x: tailJoin, y: bubble.maxY),
                    radius: tailRadius)
        tail.addLine(to: CGPoint(x: tailJoin, y: bubble.maxY))
        tail.closeSubpath()
        return bubblePath.union(tail)
    }

    /// Grows a shape by `d` on every side.
    ///
    /// Stroking it and taking the union is the only dilation `Path` offers, and
    /// a round join is what keeps the points of a star pointed as they grow.
    static func grown(_ p: Path, by d: CGFloat) -> Path {
        p.union(p.strokedPath(StrokeStyle(lineWidth: d * 2, lineCap: .round, lineJoin: .round)))
    }

    /// A four-pointed star: a tip at each compass point, sides cut in toward
    /// the middle, and the points rounded off.
    ///
    /// Drawn sharp at `radius - tipRounding`, then grown back out by that much,
    /// which rounds the four points and fills the sides out by the same amount —
    /// one number for a tip that reads as soft rather than cut off.
    static func sparkle(centre: CGPoint, radius: CGFloat) -> Path {
        let round = radius * tipRounding
        let r = radius - round
        let c = r * waist
        var p = Path()
        // One quadrant, east tip to north tip, then turned by 90° three times.
        // The controls sit on the axes: the side leaves each tip heading
        // straight at the middle, which is what makes it concave.
        let tip = CGPoint(x: r, y: 0)
        let c1 = CGPoint(x: c, y: 0)
        let c2 = CGPoint(x: 0, y: -c)
        func turned(_ pt: CGPoint, _ quarter: Int) -> CGPoint {
            var v = pt
            for _ in 0..<quarter { v = CGPoint(x: v.y, y: -v.x) }
            return CGPoint(x: centre.x + v.x, y: centre.y + v.y)
        }
        p.move(to: turned(tip, 0))
        for quarter in 0..<4 {
            p.addCurve(to: turned(tip, (quarter + 1) % 4),
                       control1: turned(c1, quarter),
                       control2: turned(c2, quarter))
        }
        p.closeSubpath()
        return grown(p, by: round)
    }
}

/// The mark at a given width, centred the way an SF Symbol would be.
///
/// 16 rather than the 13 the symbols beside it are set in: three of those four
/// points are the sparkle hanging off the top-right corner, so the bubble
/// itself lands at the size the one it replaces had.
struct ChatSparkleIcon: View {
    var width: CGFloat = 16

    var body: some View {
        ChatSparkleShape()
            .frame(width: width,
                   height: width * ChatSparkleShape.designSize.height
                                 / ChatSparkleShape.designSize.width)
    }
}
