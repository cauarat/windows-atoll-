import Foundation

@main
enum NotchSiteGeometryTests {
    static func main() {
        var cases = 0

        // Notches the app actually meets: the fallback, and real MacBooks.
        let notches: [(w: CGFloat, h: CGFloat)] = [(184, 32), (220, 38), (200, 37), (80, 24)]
        let restingPanel = CGSize(width: 720, height: 320)

        for notch in notches {
            let side  = NotchSiteGeometry.iconSide(notchHeight: notch.h)
            let frame = NotchSiteGeometry.iconFrame(panelSize: restingPanel,
                                                    notchWidth: notch.w, notchHeight: notch.h)
            cases += 1

            // The icon fits the strip it sits in, and stays big enough to hit.
            precondition(side >= 14 && side <= 22)
            precondition(side <= max(14, notch.h))

            // It is outside the compact island — the widest resting state —
            // by exactly the intended gap, so a running session never hides it.
            let compactRight = restingPanel.width / 2 + (notch.w + 160) / 2
            precondition(frame.minX - compactRight == NotchSiteGeometry.gap)

            // The island's hover region is inset by 6 pt; the icon stays clear
            // of it, or hovering the icon would peek the island open.
            precondition(frame.minX > compactRight - 6)

            // It fits inside the resting panel, which is all the panel there is
            // when the island is not showing the page.
            precondition(frame.minX >= 0 && frame.maxX <= restingPanel.width)
            precondition(frame.minY >= 0 && frame.maxY <= restingPanel.height)

            // Centred in the notch strip, top-down (AppKit counts y upward).
            let topInset = restingPanel.height - frame.maxY
            precondition(abs(topInset - (notch.h - side) / 2) < 0.001 || topInset == 2)
            precondition(topInset + side <= notch.h || notch.h < 16)
        }

        // Screens the island may hang from, with the Dock shown and hidden.
        let screens: [CGRect] = [
            CGRect(x: 0, y: 0, width: 1800, height: 1169),   // this Mac, scaled
            CGRect(x: 0, y: 0, width: 1512, height: 982),    // 14" default
            CGRect(x: 0, y: 0, width: 1728, height: 1117),   // 16" default
            CGRect(x: 0, y: 0, width: 1440, height: 900),    // small external
        ]

        for screen in screens {
            for dockTop: CGFloat in [0, 70, 94] {
                let island = NotchSiteGeometry.islandSize(screen: screen, dockTop: dockTop)
                let panel  = NotchSiteGeometry.panelSize(screen: screen, dockTop: dockTop)
                cases += 1

                // Everything stays on the screen.
                precondition(panel.width  <= screen.width)
                precondition(panel.height <= screen.height)
                precondition(island.width  <= panel.width)
                precondition(island.height <= panel.height)

                // The whole point of the view: it is big.
                precondition(island.width  >= NotchSiteGeometry.minIslandWidth)
                precondition(island.height >= NotchSiteGeometry.minIslandHeight)

                // The spring overshoots on the way open; the panel holds it, so
                // no corner is ever clipped mid-animation.
                let overshot = 1 + NotchSiteGeometry.overshoot
                precondition(island.width  * overshot <= panel.width  + 0.001)
                precondition(island.height * overshot <= panel.height + 0.001)

                // The island hangs from the screen's top edge: its bottom stops
                // above the Dock, and the panel's does too.
                precondition(screen.maxY - island.height >= dockTop)
                precondition(screen.maxY - panel.height  >= dockTop - 0.001)

                // A margin is left at the sides, so it reads as a panel.
                precondition(island.width <= screen.width - NotchSiteGeometry.sideMargin)
            }
        }

        // It really does take the screen rather than settling for a window: on
        // this Mac with the Dock hidden, four fifths of the screen in each axis.
        let full = NotchSiteGeometry.islandSize(
            screen: CGRect(x: 0, y: 0, width: 1800, height: 1169), dockTop: 0)
        precondition(full.width  > 1800 * 0.9)
        precondition(full.height > 1169 * 0.9)
        cases += 1

        // The caps are a guard for an absurd display, not a size anyone meets.
        let huge = NotchSiteGeometry.islandSize(
            screen: CGRect(x: 0, y: 0, width: 6016, height: 3384), dockTop: 0)
        precondition(huge.width  == NotchSiteGeometry.maxWidth)
        precondition(huge.height == NotchSiteGeometry.maxHeight)
        cases += 1

        print("Notch site geometry: \(cases) cases passed")
    }
}
