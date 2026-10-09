import SwiftUI

/// The timer tab: pick a length, or watch the one that is running.
///
/// The clock lives in `FocusTimer.shared`, not here — see the note on that
/// class. This only draws it, and only ticks while it is the tab on screen.
struct FocusTimerView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var timer = FocusTimer.shared

    /// Re-read every half second so the countdown moves. `remaining` is derived
    /// from a deadline rather than published, so nothing else would move it.
    @State private var tick = Date.now

    /// Only while this tab is up and something is counting.
    ///
    /// `IslandContentView` builds every view body on every render and hides the
    /// inactive ones, so an ungated ticker would run while you are on Home.
    private var ticking: Bool { state.view == .timer && timer.isRunning }

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            content
                // The Mochi gutter, as every other card leaves it.
                .padding(.leading, 108)
                .padding(.trailing, 16)
                .padding(.vertical, 12)
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
        if timer.isActive {
            running
        } else {
            idle
        }
    }

    // MARK: – Nothing running

    private var idle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timer")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#8E939C"))
            HStack(spacing: 6) {
                ForEach(Array(FocusTimer.presets.enumerated()), id: \.offset) { _, preset in
                    PresetButton(kind: preset.kind, minutes: preset.minutes)
                }
            }
            Text("Focus keeps the island out of your way; it comes back when the time is up.")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: – Counting

    private var running: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Reading `tick` is what ties this to the half-second timer.
            let _ = tick

            HStack(spacing: 7) {
                Circle()
                    .fill(Color(hex: timer.kind.hex))
                    .frame(width: 7, height: 7)
                Text(timer.kind.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                if timer.isPaused {
                    Text("paused")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                Spacer(minLength: 0)
                Text(timer.clock)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color(hex: "#F5F6F8"))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Color(hex: timer.kind.hex))
                        .frame(width: geo.size.width * timer.progress)
                }
            }
            .frame(height: 4)

            HStack(spacing: 8) {
                if timer.isPaused {
                    SecondaryButton("Resume") { timer.resume() }
                } else {
                    SecondaryButton("Pause") { timer.pause() }
                }
                SecondaryButton("+1 min") { timer.extend() }
                SecondaryButton("Stop") { timer.stop() }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
    }
}

/// One length to start. Focus and break are told apart by colour, not by words.
private struct PresetButton: View {
    let kind: FocusTimer.Kind
    let minutes: Int
    @State private var isHovered = false

    var body: some View {
        Button(action: { FocusTimer.shared.start(kind, minutes: minutes) }) {
            VStack(spacing: 1) {
                Text("\(minutes)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text(kind.label)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color(hex: kind.hex))
            }
            .frame(width: 58, height: 40)
            .background(
                isHovered ? Color(hex: kind.hex).opacity(0.16) : Color(hex: "#0E0F11")
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: kind.hex).opacity(isHovered ? 0.5 : 0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
