import Foundation
#if !APPSTORE

/// Keeps `ClaudePlanAPI` ticking while something is showing its numbers.
///
/// Like `ClaudeUsagePoller` this does not run for the life of the app, and here
/// that falls out of the layout rather than being a compromise:
/// `IslandEdgeLayout.visible(_:expanded:)` is `expanded ? all : []`, so the ring
/// is not rendered unless the island is open, and the dashboard even less often.
/// Nothing ticks while the island is hidden, which is the 0 % CPU rule met
/// exactly. The last reading is persisted, so the first open already has a
/// number on screen and the one-tick wait is invisible.
@MainActor
final class ClaudePlanAPIPoller {
    static let shared = ClaudePlanAPIPoller()

    private var timer: DispatchSourceTimer?
    private var inFlight = false
    private var lastAttempt: Date?
    /// How long to wait after a failure, doubling up to `maxBackoff`.
    private var backoff: TimeInterval = 0
    /// Both the ring and the dashboard want this running, and either one going
    /// away must not stop it for the other.
    private var holders = 0

    private static let interval: TimeInterval = 60
    private static let maxBackoff: TimeInterval = 900
    /// A floor under hook-driven refreshes. `ClaudeUsagePoller` uses two
    /// seconds, which is right for re-reading local files; this is a network
    /// call made with a token that is not ours to spend.
    private static let hookFloor: TimeInterval = 90

    private init() {}

    var isRunning: Bool { timer != nil }

    // MARK: - Ownership

    func retain() {
        holders += 1
        if holders == 1 { start() }
    }

    func release() {
        holders = max(0, holders - 1)
        if holders == 0 { stop() }
    }

    // MARK: - Lifecycle

    private func start() {
        guard timer == nil else { return }
        // On the main queue, and this is not a style choice. This class is
        // @MainActor, so a handler written here is @MainActor too, and Swift 6
        // checks that at runtime on every tick — from a background queue the
        // check is a SIGTRAP and the app is simply gone. The work itself is
        // already off-main inside the actor, so the other queue would buy
        // nothing anyway. `scripts/test-mainactor-dispatch.sh` enforces this.
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + Self.interval, repeating: Self.interval)
        t.setEventHandler { [weak self] in self?.pollNow() }
        t.resume()
        timer = t
        pollNow()
    }

    private func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Polling

    /// Asks now, unless switched off, already asking, or still backing off.
    func pollNow(minimumGap: TimeInterval = 0) {
        let state = AppState.shared
        guard AppState.isEnabledNow,
              state.claudePlanAPIEnabled,
              !state.claudePlanAPIBlocked,
              !inFlight else { return }

        if let last = lastAttempt {
            let waited = Date().timeIntervalSince(last)
            if waited < max(minimumGap, backoff) { return }
        }

        inFlight = true
        lastAttempt = Date()

        Task { [weak self] in
            let result = await ClaudePlanAPI.shared.fetch()
            self?.finish(result)
        }
    }

    /// Hook events land here. A no-op unless something is on screen to update.
    func noteAgentActivity() {
        guard isRunning else { return }
        pollNow(minimumGap: Self.hookFloor)
    }

    private func finish(_ result: Result<PlanUsage, ClaudePlanAPI.Failure>) {
        inFlight = false
        let state = AppState.shared

        switch result {
        case .success(let usage):
            backoff = 0
            state.applyPlanUsage(usage)

        case .failure(let why):
            // Whatever went wrong, the last good reading stays on screen. A
            // network blip is not news, and a ring that empties itself every
            // time the wifi hiccups is worse than one that is a minute stale.
            switch why {
            case .notApplicable:
                // The account simply has no such limits. Asking again every
                // minute would never change that answer.
                state.claudePlanAPIBlocked = true
                stop()
            case .denied, .unauthorized:
                // The one thing that must not repeat. A 60-second timer that
                // re-raises a modal Keychain dialog after the user pressed Deny
                // is hostile, so stop asking until they say otherwise.
                state.claudePlanAPIBlocked = true
                stop()
            case .rateLimited(let retryAfter):
                backoff = min(Self.maxBackoff, retryAfter ?? max(Self.interval, backoff * 2))
            case .noCredentials:
                // Claude Code has not run lately, or never signed in here.
                // Nothing to wait for on a 60-second cadence.
                backoff = min(Self.maxBackoff, 600)
            default:
                backoff = min(Self.maxBackoff, backoff == 0 ? Self.interval : backoff * 2)
            }
            appendAppLog("claude-plan.log", "plan usage: \(why.plainLine)")
        }
    }
}

#endif
