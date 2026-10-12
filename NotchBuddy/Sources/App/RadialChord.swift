import CoreGraphics
import Foundation

/// Deciding whether both mouse buttons were pressed together.
///
/// Pure, and separated from the event tap on purpose: the tap runs inside a
/// callback that must return synchronously on its own thread, and a mistake
/// there swallows real clicks and makes the whole Mac feel broken. Everything
/// that could be wrong about the *decision* is in here, where it can be put
/// through its paces with no permission, no tap and no mouse.
///
/// The shape of the problem: a chord has to be recognised from its second
/// button, but by then the first has already happened. So the first is held
/// back briefly and either swallowed (it was a chord) or let go late (it was
/// not). Only the **right** button is ever delayed — a context menu arriving
/// 60 ms late is imperceptible, where 60 ms on every left click would be felt
/// in drags, in text selection and in games.
enum RadialButton: Equatable, Sendable { case left, right }

enum ChordInput: Equatable {
    case down(RadialButton, at: CGPoint, t: Double)
    case up(RadialButton, at: CGPoint, t: Double)
    case dragged(RadialButton, at: CGPoint, t: Double)
    /// The hold timer expiring. Carries the clock so the machine never reads it.
    case tick(t: Double)
}

enum ChordOutput: Equatable {
    /// Let the event reach whatever is under the pointer.
    case passThrough
    /// Swallow it for now, and start the timer. Only ever a right-button down.
    case hold
    /// Swallow it outright.
    case swallow
    /// It was not a chord: re-post the right-down that was held back, in order.
    case flushHeld
    /// Synthesize a mouse-up, so a click the app already started is completed
    /// rather than left hanging.
    case release(RadialButton, at: CGPoint)
    /// Open the wheel here.
    case fire(at: CGPoint)
}

/// The chord recogniser.
struct RadialChordMachine {
    /// How close together the two presses have to be.
    var window: Double = 0.060
    /// And how close together on screen. This is the strong test, not the time:
    /// a right-click followed by clicking the menu it opened is far apart in
    /// both, but a slow chord is only far apart in time.
    var slop: CGFloat = 6

    private enum State: Equatable {
        case idle
        /// A right-down is being held back, pending a left.
        case heldRight(at: CGPoint, t: Double)
        /// A right-down was let through late; it is still physically down.
        case rightLive
        /// A left-down went through, as they always do.
        case leftLive(at: CGPoint, t: Double)
        /// The wheel is open and both buttons belong to it.
        case firing(left: Bool, right: Bool)
    }

    private var state: State = .idle

    /// True while a right-down is held back and the timer should be running.
    var isHolding: Bool { if case .heldRight = state { return true }; return false }

    private func together(_ a: CGPoint, _ b: CGPoint, _ t0: Double, _ t1: Double) -> Bool {
        t1 - t0 <= window && hypot(a.x - b.x, a.y - b.y) <= slop
    }

    mutating func step(_ input: ChordInput) -> [ChordOutput] {
        switch (state, input) {

        // ── A right-down starts the window, held back so a chord can swallow it.
        case (.idle, .down(.right, let p, let t)):
            state = .heldRight(at: p, t: t)
            return [.hold]

        // ── The second half of a chord, right first.
        case (.heldRight(let p0, let t0), .down(.left, let p, let t))
            where together(p0, p, t0, t):
            state = .firing(left: true, right: true)
            // The held right-down is simply dropped: nothing underneath ever
            // saw it, so there is nothing to undo.
            return [.swallow, .fire(at: p)]

        // ── The window closed, or the press turned into something else.
        case (.heldRight, .tick(let t)):
            if case .heldRight(_, let t0) = state, t - t0 < window { return [] }
            state = .rightLive
            return [.flushHeld]
        case (.heldRight, .up(.right, _, _)):
            state = .idle
            return [.flushHeld, .passThrough]
        case (.heldRight, .dragged(.right, _, _)):
            state = .rightLive
            return [.flushHeld, .passThrough]
        // A left press while a right is held but too far or too late: let both
        // through, right first, so the app sees them in the order they happened.
        case (.heldRight, .down(.left, _, _)):
            state = .rightLive
            return [.flushHeld, .passThrough]

        // ── A left-down is never delayed.
        case (.idle, .down(.left, let p, let t)):
            state = .leftLive(at: p, t: t)
            return [.passThrough]

        // ── The second half of a chord, left first.
        case (.leftLive(let p0, let t0), .down(.right, let p, let t))
            where together(p0, p, t0, t):
            state = .firing(left: true, right: true)
            // The left-down already reached the app, so end its click rather
            // than leaving a button down forever.
            return [.swallow, .release(.left, at: p0), .fire(at: p)]

        case (.leftLive, .up(.left, _, _)):
            state = .idle
            return [.passThrough]
        case (.leftLive, .down(.right, let p, let t)):
            state = .heldRight(at: p, t: t)
            return [.hold]

        case (.rightLive, .up(.right, _, _)):
            state = .idle
            return [.passThrough]

        // ── While the wheel is open both buttons are its own.
        case (.firing(let l, let r), .up(let b, _, _)):
            let left = b == .left ? false : l
            let right = b == .right ? false : r
            state = (left || right) ? .firing(left: left, right: right) : .idle
            return [.swallow]
        case (.firing, .down), (.firing, .dragged):
            return [.swallow]
        case (.firing, .tick):
            return []

        // ── Anything else is somebody else's event.
        default:
            return [.passThrough]
        }
    }

    /// Forget everything and let events through.
    ///
    /// The tap calls this whenever its own idea of what is pressed disagrees
    /// with the system's. A machine that believes a button is down while it is
    /// not would swallow every click that followed, and there would be no way
    /// to click anything to fix it.
    mutating func reset() { state = .idle }
}
