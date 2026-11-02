import AppKit

/// How tall the message card's body actually is, once it has wrapped.
///
/// Its own file, away from `IslandTypes`, for two reasons. `IslandTypes` only
/// imports Foundation and is compiled by `scripts/test-island-owner.sh` against
/// a closed list of sources, so an AppKit dependency there breaks a test that
/// has nothing to do with messages. And the arithmetic that turns this into a
/// height stays where it already lives — `IslandView.messageHeight` takes the
/// one number this produces and nothing else changes hands.
///
/// Measured ahead of layout rather than reported back by the view: the island
/// builds every view at once, so a SwiftUI preference key travelling up from
/// the card would fire for cards nobody is looking at.
enum MessageBodyMetrics {
    /// What `MessageView.bodyRow` draws with — `.font(.system(size: 12))`.
    ///
    /// Made fresh each time rather than held: `NSFont` is not `Sendable`, and
    /// a stored one here would be a shared mutable global in Swift 6.
    static var font: NSFont { .systemFont(ofSize: 12) }

    /// One wrapped line, as the layout actually spaces them.
    ///
    /// `NSLayoutManager`'s number, not `ascender - descender + leading`: that
    /// sum is 14.13 at this size and TextKit lays the lines out 15 apart, and
    /// measuring one against the other turns every two-line message into a
    /// three-line card.
    static let lineHeight: CGFloat = NSLayoutManager()
        .defaultLineHeight(for: NSFont.systemFont(ofSize: 12))

    /// The two lines the card has always kept for the body, and the floor
    /// everything here is measured against.
    static let twoLines: CGFloat = lineHeight * 2

    /// The width the body wraps in: the island, less the Mochi gutter — or the
    /// card's own inset when there is no character to leave room for — and the
    /// 16 the card keeps on the right.
    static func contentWidth(hideCharacters: Bool) -> CGFloat {
        IslandConst.expandedWidth
            - IslandConst.lead(116, flush: 16, hidden: hideCharacters)
            - 16
    }

    /// How tall `body` is at `width`, rounded up to whole lines.
    ///
    /// Whole lines on purpose: `boundingRect` comes back a fraction under what
    /// the layout takes, and a card one point short clips its last row.
    static func height(_ body: String, width: CGFloat) -> CGFloat {
        guard !body.isEmpty, width > 0 else { return lineHeight }
        let measured = NSAttributedString(string: body, attributes: [.font: font])
            .boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
            .height
        return max(1, (measured / lineHeight).rounded(.up)) * lineHeight
    }

    /// How much taller than the two lines it already keeps the card has to be.
    ///
    /// Zero whenever the preference is off, which is what leaves the geometry
    /// exactly as it shipped rather than relying on every caller to ask first.
    static func overflow(_ body: String?, expanded: Bool, hideCharacters: Bool) -> CGFloat {
        guard expanded, let body, !body.isEmpty else { return 0 }
        let tall = height(body, width: contentWidth(hideCharacters: hideCharacters))
        return max(0, tall - twoLines)
    }
}
