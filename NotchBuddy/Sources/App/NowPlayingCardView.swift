#if !APPSTORE
import SwiftUI
import AppKit

/// The Now Playing section: artwork, what is playing, where it has got to, and
/// transport.
///
/// Everything here was already arriving and going nowhere. `MusicController`
/// has published `artwork`, `elapsed`, `duration` and `progress` since it became
/// an adapter over MediaRemote, and offered `seek(to:)` — and no view in the app
/// read any of them.
///
/// It used to be a tab of its own, beside a three-line card in the red Now
/// Playing section and a thinner copy of itself on Home. One card now, reached
/// two ways: Home on automatic while something is loaded, or the Now Playing
/// pill in focus.
///
/// Mochi is not drawn in the gutter while this is up (`botDiameter: 0` on the
/// `.media` layout `layoutTwin` points Home at), which is what frees the 108 pt
/// every other card pads around by hand. The artwork sits there, and Mochi's
/// mini self sits on its corner — he is listening to it with you.
struct NowPlayingCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var controller = MusicController.shared

    /// False when something else already drew the card underneath — the
    /// focused-pill card does, and two `CardBackground`s in the same frame
    /// means the hairline border drawn twice.
    var drawsBackground: Bool = true

    /// Where the thumb is while being dragged, or nil when it is not.
    ///
    /// The bar follows playback the rest of the time, so without this the thumb
    /// would snap back to the player's position on every frame of a drag.
    @State private var scrubbing: Double?

    /// Re-read twice a second so the bar advances. `elapsed` is computed from a
    /// MediaRemote anchor rather than published, so nothing else would move it.
    @State private var tick = Date.now
    /// Held while dragging, so the bar follows the pointer rather than waiting
    /// for CoreAudio to be asked again.
    @State private var draggedVolume: Float?
    @State private var volumeTick = Date.now

    private var elapsed: Double { scrubbing ?? controller.elapsed }

    /// Only while this card is the one on screen, and something is moving.
    ///
    /// `IslandContentView` builds every view body on every render and hides the
    /// inactive ones with `opacity(0)`, so an ungated timer would keep ticking
    /// while you are looking at the clipboard — and keep the island off 0 % CPU
    /// while it is hidden entirely.
    private var ticking: Bool { onScreen && state.musicPlaying }

    /// This card is the one being looked at.
    ///
    /// Mini Mochi runs a `TimelineView(.animation)` of his own, which has no
    /// pause of its own the way the big one does — so he is only built while he
    /// can be seen. Without this he would draw behind every other tab, and the
    /// island would never reach the 0 % CPU it owes when it is hidden.
    private var onScreen: Bool {
        state.mode == .expanded
            && state.view == .overview
            && state.homeShowsPlayer
    }

    var body: some View {
        ZStack {
            if drawsBackground {
                CardBackground(wash: .red)
            }
            content
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
            emptyLine(reason)
        } else if controller.trackTitle == nil {
            emptyLine("Nothing playing.")
        } else {
            HStack(spacing: 14) {
                artworkView
                VStack(alignment: .leading, spacing: 0) {
                    titleRows
                    Spacer(minLength: 6)
                    scrubber
                    Spacer(minLength: 8)
                    transport
                    if volume != nil {
                        Spacer(minLength: 8)
                        volumeRow
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    /// Nothing playing: one line, in the gutter every other empty card leaves.
    ///
    /// Deliberately the same shape as `HomeMessageView`'s empty branch rather
    /// than centred text — with no track the island keeps `.overview`'s
    /// geometry, so Mochi is back at his usual size on the left and the card
    /// should look like every other card he is sitting beside.
    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Color(hex: "#8E939C"))
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: – Artwork, and the two corners

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
        .overlay(alignment: .bottomLeading) { sourceBadge.offset(x: -6, y: 6) }
        .overlay(alignment: .bottomTrailing) {
            if onScreen { mochiBadge.offset(x: 6, y: 6) }
        }
    }

    /// Bottom left: which application the song is coming from.
    ///
    /// The real icon of the real app, read from the bundle id MediaRemote
    /// reports. That is the application and not the website, so Spotify is
    /// Spotify's icon and a local file is QuickTime's or IINA's, but anything
    /// played in a tab — YouTube, ClickMassa, Mattermost — is the browser's.
    /// Honest about what the system actually says, which a drawn YouTube mark
    /// would not be the moment the tab was something else.
    private var sourceBadge: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#0B0C0E"))
                .frame(width: 22, height: 22)
            if let icon = controller.sourceIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
        }
        .help(controller.sourceName.isEmpty ? "" : "Playing from \(controller.sourceName)")
    }

    /// Bottom right: Mochi, on the record, listening along.
    ///
    /// His colour is the Now Playing pill's own `#FA2D48` rather than a number
    /// written here, so the section and the character stay the same red. He
    /// dances while it plays, the way he does for the pill.
    private var mochiBadge: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#0B0C0E"))
                .frame(width: 28, height: 28)
            MiniBotCanvasView(task: Self.mochiTask, isDancing: state.musicPlaying)
                .frame(width: 23 / 0.6, height: 23 / 0.6)
                .frame(width: 23, height: 23, alignment: .center)
        }
    }

    /// The pill's own task when it is loaded, and something the same colour
    /// when it is not — the card is reachable with the pill switched off.
    private static var mochiTask: AgentTask {
        if let task = AppState.shared.tasks.first(where: { $0.id == "integration_music" }) {
            return task
        }
        let def = PillCatalog.definition(for: "integration_music")
        return AgentTask(id: "integration_music",
                         name: def?.name ?? "Now Playing",
                         color: def?.color ?? "#FA2D48",
                         state: .idle,
                         steps: [],
                         source: .n8n,
                         isIntegration: true)
    }

    // MARK: – Rows

    private var titleRows: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(controller.trackTitle ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1).truncationMode(.tail)
            HStack(spacing: 5) {
                if let artist = controller.artist {
                    Text(artist)
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                }
                // Which application it is coming from. Reading the system
                // rather than one music app is only worth anything if the card
                // can say so — this is where Chrome or WhatsApp shows up.
                if !controller.sourceName.isEmpty {
                    Text("·").foregroundColor(Color(hex: "#4E535B"))
                    Text(controller.sourceName)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6E737C"))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The output volume, or nil when the current output has none of its own —
    /// most HDMI displays and some interfaces. No slider is better than one
    /// that moves and changes nothing.
    private var volume: Float? { SystemVolume.level }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Button {
                SystemVolume.setMuted(!SystemVolume.isMuted)
                volumeTick = Date()
            } label: {
                Image(systemName: SystemVolume.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                let level = CGFloat(draggedVolume ?? volume ?? 0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(Color(hex: "#D6DAE1"))
                        .frame(width: max(0, geo.size.width * level))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = Float(min(max(g.location.x / geo.size.width, 0), 1))
                        draggedVolume = f
                        SystemVolume.setLevel(f)
                    }
                    .onEnded { _ in draggedVolume = nil; volumeTick = Date() })
            }
            .frame(height: 14)
        }
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
