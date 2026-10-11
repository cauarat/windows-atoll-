import SwiftUI

/// A pill that wears its own mark instead of borrowing an SF Symbol.
///
/// The rule in `PillDefinition.icon` still stands -- no bitmaps, and no helping
/// yourself to twenty trademarks. These are the exceptions, added on request,
/// and each is drawn rather than shipped so `Assets.xcassets` goes on holding
/// nothing but the app's own icons.
enum PillLogo {
    case clickMassa
    case mattermost
}

/// How much of a mark is worth drawing at the size it is going to.
///
/// Not every mark has a simpler form. Mattermost's is one shape with nothing to
/// drop, so it draws the same either way; the level is a request, not a promise.
enum PillLogoDetail {
    /// The mark as it is published.
    case full
    /// Only the part that carries the identity, refitted to fill its box.
    case simplified
}

extension PillLogo {
    /// The mark, square, `side` points on a side.
    ///
    /// A mark that follows the surrounding appearance reads it from the
    /// environment, so a caller drawing onto a surface darker than the window
    /// -- the island's buttons are always near-black, whatever the system is
    /// set to -- should say so with `.environment(\.colorScheme, .dark)`.
    @ViewBuilder
    func view(side: CGFloat, detail: PillLogoDetail) -> some View {
        switch self {
        case .clickMassa: ClickMassaLogo(side: side, detail: detail)
        case .mattermost: MattermostLogo(side: side)
        }
    }
}
