import SwiftUI

/// The island's open and close motion, in one place.
///
/// Every dimension that grows or shrinks with the island — the window, the
/// container's width and height, its corner radius — reads these, so the whole
/// shape moves as one object rather than as several things that happen to be
/// animating nearby.
///
/// Opening springs and closing runs a curve: a spring overshoots, which reads as
/// life on the way out of the notch and as a wobble on the way back in.
///
/// Kept in step with `windows/src/core/anim.ts`, which has the same two
/// constants and integrates the same spring.
enum IslandMotion {

    /// SwiftUI spring response, seconds. Also how long the FSM waits for the
    /// open animation to land before starting a notification's hold.
    static let openResponse: Double = 0.34
    static let openDamping: Double = 0.78

    /// Close curve duration, seconds.
    static let closeDuration: Double = 0.22

    /// Growing: springs, with a little overshoot.
    static let open: Animation = .spring(response: openResponse, dampingFraction: openDamping)

    /// Shrinking: a curve, so the island settles into the notch without wobbling.
    static let close: Animation = .timingCurve(0.45, 0, 0.2, 1, duration: closeDuration)

    /// The motion for a change in this direction.
    static func forGrowing(_ growing: Bool) -> Animation { growing ? open : close }

    /// How far a change has to be before it gets the calmest spring.
    static let fullTravel: CGFloat = 400

    /// Growing, with the overshoot taken out in proportion to the distance.
    ///
    /// At damping 0.78 the open spring overshoots about 4.5 %. Over the 16 pt a
    /// card grows nobody sees it; over the 490 pt to a full screen it is a 20 pt
    /// bounce of the top of the display, at speed. At zero travel this is the
    /// shipping spring exactly, so nothing that exists today moves.
    static func grow(travel d: CGFloat) -> Animation {
        let t = Double(min(1, abs(d) / fullTravel))
        return .spring(response: openResponse + 0.16 * t,
                       dampingFraction: min(0.96, openDamping + 0.18 * t))
    }
}
