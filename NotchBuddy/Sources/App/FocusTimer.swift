import Foundation
import Combine

/// A focus or break countdown.
///
/// A singleton rather than `@State` in the view, and that is not a style choice:
/// `IslandContentView` builds every `IslandView` body on every render and hides
/// the inactive ones with `opacity(0)`, so state owned by the timer tab would be
/// rebuilt and lost, and a ticker living there would run while you were looking
/// at Home. The view reads this; this owns the clock.
///
/// Shaped like `MessageInbox`: `@MainActor`, `ObservableObject`, `.shared`.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()

    enum Kind: String, Codable {
        case focus, rest, deep

        var label: String {
            switch self {
            case .focus: return "Focus"
            case .rest:  return "Break"
            case .deep:  return "Deep Work"
            }
        }

        /// Focus is the app's working colour, a break is calmer, deep work is
        /// the one you are not meant to interrupt.
        var hex: String {
            switch self {
            case .focus: return "#FF9F0A"
            case .rest:  return "#30D158"
            case .deep:  return "#D946EF"
            }
        }
    }

    /// The three named lengths, in minutes.
    static let presets: [(kind: Kind, minutes: Int)] = [
        (.focus, 25), (.rest, 5), (.deep, 45)
    ]

    @Published private(set) var kind: Kind = .focus
    /// Nil when nothing is running.
    @Published private(set) var endsAt: Date?
    /// Set while paused, so resuming does not lose the time left.
    @Published private(set) var pausedRemaining: TimeInterval?
    /// How long the current run was asked for, for the progress ring.
    @Published private(set) var total: TimeInterval = 0

    var isRunning: Bool { endsAt != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isActive: Bool { isRunning || isPaused }

    /// Seconds left, never negative. Safe to call every frame.
    var remaining: TimeInterval {
        if let paused = pausedRemaining { return paused }
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSinceNow)
    }

    /// 0 at the start, 1 when it is done.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(1 - remaining / total, 0), 1)
    }

    /// `m:ss`, or `h:mm:ss` once there is an hour to show.
    var clock: String {
        let t = Int(remaining.rounded(.up))
        let (h, m, s) = (t / 3600, (t % 3600) / 60, t % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// What the picker is set to, before anything has started. Hours, minutes
    /// and seconds are kept apart rather than as one number of seconds so each
    /// tile can be typed into without the other two drifting.
    @Published var pickerHours = 0
    @Published var pickerMinutes = 25
    @Published var pickerSeconds = 0
    /// Which preset the picker currently holds, for Reset and for the colour.
    @Published private(set) var pickerKind: Kind = .focus

    var pickerTotal: TimeInterval {
        TimeInterval(pickerHours * 3600 + pickerMinutes * 60 + pickerSeconds)
    }

    /// Fires once, at the end. Cancellable, which is why it is a work item and
    /// not a repeating `Timer` — the house idiom for a deadline.
    private var finishWork: DispatchWorkItem?

    private init() {}

    // MARK: – Controls

    func start(_ kind: Kind, minutes: Int) {
        start(kind, seconds: TimeInterval(minutes) * 60)
    }

    /// Loads a preset into the picker without starting it, so the tiles show
    /// what Start is about to do.
    func load(_ kind: Kind, minutes: Int) {
        pickerKind = kind
        pickerHours = minutes / 60
        pickerMinutes = minutes % 60
        pickerSeconds = 0
    }

    /// Start, from whatever the tiles say.
    func startFromPicker() {
        start(pickerKind, seconds: pickerTotal)
    }

    /// Back to the preset the picker was last loaded with.
    func reset() {
        stop()
        let minutes = Self.presets.first { $0.kind == pickerKind }?.minutes ?? 25
        load(pickerKind, minutes: minutes)
    }

    /// Each tile, clamped to what it can mean.
    func setPicker(hours: Int? = nil, minutes: Int? = nil, seconds: Int? = nil) {
        if let hours { pickerHours = min(max(hours, 0), 23) }
        if let minutes { pickerMinutes = min(max(minutes, 0), 59) }
        if let seconds { pickerSeconds = min(max(seconds, 0), 59) }
    }

    func start(_ kind: Kind, seconds: TimeInterval) {
        guard seconds > 0 else { return }
        self.kind = kind
        total = seconds
        pausedRemaining = nil
        endsAt = Date().addingTimeInterval(seconds)
        arm(seconds)
        SoundEngine.shared.play("blip")
    }

    func pause() {
        guard let endsAt else { return }
        pausedRemaining = max(0, endsAt.timeIntervalSinceNow)
        self.endsAt = nil
        cancel()
    }

    func resume() {
        guard let left = pausedRemaining, left > 0 else { return }
        pausedRemaining = nil
        endsAt = Date().addingTimeInterval(left)
        arm(left)
    }

    func stop() {
        cancel()
        endsAt = nil
        pausedRemaining = nil
        total = 0
    }

    /// Adds a minute to whatever is running — the "just a bit more" button.
    func extend(by seconds: TimeInterval = 60) {
        guard isActive else { return }
        total += seconds
        if let paused = pausedRemaining {
            pausedRemaining = paused + seconds
        } else if let endsAt {
            self.endsAt = endsAt.addingTimeInterval(seconds)
            arm(max(0, self.endsAt!.timeIntervalSinceNow))
        }
    }

    // MARK: – The deadline

    private func arm(_ seconds: TimeInterval) {
        cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finishWork = nil
            self.ring()
        }
        finishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancel() {
        finishWork?.cancel()
        finishWork = nil
    }

    private func ring() {
        let finished = kind
        endsAt = nil
        pausedRemaining = nil
        total = 0
        SoundEngine.shared.play("finish")
        NotificationCenter.default.post(name: .focusTimerFinished, object: finished)
    }
}

extension Notification.Name {
    /// A focus or break ran out. Object is the `FocusTimer.Kind` that ended.
    static let focusTimerFinished = Notification.Name("focusTimerFinished")
}
