import CoreGraphics
import Foundation

/// Where a button hangs off the island.
enum IslandEdgeSide: String, Codable, CaseIterable, Sendable {
    case left, right, bottom
}

/// One button on the island's border.
///
/// `action` is an opaque id resolved by the view layer — a pill id, a view name
/// or a command. Keeping it a string is what lets this whole file stay free of
/// SwiftUI, so the geometry below can be compiled and asserted headlessly. That
/// matters more here than anywhere else in the app: these rectangles decide
/// what the pointer can click on a transparent panel covering the top of the
/// screen, and getting them wrong makes part of the display unclickable.
struct IslandEdgeButton: Codable, Equatable, Identifiable, Sendable {
    var action: String
    var side: IslandEdgeSide

    var id: String { "\(side.rawValue):\(action)" }

    init(_ action: String, _ side: IslandEdgeSide) {
        self.action = action
        self.side = side
    }
}

/// Where the buttons sit, and what the pointer can therefore hit.
///
/// Everything is in island-local coordinates: the origin is the island's
/// top-left corner and y grows downward, as in SwiftUI. The one caller that
/// needs AppKit's y-up panel space converts once, in `chromeFrame`.
enum IslandEdgeLayout {
    static let diameter: CGFloat = 34
    /// Clear air between the island's edge and a button.
    static let gap: CGFloat = 10
    /// Between two buttons on the same side.
    static let spacing: CGFloat = 8

    /// How far a run of `count` buttons reaches along its side.
    static func span(_ count: Int) -> CGFloat {
        count <= 0 ? 0 : CGFloat(count) * diameter + CGFloat(count - 1) * spacing
    }

    /// The buttons on one side, in the order they were given.
    static func buttons(_ all: [IslandEdgeButton], on side: IslandEdgeSide) -> [IslandEdgeButton] {
        all.filter { $0.side == side }
    }

    /// Centre of button `index` of `count` on `side`.
    ///
    /// Side buttons stack down the island's middle; bottom buttons spread
    /// across it. A run longer than the island simply overhangs — the island is
    /// 32 pt tall when it is resting, and two buttons are 76, so this is the
    /// normal case rather than an edge case.
    static func center(side: IslandEdgeSide, index: Int, count: Int,
                       islandWidth w: CGFloat, islandHeight h: CGFloat) -> CGPoint {
        let step = diameter + spacing
        let offset = (CGFloat(index) - CGFloat(count - 1) / 2) * step
        switch side {
        case .left:   return CGPoint(x: -(gap + diameter / 2), y: h / 2 + offset)
        case .right:  return CGPoint(x: w + gap + diameter / 2, y: h / 2 + offset)
        case .bottom: return CGPoint(x: w / 2 + offset, y: h + gap + diameter / 2)
        }
    }

    /// Every button's rect, island-local.
    static func rects(_ all: [IslandEdgeButton],
                      islandWidth w: CGFloat, islandHeight h: CGFloat) -> [CGRect] {
        var out: [CGRect] = []
        for side in IslandEdgeSide.allCases {
            let side_ = buttons(all, on: side)
            for (i, _) in side_.enumerated() {
                let c = center(side: side, index: i, count: side_.count, islandWidth: w, islandHeight: h)
                out.append(CGRect(x: c.x - diameter / 2, y: c.y - diameter / 2,
                                  width: diameter, height: diameter))
            }
        }
        return out
    }

    /// The island plus its buttons, island-local. `(0, 0, w, h)` when there are
    /// none, so an island with no buttons behaves exactly as it does today.
    static func chromeBounds(_ all: [IslandEdgeButton],
                             islandWidth w: CGFloat, islandHeight h: CGFloat) -> CGRect {
        let island = CGRect(x: 0, y: 0, width: w, height: h)
        return rects(all, islandWidth: w, islandHeight: h).reduce(island) { $0.union($1) }
    }

    /// The same thing in the panel's own coordinates, where y grows upward.
    ///
    /// `islandFrame` is the island as the panel sees it. A button below the
    /// island in island-local space is below it on screen too, which in a y-up
    /// space means a *smaller* y — hence the flip rather than a straight offset.
    static func chromeFrame(islandFrame: CGRect, buttons: [IslandEdgeButton]) -> CGRect {
        guard !buttons.isEmpty else { return islandFrame }
        let b = chromeBounds(buttons, islandWidth: islandFrame.width, islandHeight: islandFrame.height)
        return CGRect(
            x: islandFrame.minX + b.minX,
            y: islandFrame.maxY - b.maxY,
            width: b.width,
            height: b.height
        )
    }

    /// The buttons that are actually on screen.
    ///
    /// They belong to the open island, not to the notch: around a resting bar
    /// they would float in the menu bar with nothing to be attached to. One
    /// function rather than a check in each place, because the drawing and the
    /// click-through have to agree exactly — a button drawn with no clickable
    /// area does nothing, and a clickable area with no button steals clicks
    /// from whatever is behind it.
    static func visible(_ all: [IslandEdgeButton], expanded: Bool) -> [IslandEdgeButton] {
        expanded ? all : []
    }

    /// What a fresh install starts with: the pills the user already chose,
    /// split between the two sides, and nothing underneath.
    static func defaults(pills: [String]) -> [IslandEdgeButton] {
        pills.enumerated().map { i, id in
            IslandEdgeButton(id, i.isMultiple(of: 2) ? .left : .right)
        }
    }
}
