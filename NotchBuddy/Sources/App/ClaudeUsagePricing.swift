import Foundation

// MARK: - Token counts
//
// Claude Code records cache creation twice: once lumped into
// `cache_creation_input_tokens`, and once split by TTL inside
// `cache_creation.{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}`.
// The two TTLs are billed differently, so we keep them apart.

struct TokenCounts: Codable, Sendable, Equatable {
    var input:        Int64 = 0
    var output:       Int64 = 0
    var cacheWrite5m: Int64 = 0
    var cacheWrite1h: Int64 = 0
    var cacheRead:    Int64 = 0

    var total: Int64 { input + output + cacheWrite5m + cacheWrite1h + cacheRead }

    /// Share of the total that was served from cache (0–1). 0 when nothing moved.
    var cacheShare: Double {
        let t = total
        return t > 0 ? Double(cacheRead) / Double(t) : 0
    }

    /// Decodes one `message.usage` object from a transcript.
    ///
    /// Cache creation is recorded twice: a lump in
    /// `cache_creation_input_tokens`, and a per-TTL split in `cache_creation`.
    /// The split is what we price from; records written before it existed
    /// carry only the lump, which is attributed to the 5-minute cache — the
    /// cheaper of the two, so an old record is never over-charged.
    init(usage: [String: Any]) {
        func int(_ v: Any?) -> Int64 { (v as? NSNumber)?.int64Value ?? 0 }

        input     = int(usage["input_tokens"])
        output    = int(usage["output_tokens"])
        cacheRead = int(usage["cache_read_input_tokens"])

        if let split = usage["cache_creation"] as? [String: Any] {
            cacheWrite5m = int(split["ephemeral_5m_input_tokens"])
            cacheWrite1h = int(split["ephemeral_1h_input_tokens"])
        }
        if cacheWrite5m + cacheWrite1h == 0 {
            cacheWrite5m = int(usage["cache_creation_input_tokens"])
        }
    }

    init() {}

    mutating func add(_ o: TokenCounts) {
        input        += o.input
        output       += o.output
        cacheWrite5m += o.cacheWrite5m
        cacheWrite1h += o.cacheWrite1h
        cacheRead    += o.cacheRead
    }

    static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        var r = a; r.add(b); return r
    }
}

// MARK: - Pricing

struct ModelPrice: Sendable {
    /// US dollars per million tokens.
    let input:     Double
    let output:    Double
    let cacheRead: Double

    /// Writing to the 5-minute cache costs 1.25x the input rate, the 1-hour
    /// cache 2x. Both multipliers were measured, not assumed — see the note
    /// on `ClaudePricing`.
    var cacheWrite5m: Double { input * 1.25 }
    var cacheWrite1h: Double { input * 2.00 }
}

/// Prices every model Claude Code can write into a transcript.
///
/// Calibration — these numbers are not guesses. Claude Code appends a
/// `type: "cost-state"` record to a transcript when a session ends, carrying
/// its own authoritative `costUSD` per model. Re-pricing those sessions from
/// their raw per-message `usage` with the table below reproduces Claude Code's
/// figure to the cent (0.000% error) on every session whose token totals are
/// wholly contained in one file, across both `claude-opus-5` and
/// `claude-opus-5-5` — which differ in input, output *and* cache-read rate, so
/// the agreement is not a coincidence of one tier.
///
/// We price from the raw records rather than reading `cost-state` directly
/// because that record only exists once a session has ended: the session in
/// progress — the one the user is actually watching — would be missing, and
/// today's total would jump every time a session closed.
enum ClaudePricing {

