import SwiftUI
// The AI Agents dashboard reads Claude Code's transcripts under
// ~/.claude/projects. The App Store build is containerised and cannot
// reach them, so the whole feature compiles out there rather than
// shipping a permanently empty panel.
#if !APPSTORE

// MARK: - AI Agents dashboard
//
// Opened from the sparkles satellite below the island. Everything here is
// live: the two plan bars come from Claude Code's statusline relay or, for
// someone on the desktop app that never runs one, from Claude Code's own usage
// endpoint; the money and token figures come from its transcripts, re-read
// whenever the agent does something.

struct AgentsDashboardView: View {
    @ObservedObject var state: AppState

    private static let gutter: CGFloat = 10

    private var usage: AgentUsageSnapshot? { state.agentUsage }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: Self.gutter) {
                ClaudePlanBigCard(state: state)

                HStack(spacing: Self.gutter) {
                    SpendingCard(usage: usage, loading: state.agentUsageLoading)
                    NowCard(state: state, usage: usage)
                }
                .frame(height: 92)

                TrendCard(usage: usage)
                    .frame(height: 128)

                HStack(spacing: Self.gutter) {
                    BreakdownCard(title: "Models", icon: "square.stack.3d.up",
                                  rows: usage?.byModel ?? [], accent: "#C98B6B")
                    BreakdownCard(title: "Projects", icon: "folder",
                                  rows: usage?.byProject ?? [], accent: "#7C8BF5")
                }
                .frame(height: 118)

                ActivityCard(usage: usage)
                    .frame(height: 132)
            }
            .padding(.bottom, 4)
        }
        .onAppear {
            ClaudeUsagePoller.shared.start()
            ClaudePlanAPIPoller.shared.retain()
            state.refreshPlanRelayState()
        }
        .onDisappear {
            ClaudeUsagePoller.shared.stop()
            ClaudePlanAPIPoller.shared.release()
        }
    }
}

// MARK: - Shared chrome

/// Title row used by every card: a small tinted glyph, the name, and an
/// optional trailing note.
private struct CardTitle: View {
    let icon: String
    let text: String
    var accent: String = "#8E939C"
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(hex: accent))
            Text(loc: text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#C5C8CD"))
            Spacer(minLength: 4)
            if let trailing {
                Text(loc: trailing)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .fixedSize()
            }
        }
    }
}

/// Grouping separators need a formatter — `String(format:)` has no `%,` flag
/// and silently emits the format string itself.
private let groupedDollars: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US_POSIX")
    f.maximumFractionDigits = 0
    f.groupingSeparator = ","
    f.usesGroupingSeparator = true
    return f
}()

private func money(_ value: Double) -> String {
    // Past a thousand the cents stop telling anyone anything, and the card is
    // narrow — "$1,242" rather than "$1242.45".
    if value >= 1000 {
        let n = groupedDollars.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "$\(n)"
    }
    return String(format: "$%.2f", value)
}

private func compactTokens(_ n: Int64) -> String {
    let d = Double(n)
    if d >= 1_000_000_000 { return String(format: "%.1fB", d / 1_000_000_000) }
    if d >= 1_000_000     { return String(format: "%.1fM", d / 1_000_000) }
    if d >= 1_000         { return String(format: "%.1fK", d / 1_000) }
    return "\(n)"
}

private func relative(_ date: Date) -> String {
    let secs = Date().timeIntervalSince(date)
    if secs < 60   { return L("\(max(1, Int(secs))) sec. ago") }
    if secs < 3600 { return L("\(Int(secs / 60)) min. ago") }
    if secs < 86400 { return L("\(Int(secs / 3600)) h ago") }
    return L("\(Int(secs / 86400)) d ago")
}

// MARK: - Claude plan card

/// The session and week gauges. Wider than the compact plan card in the
/// overview, but the same numbers and the same colour rules.
private struct ClaudePlanBigCard: View {
    @ObservedObject var state: AppState
    @State private var now = Date()

    private var usage: PlanUsage? { state.claudePlanUsage }

