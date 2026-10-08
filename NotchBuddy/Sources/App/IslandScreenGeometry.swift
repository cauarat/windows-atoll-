import Foundation

/// Resting island dimensions, using a physical notch only when the screen has one.
struct IslandScreenGeometry {
    static let fallbackNotchWidth: CGFloat = 184
    private static let noNotchWidth: CGFloat = 80
    private static let noNotchHeight: CGFloat = 24

    let hasNotch: Bool
    let width: CGFloat
    let height: CGFloat

    /// `notchHeightOverride` and `plainHeightOverride` are the user's chosen
    /// resting heights, in points, or nil to measure the screen as before.
    ///
    /// They are separate because the two cases are not the same problem. On a
    /// notched screen the bar hangs below a fixed physical cutout, so only its
    /// height is anyone's to choose. On a screen without one there is nothing to
    /// match, and the measured 80 × 24 is a small thing to find with a pointer —
    /// which is why the height is worth raising and why the width goes up with
    /// it, keeping the resting bar's proportions rather than stretching it.
    init(screenWidth: CGFloat, safeAreaTop: CGFloat,
         auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?,
         menuBarHeight: CGFloat,
         notchHeightOverride: CGFloat? = nil,
         plainHeightOverride: CGFloat? = nil) {
        hasNotch = safeAreaTop > 0
        if hasNotch {
            if let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
                let measuredWidth = screenWidth - left - right
                width = measuredWidth > 0 && measuredWidth < screenWidth
                    ? measuredWidth : Self.fallbackNotchWidth
            } else {
                width = Self.fallbackNotchWidth
            }
            // Never shorter than the cutout, or the notch would show above it.
            height = max(safeAreaTop, notchHeightOverride ?? safeAreaTop)
        } else {
            let measured = min(Self.noNotchHeight, menuBarHeight)
            height = plainHeightOverride ?? measured
            // At the measured height this is exactly the 80 pt it always was.
            width = Self.noNotchWidth * (height / Self.noNotchHeight)
        }
    }
}

/// Shared by the compact view and the greeting's collapse destination.
struct IslandRestingLayout {
    let width: CGFloat
    let height: CGFloat

    /// 20 pt in a measured bar, as it has always been, and bigger only once the
    /// bar is taller than any Mac actually measures — a chosen height. Below
    /// 38 pt this is exactly `min(20, height - 6)`, so nothing that ships moves.
    var botDiameter: CGFloat { min(max(20, height - 18), max(0, height - 6)) }
    var botCenterY: CGFloat { height / 2 }
    var miniGridScale: CGFloat { min(1, max(0, height - 4) / 28) }
    var miniGridCenterX: CGFloat { width - 40 }
}
