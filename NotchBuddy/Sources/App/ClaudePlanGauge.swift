import Foundation

// MARK: - Plan window

struct PlanWindow: Codable {
    let usedPct: Double   // 0–100, clamped
    let resetsAt: Date
}

// MARK: - Plan usage

/// Which of the two feeds a reading came from.
enum PlanUsageSource: String, Codable {
    /// Pushed in by Claude Code's statusline, which only its terminal UI runs.
    case statusline
    /// Asked for over the network, the way `/usage` itself asks.
    case api
}

struct PlanUsage: Codable {
    var fiveHour: PlanWindow?
    var sevenDay: PlanWindow?
    var updatedAt: Date
    /// Optional on purpose, twice over: a reading persisted by an earlier build
    /// has no such key and must still decode, and the default keeps the
    /// three-argument memberwise initialiser the existing callers use.
    var source: PlanUsageSource? = nil
}

// MARK: - Parsing + helpers (Foundation-only, no AppKit/SwiftUI)

enum ClaudePlanGauge {

    /// Parses rate_limits from a statusline payload dict. Returns nil if absent/malformed.
    static func parse(payload: [String: Any]) -> PlanUsage? {
        guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let fh = parseWindow(limits["five_hour"])
        let sd = parseWindow(limits["seven_day"])
        guard fh != nil || sd != nil else { return nil }
        return PlanUsage(fiveHour: fh, sevenDay: sd, updatedAt: Date(), source: .statusline)
    }

    private static func parseWindow(_ raw: Any?) -> PlanWindow? {
        guard let d = raw as? [String: Any] else { return nil }
        let rawPct: Double
        if let v = d["used_percentage"] as? Double { rawPct = v }
        else if let v = d["used_percentage"] as? Int { rawPct = Double(v) }
        else { return nil }
        guard rawPct >= 0, rawPct <= 200 else { return nil }
        let pct = min(100, rawPct)   // clamp 100–200 down to 100
        let rawEpoch: Double
        if let v = d["resets_at"] as? Double { rawEpoch = v }
        else if let v = d["resets_at"] as? Int { rawEpoch = Double(v) }
        else { return nil }
        guard rawEpoch > 0 else { return nil }
        // Reject if more than 400 days in the future (likely milliseconds, not seconds)
        let maxEpoch = Date().timeIntervalSince1970 + 400 * 86400
        guard rawEpoch <= maxEpoch else { return nil }
        return PlanWindow(usedPct: pct, resetsAt: Date(timeIntervalSince1970: rawEpoch))
    }

    // MARK: - The usage endpoint

    /// Parses a body from `/api/oauth/usage` — what Claude Code's own `/usage`
    /// reads, and the only way to these figures for someone running the desktop
    /// app, which never executes a status line.
    ///
    /// Deliberately a second parser rather than a branch inside the one above.
    /// The two shapes only look alike: here `utilization` is already a
    /// percentage and `resets_at` is ISO 8601, where the statusline sends
    /// `used_percentage` and a Unix epoch. A third shape exists that neither of
    /// these reads — the rate-limit response headers, whose utilization runs 0
    /// to 1. A single parser would have to guess which of the three it was
    /// holding, and a 0-to-1 utilization read as a percentage draws a green ring
    /// on a spent account. The bounds and the clamp below are shared, because
    /// those are about what is worth showing rather than about where it came
    /// from.
    static func parse(usageJSON data: Data) -> PlanUsage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let fh = parseAPIWindow(root["five_hour"])
        let sd = parseAPIWindow(root["seven_day"])
        guard fh != nil || sd != nil else { return nil }
        return PlanUsage(fiveHour: fh, sevenDay: sd, updatedAt: Date(), source: .api)
    }

    private static func parseAPIWindow(_ raw: Any?) -> PlanWindow? {
        guard let d = raw as? [String: Any] else { return nil }
        // Both keys are nullable in the schema, and JSONSerialization hands back
        // NSNull rather than nothing — which fails these casts, which is the
        // right answer: a window with no number is not a window.
        let rawPct: Double
        if let v = d["utilization"] as? Double { rawPct = v }
        else if let v = d["utilization"] as? Int { rawPct = Double(v) }
        else { return nil }
        guard rawPct >= 0, rawPct <= 200 else { return nil }
        let pct = min(100, rawPct)   // clamp 100–200 down to 100, as above
        guard let s = d["resets_at"] as? String, let reset = isoDate(s) else { return nil }
        // Same 400-day guard the statusline parser uses, for the same reason: a
        // reset that far out is a unit mix-up, not a reset.
        guard reset <= Date().addingTimeInterval(400 * 86400) else { return nil }
        return PlanWindow(usedPct: pct, resetsAt: reset)
    }

    /// Reads the endpoint's `resets_at`.
    ///
    /// Fractional seconds are tried first: `ISO8601DateFormatter` in its default
    /// options returns nil for a timestamp that has them rather than ignoring
    /// them, so going the other way round would drop every reading from a server
    /// that sends milliseconds.
    ///
    /// Built per call rather than kept in a static. `ISO8601DateFormatter` is
    /// not `Sendable`, so a shared one is a data race Swift 6 refuses to
    /// compile, and this runs twice a minute at most.
    static func isoDate(_ s: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// Effective % for display: 0 if the reset time is in the past.
    static func effectivePct(_ w: PlanWindow) -> Double {
        w.resetsAt <= Date() ? 0 : w.usedPct
    }

    /// The higher of the two effective percentages. nil if both windows absent.
    static func dominantPct(_ usage: PlanUsage) -> Double? {
        let p1 = usage.fiveHour.map { effectivePct($0) }
        let p2 = usage.sevenDay.map { effectivePct($0) }
        switch (p1, p2) {
        case (.none, .none): return nil
        case (let x?, .none): return x
        case (.none, let y?): return y
        case (let x?, let y?): return max(x, y)
        }
    }

    /// Hex color for a given percentage (nil → grey).
    static func color(for pct: Double?) -> String {
        guard let p = pct else { return "#6B7079" }
        if p < 50  { return "#22C55E" }
        if p < 80  { return "#F59E0B" }
        return "#F4505E"
    }

    /// Label shown in the island pill chip.
    static func pillLabel(_ usage: PlanUsage?) -> String {
        guard let usage, let pct = dominantPct(usage) else { return "Claude plan" }
        return "Claude \(Int(pct.rounded()))%"
    }
}
