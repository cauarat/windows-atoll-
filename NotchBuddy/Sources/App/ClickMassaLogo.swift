import SwiftUI

// MARK: - What the catalog refers to

/// A pill that wears its own mark instead of borrowing an SF Symbol.
///
/// Declared here rather than beside `PillDefinition` so this file still
/// compiles on its own against a throwaway render harness. The ratios further
/// down are the only record of the artwork there is -- no copy of it ships in
/// this repository -- so being able to check them without building the whole
/// app is worth more than keeping every pill-ish type in one file.
enum PillLogo {
    case clickMassa
}

/// How much of a mark is worth drawing at the size it is going to.
enum PillLogoDetail {
    /// The mark as it is published.
    case full
    /// Only the part that carries the identity, refitted to fill its box.
    case simplified
}

extension PillLogo {
    /// The mark, square, `side` points on a side.
    @ViewBuilder
    func view(side: CGFloat, detail: PillLogoDetail) -> some View {
        switch self {
        case .clickMassa: ClickMassaLogo(side: side, detail: detail)
        }
    }
}

// MARK: - The parts

/// One of the mark's speech bubbles: a square with three corners rounded the
/// whole way to a half-circle and the fourth left nearly square, which is the
/// tail.
///
/// Measuring the artwork is what turned this into a rounded square rather than
/// a circle with a nub stuck on the side. The bubble's left edge is flat for a
/// third of its height and its bottom edge is flat for half its width; those
/// are the two tangents of the circle it appears to be, and the tail is simply
/// where they meet. Built that way it stays exact at any size, and there is no
/// seam to go wrong, because it is one contour rather than two shapes unioned.
///
/// One shape serves both bubbles -- the blue one's tail is at the bottom left,
/// the white one's at the bottom right -- so the two cannot drift apart.
struct ClickMassaBubble: Shape {
    /// Which bottom corner stays square and becomes the tail.
    var tailOnLeft: Bool

    /// The tail corner's radius as a fraction of the side. Measured at roughly
    /// 11 px on a 170 px bubble: eased just enough not to be a sharp point.
    static let tailRadius: CGFloat = 0.065

    func path(in rect: CGRect) -> Path {
        let side  = min(rect.width, rect.height)
        let round = side / 2                // the three corners: a half-circle
        let tail  = side * Self.tailRadius  // the fourth
        return UnevenRoundedRectangle(
            topLeadingRadius:     round,
            bottomLeadingRadius:  tailOnLeft ? tail  : round,
            bottomTrailingRadius: tailOnLeft ? round : tail,
            topTrailingRadius:    round,
            style: .circular
        ).path(in: CGRect(x: rect.midX - round, y: rect.midY - round,
                          width: side, height: side))
    }
}

/// The smile across the blue bubble's lower half.
///
/// A plain circular arc, so its curvature does not vary along its length and
/// the round caps land on its tangents. A quad curve through the same three
/// points is tighter in the middle, which is invisible at 128 pt and reads as
/// lopsided once the whole arc is a few points wide.
struct ClickMassaSmile: Shape {
    // Measured off the artwork, as fractions of the bubble's side. These
    // describe the arc's centreline, not the ink: the round caps push the
    // painted mark about half a stroke past each end, so measuring the shape
    // you can see and using it directly gives an arc too wide and too flat.
    // Taking the caps back off the artwork's 70x18 px smile leaves a 60 px
    // chord with an 8 px rise, which is what these come from.
    static let centre = CGPoint(x: 0.471, y: 0.407)
    static let radius: CGFloat = 0.354
    static let stroke: CGFloat = 0.053
    static let from = Angle.degrees(60)
    static let to   = Angle.degrees(120)

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        var p = Path()
        p.addArc(center: CGPoint(x: rect.minX + side * Self.centre.x,
                                 y: rect.minY + side * Self.centre.y),
                 radius: side * Self.radius,
                 startAngle: Self.from, endAngle: Self.to, clockwise: false)
        return p
    }
}

// MARK: - The mark

/// ClickMassa's mark: two overlapping speech bubbles, a white one behind and up
/// to the right, a blue one in front and down to the left carrying a white
/// smile.
///
/// Drawn rather than shipped as an image, the way the site mark beside the
/// notch already is, so it stays sharp at any size and `Assets.xcassets` goes
/// on holding nothing but the app's own two icons.
///
/// Every ratio here was measured off the published artwork. That artwork is not
/// in this repository, so these numbers are the only record of it: change them
/// against the real thing, not against how the result looks.
struct ClickMassaLogo: View {
    var side: CGFloat
    var detail: PillLogoDetail = .full

    /// The mark's own colours, written out rather than read from the pill. This
    /// is artwork, not a tint: if the pill's colour is ever nudged for contrast
    /// against the island, the logo must not quietly follow it and turn into
    /// ClickMassa's logo in the wrong blue. The same value as the pill's and
    /// `MessageSource.clickMassa.accentHex` today, and deliberately separate.
    private static let blue  = Color(hex: "#41BFEF")
    private static let white = Color(hex: "#FFFFFF")

    /// Where the white bubble sits relative to the blue one, in units of a
    /// bubble's side. Measured: the two bubbles are the same size, and the
    /// white one is up and to the right.
    private static let backOffset = CGSize(width: 0.315, height: -0.135)

    /// So the whole mark is this much wider and taller than one bubble.
    private static let fullWidth:  CGFloat = 1 + backOffset.width   // 1.315
    private static let fullHeight: CGFloat = 1 - backOffset.height  // 1.135

    /// A bubble's side.
    ///
    /// `.simplified` hands the entire box to the blue bubble, which is the
    /// whole point of it: with the white one gone the survivor is refitted
    /// rather than left stranded in the corner of the frame it used to share,
    /// and the smile wins back about a quarter of its length -- which is the
    /// difference between reading as the mark and reading as a blue blob.
    private var bubble: CGFloat {
        detail == .full ? side / Self.fullWidth : side
    }

    var body: some View {
        let b = bubble
        // `.full` is wider than it is tall, so it is centred in its square box.
        let inset  = detail == .full ? (side - b * Self.fullHeight) / 2 : 0
        let frontY = detail == .full ? inset - b * Self.backOffset.height : 0

        ZStack(alignment: .topLeading) {
            if detail == .full {
                ClickMassaBubble(tailOnLeft: false)
                    .fill(Self.white)
                    .frame(width: b, height: b)
                    .offset(x: b * Self.backOffset.width, y: inset)
            }
            ZStack {
                ClickMassaBubble(tailOnLeft: true).fill(Self.blue)
                ClickMassaSmile()
                    .stroke(Self.white,
                            style: StrokeStyle(
                                // A floor, or the smile vanishes on the island's
                                // 34 pt buttons -- the one place it matters most.
                                lineWidth: max(1, b * ClickMassaSmile.stroke),
                                lineCap: .round))
            }
            .frame(width: b, height: b)
            .offset(x: 0, y: frontY)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        // The mark never mirrors: leading and trailing would swap the tails in
        // a right-to-left locale, and a mirrored logo is the wrong logo.
        .environment(\.layoutDirection, .leftToRight)
    }
}