    var body: some View {
        ZStack {
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#C98B6B"))
                    Text("Claude")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Spacer()
                    if usage != nil {
                        Text(freshness)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                }

                if state.planUsageConnected, usage != nil {
                    VStack(alignment: .leading, spacing: 13) {
                        PlanBarRow(label: "Session limit", window: usage?.fiveHour, now: now)
                        PlanBarRow(label: "Weekly", window: usage?.sevenDay, now: now, weekly: true)
                    }
                    .padding(.top, 10)
                } else {
                    ConnectPrompt(connected: state.planUsageConnected)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        // 144 is what the content actually asks for with both rows laid out
        // three lines each — measured with ImageRenderer rather than guessed,
        // because a card an inch too tall leaves a hole above the next one.
        .frame(height: state.planUsageConnected && usage != nil ? 144 : 78)
        .background(
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Color.clear.onChange(of: ctx.date) { _, d in now = d }
            }
        )
    }

    private var freshness: String {
        guard let usage else { return "" }
        let diff = now.timeIntervalSince(usage.updatedAt)
        if diff < 60 { return "just now" }
        let mins = Int(diff / 60)
        return mins < 60 ? L("\(mins) min ago") : L("\(mins / 60) h ago")
    }
}

/// Shown until one of the two sources is actually feeding figures.
///
/// Asks about `planUsageConnected` rather than the relay alone. There are two
/// ways to these numbers now, and a card that only knew about the relay would
/// offer to connect Claude Code while the ring above it was already showing a
/// percentage from the other one. Both are set up in Settings, which is where
/// this points.
private struct ConnectPrompt: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(connected
                 ? L("Waiting for a Claude Code reply")
                 : L("Connect Claude Code to see session and week usage"))
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
            Spacer(minLength: 6)
            if !connected {
                Button {
                    NotificationCenter.default.post(name: .openFullSettings, object: nil)
                } label: {
                    Text("Connect")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#0B0C0E"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: "#F5F6F8")))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// "Wed 9:00 PM", the way Claude Code writes it. Twelve-hour and `en_US_POSIX`
/// like the other formatters in this file, so the card reads the same as the
/// panel it is mirroring rather than drifting with the system locale.
private let weekResetFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE h:mm a"
    return f
}()

/// One limit, laid out the way Claude Code's own usage panel lays it out:
/// the name and what is spent on one line, the bar on its own underneath, and
/// the reset below that.
///
/// Three lines rather than the single row this used to be. Squeezing a label, a
/// bar, a percentage and a reset time onto one line left the bar about fifty
/// points wide — too short to read a proportion off, which is the only thing a
/// bar is for.
private struct PlanBarRow: View {
    let label: String
    let window: PlanWindow?
    let now: Date
    var weekly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let w = window {
                let pct = ClaudePlanGauge.effectivePct(w)

                HStack(spacing: 8) {
                    Text(loc: label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Spacer(minLength: 4)
                    Text(L("\(Int(pct.rounded()))% used"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                        .monospacedDigit()
                        .fixedSize()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Color(hex: ClaudePlanGauge.color(for: pct)))
                            .frame(width: max(0, geo.size.width * CGFloat(pct / 100)))
                    }
                }
                .frame(height: 5)

                Text(resetLabel(w))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .fixedSize()
            } else {
                HStack(spacing: 8) {
                    Text(loc: label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Spacer(minLength: 4)
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
            }
        }
    }

    /// "Resets in 4 hr 37 min" and "Resets Wed 9:00 PM", as Claude Code says
    /// them.
    private func resetLabel(_ w: PlanWindow) -> String {
        let secs = w.resetsAt.timeIntervalSince(now)
        guard secs > 0 else { return L("Resetting…") }
        if weekly { return L("Resets \(weekResetFormatter.string(from: w.resetsAt))") }
        let h = Int(secs / 3600)
        let m = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? L("Resets in \(h) hr \(m) min") : L("Resets in \(m) min")
    }
}

// MARK: - Spending

private struct SpendingCard: View {
    let usage: AgentUsageSnapshot?
    let loading: Bool

    var body: some View {
        ZStack {
            CardBackground(wash: .soft)
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(icon: "dollarsign.circle", text: "Spending",
                          accent: "#34D399", trailing: "Today")

                Text(loading && usage == nil ? "—" : money(usage?.spendToday ?? 0))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .monospacedDigit()
                    .padding(.top, 5)

                Spacer(minLength: 2)

                if let u = usage {
                    CacheBar(cacheShare: u.cacheShareToday)
                        .frame(height: 4)
                        .padding(.bottom, 5)
                    Text(L("\(compactTokens(u.tokensToday)) tokens · \(Int(u.cacheShareToday * 100))% from cache"))
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .lineLimit(1)
                } else {
                    Text(loading ? "Reading transcripts…" : "No activity yet")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }
}

/// Fresh tokens versus tokens served from cache.
private struct CacheBar: View {
    let cacheShare: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                Capsule()
                    .fill(Color(hex: "#C98B6B"))
                    .frame(width: max(2, geo.size.width * CGFloat(1 - cacheShare)))
                Capsule()
                    .fill(Color(hex: "#7C8BF5"))
            }
        }
    }
}

// MARK: - Now

private struct NowCard: View {
    @ObservedObject var state: AppState
    let usage: AgentUsageSnapshot?

    var body: some View {
        ZStack {
            CardBackground(wash: .soft)
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(icon: "clock", text: "Now", accent: "#8E939C")

                if let last = usage?.lastActivity {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#C98B6B"))
                        Text("Claude")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#C5C8CD"))
                        Spacer(minLength: 4)
                        Text(relative(last))
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .fixedSize()
                    }
                    .padding(.top, 9)
                } else {
                    Text("Nothing running")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 9)
                }

                Spacer(minLength: 0)

                if usage?.hasUnknownModel == true {
                    Text("A new model was seen — figures are estimates")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#F59E0B"))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }
}

// MARK: - Trend

private struct TrendCard: View {
    let usage: AgentUsageSnapshot?

    var body: some View {
        ZStack {
            CardBackground(wash: .soft)
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(icon: "chart.bar", text: "Trend", accent: "#7C8BF5",
                          trailing: usage.map { L("Today · \(money($0.spendToday))") })

                let hours = usage?.hourlyToday ?? Array(repeating: 0, count: 24)
                let peak = max(hours.max() ?? 0, 0.0001)

                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<24, id: \.self) { h in
                        let value = hours[h]
                        RoundedRectangle(cornerRadius: 2)
                            .fill(value > 0
                                  ? Color(hex: h < 12 ? "#C98B6B" : "#7C8BF5")
                                  : Color.white.opacity(0.05))
                            .frame(height: value > 0
                                   ? max(3, CGFloat(value / peak) * 52)
                                   : 3)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 56, alignment: .bottom)
                .padding(.top, 8)

                HStack {
                    Text("12 AM").font(.system(size: 9)).foregroundColor(Color(hex: "#6B7079"))
                    Spacer()
                    Text("12 PM").font(.system(size: 9)).foregroundColor(Color(hex: "#6B7079"))
                    Spacer()
                    Text("11 PM").font(.system(size: 9)).foregroundColor(Color(hex: "#6B7079"))
                }
                .padding(.top, 5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }
}

// MARK: - Models / Projects

private struct BreakdownCard: View {
    let title: String
    let icon: String
    let rows: [UsageRow]
    let accent: String

    var body: some View {
        ZStack {
            CardBackground(wash: .soft)
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(icon: icon, text: title, accent: accent)

                if rows.isEmpty {
                    Spacer()
                    Text("Nothing today")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                    Spacer()
                } else {
                    let peak = max(rows.first?.spend ?? 1, 0.0001)
                    VStack(spacing: 6) {
                        ForEach(rows.prefix(3)) { row in
                            HStack(spacing: 8) {
                                Text(row.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#C5C8CD"))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 92, alignment: .leading)
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(Color(hex: accent))
                                        .frame(width: max(3, geo.size.width * CGFloat(row.spend / peak)))
                                }
                                .frame(height: 4)
                                Text(money(row.spend))
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#8E939C"))
                                    .monospacedDigit()
                                    .frame(width: 54, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.top, 9)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }
}

// MARK: - Activity

private struct ActivityCard: View {
    let usage: AgentUsageSnapshot?

    private static let columns = 13
    private static let rows = 7

    var body: some View {
        ZStack {
            CardBackground(wash: .soft)
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(icon: "square.grid.3x3", text: "Activity", accent: "#8E939C",
                          trailing: usage.map { L("\($0.activeDays) active days") })

                HStack(alignment: .top, spacing: 14) {
                    grid
                    stats
                    Spacer(minLength: 0)
                }
                .padding(.top, 9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    /// 13 weeks, oldest column first, each column a Sunday-to-Saturday week.
    private var grid: some View {
        let cells = usage?.activity ?? []
        let peak = max(cells.map(\.spend).max() ?? 0, 0.0001)
        return HStack(spacing: 2.5) {
            ForEach(0..<Self.columns, id: \.self) { col in
                VStack(spacing: 2.5) {
                    ForEach(0..<Self.rows, id: \.self) { row in
                        let idx = col * Self.rows + row
                        let spend = idx < cells.count ? cells[idx].spend : 0
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(shade(spend, peak: peak))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
    }

    private func shade(_ spend: Double, peak: Double) -> Color {
        guard spend > 0 else { return Color.white.opacity(0.055) }
        // Four steps, like a contribution graph; square-rooted so a single
        // very expensive day doesn't flatten everything else to the floor.
        let t = (spend / peak).squareRoot()
        if t > 0.75 { return Color.white.opacity(0.92) }
        if t > 0.45 { return Color.white.opacity(0.62) }
        if t > 0.20 { return Color.white.opacity(0.38) }
        return Color.white.opacity(0.20)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(money(usage?.windowSpend ?? 0))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .monospacedDigit()
            Text(L("\(usage?.windowWeeks ?? 13) weeks"))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#6B7079"))
            Spacer(minLength: 6)
            if let busiest = usage?.busiestDay, busiest.spend > 0 {
                Text("Busiest day")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#6B7079"))
                Text("\(busyFormatter.string(from: busiest.day)) · \(money(busiest.spend))")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .fixedSize()
            }
        }
    }
}

private let busyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MMM d"
    return f
}()

#endif
