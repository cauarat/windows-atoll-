import CoreGraphics
import Foundation

/// The wheel's arithmetic: which wedge the pointer is in, and where the wheel
/// can sit so all of it stays on screen.
///
/// Angles are in the screen's own convention, where y grows upward — the same
/// space `NSEvent.mouseLocation` reports in. Wedge 0 is centred straight up and
/// they run clockwise from there, which is how they are drawn.
enum RadialGeometry {

    static let outerRadius: CGFloat = 110
    /// Inside this, no wedge is chosen. A chord with no movement commits to
    /// nothing, so opening the wheel and letting go is never an accident.
    static let innerRadius: CGFloat = 34
    /// Room for the shadow, so the panel does not clip it.
    static let shadowPad: CGFloat = 24

    static var panelSide: CGFloat { (outerRadius + shadowPad) * 2 }

    /// How many wedges are worth having.
    ///
    /// Below two there is no choice to make; above eight each is under 45° and
    /// a flick starts picking the neighbour.
    static let minWedges = 2
    static let maxWedges = 8

    /// The wedge a pointer offset falls in, or nil inside the dead zone.
    ///
    /// Deliberately unbounded outwards: once past the dead zone the wedge stays
    /// chosen however far the pointer goes, or a fast flick — which is how a
    /// radial menu is meant to be used — would let go of it again.
    static func wedge(dx: CGFloat, dy: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard hypot(dx, dy) > innerRadius else { return nil }
        let a = atan2(dy, dx)
        let step = 2 * .pi / CGFloat(count)
        // Measured from straight up, clockwise.
        var t = (.pi / 2 - a).truncatingRemainder(dividingBy: 2 * .pi)
        if t < 0 { t += 2 * .pi }
        return Int((t + step / 2) / step) % count
    }

    /// The centre of wedge `i`, as an angle in the same convention.
    static func angle(of i: Int, count: Int) -> CGFloat {
        guard count > 0 else { return .pi / 2 }
        return .pi / 2 - CGFloat(i) * (2 * .pi / CGFloat(count))
    }

    /// Where the wheel can be centred so none of it leaves the screen.
    ///
    /// The centre moves, not the window. Clamping the window while keeping the
    /// wheel on the pointer would push wedges off the edge; moving the centre
    /// leaves the pointer off-centre inside the wheel instead, and since the
    /// angle is measured from the centre, aiming still works.
    static func center(for pointer: CGPoint, on screen: CGRect) -> CGPoint {
        let inset = outerRadius + 12
        let safe = screen.insetBy(dx: min(inset, screen.width / 2 - 1),
                                  dy: min(inset, screen.height / 2 - 1))
        return CGPoint(x: min(max(pointer.x, safe.minX), safe.maxX),
                       y: min(max(pointer.y, safe.minY), safe.maxY))
    }
}
