import Foundation

// Hydration: the rules, with no UI and no clock of their own.
//
// Everything here is a pure function of its arguments, so the same vectors can
// be run against the TypeScript twin (`windows/src/core/hydration.ts`). The
// numbers are a product heuristic anchored on public reference intakes (EFSA,
// the US National Academies, NHMRC) — a starting estimate for a healthy adult,
// never a prescription. `HydrationEstimator.block` lists who gets no number.

// MARK: - Answers

enum HydrationAge: String, Codable, CaseIterable, Sendable {
    case under18, from18to39, from40to64, over65, skipped
}

enum HydrationReference: String, Codable, CaseIterable, Sendable {
    case female, male, skipped
}

enum HydrationWeight: String, Codable, CaseIterable, Sendable {
    case under55, from55to85, over85, skipped
}

enum HydrationActivity: String, Codable, CaseIterable, Sendable {
    case still, light, moderate, intense
}

enum HydrationSweat: String, Codable, CaseIterable, Sendable {
    case little, some, lots
}

enum HydrationClimate: String, Codable, CaseIterable, Sendable {
    case mild, hot, intenseHeat
}

enum HydrationPregnancy: String, Codable, CaseIterable, Sendable {
    case no, pregnant, breastfeeding, skipped
}

enum HydrationHealth: String, Codable, CaseIterable, Sendable {
    case none, organs, medication, guidance, other, skipped
}

struct HydrationAnswers: Codable, Equatable, Sendable {
    var age: HydrationAge?
    var reference: HydrationReference?
    var weight: HydrationWeight?
    var activity: HydrationActivity?
    var sweat: HydrationSweat?
    var climate: HydrationClimate?
    var pregnancy: HydrationPregnancy?
    var health: HydrationHealth?
}

// MARK: - Estimate

/// Why the app gives no automatic number. Each one sends the person to the
/// manual goal and to whoever looks after their health.
enum HydrationBlock: String, Equatable, Sendable {
    case minor
    case pregnant, breastfeeding, pregnancySkipped
    case organs, medication, guidance, otherCondition, healthSkipped
}

enum HydrationPart: Equatable, Sendable {
    case base(HydrationReference)
    case weight(HydrationWeight)
    case activity(HydrationActivity)
    case sweat(HydrationSweat)
    case climate(HydrationClimate)
    /// Activity, sweat and climate measure partly the same thing: together
    /// they never add more than `HydrationEstimator.extrasCap`.
    case cap
    /// Shown so the person sees age was considered: it changes nothing.
    case over65
}

struct HydrationLine: Equatable, Sendable {
    let part: HydrationPart
    let ml: Int
}

struct HydrationEstimate: Equatable, Sendable {
    let totalML: Int
    let lines: [HydrationLine]
}

enum HydrationEstimator {
    static let extrasCap = 800
    static let minimumML = 1600
    static let maximumML = 3400

    static func block(for a: HydrationAnswers) -> HydrationBlock? {
        if a.age == .under18 { return .minor }
        switch a.pregnancy {
        case .pregnant: return .pregnant
        case .breastfeeding: return .breastfeeding
        case .skipped: return .pregnancySkipped
        case .no, .none: break
        }
        switch a.health {
        case .organs: return .organs
        case .medication: return .medication
        case .guidance: return .guidance
        case .other: return .otherCondition
        case .skipped: return .healthSkipped
        case .some(HydrationHealth.none), nil: break
        }
        return nil
    }

    static func baseML(_ reference: HydrationReference) -> Int {
        switch reference {
        case .female: return 1800
        case .male: return 2300
        case .skipped: return 2000
        }
    }

    static func weightML(_ w: HydrationWeight) -> Int {
        switch w {
        case .under55: return -200
        case .over85: return 200
        case .from55to85, .skipped: return 0
        }
    }

    static func activityML(_ a: HydrationActivity) -> Int {
        switch a {
        case .still: return 0
        case .light: return 100
        case .moderate: return 300
        case .intense: return 400
        }
    }

    static func sweatML(_ s: HydrationSweat) -> Int {
        switch s {
        case .little: return 0
        case .some: return 100
        case .lots: return 200
        }
    }

    static func climateML(_ c: HydrationClimate) -> Int {
        switch c {
        case .mild: return 0
        case .hot: return 100
        case .intenseHeat: return 200
        }
    }

