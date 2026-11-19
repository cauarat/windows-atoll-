import AppKit
import Combine
import Foundation

/// Today's glasses, the goal, the streak and the one deadline for the next
/// reminder.
///
/// The rules are in `Hydration.swift`, pure and tested; this is the part that
/// has a clock, a disk and an island to open. A singleton for the same reason
/// `FocusTimer` is one: the island builds every view at once, so state kept in
/// a view would be state kept in all of them.
///
/// Nothing here leaves the Mac. The log, the answers and the settings are one
/// JSON value in the app's own defaults.
@MainActor
final class HydrationStore: ObservableObject {
    static let shared = HydrationStore()

    /// What the reminder card is showing. Not persisted: a card that was on
    /// screen when the app quit is not on screen when it starts.
    enum Prompt: Equatable {
        case reminder, logged, snoozed, goal
    }

    enum PauseChoice {
        case hour, tomorrow, indefinitely
    }

    // MARK: Persisted

    @Published private(set) var enabled = false
    @Published private(set) var settings = HydrationSettings()
    @Published private(set) var goal = HydrationGoal.unset
    @Published private(set) var answers: HydrationAnswers?
    @Published private(set) var name = ""
    @Published private(set) var dayKey = ""
    @Published private(set) var entries: [HydrationEntry] = []
    @Published private(set) var streak = HydrationStreak()
    @Published private(set) var schedule = HydrationSchedule()
    /// A reminder was shown and nobody has answered it yet.
    @Published private(set) var awaiting = false

    // MARK: Transient

    @Published private(set) var prompt: Prompt?
    /// True for a couple of seconds after the goal is first reached.
    @Published private(set) var celebrating = false
    /// Counts logs, so the glass knows a drop fell even when the level did not move.
    @Published private(set) var pulse = 0
    @Published private(set) var nextDue: Date?

    private struct Snapshot: Codable {
        var v = 1
        var enabled = false
        var settings = HydrationSettings()
        var goal = HydrationGoal.unset
        var answers: HydrationAnswers?
        var name = ""
        var dayKey = ""
        var entries: [HydrationEntry] = []
        var streak = HydrationStreak()
        var schedule = HydrationSchedule()
        var awaiting = false
    }

    private static let defaultsKey = "hydration"
    private var work: DispatchWorkItem?
    private var celebration: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    /// Seeded for a look at the cards: nothing done in that state is written
    /// over the person's real day.
    private var previewing = false

    /// Monday-first weeks with ISO numbering, in the Mac's own time zone: the
    /// week row reads Monday to Sunday whatever the region's first weekday is.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }

    private init() {}

    // MARK: Derived

    var total: Int { entries.reduce(0) { $0 + $1.ml } }
    var level: Double { goal.level(totalML: total) }
    var remindersDone: Bool { goal.remindersDone(totalML: total, portionML: settings.portionML) }
    var celebrates: Bool { goal.celebrates(totalML: total) }
    var isHot: Bool { schedule.hotDay == dayKey && !dayKey.isEmpty }
    var isPaused: Bool {
        switch schedule.pause {
        case .none: return false
        case .indefinitely: return true
        case .until(let date): return date > Date()
        }
    }
    var week: [HydrationDot] { streak.week(today: dayKey, calendar: calendar) }

