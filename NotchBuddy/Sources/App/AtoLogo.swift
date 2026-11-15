import SwiftUI

/// Ato's mark: a still of Ato's own mascot — the orange, cyan and blue orb
/// with two white dot eyes — drawn by the same port of Actuar's engine that
/// animates it (`AtoBot`), at rest, eyes open. Drawn rather than shipped, like
/// ``MattermostLogo``, so `Assets.xcassets` holds only the app's own icons.
///
/// One picture with nothing to drop, so it draws the same at every size.
struct AtoLogo: View {
    let side: CGFloat

    /// At rest, as the original's `poseAt` draws a still.
    private static let scene = AtoBot.scene(AtoBot.poseAt(.idle, 0))

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            // The layers wobble out to 107 % of the orb's radius and the
            // turned ones a little past it: 110 keeps every lobe in the box.
            AtoBotRenderer.draw(Self.scene, in: context,
                                center: CGPoint(x: size.width / 2, y: size.height / 2),
                                unit: s / 220)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
