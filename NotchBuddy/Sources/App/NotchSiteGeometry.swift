import CoreGraphics

/// Where the site's icon sits beside the notch, and how much of the screen the
/// island takes while the page is up.
///
/// Plain numbers and no AppKit, the way `IslandScreenGeometry` is built: the
/// answers are the same whether they come from a real screen or from a test.
struct NotchSiteGeometry {

    /// Space between the compact island's edge and the icon.
    static let gap: CGFloat = 12
    /// Must match `IslandConst.expandedWidth` — the narrowest the island opens.
    static let minIslandWidth:  CGFloat = 640
    static let minIslandHeight: CGFloat = 320

    static let sideMargin:   CGFloat = 20
    static let bottomMargin: CGFloat = 14
    /// Only a guard against an absurd external display — a MacBook never hits it.
    static let maxWidth:  CGFloat = 2000
    static let maxHeight: CGFloat = 1300
    /// The opening spring passes its target by about 4 % of the distance it
    /// travels before settling back onto it.
    static let overshoot: CGFloat = 0.04

    // MARK: Icon

    /// Big enough to read, never taller than the strip it sits in.
    static func iconSide(notchHeight: CGFloat) -> CGFloat {
        min(22, max(14, notchHeight - 10))
    }

    /// Distance from the panel's horizontal centre to the icon's centre. It
    /// clears the compact island — the widest resting state — so a running
    /// session never covers the icon.
    static func iconCenterOffsetX(notchWidth: CGFloat, notchHeight: CGFloat) -> CGFloat {
        (notchWidth + 160) / 2 + gap + iconSide(notchHeight: notchHeight) / 2
    }

    /// Distance from the panel's top edge to the icon's top edge.
    static func iconTopInset(notchHeight: CGFloat) -> CGFloat {
        max(2, (notchHeight - iconSide(notchHeight: notchHeight)) / 2)
    }

    /// The icon's rect in panel coordinates (AppKit: y grows upward). The 60 Hz
    /// loop needs it to stop being click-through over the icon, which sits
    /// outside every rect the island itself reports.
    static func iconFrame(panelSize: CGSize,
                          notchWidth: CGFloat, notchHeight: CGFloat) -> CGRect {
        let side = iconSide(notchHeight: notchHeight)
        let cx   = panelSize.width / 2
                 + iconCenterOffsetX(notchWidth: notchWidth, notchHeight: notchHeight)
        let top  = iconTopInset(notchHeight: notchHeight)
        return CGRect(x: cx - side / 2, y: panelSize.height - top - side,
                      width: side, height: side)
    }

    // MARK: Island and panel while the page is up

    /// As wide and as tall as the screen allows: a web page needs the room, and
    /// this is the one view the user opened on purpose.
    ///
    /// - Parameter dockTop: the top of the Dock, or the screen's bottom when it
    ///   is hidden — `NSScreen.visibleFrame.minY`. The island stops above it.
    static func islandSize(screen: CGRect, dockTop: CGFloat) -> CGSize {
        let availableW = screen.width - sideMargin * 2
        let availableH = screen.maxY - max(dockTop, screen.minY) - bottomMargin
        // Hold back the room the spring overshoots into, so no corner is ever
        // clipped against the panel on the way open.
        return CGSize(
            width:  min(maxWidth,  max(minIslandWidth,  availableW / (1 + overshoot))),
            height: min(maxHeight, max(minIslandHeight, availableH / (1 + overshoot)))
        )
    }

    /// The panel has to hold the island plus whatever the spring overshoots.
    static func panelSize(screen: CGRect, dockTop: CGFloat) -> CGSize {
        let island = islandSize(screen: screen, dockTop: dockTop)
        return CGSize(width:  min(screen.width,  island.width  * (1 + overshoot)),
                      height: min(screen.height, island.height * (1 + overshoot)))
    }
}
