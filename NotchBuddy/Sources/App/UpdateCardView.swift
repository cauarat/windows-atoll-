#if !APPSTORE

import SwiftUI

/// "Version x.y.z is here" — the updater's notification card.
///
/// Built like the hydration reminder: the 108 pt gutter for Mochi, a who line,
/// one title, one grey line, the buttons, and a mark on the right — an arrow
/// in a ring, with the jump from this version to the new one under it. Indigo,
/// a wash no other notification uses, so it is not mistaken for a finished
/// task (green) or a reminder (cyan).
///
/// Everything here reads `Updater`; nothing starts from `onAppear`, because the
/// island builds every view whenever it opens.
struct UpdateCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var updater = Updater.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When Update now went through: the confetti's clock, and nil the rest of
    /// the time, so nothing animates while the card is only being offered.
    @State private var burstAt: Date?

    var body: some View {
        ZStack {
            CardBackground(wash: .indigo)
            // Behind the words, inside the card: the click is the moment.
            if let burstAt, state.view == .update {
                UpdateConfetti(startedAt: burstAt)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    who
                    if let offer = updater.offer { content(offer) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let offer = updater.offer {
                    mark(offer.version).frame(minWidth: 84)
                }
            }
            .padding(.leading, IslandConst.lead(108, flush: 18, hidden: state.hideCharacters))
            .padding(.trailing, 18)
        }
        .onChange(of: updater.offer) { _, offer in
            // The click's moment: Update now has just turned the card into
            // "Restarting…". Read off the offer rather than the button so the
            // screenshot seeder can set it off too.
            if case .restarting = offer, !reduceMotion { burstAt = .now }
        }
        .task(id: burstAt) {
            // Gone once it has fallen, so the timeline stops with it.
            guard burstAt != nil else { return }
            try? await Task.sleep(for: .seconds(UpdateConfetti.duration))
            burstAt = nil
        }
    }

    private var who: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(hex: "#818CF8")).frame(width: 7, height: 7)
            Text(verbatim: "Notchy").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            Text("new version").font(.system(size: 12)).foregroundColor(Color(hex: "#9398A1"))
        }
    }

    @ViewBuilder private func content(_ offer: Updater.Offer) -> some View {
        switch offer {
        case .ready(let version), .available(let version):
            lines(title: Text("Version \(version) is here"),
                  sub: Text("It takes a few seconds, and Notchy comes right back."))
            HStack(spacing: 7) {
                PrimaryButton(L("Update now")) { updater.install() }
                SecondaryButton(L("Later")) { updater.later() }
            }
            .padding(.top, 8)
        case .restarting(let version):
            lines(title: Text("Restarting…"),
                  sub: Text("Back in a moment, on \(version)."))
        }
    }

    private func mark(_ version: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color(hex: "#6366F1").opacity(0.16))
                Circle().strokeBorder(Color(hex: "#818CF8").opacity(0.7), lineWidth: 1.5)
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "#C7D2FE"))
            }
            .frame(width: 46, height: 46)
            Text(verbatim: "\(updater.currentVersion) → \(version)")
                .font(.system(size: 11).monospacedDigit()).foregroundColor(Color(hex: "#9398A1"))
                .lineLimit(1).fixedSize()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func lines(title: Text, sub: Text) -> some View {
        title.font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8).padding(.top, 4)
        sub.font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1")).lineLimit(1).minimumScaleFactor(0.85).padding(.top, 1)
    }
}

/// A burst of paper from the middle of the card when Update now is clicked:
/// out, then down, flipping as it falls, gone in two and a half seconds.
///
/// The pieces are fixed — the same burst every time — and each one's place is
/// worked out from the time since the click (drag and gravity, solved), so
/// there is nothing to step and nothing kept between frames. Drawn like every
/// other moving thing in the app: a `Canvas` in a `TimelineView`, which only
/// exists while `burstAt` is set.
struct UpdateConfetti: View {
    let startedAt: Date

    static let duration: Double = 2.5

    private struct Piece {
        let vx, vy, w, h, spin, turn, flip, phase: CGFloat
        let round: Bool
        let color: Color
    }

    /// 64 pieces, from a fixed hash rather than `random()`: the design's
    /// spread, the same on every click.
    private static let pieces: [Piece] = {
        let colours = ["#818CF8", "#A5B4FC", "#F472B6", "#FBBF24", "#34D399", "#22D3EE", "#F5F6F8", "#FB7185"]
        func unit(_ i: Int, _ salt: UInt64) -> CGFloat {
            var x = UInt64(i + 1) &* 0x9E3779B97F4A7C15 &+ salt &* 0xBF58476D1CE4E5B9
            x ^= x >> 31; x &*= 0x94D049BB133111EB; x ^= x >> 29
            return CGFloat(x % 10_000) / 10_000
        }
        return (0..<64).map { i in
            let angle = unit(i, 1) * 2 * .pi
            let speed = 160 + unit(i, 2) * 300
            let round = unit(i, 3) < 0.22
            return Piece(
                vx: cos(angle) * speed * 1.4, vy: sin(angle) * speed - 140,
                w: round ? 6 : 5 + unit(i, 4) * 4, h: round ? 6 : 9 + unit(i, 5) * 5,
                spin: unit(i, 6) * 360, turn: (unit(i, 7) - 0.5) * 900,
                flip: 5 + unit(i, 8) * 9, phase: unit(i, 9) * 6,
                round: round, color: Color(hex: colours[i % colours.count])
            )
        }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = CGFloat(timeline.date.timeIntervalSince(startedAt))
                guard t >= 0, t < Self.duration else { return }
                // The design's numbers are for a 160 pt card; this one is
                // shorter, so the throw is scaled to fit it.
                let k = size.height / 160
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.55)
                let dragX: CGFloat = 1.5, dragY: CGFloat = 1.1, gravity = 430 * k
                let fade = t > 1.8 ? max(0, 1 - (t - 1.8) / 0.7) : min(1, t / 0.05)
                for p in Self.pieces {
                    let x = origin.x + p.vx * k / dragX * (1 - exp(-dragX * t))
                    let y = origin.y + gravity / dragY * t
                        + (p.vy * k - gravity / dragY) * (1 - exp(-dragY * t)) / dragY
                    var piece = ctx
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .degrees(Double(p.spin + p.turn * t)))
                    piece.scaleBy(x: cos(t * p.flip + p.phase), y: 1)
                    // Paper keeps its size; only the throw is scaled.
                    let rect = CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h)
                    let shape = p.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                    piece.fill(shape, with: .color(p.color.opacity(Double(fade))))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#endif
