#if !APPSTORE
import SwiftUI

// MARK: - The Christmas album

/// Notchy's Christmas music, as an album waiting on the left of the player.
///
/// It only shows while something else is on the card. Christmas playing is the
/// album in the main view, with nothing beside it; anything else playing sends
/// it out of the main view to this slot, where a click opens it again — it
/// slides back into the artwork and the Christmas music picks up where it
/// stopped.
///
/// Its own slot in the row, with the card's usual gap before the artwork, so
/// it can never be mistaken for part of the cover — the first version tucked
/// it under the art and the two read as one. Coverflow-tilted towards the art
/// it would replace, the album's real cover once it has loaded and a drawn
/// red sleeve until then, with a snowflake on the corner where the main art
/// carries the app it comes from.
struct ChristmasAlbumView: View {
    @ObservedObject private var player = ChristmasMusicPlayer.shared
    @State private var hovering = false

    /// The width the slot takes in the row.
    static let width: CGFloat = 52
    /// The artwork it stands beside, whose height it shares.
    static let height: CGFloat = 108

    private static let cover: CGFloat = 66
    private static let sleeveTop = Color(hex: "#D23A4A")
    private static let sleeveBottom = Color(hex: "#8C1626")
    private static let gold = Color(hex: "#E8B64C")

    var body: some View {
        Button {
            ChristmasMusicPlayer.shared.play()
        } label: {
            album
                .rotation3DEffect(.degrees(hovering ? -24 : -38),
                                  axis: (x: 0, y: 1, z: 0),
                                  anchor: .trailing,
                                  perspective: 0.5)
                .scaleEffect(hovering ? 1.05 : 1, anchor: .trailing)
                .frame(width: Self.width, height: Self.height, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text("Play Notchy's Christmas music"))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        // The cover is the thumbnail the player shows once it plays. Fetched
        // when the slot appears, so the album looks like itself before the
        // first click rather than after it.
        .onAppear { player.loadArtwork() }
    }

    private var album: some View {
        ZStack {
            if let art = player.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Self.sleeveTop, Self.sleeveBottom],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "snowflake")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .frame(width: Self.cover, height: Self.cover)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Self.gold.opacity(hovering ? 0.9 : 0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
        .overlay(alignment: .bottomLeading) { badge.offset(x: -5, y: 5) }
    }

    /// The same disc the main art's source badge sits on, with a snowflake.
    private var badge: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#0B0C0E"))
                .frame(width: 20, height: 20)
            Circle()
                .fill(Self.sleeveTop)
                .frame(width: 15, height: 15)
            Image(systemName: "snowflake")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
        }
    }
}
#endif