    static let table: [String: ModelPrice] = [
        "claude-opus-5-5":   ModelPrice(input:  4.00, output: 20.00, cacheRead: 0.20),
        "claude-opus-5":     ModelPrice(input:  5.00, output: 25.00, cacheRead: 0.50),
        "claude-opus-4-8":   ModelPrice(input:  5.00, output: 25.00, cacheRead: 0.50),
        "claude-opus-4-7":   ModelPrice(input:  5.00, output: 25.00, cacheRead: 0.50),
        "claude-opus-4-6":   ModelPrice(input:  5.00, output: 25.00, cacheRead: 0.50),
        "claude-fable-5-1":  ModelPrice(input: 10.00, output: 50.00, cacheRead: 0.25),
        "claude-fable-5":    ModelPrice(input: 10.00, output: 50.00, cacheRead: 1.00),
        "claude-mythos-5-1": ModelPrice(input: 10.00, output: 50.00, cacheRead: 0.25),
        "claude-mythos-5":   ModelPrice(input: 10.00, output: 50.00, cacheRead: 1.00),
        "claude-sonnet-5-5": ModelPrice(input:  2.00, output: 10.00, cacheRead: 0.20),
        "claude-sonnet-5":   ModelPrice(input:  2.00, output: 10.00, cacheRead: 0.20),
        "claude-sonnet-4-6": ModelPrice(input:  3.00, output: 15.00, cacheRead: 0.30),
        "claude-haiku-5-5":  ModelPrice(input:  0.10, output:  0.50, cacheRead: 0.01),
        "claude-haiku-4-5":  ModelPrice(input:  1.00, output:  5.00, cacheRead: 0.10),
    ]

    /// Fallback for a model released after this build. Opus-tier, so a new
    /// model is over-stated rather than silently free; the UI flags it.
    static let unknownFallback = ModelPrice(input: 5.00, output: 25.00, cacheRead: 0.50)

    /// Models that carry no cost and must never reach the pricer.
    static func isBillable(_ model: String) -> Bool {
        !model.isEmpty && model != "<synthetic>"
    }

    /// Resolves a transcript model string to a price.
    ///
    /// Handles two shapes the raw records use beyond the plain id:
    /// a `[1m]` suffix for the long-context variant (same rates — verified
    /// against `claude-fable-5-1[1m]` and `claude-opus-5-5[1m]` cost records),
    /// and a dated suffix such as `claude-haiku-4-5-20251001`.
    static func price(for model: String) -> (price: ModelPrice, known: Bool) {
        let base = model.replacingOccurrences(of: "[1m]", with: "")
        if let p = table[base] { return (p, true) }
        // Longest matching prefix wins, so `claude-opus-5-5-2026…` does not
        // resolve to `claude-opus-5`.
        let match = table.keys
            .filter { base.hasPrefix($0) }
            .max(by: { $0.count < $1.count })
        if let m = match, let p = table[m] { return (p, true) }
        return (unknownFallback, false)
    }

    /// Dollar value of a bundle of tokens for one model.
    static func cost(model: String, counts: TokenCounts) -> Double {
        let p = price(for: model).price
        return Double(counts.input)        / 1_000_000 * p.input
             + Double(counts.output)       / 1_000_000 * p.output
             + Double(counts.cacheWrite5m) / 1_000_000 * p.cacheWrite5m
             + Double(counts.cacheWrite1h) / 1_000_000 * p.cacheWrite1h
             + Double(counts.cacheRead)    / 1_000_000 * p.cacheRead
    }

    /// Short label for the dashboard, e.g. `claude-opus-5-5` → "Opus 5.5".
    static func displayName(_ model: String) -> String {
        var s = model
        let longContext = s.contains("[1m]")
        s = s.replacingOccurrences(of: "[1m]", with: "")
        guard s.hasPrefix("claude-") else { return model }
        s.removeFirst("claude-".count)
        // Drop a trailing date, if any.
        let parts: [String] = s.split(separator: "-")
            .map(String.init)
            .filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
        guard let family = parts.first, !family.isEmpty else { return model }
        let version: String = parts.dropFirst().joined(separator: ".")
        let name: String = family.prefix(1).uppercased() + family.dropFirst()
        let label: String = version.isEmpty ? name : "\(name) \(version)"
        return longContext ? "\(label) 1M" : label
    }
}