    /// The estimate for answers that are not blocked. An unanswered question
    /// counts as "no adjustment", so a half-filled form still gives a number.
    static func estimate(_ a: HydrationAnswers) -> HydrationEstimate {
        let reference = a.reference ?? .skipped
        var lines = [HydrationLine(part: .base(reference), ml: baseML(reference))]
        var total = baseML(reference)

        if let w = a.weight, weightML(w) != 0 {
            lines.append(HydrationLine(part: .weight(w), ml: weightML(w)))
            total += weightML(w)
        }

        var extras = 0
        if let act = a.activity, activityML(act) != 0 {
            lines.append(HydrationLine(part: .activity(act), ml: activityML(act)))
            extras += activityML(act)
        }
        if let s = a.sweat, sweatML(s) != 0 {
            lines.append(HydrationLine(part: .sweat(s), ml: sweatML(s)))
            extras += sweatML(s)
        }
        if let c = a.climate, climateML(c) != 0 {
            lines.append(HydrationLine(part: .climate(c), ml: climateML(c)))
            extras += climateML(c)
        }
        if extras > extrasCap {
            lines.append(HydrationLine(part: .cap, ml: extrasCap - extras))
            extras = extrasCap
        }
        total += extras

        if a.age == .over65 { lines.append(HydrationLine(part: .over65, ml: 0)) }

        let rounded = Int((Double(total) / 100).rounded()) * 100
        return HydrationEstimate(totalML: min(maximumML, max(minimumML, rounded)), lines: lines)
    }
}

// MARK: - Goal

enum HydrationGoalKind: String, Codable, Sendable {
    /// From the questions: a target, celebrated when reached.
    case estimated
    /// Typed by the person as something to reach.
    case target
    /// Typed by the person as something not to pass (a fluid restriction).
    case limit
    /// Log only.
    case none
}

struct HydrationGoal: Codable, Equatable, Sendable {
    var kind: HydrationGoalKind
    var ml: Int

    static let unset = HydrationGoal(kind: .none, ml: 0)

    /// Reminders stop for the day. A limit stops them one serving early, so the
    /// app never nudges someone past the number their doctor gave them.
    func remindersDone(totalML: Int, portionML: Int) -> Bool {
        switch kind {
        case .estimated, .target: return ml > 0 && totalML >= ml
        case .limit: return ml > 0 && totalML + portionML > ml
        case .none: return false
        }
    }

    /// The glass is full and Mochi celebrates. Only an estimate is celebrated:
    /// a manual number may be a limit, and volume is not a prize there.
    func celebrates(totalML: Int) -> Bool {
        kind == .estimated && ml > 0 && totalML >= ml
    }

    /// The day counts for the streak. With a manual goal, logging is enough.
    func countsForStreak(totalML: Int, entries: Int) -> Bool {
        switch kind {
        case .estimated: return ml > 0 && totalML >= ml
        case .target, .limit, .none: return entries > 0
        }
    }

    /// 0…1 for the glass. A limit fills toward the limit too.
    func level(totalML: Int) -> Double {
        guard ml > 0 else { return totalML > 0 ? 0.5 : 0 }
        return min(1, max(0, Double(totalML) / Double(ml)))
    }
}

// MARK: - Day and log

struct HydrationEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var ml: Int
    var at: Date
}

/// Minutes since midnight, 0..<1440.
typealias HydrationMinute = Int

enum HydrationDay {
    /// The hydration day a moment belongs to starts when the person's online
    /// window starts, not at midnight: a glass at 00:30 belongs to "yesterday".
    static func start(containing date: Date, windowStart: HydrationMinute, calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: date)
        let todayStart = calendar.date(byAdding: .minute, value: windowStart, to: midnight) ?? midnight
        if date >= todayStart { return todayStart }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
        return calendar.date(byAdding: .minute, value: windowStart, to: yesterday) ?? yesterday
    }

    static func key(for dayStart: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: dayStart)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func key(containing date: Date, windowStart: HydrationMinute, calendar: Calendar) -> String {
        key(for: start(containing: date, windowStart: windowStart, calendar: calendar), calendar: calendar)
    }

    static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func key(_ key: String, offsetBy days: Int, calendar: Calendar) -> String? {
        guard let d = date(fromKey: key, calendar: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: d) else { return nil }
        return self.key(for: moved, calendar: calendar)
    }

    /// "2026-W47": the week a freeze is granted for.
    static func weekKey(_ key: String, calendar: Calendar) -> String? {
        guard let d = date(fromKey: key, calendar: calendar) else { return nil }
        let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }
}

// MARK: - Streak

enum HydrationMark: String, Codable, Sendable {
    /// The day counted: it "froze".
    case frozen
    /// The day was missed and a rest day covered it.
    case rest
}

/// What one weekday dot shows.
enum HydrationDot: Equatable, Sendable {
    case frozen, rest, missed, today, future
}

struct HydrationStreak: Codable, Equatable, Sendable {
    var days = 0
    /// The last day that counted.
    var lastDay: String?
    /// Rest days in the bank.
    var rests = 0
    var lastGrantWeek: String?
    var marks: [String: HydrationMark] = [:]

    static let maxRests = 2
    static let keptMarks = 28

