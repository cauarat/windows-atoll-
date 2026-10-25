import Foundation

@main
enum IslandScreenGeometryTests {
    static func main() {
        // Regression: absent auxiliary areas must never mean "screen-wide notch".
        for screenWidth: CGFloat in [1080, 1920, 2560, 3840] {
            let geometry = IslandScreenGeometry(
                screenWidth: screenWidth, safeAreaTop: 0,
                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 30
            )
            precondition(!geometry.hasNotch)
            precondition(geometry.width == 80)
            precondition(geometry.height == 24)
        }

        // A shorter menu bar must also contain the resting island.
        let shortMenuBar = IslandScreenGeometry(
            screenWidth: 1920, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 22
        )
        precondition(shortMenuBar.height == 22)

        // Real MacBook notch measurements retain their physical dimensions.
        let macBook = IslandScreenGeometry(
            screenWidth: 1512, safeAreaTop: 32,
            auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32
        )
        precondition(macBook.hasNotch)
        precondition(macBook.width == 192 && macBook.height == 32)

        // Incomplete or invalid measurements use the notch fallback, not the screen.
        for auxiliaryWidth: CGFloat? in [nil, 0, 1000] {
            let geometry = IslandScreenGeometry(
                screenWidth: 1512, safeAreaTop: 32,
                auxiliaryLeftWidth: auxiliaryWidth, auxiliaryRightWidth: auxiliaryWidth,
                menuBarHeight: 32
            )
            precondition(geometry.width == 184 && geometry.height == 32)
        }
        // Compact/greeting destinations share the measured resting height.
        for height: CGFloat in [22, 24, 32, 38] {
            let compact = IslandRestingLayout(width: 240, height: height)
            precondition(compact.botCenterY == height / 2)
            precondition(compact.botDiameter == min(20, height - 6))
            precondition(compact.botCenterY - compact.botDiameter / 2 >= 3)
            precondition(compact.botCenterY + compact.botDiameter / 2 <= height - 3)
            precondition(compact.miniGridCenterX == 200)
            precondition(compact.miniGridScale * 28 <= height - 4)
        }
        // ── Chosen heights ──────────────────────────────────────────────────
        //
        // The measured 80 × 24 bar on a screen without a notch is a small thing
        // to find with a pointer. These let it be raised, per kind of screen.

        // A notched screen: the cutout is physical, so only the height moves.
        let tallNotch = IslandScreenGeometry(
            screenWidth: 1512, safeAreaTop: 32,
            auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32,
            notchHeightOverride: 48
        )
        precondition(tallNotch.hasNotch)
        precondition(tallNotch.height == 48)
        precondition(tallNotch.width == 192, "the cutout's width is not anyone's to change")

        // Never shorter than the cutout, or the notch shows above the island.
        let tooShort = IslandScreenGeometry(
            screenWidth: 1512, safeAreaTop: 32,
            auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32,
            notchHeightOverride: 10
        )
        precondition(tooShort.height == 32)

        // A screen without one: the width goes up with the height, so the bar
        // keeps its proportions instead of stretching into a sliver.
        let tallPlain = IslandScreenGeometry(
            screenWidth: 2560, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24,
            plainHeightOverride: 48
        )
        precondition(!tallPlain.hasNotch)
        precondition(tallPlain.height == 48)
        precondition(tallPlain.width == 160, "80 × 48/24")

        // A chosen height is allowed to exceed the menu bar — that is the point.
        let overMenuBar = IslandScreenGeometry(
            screenWidth: 2560, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 22,
            plainHeightOverride: 40
        )
        precondition(overMenuBar.height == 40)

        // Each override only touches its own kind of screen.
        let notchWithPlainOverride = IslandScreenGeometry(
            screenWidth: 1512, safeAreaTop: 32,
            auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32,
            plainHeightOverride: 60
        )
        precondition(notchWithPlainOverride.height == 32)
        let plainWithNotchOverride = IslandScreenGeometry(
            screenWidth: 2560, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24,
            notchHeightOverride: 60
        )
        precondition(plainWithNotchOverride.height == 24 && plainWithNotchOverride.width == 80)

        // Mochi still fits the bar at every height the sliders offer, and keeps
        // 3 pt of air above and below.
        for height: CGFloat in stride(from: 22, through: 60, by: 2) {
            let layout = IslandRestingLayout(width: 80 * height / 24, height: height)
            precondition(layout.botDiameter > 0)
            precondition(layout.botCenterY - layout.botDiameter / 2 >= 3)
            precondition(layout.botCenterY + layout.botDiameter / 2 <= height - 3)
        }

        // She only grows once the bar is taller than any Mac measures, so every
        // height that ships today draws exactly what it drew before.
        for height: CGFloat in stride(from: 0, through: 38, by: 1) {
            let layout = IslandRestingLayout(width: 240, height: height)
            precondition(layout.botDiameter == min(20, max(0, height - 6)),
                         "a measured bar must not change size")
        }
        precondition(IslandRestingLayout(width: 240, height: 48).botDiameter == 30,
                     "a chosen bar gives Mochi room")

        // Equality is what makes SwiftUI redraw: the geometry is published, and
        // a value that compares equal to the last one changes nothing on screen.
        // This is the whole reason the height sliders used to do nothing.
        func geometry(plain: CGFloat?) -> IslandScreenGeometry {
            IslandScreenGeometry(
                screenWidth: 1920, safeAreaTop: 0,
                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24,
                plainHeightOverride: plain
            )
        }
        precondition(geometry(plain: nil) == geometry(plain: nil),
                     "the same screen must compare equal, or it would redraw every frame")
        precondition(geometry(plain: 40) != geometry(plain: nil),
                     "a chosen height must compare different, or nothing redraws")
        precondition(geometry(plain: 40) != geometry(plain: 42),
                     "every step of the slider must be a new value")

        // Moving between two screens that measure differently is the other case
        // that has to be visible to SwiftUI.
        let notched = IslandScreenGeometry(
            screenWidth: 1512, safeAreaTop: 32,
            auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32
        )
        precondition(notched != geometry(plain: nil),
                     "a notched screen and a plain one must not look the same")

        print("Island screen geometry and resting layout: all cases passed")
    }
}
