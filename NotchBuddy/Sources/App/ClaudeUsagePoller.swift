import Foundation
// The AI Agents dashboard reads Claude Code's transcripts under
// ~/.claude/projects. The App Store build is containerised and cannot
// reach them, so the whole feature compiles out there rather than
// shipping a permanently empty panel.
#if !APPSTORE

/// Drives `ClaudeUsageReader` and publishes its snapshot into `AppState`.
///
/// Unlike the service pollers this one does **not** run for the life of the
/// app. Nothing outside the AI Agents dashboard consumes transcript data — the
/// satellite ring is fed by the plan gauges instead, from the statusline relay
/// or `ClaudePlanAPI` — so the timer only turns over while that view is on
/// screen, which is what keeps the island at no measurable cost when it is
/// hidden.
///
/// Between ticks, hook events push refreshes: `HookServer` calls `pollNow()`
/// when Claude Code stops or finishes a tool, so figures move as the session
/// runs rather than waiting out the interval.
@MainActor
final class ClaudeUsagePoller {
    static let shared = ClaudeUsagePoller()

    private var timer: DispatchSourceTimer?
    private var inFlight = false
    /// Coalesces the burst of hook events a single turn produces.
    private var pendingSince: Date?
    private static let interval: TimeInterval = 30
    private static let minGap: TimeInterval = 2

    private init() {}

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        // On the main queue, like the hook server's sources. This class is
        // @MainActor, so a handler written here is @MainActor too, and Swift 6
        // asserts that at runtime on every tick — from a background queue that
        // assertion is a SIGTRAP and the app is simply gone. Nothing is bought
        // by the other queue either: the handler only hops back, and the scan
        // itself already runs off-main inside pollNow's Task.
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + Self.interval, repeating: Self.interval)
        t.setEventHandler { [weak self] in self?.pollNow() }
        t.resume()
        timer = t
        pollNow()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Refreshes now, unless a scan is already running or one just finished.
    func pollNow() {
        guard AppState.isEnabledNow, !inFlight else { return }
        if let last = pendingSince, Date().timeIntervalSince(last) < Self.minGap { return }

        let state = AppState.shared
        inFlight = true
        if state.agentUsage == nil { state.agentUsageLoading = true }

        Task { [weak self] in
            let snapshot = await ClaudeUsageReader.shared.refresh()
            state.agentUsage = snapshot
            state.agentUsageLoading = false
            self?.inFlight = false
            self?.pendingSince = Date()
        }
    }

    /// Called from the hook server when an agent event lands. Cheap no-op
    /// unless the dashboard is open.
    func noteAgentActivity() {
        guard isRunning else { return }
        pollNow()
    }
}

#endif
