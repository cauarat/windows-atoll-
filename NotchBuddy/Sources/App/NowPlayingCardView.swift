#if !APPSTORE
import SwiftUI
import AppKit

/// The media tab: artwork, what is playing, where it has got to, and transport.
///
/// Everything here was already arriving and going nowhere. `MusicController`
/// has published `artwork`, `elapsed`, `duration` and `progress` since it became
/// an adapter over MediaRemote, and offered `seek(to:)` — and no view in the app
/// read any of them. The old `MusicCardView` is three lines of text squeezed
/// beside Mochi in a shared card; this is the whole panel.
///
/// Mochi is not drawn on this tab (`botDiameter: 0` in `viewLayouts`, the way
/// `.greeting` does it), which is what frees the 108 pt gutter every other card
/// pads around by hand. The artwork sits there.
struct NowPlayingCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var controller = MusicController.shared

    /// Where the thumb is while being dragged, or nil when it is not.
    ///
    /// The bar follows playback the rest of the time, so without this the thumb
    /// would snap back to the player's position on every frame of a drag.
    @State private var scrubbing: Double?

    /// Re-read twice a second so the bar advances. `elapsed` is computed from a
    /// MediaRemote anchor rather than published, so nothing else would move it.
    @State private var tick = Date.now

    private var elapsed: Double { scrubbing ?? controller.elapsed }

    /// Only while this tab is the one on screen.
    ///
    /// `IslandContentView` builds every view body on every render and hides the
    /// inactive ones with `opacity(0)`, so a timer in here would otherwise keep
    /// ticking while you are looking at Home.
    private var ticking: Bool { state.view == .media && state.musicPlaying }

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            content.padding(.horizontal, 14).padding(.vertical, 12)
        }
        .background(
            Group {
                if ticking {
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        Color.clear.onChange(of: ctx.date) { _, d in tick = d }
                    }
                }
            }
        )
    }

    @ViewBuilder private var content: some View {
        if let reason = controller.unavailableReason {
            centred(reason)
        } else if controller.trackTitle == nil {
            centred("Nothing playing")
        } else {
            HStack(spacing: 14) {
                artworkView
                VStack(alignment: .leading, spacing: 0) {
                    titleRows
                    Spacer(minLength: 6)
                    scrubber
                    Spacer(minLength: 8)
                    transport
                }
            }
        }
    }

    private func centred(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Color(hex: "#8E939C"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Pieces

    private var artworkView: some View {
        Group {
            if let art = controller.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else {
                // Not every player sends art; the square must not collapse.
                ZStack {
                    Color(hex: "#0E0F11")
                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "#5F646D"))
                }
            }
        }
        .frame(width: 108, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var titleRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(controller.trackTitle ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1).truncationMode(.tail)
            if let artist = controller.artist {
                Text(artist)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrubber: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                // Reading `tick` is what ties this view to the half-second
                // timer; without it the bar would only move when something else
                // happened to redraw.
                let _ = tick
                let total = max(controller.duration, 0.01)
                let fraction = min(max(elapsed / total, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Color(hex: "#F5F6F8"))
                        .frame(width: geo.size.width * fraction)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            let f = min(max(g.location.x / geo.size.width, 0), 1)
                            scrubbing = f * total
                        }
                        .onEnded { g in
                            let f = min(max(g.location.x / geo.size.width, 0), 1)
                            controller.seek(to: f * total)
                            // Held briefly: the player takes a moment to report
                            // the new position, and letting go any sooner makes
                            // the thumb jump back before it catches up.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                scrubbing = nil
                            }
                        }
                )
            }
            .frame(height: 4)

            HStack {
                Text(Self.clock(elapsed))
                Spacer()
                Text(Self.clock(controller.duration))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundColor(Color(hex: "#6B7079"))
        }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            Spacer()
            button("backward.fill", size: 13) { controller.previousTrack() }
            button(state.musicPlaying ? "pause.fill" : "play.fill", size: 17) {
                controller.playPause()
            }
            button("forward.fill", size: 13) { controller.nextTrack() }
            Spacer()
        }
    }

    private func button(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundColor(Color(hex: "#F1F2F4"))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// `m:ss`, or `h:mm:ss` for anything long enough to need it.
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
#endif
