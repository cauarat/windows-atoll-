import SwiftUI

/// The timer tab: set a length and start it, or watch the one that is running.
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
                .padding(.vertical, 10)
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
            HStack(alignment: .top, spacing: 18) {
                picker
                Spacer(minLength: 0)
                presets
            }
        }
    }

    // MARK: – Nothing running: set a length

    private var picker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                tile(timer.pickerHours, "Hours") { timer.setPicker(hours: $0) }
                colon
                tile(timer.pickerMinutes, "Minutes") { timer.setPicker(minutes: $0) }
                colon
                tile(timer.pickerSeconds, "Seconds") { timer.setPicker(seconds: $0) }
            }
            HStack(spacing: 8) {
                Button(action: { timer.startFromPicker() }) {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#0B0C0E"))
                        .padding(.horizontal, 18)
                        .frame(height: 30)
                        .background(Color(hex: "#30D158"))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .disabled(timer.pickerTotal <= 0)
                .opacity(timer.pickerTotal <= 0 ? 0.4 : 1)

                Button(action: { timer.reset() }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F1F2F4"))
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// One number, typed into or scrolled. A plain stepper would need six more
    /// controls in a row that has no room for them.
    private func tile(_ value: Int, _ label: String, set: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 3) {
            TextField("", value: Binding(get: { value }, set: set), format: .number)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundColor(Color(hex: "#F5F6F8"))
                .frame(width: 54, height: 42)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                // Scrolling over a number is the fastest way to nudge it, and
                // costs nothing to offer beside typing.
                .onContinuousHover { _ in }
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { g in
                            set(value - Int(g.translation.height / 12))
                        }
                )
            Text(label)
                .font(.system(size: 9.5))
                .foregroundColor(Color(hex: "#8E939C"))
        }
    }

    private var colon: some View {
        VStack(spacing: 4) {
            Circle().fill(Color(hex: "#5F646D")).frame(width: 3, height: 3)
            Circle().fill(Color(hex: "#5F646D")).frame(width: 3, height: 3)
        }
        .padding(.top, 17)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(FocusTimer.presets.enumerated()), id: \.offset) { _, preset in
                PresetRow(kind: preset.kind, minutes: preset.minutes)
            }
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
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
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

/// One named length: a coloured dot, the name, and how long it is.
/// Clicking loads it into the tiles rather than starting it, so Start is always
/// the thing that starts something.
private struct PresetRow: View {
    let kind: FocusTimer.Kind
    let minutes: Int
    @State private var isHovered = false

    var body: some View {
        Button(action: { FocusTimer.shared.load(kind, minutes: minutes) }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: kind.hex))
                    .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(kind.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: kind.hex))
                        .lineLimit(1)
                    Text(String(format: "%02d:00", minutes))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(Color(hex: "#8E939C"))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(width: 128, height: 30)
            .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
