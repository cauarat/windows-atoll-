#if !APPSTORE
import SwiftUI

// MARK: - The Christmas folder

/// Notchy's Christmas music, as a record left in the rack beside whatever is
/// playing.
///
/// A cover tilted away behind the artwork, coverflow-fashion, so only its
/// edge shows in the gutter left of the art. It stays there whatever plays,
/// and a click brings the Christmas music back. Drawn, like everything else
/// here: a red sleeve, a green spine and a snowflake.
///
/// Laid out as the artwork's background, `gutter + artSize` wide with the art
/// over its right-hand part. The cover never takes a click — most of it is
/// under the artwork, and a button there would answer clicks meant for the
/// art. The button is the strip of gutter the cover shows in, and nothing
/// else.
struct ChristmasFolderView: View {
    @ObservedObject private var player = ChristmasMusicPlayer.shared
    @State private var hovering = false

    /// The artwork it hides behind.
    let artSize: CGFloat
    /// The space left of the artwork the folder shows in.
    let gutter: CGFloat

    private static let sleeveTop = Color(hex: "#D23A4A")
    private static let sleeveBottom = Color(hex: "#8C1626")
    private static let spine = Color(hex: "#1F7A4A")
    private static let gold = Color(hex: "#E8B64C")

    /// The cover, a little smaller than the art so its tilt stays inside it.
    private var size: CGFloat { (artSize * 0.86).rounded() }

    /// How far the cover's far edge sits from the artwork's left side.
    private var reveal: CGFloat { hovering ? gutter - 1 : gutter - 5 }

    var body: some View {
        ZStack(alignment: .leading) {
            cover
                .rotation3DEffect(.degrees(hovering ? 38 : 50),
                                  axis: (x: 0, y: 1, z: 0),
                                  anchor: .leading,
                                  perspective: 0.4)
                .frame(width: size, height: size)
                .offset(x: gutter - reveal)
                .allowsHitTesting(false)

            Button {
                ChristmasMusicPlayer.shared.play()
            } label: {
                Color.clear
                    .frame(width: gutter, height: artSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(player.isActive ? Text("Playing Notchy's Christmas music")
                                  : Text("Play Notchy's Christmas music"))
        }
        .frame(width: gutter + artSize, height: artSize, alignment: .leading)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: hovering)
    }

    private var cover: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Self.sleeveTop, Self.sleeveBottom],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: "snowflake")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
            // The spine: the part left showing, so the part that has to say
            // "Christmas" on its own. The flakes hug its outer edge — the tilt
            // squeezes the spine, and only its first few points clear the art.
            ZStack(alignment: .leading) {
                Self.spine
                VStack(spacing: size * 0.16) {
                    ForEach(0..<3, id: \.self) { _ in
                        Image(systemName: "snowflake")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.92))
                    }
                }
                .padding(.leading, 3)
            }
            .frame(width: size * 0.3)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Self.gold.opacity(player.isActive ? 0.95 : 0.4),
                        lineWidth: player.isActive ? 1.5 : 1)
        )
        .shadow(color: Self.sleeveTop.opacity(player.isActive ? 0.6 : 0), radius: 5)
    }
}
#endif
