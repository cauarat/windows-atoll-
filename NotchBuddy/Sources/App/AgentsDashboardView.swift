import SwiftUI
// The AI Agents dashboard reads Claude Code's transcripts under
// ~/.claude/projects. The App Store build is containerised and cannot
// reach them, so the whole feature compiles out there rather than
// shipping a permanently empty panel.
#if !APPSTORE

// MARK: - AI Agents dashboard
//
// Opened from the sparkles satellite below the island. Everything here is
// live: the two plan bars come from Claude Code's statusline relay, the money
// and token figures from its transcripts, re-read whenever the agent does
// something.

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
            state.refreshPlanRelayState()
        }
        .onDisappear { ClaudeUsagePoller.shared.stop() }
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
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#C5C8CD"))
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .fixedSize()
            }
        }
    }
}

private func money(_ value: Double) -> String {
    if value >= 1000 {
        return String(format: "$%,.0f", value)
            .replacingOccurrences(of: ",", with: ",")
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
    if secs < 60   { return "\(max(1, Int(secs))) sec. ago" }
    if secs < 3600 { return "\(Int(secs / 60)) min. ago" }
    if secs < 86400 { return "\(Int(secs / 3600)) h ago" }
    return "\(Int(secs / 86400)) d ago"
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

                if state.planRelayInstalled, usage != nil {
                    VStack(alignment: .leading, spacing: 7) {
                        PlanBarRow(label: "Session", window: usage?.fiveHour, now: now)
                        PlanBarRow(label: "Week", window: usage?.sevenDay, now: now, weekly: true)
                    }
                    .padding(.top, 10)
                } else {
                    ConnectPrompt(installed: state.planRelayInstalled)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .frame(height: state.planRelayInstalled && usage != nil ? 86 : 78)
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
        return mins < 60 ? "\(mins) min ago" : "\(mins / 60) h ago"
    }
}

/// Shown until Claude Code's statusline is relaying rate limits. The install
/// itself happens in Settings, which backs up and diffs settings.json before
/// touching it — this only points the way.
private struct ConnectPrompt: View {
    let installed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(installed
                 ? "Waiting for a Claude Code reply"
                 : "Connect Claude Code to see session and week usage")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
            Spacer(minLength: 6)
            if !installed {
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

private let weekResetFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "EEE H:mm"
    return f
}()

private struct PlanBarRow: View {
    let label: String
    let window: PlanWindow?
    let now: Date
    var weekly = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
                .frame(width: 52, alignment: .leading)

            if let w = window {
                let pct = ClaudePlanGauge.effectivePct(w)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Color(hex: ClaudePlanGauge.color(for: pct)))
                            .frame(width: max(0, geo.size.width * CGFloat(pct / 100)))
                    }
                }
                .frame(height: 5)

                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)

                Text(resetLabel(w))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .frame(width: 74, alignment: .trailing)
                    .fixedSize()
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                Spacer()
            }
        }
    }

    private func resetLabel(_ w: PlanWindow) -> String {
        let secs = w.resetsAt.timeIntervalSince(now)
        guard secs > 0 else { return "resetting…" }
        if weekly { return weekResetFormatter.string(from: w.resetsAt) }
        let h = Int(secs / 3600)
        let m = Int(secs.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "in \(h) h \(m)" : "in \(m) min"
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
                    Text("\(compactTokens(u.tokensToday)) tokens · \(Int(u.cacheShareToday * 100))% from cache")
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
                          trailing: usage.map { "Today · \(money($0.spendToday))" })

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
                          trailing: usage.map { "\($0.activeDays) active days" })

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
            Text("\(usage?.windowWeeks ?? 13) weeks")
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
