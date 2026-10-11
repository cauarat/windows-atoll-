import Foundation

// MARK: - Snapshot handed to the UI

struct UsageRow: Sendable, Identifiable {
    let name:  String
    let spend: Double
    var id: String { name }
}

struct ActivityDay: Sendable {
    let day:   Date
    let spend: Double
}

/// Everything the AI Agents dashboard draws, computed off the main actor.
struct AgentUsageSnapshot: Sendable {
    var spendToday:      Double  = 0
    var tokensToday:     Int64   = 0
    var cacheShareToday: Double  = 0
    /// 24 buckets, local midnight → 23:00, in dollars.
    var hourlyToday:     [Double] = Array(repeating: 0, count: 24)
    var byModel:         [UsageRow] = []   // today, richest first
    var byProject:       [UsageRow] = []   // today, richest first
    var activity:        [ActivityDay] = []  // the whole window, oldest first
    var windowSpend:     Double  = 0
    var windowWeeks:     Int     = 0
    var activeDays:      Int     = 0
    var busiestDay:      ActivityDay?
    var lastActivity:    Date?
    /// A model with no entry in the price table was seen; figures are estimates.
    var hasUnknownModel: Bool    = false
    var computedAt:      Date    = .distantPast
    /// No transcripts found at all — Claude Code has never run here.
    var isEmpty:         Bool    = true
}