    /// Run at the start of a day (and at launch): grants the week's rest day and
    /// settles the days missed since the streak last moved. A missed day spends
    /// a rest day; with none left the count starts over — quietly.
    mutating func settle(today: String, calendar: Calendar) {
        if let week = HydrationDay.weekKey(today, calendar: calendar), week != lastGrantWeek {
            lastGrantWeek = week
            rests = min(Self.maxRests, rests + 1)
        }
        if let last = lastDay, last < today {
            var day = HydrationDay.key(last, offsetBy: 1, calendar: calendar)
            var guardCount = 0
            while let d = day, d < today, guardCount < 400 {
                guardCount += 1
                if marks[d] == nil {
                    if rests > 0 {
                        rests -= 1
                        marks[d] = .rest
                    } else {
                        days = 0
                        lastDay = nil
                        break
                    }
                }
                day = HydrationDay.key(d, offsetBy: 1, calendar: calendar)
            }
        }
        if let oldest = HydrationDay.key(today, offsetBy: -Self.keptMarks, calendar: calendar) {
            marks = marks.filter { $0.key >= oldest }
        }
    }

    /// The day counted. Safe to call again for the same day.
    mutating func freeze(_ today: String) {
        guard marks[today] != .frozen else { return }
        marks[today] = .frozen
        days += 1
        lastDay = today
    }

    /// Undo took the day back under the goal.
    mutating func unfreeze(_ today: String) {
        guard marks[today] == .frozen else { return }
        marks[today] = nil
        days = max(0, days - 1)
        lastDay = marks.filter { $0.value == .frozen && $0.key < today }.keys.max()
    }

    func isFrozen(_ day: String) -> Bool { marks[day] == .frozen }

    /// Monday…Sunday of the week `today` is in.
    func week(today: String, calendar: Calendar) -> [HydrationDot] {
        guard let date = HydrationDay.date(fromKey: today, calendar: calendar) else { return [] }
        let weekday = calendar.component(.weekday, from: date)   // 1 = Sunday
        let fromMonday = (weekday + 5) % 7
        return (0..<7).map { i in
            let offset = i - fromMonday
            guard let key = HydrationDay.key(today, offsetBy: offset, calendar: calendar) else { return .future }
            if let mark = marks[key] { return mark == .frozen ? .frozen : .rest }
            if offset == 0 { return .today }
            return offset > 0 ? .future : .missed
        }
    }
}

// MARK: - Reminders

enum HydrationAfterGoal: String, Codable, Sendable {
    case stop, light
}

struct HydrationSettings: Codable, Equatable, Sendable {
    var enabled = true
    /// "I'm online from … to …": reminders only happen inside it.
    var windowStart: HydrationMinute = 8 * 60
    var windowEnd: HydrationMinute = 22 * 60
    var intervalMinutes = 90
    var quietEnabled = false
    var quietStart: HydrationMinute = 12 * 60
    var quietEnd: HydrationMinute = 13 * 60 + 30
    var holdDuringFocus = true
    var afterGoal: HydrationAfterGoal = .stop
    var streakEnabled = true
    var portionML = 250

    static let intervals = [45, 60, 90, 120]
    static let portions = [150, 250, 350, 500]
    /// No reminder in the last hour of the window.
    static let tailMinutes = 60
    static let lightIntervalMinutes = 180
    static let minimumIntervalMinutes = 30
    static let snoozeMinutes = 30
    /// A reminder that came due while the Mac slept shows once, a little after
    /// wake — never a stack of the ones that were missed.
    static let lateGraceSeconds: TimeInterval = 60

    var windowLength: Int {
        let length = windowEnd - windowStart
        return length > 0 ? length : length + 24 * 60
    }
}

enum HydrationPause: Codable, Equatable, Sendable {
    case none
    case until(Date)
    case indefinitely
}

struct HydrationSchedule: Codable, Equatable, Sendable {
    var pause: HydrationPause = .none
    /// The day key "today is hot / I moved more" applies to. It expires with the day.
    var hotDay: String?
    var lastLogAt: Date?
    var lastReminderAt: Date?
    var snoozedUntil: Date?
    /// Reminders shown since the last log or answer.
    var ignored = 0
}

enum HydrationScheduler {
    /// Minutes between reminders, or nil when the day's reminders are over.
    static func interval(settings: HydrationSettings, hot: Bool, ignored: Int, goalDone: Bool) -> Int? {
        if goalDone {
            return settings.afterGoal == .light ? HydrationSettings.lightIntervalMinutes : nil
        }
        var minutes = Double(settings.intervalMinutes)
        if hot { minutes *= 0.75 }
        if ignored >= 3 { minutes *= 1.5 }
        let rounded = Int((minutes / 5).rounded()) * 5
        return max(HydrationSettings.minimumIntervalMinutes, rounded)
    }

