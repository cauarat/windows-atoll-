import Foundation

// Hydration: what the rules promise, and a script both platforms run.
//
// `--dump` prints the script's samples for tests/hydration-parity.ts, which
// runs the same steps through windows/src/core/hydration.ts and compares. Both
// sides read days in UTC so a CI runner in another zone sees the same ones.

@main
enum HydrationTests {
    static var failures = 0

    static func check(_ ok: Bool, _ what: String) {
        print("  \(ok ? "✓" : "✗") \(what)")
        if !ok { failures += 1 }
    }

    static let calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// A moment in November 2026.
    static func nov(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    static func stamp(_ date: Date?) -> String {
        guard let date else { return "nil" }
        return String(Int(date.timeIntervalSince1970))
    }

    static func next(
        now: Date,
        settings: HydrationSettings = HydrationSettings(),
        schedule: HydrationSchedule = HydrationSchedule(),
        done: Bool = false
    ) -> Date? {
        HydrationScheduler.next(after: now, settings: settings, schedule: schedule, goalDoneToday: done, calendar: calendar)
    }

    static func dot(_ d: HydrationDot) -> String {
        switch d {
        case .frozen: return "frozen"
        case .rest: return "rest"
        case .missed: return "missed"
        case .today: return "today"
        case .future: return "future"
        }
    }

    /// The script. tests/hydration-parity.ts has the same steps, in the same
    /// order: change one and change the other.
    static func script() -> [String] {
        var lines: [String] = []
        func add(_ name: String, _ values: [String]) { lines.append(([name] + values).joined(separator: "\t")) }

        // Estimates.
        let answers: [(String, HydrationAnswers)] = [
            ("empty", HydrationAnswers()),
            ("female-moderate-hot", HydrationAnswers(reference: .female, activity: .moderate, climate: .hot)),
            ("male-everything", HydrationAnswers(reference: .male, weight: .over85, activity: .intense, sweat: .lots, climate: .intenseHeat)),
            ("female-light-still", HydrationAnswers(reference: .female, weight: .under55, activity: .still)),
            ("over65", HydrationAnswers(age: .over65, reference: .skipped, sweat: .some)),
        ]
        for (name, a) in answers {
            let e = HydrationEstimator.estimate(a)
            add("estimate-\(name)", [String(e.totalML), String(e.lines.count)] + e.lines.map { String($0.ml) })
        }

        // Who gets no number.
        let blocked: [(String, HydrationAnswers)] = [
            ("none", HydrationAnswers(age: .from18to39, pregnancy: .no, health: HydrationHealth.none)),
            ("minor", HydrationAnswers(age: .under18)),
            ("pregnant", HydrationAnswers(pregnancy: .pregnant)),
            ("breastfeeding", HydrationAnswers(pregnancy: .breastfeeding)),
            ("pregnancy-skipped", HydrationAnswers(pregnancy: .skipped)),
            ("organs", HydrationAnswers(health: .organs)),
            ("medication", HydrationAnswers(health: .medication)),
            ("guidance", HydrationAnswers(health: .guidance)),
            ("other", HydrationAnswers(health: .other)),
            ("health-skipped", HydrationAnswers(health: .skipped)),
        ]
        for (name, a) in blocked {
            add("block-\(name)", [HydrationEstimator.block(for: a)?.rawValue ?? "nil"])
        }

        // Goals.
        let goals: [(String, HydrationGoal)] = [
            ("estimated", HydrationGoal(kind: .estimated, ml: 2200)),
            ("target", HydrationGoal(kind: .target, ml: 1500)),
            ("limit", HydrationGoal(kind: .limit, ml: 1500)),
            ("none", HydrationGoal.unset),
        ]
        for (name, g) in goals {
            for total in [0, 1300, 1500, 2200, 2450] {
                add("goal-\(name)-\(total)", [
                    g.remindersDone(totalML: total, portionML: 250) ? "1" : "0",
                    g.celebrates(totalML: total) ? "1" : "0",
                    g.countsForStreak(totalML: total, entries: total > 0 ? 1 : 0) ? "1" : "0",
                    String(format: "%.6f", g.level(totalML: total)),
                ])
            }
        }

        // Days start with the online window, not at midnight.
        for (name, moment) in [("morning", nov(19, 9)), ("before-window", nov(19, 6)), ("after-midnight", nov(20, 0, 30)), ("at-start", nov(19, 8))] {
            add("day-\(name)", [HydrationDay.key(containing: moment, windowStart: 8 * 60, calendar: calendar)])
        }
        add("week", [HydrationDay.weekKey("2026-11-19", calendar: calendar) ?? "nil", HydrationDay.weekKey("2026-11-23", calendar: calendar) ?? "nil"])

        // A streak across a missed day, an undo, a reset and a new week.
        var streak = HydrationStreak()
        func streakLine(_ name: String, today: String) {
            add("streak-\(name)", [String(streak.days), streak.lastDay ?? "nil", String(streak.rests)]
                + streak.week(today: today, calendar: calendar).map(dot))
        }
        streak.settle(today: "2026-11-16", calendar: calendar); streak.freeze("2026-11-16")
        streakLine("monday", today: "2026-11-16")
        streak.settle(today: "2026-11-17", calendar: calendar); streak.freeze("2026-11-17")
        streak.settle(today: "2026-11-19", calendar: calendar)
        streakLine("rested", today: "2026-11-19")
        streak.freeze("2026-11-19"); streak.freeze("2026-11-19")
        streakLine("thursday", today: "2026-11-19")
        streak.unfreeze("2026-11-19")
        streakLine("undone", today: "2026-11-19")
        streak.freeze("2026-11-19")
        streak.settle(today: "2026-11-21", calendar: calendar)
        streakLine("reset", today: "2026-11-21")
        streak.freeze("2026-11-21")
        streak.settle(today: "2026-11-23", calendar: calendar)
        streak.settle(today: "2026-11-23", calendar: calendar)
        streakLine("new-week", today: "2026-11-23")

        // Reminders.
        var s = HydrationSettings()
        var sch = HydrationSchedule()
        add("next-first", [stamp(next(now: nov(19, 9)))])
        sch.lastLogAt = nov(19, 10, 15)
        add("next-after-log", [stamp(next(now: nov(19, 10, 20), schedule: sch))])
        sch.hotDay = "2026-11-19"
        add("next-hot", [stamp(next(now: nov(19, 10, 20), schedule: sch))])
        sch.hotDay = "2026-11-18"
        add("next-hot-expired", [stamp(next(now: nov(19, 10, 20), schedule: sch))])
        sch.hotDay = nil; sch.ignored = 3
        add("next-ignored", [stamp(next(now: nov(19, 10, 20), schedule: sch))])

        sch = HydrationSchedule(); sch.lastLogAt = nov(19, 10, 45)
        s.quietEnabled = true
        add("next-quiet", [stamp(next(now: nov(19, 10, 50), settings: s, schedule: sch))])
        s.quietEnabled = false
        sch.pause = .until(nov(19, 15))
        add("next-paused-until", [stamp(next(now: nov(19, 10, 50), settings: s, schedule: sch))])
        sch.pause = .indefinitely
        add("next-paused", [stamp(next(now: nov(19, 10, 50), settings: s, schedule: sch))])

        sch = HydrationSchedule(); sch.lastReminderAt = nov(19, 12); sch.snoozedUntil = nov(19, 12, 30)
        add("next-snoozed", [stamp(next(now: nov(19, 12, 1), schedule: sch))])
        sch = HydrationSchedule(); sch.lastLogAt = nov(19, 9)
        add("next-late", [stamp(next(now: nov(19, 14), schedule: sch))])
        sch.lastLogAt = nov(19, 14)
        add("next-done-stop", [stamp(next(now: nov(19, 15), schedule: sch, done: true))])
        s.afterGoal = .light; sch.lastLogAt = nov(19, 15)
        add("next-done-light", [stamp(next(now: nov(19, 15, 5), settings: s, schedule: sch, done: true))])
        s.afterGoal = .stop; sch.lastLogAt = nov(19, 20, 30)
        add("next-tail", [stamp(next(now: nov(19, 20, 31), settings: s, schedule: sch))])
        add("next-before-window", [stamp(next(now: nov(19, 6)))])

        s = HydrationSettings(); s.windowStart = 20 * 60; s.windowEnd = 4 * 60
        sch = HydrationSchedule(); sch.lastLogAt = nov(19, 22, 30)
        add("next-night-window", [stamp(next(now: nov(19, 23), settings: s, schedule: sch))])
        s = HydrationSettings(); s.windowEnd = 2 * 60; s.quietEnabled = true; s.quietStart = 23 * 60; s.quietEnd = 30
        sch = HydrationSchedule(); sch.lastLogAt = nov(19, 21, 45)
        add("next-night-quiet", [stamp(next(now: nov(19, 21, 50), settings: s, schedule: sch))])
        s = HydrationSettings(); s.enabled = false
        add("next-off", [stamp(next(now: nov(19, 9), settings: s))])

        // The row of dots in Settings.
        s = HydrationSettings()
        add("timeline", HydrationScheduler.timeline(settings: s, hot: false).map(String.init))
        add("timeline-hot", HydrationScheduler.timeline(settings: s, hot: true).map(String.init))
        s.quietEnabled = true
        add("timeline-quiet", HydrationScheduler.timeline(settings: s, hot: false).map(String.init))
        s.intervalMinutes = 45
        add("timeline-45", HydrationScheduler.timeline(settings: s, hot: false).map(String.init))

        // Amounts.
        add("amounts", [0, 850, 1000, 1100, 1250, 2050, 2200, 3400].map { HydrationFormat.amount($0, decimalSeparator: ",") })
        add("clock", [0, 480, 810, 1320, 1470].map { HydrationFormat.clock($0) })
        return lines
    }

    static func value(_ name: String, in lines: [String]) -> [String] {
        guard let line = lines.first(where: { $0.hasPrefix(name + "\t") }) else { return [] }
        return Array(line.split(separator: "\t", omittingEmptySubsequences: false).dropFirst().map(String.init))
    }

    static func main() {
        let lines = script()
        if CommandLine.arguments.contains("--dump") {
            print(lines.joined(separator: "\n"))
            return
        }

        print("Hydration")
        func v(_ name: String) -> [String] { value(name, in: lines) }

        check(v("estimate-empty").first == "2000", "no answers start from 2.0 L")
        check(v("estimate-female-moderate-hot").first == "2200", "the canvas example: 1.8 L + 300 + 100 = 2.2 L")
        check(v("estimate-male-everything").first == "3300", "the most the questions can add up to is 3.3 L")
        check(v("estimate-female-light-still").first == "1600", "and the least is 1.6 L")
        check(v("estimate-over65") == ["2100", "3", "2000", "100", "0"], "65+ is shown and changes nothing")

        check(v("block-none") == ["nil"], "a healthy adult gets an estimate")
        check(v("block-minor") == ["minor"], "under 18 gets none")
        check(v("block-pregnant") == ["pregnant"] && v("block-breastfeeding") == ["breastfeeding"], "nor pregnancy or breastfeeding")
        check(v("block-organs") == ["organs"] && v("block-medication") == ["medication"] && v("block-guidance") == ["guidance"], "nor a condition, a medicine or a doctor's guidance")
        check(v("block-pregnancy-skipped") == ["pregnancySkipped"] && v("block-health-skipped") == ["healthSkipped"], "nor an unanswered health question")

        check(v("goal-estimated-2200") == ["1", "1", "1", "1.000000"], "an estimate reached: reminders stop, Mochi celebrates, the day counts")
        check(v("goal-estimated-2450")[3] == "1.000000", "past the goal the glass stays full, it does not overflow")
        check(v("goal-target-1500") == ["1", "0", "1", "1.000000"], "a manual target is never celebrated by volume")
        check(v("goal-limit-1300")[0] == "1", "a limit stops reminders one serving early")
        check(v("goal-limit-0")[2] == "0" && v("goal-limit-1300")[2] == "1", "with a manual goal, logging is what counts for the streak")
        check(v("goal-none-2450") == ["0", "0", "1", "0.500000"], "with no goal the glass sits half full and nothing ends")

        check(v("day-morning") == ["2026-11-19"] && v("day-at-start") == ["2026-11-19"], "the day starts with the online window")
        check(v("day-before-window") == ["2026-11-18"] && v("day-after-midnight") == ["2026-11-19"], "a glass after midnight belongs to the day before")
        check(v("week") == ["2026-W47", "2026-W48"], "rest days are granted by ISO week")

        check(v("streak-monday") == ["1", "2026-11-16", "1", "frozen", "future", "future", "future", "future", "future", "future"], "the first day freezes and the week grants a rest day")
        check(v("streak-rested") == ["2", "2026-11-17", "0", "frozen", "frozen", "rest", "today", "future", "future", "future"], "a missed day spends the rest day and keeps the count")
        check(v("streak-thursday")[0] == "3", "freezing the same day twice counts once")
        check(Array(v("streak-undone").prefix(2)) == ["2", "2026-11-17"], "undo gives the day back")
        check(Array(v("streak-reset").prefix(3)) == ["0", "nil", "0"] && v("streak-reset")[7] == "missed", "with no rest day left the count starts over")
        check(Array(v("streak-new-week").prefix(3)) == ["1", "2026-11-21", "0"], "settling twice spends one rest day, not two")

        check(v("next-first") == [stamp(nov(19, 9, 30))], "the first reminder is one interval into the window")
        check(v("next-after-log") == [stamp(nov(19, 11, 45))], "a log restarts the interval")
        check(v("next-hot") == [stamp(nov(19, 11, 25))], "a hot day brings them a little closer")
        check(v("next-hot-expired") == v("next-after-log"), "and only that day")
        check(v("next-ignored") == [stamp(nov(19, 12, 30))], "three unanswered reminders widen the interval")
        check(v("next-quiet") == [stamp(nov(19, 13, 30))], "quiet hours push a reminder to their end")
        check(v("next-paused-until") == [stamp(nov(19, 15))] && v("next-paused") == ["nil"], "a pause holds them, forever if asked")
        check(v("next-snoozed") == [stamp(nov(19, 12, 30))], "later means thirty minutes")
        check(v("next-late") == [stamp(nov(19, 14, 1))], "a missed reminder shows once, a minute after wake")
        check(v("next-done-stop") == [stamp(nov(20, 9, 30))], "the goal ends the day's reminders")
        check(v("next-done-light") == [stamp(nov(19, 18))], "or leaves one every three hours")
        check(v("next-tail") == [stamp(nov(20, 9, 30))], "nothing in the window's last hour")
        check(v("next-before-window") == [stamp(nov(19, 9, 30))], "before the window, the next one is this morning's")
        check(v("next-night-window") == [stamp(nov(20, 0))], "a window can cross midnight")
        check(v("next-night-quiet") == [stamp(nov(20, 0, 30))], "and so can quiet hours")
        check(v("next-off") == ["nil"], "off means off")

        check(v("timeline") == ["570", "660", "750", "840", "930", "1020", "1110", "1200"], "eight reminders in a default day")
        check(v("timeline-hot").count == 11 && v("timeline-hot").first == "550", "eleven on a hot one")
        check(v("timeline-quiet") == ["570", "660", "810", "900", "990", "1080", "1170", "1260"], "quiet hours shift the ones after them")
        check(v("amounts") == ["0 ml", "850 ml", "1 L", "1,1 L", "1,25 L", "2,05 L", "2,2 L", "3,4 L"], "amounts switch to litres at one")
        check(v("clock") == ["00:00", "08:00", "13:30", "22:00", "00:30"], "minutes read as a clock")

        print("")
        if failures > 0 {
            print("\(failures) failed")
            exit(1)
        }
        print("Hydration tests passed")
    }
}
