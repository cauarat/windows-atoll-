import SwiftUI

/// Ato's mark: the indigo blob with two happy eyes that the inbox itself
/// wears. Drawn rather than shipped, like ``ClickMassaLogo`` and
/// ``MattermostLogo``, so `Assets.xcassets` holds only the app's own icons.
///
/// One shape with nothing to drop, so it draws the same at every size.
struct AtoLogo: View {
    let side: CGFloat

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - s) / 2, y: (size.height - s) / 2)

            // A soft, slightly lumpy round body — a superellipse reads as the
            // blob at pill size where the real wobble would be lost.
            let body = Path(roundedRect: CGRect(x: origin.x, y: origin.y, width: s, height: s),
                            cornerRadius: s * 0.42, style: .continuous)
            context.fill(body, with: .color(Color(hex: MessageSource.ato.accentHex)))

            // The eyes: two upturned arcs, "^ ^".
            let stroke = StrokeStyle(lineWidth: max(1, s * 0.09), lineCap: .round)
            for x in [0.34, 0.66] {
                var eye = Path()
                let centre = CGPoint(x: origin.x + s * x, y: origin.y + s * 0.52)
                eye.addArc(center: centre, radius: s * 0.1,
                           startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
                context.stroke(eye, with: .color(.white), style: stroke)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