    static func minuteOfDay(_ date: Date, calendar: Calendar) -> HydrationMinute {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// The end of the quiet hours `date` falls in, or nil when it is outside them.
    static func quietEnd(for date: Date, settings: HydrationSettings, calendar: Calendar) -> Date? {
        guard settings.quietEnabled, settings.quietStart != settings.quietEnd else { return nil }
        let m = minuteOfDay(date, calendar: calendar)
        let midnight = calendar.startOfDay(for: date)
        if settings.quietStart < settings.quietEnd {
            guard m >= settings.quietStart, m < settings.quietEnd else { return nil }
            return calendar.date(byAdding: .minute, value: settings.quietEnd, to: midnight)
        }
        // Quiet hours cross midnight.
        if m >= settings.quietStart {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
            return calendar.date(byAdding: .minute, value: settings.quietEnd, to: tomorrow)
        }
        if m < settings.quietEnd {
            return calendar.date(byAdding: .minute, value: settings.quietEnd, to: midnight)
        }
        return nil
    }

    /// When the next reminder is due, on the wall clock. One deadline, not a
    /// ticker: the caller arms a single timer for it and recomputes on wake, on
    /// every log and on every settings change.
    static func next(
        after now: Date,
        settings: HydrationSettings,
        schedule: HydrationSchedule,
        goalDoneToday: Bool,
        calendar: Calendar
    ) -> Date? {
        guard settings.enabled else { return nil }
        if case .indefinitely = schedule.pause { return nil }

        let today = HydrationDay.start(containing: now, windowStart: settings.windowStart, calendar: calendar)
        var dayStart = today
        for _ in 0..<3 {
            let isToday = dayStart == today
            let key = HydrationDay.key(for: dayStart, calendar: calendar)
            let minutes = interval(
                settings: settings,
                hot: schedule.hotDay == key,
                ignored: isToday ? schedule.ignored : 0,
                goalDone: isToday && goalDoneToday
            )
            if let minutes {
                let end = dayStart.addingTimeInterval(TimeInterval(settings.windowLength * 60))
                let last = end.addingTimeInterval(TimeInterval(-HydrationSettings.tailMinutes * 60))

                var anchor = dayStart
                for moment in [schedule.lastLogAt, schedule.lastReminderAt] {
                    if let moment, moment > anchor, moment <= now { anchor = moment }
                }
                var due = anchor.addingTimeInterval(TimeInterval(minutes * 60))
                if isToday, let snoozed = schedule.snoozedUntil, snoozed > now { due = snoozed }
                if due < now { due = now.addingTimeInterval(HydrationSettings.lateGraceSeconds) }
                if case .until(let resume) = schedule.pause, resume > due { due = resume }
                if let quietEnd = quietEnd(for: due, settings: settings, calendar: calendar) { due = quietEnd }
                if due <= last { return due }
            }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            dayStart = tomorrow
        }
        return nil
    }

    /// Where a day's reminders would fall if nothing were logged: the row of
    /// dots in Settings. Minutes since midnight, possibly past 1440 when the
    /// window crosses midnight.
    static func timeline(settings: HydrationSettings, hot: Bool) -> [Int] {
        guard let step = interval(settings: settings, hot: hot, ignored: 0, goalDone: false) else { return [] }
        let start = settings.windowStart
        let last = start + settings.windowLength - HydrationSettings.tailMinutes
        var quietStart = settings.quietStart
        var quietEnd = settings.quietEnd
        if quietEnd <= quietStart { quietEnd += 24 * 60 }
        if quietEnd <= start { quietStart += 24 * 60; quietEnd += 24 * 60 }

        var result: [Int] = []
        var t = start + step
        while t <= last, result.count < 64 {
            var due = t
            if settings.quietEnabled, settings.quietStart != settings.quietEnd, due >= quietStart, due < quietEnd {
                due = quietEnd
            }
            if due <= last { result.append(due) }
            t = due + step
        }
        return result
    }
}

// MARK: - Amounts as text

enum HydrationFormat {
    /// "850 ml", "1.1 L", "2.25 L". The unit switches at a litre so the counter
    /// never reads "1100 ml"; the separator follows the person's locale.
    static func amount(_ ml: Int, decimalSeparator: String = Locale.current.decimalSeparator ?? ".") -> String {
        if ml < 1000 { return "\(ml) ml" }
        let hundredths = Int((Double(ml) / 10).rounded())
        let whole = hundredths / 100
        let fraction = hundredths % 100
        if fraction == 0 { return "\(whole) L" }
        let digits = fraction % 10 == 0 ? "\(fraction / 10)" : String(format: "%02d", fraction)
        return "\(whole)\(decimalSeparator)\(digits) L"
    }

    /// "08:00" from minutes since midnight.
    static func clock(_ minute: Int) -> String {
        let m = ((minute % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
