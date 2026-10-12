import Foundation

@main
enum ClaudeUsagePricingTests {

    static var failures = 0

    static func check(_ label: String, _ got: String, _ expected: String) {
        if got == expected {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(got.debugDescription)")
            print("    expected: \(expected.debugDescription)")
            failures += 1
        }
    }

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") }
        else      { print("  ✗ \(label)"); failures += 1 }
    }

    /// Costs are compared to the cent — Claude Code's own figure is the oracle,
    /// and the point of these cases is that we land on it exactly.
    static func checkCost(_ label: String, _ got: Double, _ expected: Double) {
        if abs(got - expected) < 0.000001 {
            print("  ✓ \(label)  $\(String(format: "%.6f", got))")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            print("    off by:   \(got - expected)")
            failures += 1
        }
    }

    static func main() {

        // ── Calibration against Claude Code's own cost records ───────────────
        //
        // When a session ends Claude Code appends a `cost-state` record with
        // the dollar figure it computed itself. Each case below is a real
        // session from a real machine: its summed per-message token counts,
        // and the cost Claude Code recorded for them. Re-pricing those tokens
        // has to reproduce that number exactly.
        //
        // The three cases are chosen to pin different constants:
        //   1 & 2  Opus 5, cache written at the 1-hour TTL  → fixes 2.00x
        //   3      Opus 5.5, cache written at the 5-minute TTL → fixes 1.25x,
        //          and a second model's input/output/cache-read rates
        //   4      the [1m] long-context variant, which bills at base rates
        print("ClaudePricing.cost — against Claude Code's own cost-state records")

        var opus5a = TokenCounts()
        opus5a.input = 184; opus5a.output = 111_152
        opus5a.cacheWrite1h = 251_682; opus5a.cacheRead = 15_637_496
        checkCost("opus-5, 1h cache, $13.12 session",
                  ClaudePricing.cost(model: "claude-opus-5", counts: opus5a),
                  13.115288000000001)

        var opus5b = TokenCounts()
        opus5b.input = 204; opus5b.output = 151_389
        opus5b.cacheWrite1h = 220_101; opus5b.cacheRead = 18_548_999
        checkCost("opus-5, 1h cache, $15.26 session",
                  ClaudePricing.cost(model: "claude-opus-5", counts: opus5b),
                  15.261254500000003)

        var opus55 = TokenCounts()
        opus55.input = 1_444; opus55.output = 32
        opus55.cacheWrite5m = 37_219
        checkCost("opus-5.5, 5m cache, $0.19 session",
                  ClaudePricing.cost(model: "claude-opus-5-5", counts: opus55),
                  0.19251100000000002)

        var long = TokenCounts()
        long.input = 17_913_088; long.output = 76_212
        long.cacheWrite5m = 754_868; long.cacheRead = 8_754_099
        checkCost("opus-5.5[1m] bills at base rates, $78.70 session",
                  ClaudePricing.cost(model: "claude-opus-5-5[1m]", counts: long),
                  78.7017518)

        // ── Model resolution ────────────────────────────────────────────────
        print("ClaudePricing.price")

        checkTrue("plain id is known",       ClaudePricing.price(for: "claude-opus-5").known)
        checkTrue("[1m] suffix is known",    ClaudePricing.price(for: "claude-fable-5-1[1m]").known)
        checkTrue("dated suffix is known",   ClaudePricing.price(for: "claude-haiku-4-5-20251001").known)
        checkTrue("unknown model is flagged", !ClaudePricing.price(for: "claude-nova-9").known)
        checkTrue("unknown model still priced",
                  ClaudePricing.cost(model: "claude-nova-9",
                                     counts: { var c = TokenCounts(); c.output = 1_000_000; return c }()) > 0)

        // A longer prefix must win, or 5.5 would silently bill at 5's rate.
        checkCost("opus-5-5 dated does not fall back to opus-5",
                  ClaudePricing.cost(model: "claude-opus-5-5-20260401",
                                     counts: { var c = TokenCounts(); c.output = 1_000_000; return c }()),
                  20.0)

        checkTrue("synthetic is not billable", !ClaudePricing.isBillable("<synthetic>"))
        checkTrue("empty is not billable",     !ClaudePricing.isBillable(""))
        checkTrue("real model is billable",     ClaudePricing.isBillable("claude-opus-5"))

        // ── Display names ───────────────────────────────────────────────────
        print("ClaudePricing.displayName")
        check("opus 5.5",   ClaudePricing.displayName("claude-opus-5-5"),   "Opus 5.5")
        check("opus 5",     ClaudePricing.displayName("claude-opus-5"),     "Opus 5")
        check("sonnet 5.5", ClaudePricing.displayName("claude-sonnet-5-5"), "Sonnet 5.5")
        check("fable 5.1",  ClaudePricing.displayName("claude-fable-5-1"),  "Fable 5.1")
        check("long ctx",   ClaudePricing.displayName("claude-fable-5-1[1m]"), "Fable 5.1 1M")
        check("dated",      ClaudePricing.displayName("claude-haiku-4-5-20251001"), "Haiku 4.5")
        check("unrecognised passes through", ClaudePricing.displayName("gpt-6"), "gpt-6")

        // ── Decoding raw usage ──────────────────────────────────────────────
        print("TokenCounts(usage:)")

        let split = TokenCounts(usage: [
            "input_tokens": 2,
            "output_tokens": 305,
            "cache_read_input_tokens": 42_303,
            "cache_creation_input_tokens": 61_728,
            "cache_creation": ["ephemeral_1h_input_tokens": 61_728,
                               "ephemeral_5m_input_tokens": 0],
        ])
        check("1h split read",  "\(split.cacheWrite1h)", "61728")
        check("5m stays zero",  "\(split.cacheWrite5m)", "0")
        check("read tokens",    "\(split.cacheRead)",    "42303")
        check("total",          "\(split.total)",        "\(2 + 305 + 42_303 + 61_728)")

        // Records written before the TTL split existed carry only the lump.
        let legacy = TokenCounts(usage: [
            "input_tokens": 10,
            "output_tokens": 20,
            "cache_creation_input_tokens": 5_000,
        ])
        check("legacy lump goes to the cheaper 5m bucket", "\(legacy.cacheWrite5m)", "5000")
        check("legacy 1h stays empty",                      "\(legacy.cacheWrite1h)", "0")

        // A lump that disagrees with the split must not be double counted.
        let both = TokenCounts(usage: [
            "cache_creation_input_tokens": 999,
            "cache_creation": ["ephemeral_5m_input_tokens": 400,
                               "ephemeral_1h_input_tokens": 600],
        ])
        check("split wins over the lump", "\(both.cacheWrite5m + both.cacheWrite1h)", "1000")

        let empty = TokenCounts(usage: [:])
        check("missing fields are zero", "\(empty.total)", "0")

        // ── Cache share ─────────────────────────────────────────────────────
        print("TokenCounts.cacheShare")
        var share = TokenCounts()
        share.input = 10; share.cacheRead = 90
        check("90% cached", "\(Int(share.cacheShare * 100))", "90")
        check("no tokens is 0, not NaN", "\(TokenCounts().cacheShare)", "0.0")

        var sum = TokenCounts(); sum.input = 1; sum.output = 2
        var other = TokenCounts(); other.input = 10; other.cacheRead = 5
        sum.add(other)
        check("add merges every field", "\(sum.input)/\(sum.output)/\(sum.cacheRead)", "11/2/5")

        print("")
        if failures == 0 {
            print("All pricing tests passed.")
        } else {
            print("\(failures) failure(s).")
            exit(1)
        }
    }
}
