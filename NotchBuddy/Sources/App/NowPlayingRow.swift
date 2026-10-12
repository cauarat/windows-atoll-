import SwiftUI

/// What is playing, on Home.
///
/// The short version: artwork, what it is, where it came from, and enough
/// transport to not have to go anywhere. Home is one row tall, so the scrubber
/// and the volume live in the full player — this is the glance.
struct NowPlayingRow: View {
    @ObservedObject private var controller = MusicController.shared
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.trackTitle ?? "Nothing playing")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if let artist = controller.artist {
                            Text(artist)
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#9398A1"))
                                .lineLimit(1)
                        }
                        // Which app it is coming from. The whole point of
                        // reading the system rather than one music app is that
                        // this can say Spotify, or Chrome, or WhatsApp.
                        if !controller.sourceName.isEmpty {
                            Text("·").foregroundColor(Color(hex: "#555A63"))
                            Text(controller.sourceName)
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#6E737C"))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                transport
                Button {
                    state.view = .media
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                .buttonStyle(.plain)
                .help("Open the player")
            }
            .padding(.leading, 108)
            .padding(.trailing, 16)
        }
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.05))
            .frame(width: 42, height: 42)
            .overlay {
                if let art = controller.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "#6E737C"))
                }
            }
    }

    private var transport: some View {
        HStack(spacing: 14) {
            button("backward.fill") { controller.previousTrack() }
            button(controller.isPlaying ? "pause.fill" : "play.fill") { controller.playPause() }
            button("forward.fill") { controller.nextTrack() }
        }
    }

    private func button(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "#D6DAE1"))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