    /// The level the island's own Mochi should be filled to, or nil for the
    /// Mochi everyone knows. Glass only on the hydration cards, and only once
    /// the feature is on: every other view draws him exactly as before.
    func mascotLevel(view: IslandView, mode: IslandMode) -> CGFloat? {
        guard enabled, mode == .expanded, view == .hydration || view == .sip else { return nil }
        return CGFloat(level)
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        load()
        if name.isEmpty {
            name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        }
        rollIfNeeded()
        arm()

        // A deadline armed before the lid closed is not to be trusted after it
        // opens, and the day may have turned while the Mac slept.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rollIfNeeded()
                self?.arm()
            }
            .store(in: &cancellables)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        enabled = s.enabled
        settings = s.settings
        goal = s.goal
        answers = s.answers
        name = s.name
        dayKey = s.dayKey
        entries = s.entries
        streak = s.streak
        schedule = s.schedule
        awaiting = s.awaiting
    }

    private func save() {
        guard !previewing else { return }
        let s = Snapshot(enabled: enabled, settings: settings, goal: goal, answers: answers, name: name,
                         dayKey: dayKey, entries: entries, streak: streak, schedule: schedule, awaiting: awaiting)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func commit() {
        save()
        arm()
    }

    /// A new hydration day starts when the online window does. Yesterday's
    /// glasses go, the streak settles what was missed, and anything that only
    /// made sense "today" — a snooze, a hot day, an unanswered card — goes too.
    func rollIfNeeded(now: Date = Date()) {
        let key = HydrationDay.key(containing: now, windowStart: settings.windowStart, calendar: calendar)
        guard key != dayKey else { return }
        let first = dayKey.isEmpty
        dayKey = key
        entries = []
        schedule.ignored = 0
        schedule.snoozedUntil = nil
        awaiting = false
        prompt = nil
        celebrating = false
        if settings.streakEnabled { streak.settle(today: key, calendar: calendar) }
        if !first || !streak.marks.isEmpty || streak.rests > 0 { save() }
    }

    // MARK: Logging

    func log(_ ml: Int? = nil) {
        rollIfNeeded()
        let amount = ml ?? settings.portionML
        let now = Date()
        let wasCelebrating = celebrates
        entries.append(HydrationEntry(id: UUID(), ml: amount, at: now))
        schedule.lastLogAt = now
        schedule.ignored = 0
        schedule.snoozedUntil = nil
        awaiting = false
        pulse += 1
        if settings.streakEnabled, goal.countsForStreak(totalML: total, entries: entries.count) {
            streak.freeze(dayKey)
        }

        if celebrates && !wasCelebrating {
            celebrate()
            if prompt != nil { prompt = .goal }
        } else {
            SoundEngine.shared.play("gulp")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            if prompt == .reminder || prompt == .logged { prompt = .logged }
        }
        commit()
    }

    func undo() {
        guard let last = entries.last else { return }
        remove(last.id)
    }

    func remove(_ id: UUID) {
        rollIfNeeded()
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        schedule.lastLogAt = entries.last?.at
        if settings.streakEnabled, !goal.countsForStreak(totalML: total, entries: entries.count) {
            streak.unfreeze(dayKey)
        }
        celebration?.cancel()
        celebrating = false
        if prompt != nil { prompt = .reminder }
        commit()
    }

    private func celebrate() {
        celebrating = true
        SoundEngine.shared.play("proud")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
        celebration?.cancel()
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.celebrating = false } }
        celebration = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: item)
    }

    // MARK: The reminder card

    func snooze() {
        let now = Date()
        schedule.snoozedUntil = now.addingTimeInterval(TimeInterval(HydrationSettings.snoozeMinutes * 60))
        schedule.lastReminderAt = now
        awaiting = false
        prompt = .snoozed
        commit()
    }

    func unsnooze() {
        schedule.snoozedUntil = nil
        prompt = .reminder
        commit()
    }

    /// Leaving the card ends what it was saying. A reminder nobody answered
    /// stays a reminder, so the question is still there when the island opens.
    func clearPrompt() {
        if prompt != nil, prompt != .reminder { prompt = nil }
    }

    // MARK: Settings

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on { rollIfNeeded() } else { awaiting = false; prompt = nil }
        commit()
    }

    func update(_ change: (inout HydrationSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        rollIfNeeded()
        commit()
    }

    func setGoal(_ newGoal: HydrationGoal) {
        goal = newGoal
        // "Today is hot" has no place beside a number that may be a limit.
        if newGoal.kind == .limit { schedule.hotDay = nil }
        if settings.streakEnabled {
            if goal.countsForStreak(totalML: total, entries: entries.count) {
                streak.freeze(dayKey)
            } else {
                streak.unfreeze(dayKey)
            }
        }
        commit()
    }

    func setAnswers(_ newAnswers: HydrationAnswers?) {
        answers = newAnswers
        save()
    }

    func setName(_ newName: String) {
        name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func setHot(_ on: Bool) {
        rollIfNeeded()
        schedule.hotDay = on && goal.kind != .limit ? dayKey : nil
        commit()
    }

    func pause(_ choice: PauseChoice) {
        let now = Date()
        switch choice {
        case .hour:
            schedule.pause = .until(now.addingTimeInterval(3600))
        case .tomorrow:
            let today = HydrationDay.start(containing: now, windowStart: settings.windowStart, calendar: calendar)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
            schedule.pause = .until(tomorrow)
        case .indefinitely:
            schedule.pause = .indefinitely
        }
        awaiting = false
        commit()
    }

    func resume() {
        schedule.pause = .none
        commit()
    }

    // MARK: The deadline

    /// Arms the one deadline for the next reminder, replacing any other. A
    /// deadline, not a ticker: with the island hidden this costs nothing until
    /// it fires.
    private func arm() {
        work?.cancel()
        work = nil
        if case .until(let date) = schedule.pause, date <= Date() { schedule.pause = .none }
        let next = enabled
            ? HydrationScheduler.next(after: Date(), settings: settings, schedule: schedule,
                                      goalDoneToday: remindersDone, calendar: calendar)
            : nil
        nextDue = next
        guard let next else { return }
        armWork(at: next) { [weak self] in self?.due() }
    }

    private func armWork(at date: Date, _ body: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem { MainActor.assumeIsolated { body() } }
        work = item
        // The wall clock, not uptime: an uptime deadline stands still while the
        // Mac sleeps and would fire late by however long the lid was shut.
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + max(0, date.timeIntervalSinceNow), execute: item)
    }

    private func due() {
        work = nil
        rollIfNeeded()
        let state = AppState.shared
        // Not in the middle of a focus block, if the person asked for that.
        if settings.holdDuringFocus, FocusTimer.shared.isActive {
            armWork(at: Date().addingTimeInterval(5 * 60)) { [weak self] in self?.due() }
            return
        }
        // Never in front of something waiting on an answer, or over a reply
        // half-written: water can wait two minutes.
        if state.pendingApproval != nil || state.pendingQuestion != nil || state.isReplying || state.viewHoldsIslandOpen {
            armWork(at: Date().addingTimeInterval(2 * 60)) { [weak self] in self?.due() }
            return
        }
        // The moment may have passed while this waited: the goal reached, a
        // pause set, the window over.
        guard enabled, let planned = HydrationScheduler.next(
            after: Date().addingTimeInterval(-1), settings: settings, schedule: schedule,
            goalDoneToday: remindersDone, calendar: calendar
        ), planned <= Date().addingTimeInterval(HydrationSettings.lateGraceSeconds + 1) else {
            arm()
            return
        }

        if awaiting { schedule.ignored += 1 }
        schedule.lastReminderAt = Date()
        schedule.snoozedUntil = nil
        awaiting = true
        prompt = .reminder
        commit()
        NotificationCenter.default.post(name: .hydrationReminderDue, object: nil)
    }

    // MARK: Preview

    /// Fills the store for looking at the cards without living a day first.
    /// `NOTCHY_SEED_HYDRATION` picks the scene: `mid`, `goal`, `empty`, `limit`.
    func seedForPreview(_ scene: String) {
        started = true
        previewing = true
        enabled = true
        settings = HydrationSettings()
        name = "Cauã"
        dayKey = HydrationDay.key(containing: Date(), windowStart: settings.windowStart, calendar: calendar)
        streak = HydrationStreak()
        for offset in [-3, -1] {
            if let key = HydrationDay.key(dayKey, offsetBy: offset, calendar: calendar) { streak.marks[key] = .frozen }
        }
        if let key = HydrationDay.key(dayKey, offsetBy: -2, calendar: calendar) { streak.marks[key] = .rest }
        streak.days = 5
        streak.rests = 1
        streak.lastDay = HydrationDay.key(dayKey, offsetBy: -1, calendar: calendar)
        let now = Date()
        func entry(_ ml: Int, _ minutesAgo: Double) -> HydrationEntry {
            HydrationEntry(id: UUID(), ml: ml, at: now.addingTimeInterval(-minutesAgo * 60))
        }
        switch scene {
        case "goal":
            goal = HydrationGoal(kind: .estimated, ml: 2200)
            entries = [entry(500, 400), entry(500, 300), entry(500, 200), entry(350, 120), entry(350, 30)]
            streak.freeze(dayKey)
        case "empty":
            goal = HydrationGoal(kind: .estimated, ml: 2200)
            entries = []
        case "off":
            enabled = false
            entries = []
        case "limit":
            goal = HydrationGoal(kind: .limit, ml: 1500)
            entries = [entry(250, 200), entry(250, 90)]
            answers = HydrationAnswers(age: .from40to64, health: .guidance)
        default:
            goal = HydrationGoal(kind: .estimated, ml: 2200)
            entries = [entry(250, 330), entry(250, 235), entry(350, 100)]
            answers = HydrationAnswers(age: .from40to64, reference: .female, weight: .from55to85,
                                       activity: .moderate, sweat: .little, climate: .hot,
                                       pregnancy: .no, health: HydrationHealth.none)
        }
        schedule = HydrationSchedule()
        schedule.lastLogAt = entries.last?.at
        nextDue = HydrationScheduler.next(after: now, settings: settings, schedule: schedule,
                                          goalDoneToday: remindersDone, calendar: calendar)
    }

    func previewPrompt(_ p: Prompt?) {
        prompt = p
        awaiting = p == .reminder
    }
}

extension Notification.Name {
    /// A reminder came due: the island opens on the reminder card.
    static let hydrationReminderDue = Notification.Name("hydrationReminderDue")
}
