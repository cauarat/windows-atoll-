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
        case focus, rest

        var label: String { self == .focus ? "Focus" : "Break" }
        /// Focus is the app's working colour; a break is deliberately calmer.
        var hex: String { self == .focus ? "#F5A524" : "#34D399" }
    }

    /// What the buttons offer, in minutes. A Pomodoro and its short break, plus
    /// a long break and a short sprint for when 25 is too much to commit to.
    static let presets: [(kind: Kind, minutes: Int)] = [
        (.focus, 25), (.focus, 50), (.rest, 5), (.rest, 15)
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

    /// Fires once, at the end. Cancellable, which is why it is a work item and
    /// not a repeating `Timer` — the house idiom for a deadline.
    private var finishWork: DispatchWorkItem?

    private init() {}

    // MARK: – Controls

    func start(_ kind: Kind, minutes: Int) {
        start(kind, seconds: TimeInterval(minutes) * 60)
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
