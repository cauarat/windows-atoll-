import SwiftUI

/// Settings › Hydration: the goal, the reminders, and the three screens the
/// goal comes from — the questions, the estimate they give, and the number you
/// type yourself when an estimate would be the wrong thing to offer.
///
/// One pane that swaps its content rather than five sidebar rows: the questions
/// are a path you walk once, not a place you live in.
struct HydrationSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = HydrationStore.shared
    @ObservedObject private var route = HydrationRoute.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch route.screen {
            case .main:      main
            case .questions: HydrationQuestionsView()
            case .estimate:  HydrationEstimateView()
            case .manual:    HydrationManualView()
            case .sources:   HydrationSourcesView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Main

    @ViewBuilder private var main: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Hydration reminders", isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) }))
                hint("Mochi reminds you to drink through the day. Nothing leaves this computer.")
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if store.enabled {
            goalBox
            remindersBox
            quietBox
        } else {
            HStack(spacing: 8) {
                Button(L("Answer the questions")) { route.screen = .questions }
                Button(L("Where the numbers come from")) { route.screen = .sources }.buttonStyle(.link)
            }
        }
    }

    private func hint(_ key: String) -> some View {
        Text(loc: key).font(.system(size: 11)).foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ key: String, width: CGFloat = 150) -> some View {
        Text(loc: key).frame(width: width, alignment: .leading)
    }

    private var goalBox: some View {
        GroupBox(L("Your goal")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    label("Daily goal")
                    if store.goal.kind == .none {
                        Text("no goal, just logging").foregroundColor(.secondary)
                    } else {
                        Button(action: { step(-100) }) { Image(systemName: "minus") }
                            .accessibilityLabel(L("Decrease by 100 ml"))
                        Text(verbatim: HydrationText.amount(store.goal.ml))
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .frame(minWidth: 56)
                        Button(action: { step(100) }) { Image(systemName: "plus") }
                            .accessibilityLabel(L("Increase by 100 ml"))
                        Text(loc: goalCaption).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    label("Your answers")
                    Button(L(key: store.answers == nil ? "Answer the questions" : "Redo the questions")) { route.screen = .questions }
                        .fixedSize()
                    Button(L("Set my own number")) { route.screen = .manual }
                        .fixedSize()
                }
                // On a line of its own: beside two buttons it squeezed them
                // down to an ellipsis in Portuguese.
                Button(L("Where the numbers come from")) { route.screen = .sources }
                    .buttonStyle(.link).padding(.leading, 158)
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    label("Day streak")
                    Toggle("", isOn: Binding(get: { store.settings.streakEnabled }, set: { on in store.update { $0.streakEnabled = on } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    hint("A missed day spends a rest day; you earn one a week.")
                }
                HStack(spacing: 8) {
                    label("Your name, for the reminder").fixedSize(horizontal: false, vertical: true)
                    TextField("", text: Binding(get: { store.name }, set: { store.setName($0) }))
                        .textFieldStyle(.roundedBorder).frame(width: 160)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var goalCaption: String {
        switch store.goal.kind {
        case .estimated: return "starting estimate, yours to adjust"
        case .target:    return "your own number"
        case .limit:     return "a limit not to pass"
        case .none:      return "no goal, just logging"
        }
    }

    private func step(_ delta: Int) {
        var g = store.goal
        g.ml = min(4000, max(500, g.ml + delta))
        store.setGoal(g)
    }

    /// A time of day as the `Date` a picker wants, and back.
    private func time(_ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: get() / 60 % 24, minute: get() % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                set((c.hour ?? 0) * 60 + (c.minute ?? 0))
            }
        )
    }

    private func timePicker(_ binding: Binding<Date>) -> some View {
        DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
            .labelsHidden().datePickerStyle(.field).frame(width: 78)
    }

    private var remindersBox: some View {
        GroupBox(L("Reminders")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    label("I'm online")
                    timePicker(time({ store.settings.windowStart }, { v in store.update { $0.windowStart = v } }))
                    Text("until").foregroundColor(.secondary)
                    timePicker(time({ store.settings.windowEnd }, { v in store.update { $0.windowEnd = v } }))
                }
                HStack(spacing: 8) {
                    label("Remind every")
                    Picker("", selection: Binding(get: { store.settings.intervalMinutes }, set: { v in store.update { $0.intervalMinutes = v } })) {
                        ForEach(HydrationSettings.intervals, id: \.self) { minutes in
                            Text(verbatim: HydrationText.duration(minutes: minutes)).tag(minutes)
                        }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 280)
                }
                HStack(spacing: 8) {
                    label("Quiet hours")
                    Toggle("", isOn: Binding(get: { store.settings.quietEnabled }, set: { on in store.update { $0.quietEnabled = on } }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    Text("from").foregroundColor(.secondary)
                    timePicker(time({ store.settings.quietStart }, { v in store.update { $0.quietStart = v } }))
                    Text("to").foregroundColor(.secondary)
                    timePicker(time({ store.settings.quietEnd }, { v in store.update { $0.quietEnd = v } }))
                }
                .disabled(false)
                if store.goal.kind != .limit {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Toggle("Today is hot or I moved more", isOn: Binding(get: { store.isHot }, set: { store.setHot($0) }))
                            .toggleStyle(.switch).controlSize(.small)
                    }
                    hint("Just for today, reminders come a little closer. The suggested portion does not change, and tomorrow it is back to normal.")
                }

                HydrationTimeline(settings: store.settings, hot: store.isHot)
                    .padding(.top, 2)
                hint("Every log restarts the interval, so nobody who is already drinking gets interrupted. After three unanswered reminders the interval widens by itself.")
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quietBox: some View {
        GroupBox(L("When not to notify")) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("During a focus timer", isOn: Binding(get: { store.settings.holdDuringFocus }, set: { on in store.update { $0.holdDuringFocus = on } }))
                HStack(spacing: 8) {
                    label("Pause reminders")
                    if store.isPaused {
                        Button(L("Resume reminders")) { store.resume() }
                        Text("Paused. Logging still works.").font(.system(size: 11)).foregroundColor(.secondary)
                    } else {
                        Button(L("1 hour")) { store.pause(.hour) }
                        Button(L("Until tomorrow")) { store.pause(.tomorrow) }
                        Button(L("Until I turn them back on")) { store.pause(.indefinitely) }
                    }
                }
                HStack(spacing: 8) {
                    label("When the goal is reached")
                    Picker("", selection: Binding(get: { store.settings.afterGoal }, set: { v in store.update { $0.afterGoal = v } })) {
                        Text("Stop until tomorrow").tag(HydrationAfterGoal.stop)
                        Text("A light nudge every 3 h").tag(HydrationAfterGoal.light)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 340)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - The day, as a row of dots

/// Where the day's reminders would fall if nothing were logged.
struct HydrationTimeline: View {
    let settings: HydrationSettings
    let hot: Bool

    var body: some View {
        let times = HydrationScheduler.timeline(settings: settings, hot: hot)
        let start = CGFloat(settings.windowStart)
        let length = CGFloat(max(1, settings.windowLength))
        let step = HydrationScheduler.interval(settings: settings, hot: hot, ignored: 0, goalDone: false) ?? settings.intervalMinutes

        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4).offset(y: 9)
                    if settings.quietEnabled, let band = quietBand(start: start, length: length) {
                        RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.28))
                            .frame(width: max(2, band.width * w), height: 16)
                            .offset(x: band.x * w, y: 3)
                    }
                    RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07))
                        .frame(width: CGFloat(HydrationSettings.tailMinutes) / length * w, height: 16)
                        .offset(x: w - CGFloat(HydrationSettings.tailMinutes) / length * w, y: 3)
                    ForEach(times, id: \.self) { t in
                        Circle().fill(Color(hex: "#22D3EE"))
                            .frame(width: 10, height: 10)
                            .offset(x: (CGFloat(t) - start) / length * w - 5, y: 6)
                    }
                }
            }
            .frame(height: 22)

            HStack {
                Text(verbatim: HydrationFormat.clock(settings.windowStart))
                Spacer()
                summary(count: times.count, step: step)
                Spacer()
                Text(verbatim: HydrationFormat.clock(settings.windowEnd))
            }
            .font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary)

            HStack(spacing: 14) {
                legend(Circle().fill(Color(hex: "#22D3EE")).frame(width: 8, height: 8), "reminder, if you do not log before")
                legend(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.28)).frame(width: 14, height: 8), "quiet")
                legend(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.12)).frame(width: 14, height: 8), "last hour, no reminders")
            }
            .font(.system(size: 11)).foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func summary(count: Int, step: Int) -> Text {
        if count == 0 { return Text("No reminder fits in this window") }
        if count == 1 { return Text("1 reminder in the day") }
        return Text("\(count) reminders in the day, one every \(HydrationText.duration(minutes: step))")
    }

    private func legend<Mark: View>(_ mark: Mark, _ key: String) -> some View {
        HStack(spacing: 6) { mark; Text(loc: key) }
    }

    /// The quiet hours as a fraction of the row, clipped to the window.
    private func quietBand(start: CGFloat, length: CGFloat) -> (x: CGFloat, width: CGFloat)? {
        guard settings.quietStart != settings.quietEnd else { return nil }
        var a = CGFloat(settings.quietStart), b = CGFloat(settings.quietEnd)
        if b <= a { b += 1440 }
        if b <= start { a += 1440; b += 1440 }
        let lo = max(start, a), hi = min(start + length, b)
        guard hi > lo else { return nil }
        return ((lo - start) / length, (hi - lo) / length)
    }
}

// MARK: - Words for the answers

enum HydrationWords {
    static let skip = "I'd rather not say"

    static func age(_ v: HydrationAge) -> String {
        switch v {
        case .under18: return "Under 18"
        case .from18to39: return "18 to 39"
        case .from40to64: return "40 to 64"
        case .over65: return "65 or older"
        case .skipped: return skip
        }
    }
    static func reference(_ v: HydrationReference) -> String {
        switch v {
        case .female: return "Female"
        case .male: return "Male"
        case .skipped: return skip
        }
    }
    static func weight(_ v: HydrationWeight) -> String {
        switch v {
        case .under55: return "Under 55 kg"
        case .from55to85: return "55 to 85 kg"
        case .over85: return "Over 85 kg"
        case .skipped: return skip
        }
    }
    static func activity(_ v: HydrationActivity) -> String {
        switch v {
        case .still: return "I spend most of the day without moving much"
        case .light: return "I walk or move a little every day"
        case .moderate: return "I train a few times a week"
        case .intense: return "I train hard almost every day"
        }
    }
    static func sweat(_ v: HydrationSweat) -> String {
        switch v {
        case .little: return "A little"
        case .some: return "Somewhat"
        case .lots: return "A lot"
        }
    }
    static func climate(_ v: HydrationClimate) -> String {
        switch v {
        case .mild: return "Mild, or air-conditioned"
        case .hot: return "Hot"
        case .intenseHeat: return "Frequent spells of intense heat"
        }
    }
    static func pregnancy(_ v: HydrationPregnancy) -> String {
        switch v {
        case .no: return "No"
        case .pregnant: return "I am pregnant"
        case .breastfeeding: return "I am breastfeeding"
        case .skipped: return skip
        }
    }
    static func health(_ v: HydrationHealth) -> String {
        switch v {
        case .none: return "None of these"
        case .organs: return "Kidney, heart or liver disease"
        case .medication: return "I take medicine that affects fluids, such as a diuretic"
        case .guidance: return "I was told to limit or increase fluids"
        case .other: return "Another health condition"
        case .skipped: return "I don't know, or I'd rather not say"
        }
    }

    /// What the person marked, for the screen that explains why there is no number.
    static func block(_ b: HydrationBlock) -> String {
        switch b {
        case .minor: return "Under 18"
        case .pregnant: return "I am pregnant"
        case .breastfeeding: return "I am breastfeeding"
        case .pregnancySkipped: return "Preferred not to answer about pregnancy or breastfeeding"
        case .organs: return "Kidney, heart or liver disease"
        case .medication: return "I take medicine that affects fluids, such as a diuretic"
        case .guidance: return "I was told to limit or increase fluids"
        case .otherCondition: return "Another health condition"
        case .healthSkipped: return "Not sure, or preferred not to answer about health"
        }
    }

    static func part(_ p: HydrationPart) -> String {
        switch p {
        case .base(.female): return "Starting point, female reference"
        case .base(.male): return "Starting point, male reference"
        case .base(.skipped): return "Starting point, between the two references"
        case .weight(.under55): return "Weight under 55 kg"
        case .weight: return "Weight over 85 kg"
        case .activity(.light): return "Light movement every day"
        case .activity(.moderate): return "Training a few times a week"
        case .activity: return "Hard training almost every day"
        case .sweat(.some): return "Sweats somewhat"
        case .sweat: return "Sweats a lot"
        case .climate(.hot): return "Hot weather"
        case .climate: return "Frequent intense heat"
        case .cap: return "Ceiling on the activity, sweat and weather adjustments"
        case .over65: return "65 or older: does not change the number"
        }
    }

    static func value(_ line: HydrationLine) -> String {
        if case .base = line.part { return HydrationText.amount(line.ml) }
        if line.ml == 0 { return "0 ml" }
        return (line.ml > 0 ? "+" : "−") + "\(abs(line.ml)) ml"
    }
}

// MARK: - Screens

private struct BackRow: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                Text("Back")
            }
        }
        .buttonStyle(.link)
    }
}

private let hydrationFootnote = "An estimate for healthy adults. Not medical advice."

/// The eight questions, one at a time. Picking an answer moves on; an answer
/// that rules an estimate out goes straight to the manual goal, without asking
/// the rest.
struct HydrationQuestionsView: View {
    @ObservedObject private var store = HydrationStore.shared
    @ObservedObject private var route = HydrationRoute.shared
    @State private var step = 0
    @State private var answers = HydrationAnswers()

    private struct Question {
        let title: String
        let hint: String
        let options: [(label: String, selected: Bool, pick: (inout HydrationAnswers) -> Void)]
    }

    private let count = 8

    var body: some View {
        if step == 0 {
            intro
        } else {
            let q = question(step)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    BackRow { step -= 1 }
                    ProgressView(value: Double(step), total: Double(count)).frame(maxWidth: .infinity)
                    Text("\(step) of \(count)").font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc: q.title).font(.system(size: 17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(loc: q.hint).font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { _, option in
                        Button(action: { choose(option.pick) }) {
                            Text(loc: option.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(option.selected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(loc: hydrationFootnote).font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            BackRow { route.screen = .main }
            Text("Let's find a starting point").font(.system(size: 20, weight: .semibold))
            Text("Eight quick questions. With them I suggest a daily fluid goal to start from. It is an estimate, not a prescription: needs change from person to person and from one day to the next, and you can adjust the number whenever you like.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Label { Text("Notchy is not a medical tool and does not replace professional advice.") } icon: { Image(systemName: "cross.case") }
                Label { Text("Your answers stay on this computer. Every question can be skipped.") } icon: { Image(systemName: "lock") }
            }
            .font(.system(size: 12)).foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button(L("Begin")) { answers = HydrationAnswers(); step = 1 }.keyboardShortcut(.defaultAction)
                Button(L("I already have a goal")) { store.setAnswers(nil); route.screen = .manual }
            }
            .padding(.top, 4)
        }
    }

    private func choose(_ pick: (inout HydrationAnswers) -> Void) {
        pick(&answers)
        if HydrationEstimator.block(for: answers) != nil {
            store.setAnswers(answers)
            route.screen = .manual
            return
        }
        if step < count {
            step += 1
        } else {
            store.setAnswers(answers)
            route.screen = .estimate
        }
    }

    private func question(_ n: Int) -> Question {
        switch n {
        case 1:
            return Question(title: "How old are you?",
                            hint: "In ranges, to ask no more than needed. The estimate was made for adults.",
                            options: HydrationAge.allCases.map { v in (HydrationWords.age(v), answers.age == v, { $0.age = v }) })
        case 2:
            return Question(title: "Which reference should I use?",
                            hint: "EFSA, the US National Academies and NHMRC publish separate values by sex. With no answer, I use a point between the two.",
                            options: HydrationReference.allCases.map { v in (HydrationWords.reference(v), answers.reference == v, { $0.reference = v }) })
        case 3:
            return Question(title: "What is your weight?",
                            hint: "Also in ranges. It is a small adjustment, not a millilitres-per-kilo sum.",
                            options: HydrationWeight.allCases.map { v in (HydrationWords.weight(v), answers.weight == v, { $0.weight = v }) })
        case 4:
            return Question(title: "How would you describe your physical activity?",
                            hint: "Think of an ordinary week.",
                            options: HydrationActivity.allCases.map { v in (HydrationWords.activity(v), answers.activity == v, { $0.activity = v }) })
        case 5:
            return Question(title: "Do you sweat a lot, exercising or day to day?",
                            hint: "Sweat varies a lot from person to person.",
                            options: HydrationSweat.allCases.map { v in (HydrationWords.sweat(v), answers.sweat == v, { $0.sweat = v }) })
        case 6:
            return Question(title: "What is the weather like where you spend most of the day?",
                            hint: "You answer for yourself: Notchy does not look up any weather service.",
                            options: HydrationClimate.allCases.map { v in (HydrationWords.climate(v), answers.climate == v, { $0.climate = v }) })
        case 7:
            return Question(title: "Are you pregnant or breastfeeding?",
                            hint: "In these phases the need for fluids changes and deserves its own guidance.",
                            options: HydrationPregnancy.allCases.map { v in (HydrationWords.pregnancy(v), answers.pregnancy == v, { $0.pregnancy = v }) })
        default:
            return Question(title: "Any health condition or medical guidance about fluids?",
                            hint: "If any option applies, the goal is up to you and the professional who looks after you.",
                            options: HydrationHealth.allCases.map { v in (HydrationWords.health(v), answers.health == v, { $0.health = v }) })
        }
    }
}

/// The number the answers give, how it was reached, and a slider for anyone
/// who would rather start somewhere else.
struct HydrationEstimateView: View {
    @ObservedObject private var store = HydrationStore.shared
    @ObservedObject private var route = HydrationRoute.shared
    @State private var chosen: Double = 0

    var body: some View {
        let estimate = HydrationEstimator.estimate(store.answers ?? HydrationAnswers())
        let ml = chosen > 0 ? Int(chosen) : estimate.totalML
        VStack(alignment: .leading, spacing: 12) {
            BackRow { route.screen = .questions }
            HStack(spacing: 16) {
                HydrationGlass(level: 0.25 + Double(ml - 1600) / 1800 * 0.6).frame(width: 60)
                    .padding(8).background(Color.black.opacity(0.85)).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your starting estimate").font(.system(size: 12)).foregroundColor(.secondary)
                    Text("about \(HydrationText.amount(ml))").font(.system(size: 26, weight: .semibold).monospacedDigit())
                    Text("of fluids a day, counting everything you drink").font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 8) {
                Text("Adjust, if you prefer").font(.system(size: 12)).foregroundColor(.secondary)
                Text(verbatim: HydrationText.amount(HydrationEstimator.minimumML)).font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary)
                Slider(value: Binding(get: { Double(ml) }, set: { chosen = $0 }),
                       in: Double(HydrationEstimator.minimumML)...Double(HydrationEstimator.maximumML), step: 100)
                Text(verbatim: HydrationText.amount(HydrationEstimator.maximumML)).font(.system(size: 11).monospacedDigit()).foregroundColor(.secondary)
            }
            GroupBox(L("How I got to this number")) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(estimate.lines.enumerated()), id: \.offset) { _, line in
                        HStack {
                            Text(loc: HydrationWords.part(line.part))
                            Spacer()
                            Text(verbatim: HydrationWords.value(line)).monospacedDigit()
                        }
                        .font(.system(size: 12))
                    }
                }
                .padding(6)
            }
            Text("It is a starting point, not a rule. Other drinks and food count too, and there is no reason to force fluids or to go past the goal. Day to day, thirst and pale-yellow urine are good general signs, but they do not replace medical advice.")
                .font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(L("Start with \(HydrationText.amount(ml))")) {
                    store.setGoal(HydrationGoal(kind: .estimated, ml: ml))
                    store.setEnabled(true)
                    route.screen = .main
                }
                .keyboardShortcut(.defaultAction)
                Button(L("Redo")) { route.screen = .questions }
                Spacer()
                Button(L("Where the numbers come from")) { route.screen = .sources }.buttonStyle(.link)
            }
            Text(loc: hydrationFootnote).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}

/// No estimate: the person's own number, as a target or as a limit.
struct HydrationManualView: View {
    @ObservedObject private var store = HydrationStore.shared
    @ObservedObject private var route = HydrationRoute.shared
    @State private var text = ""
    @State private var isLimit = false

    var body: some View {
        let block = store.answers.flatMap { HydrationEstimator.block(for: $0) }
        let minor = block == .minor
        let ml = Int(text.filter(\.isNumber)) ?? 0
        VStack(alignment: .leading, spacing: 12) {
            BackRow { route.screen = .main }
            (minor ? Text("This estimate was made for adults") : Text("Here, you set the number"))
                .font(.system(size: 20, weight: .semibold))
            if block != nil {
                (minor
                     ? Text("For anyone under 18 the need for fluids is different, so I do not suggest a number. You can still use the glass and the reminders with a goal agreed with a guardian or a health professional.")
                     : Text("From your answers, it is better not to use an automatic estimate. The right amount of fluids, in your case, is the one recommended by the health professional who looks after you."))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let block {
                HStack(spacing: 8) {
                    Text("You marked").font(.system(size: 12)).foregroundColor(.secondary)
                    Text(loc: HydrationWords.block(block)).font(.system(size: 11.5))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Color.primary.opacity(0.07)).clipShape(Capsule())
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("Your reference for the day").frame(width: 170, alignment: .leading)
                        TextField("", text: $text).textFieldStyle(.roundedBorder).frame(width: 90)
                        Text(verbatim: "ml").foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text("This number is").frame(width: 170, alignment: .leading)
                        Picker("", selection: $isLimit) {
                            Text("a target to reach").tag(false)
                            Text("a limit not to pass").tag(true)
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 320)
                    }
                    Text("With a limit, the glass shows how much still fits in the day and reminders stop before you reach it. You can change the number whenever you like.")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("No celebration for volume: the streak counts the days you logged, not how much you drank.")
                .font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(L("Save reference")) {
                    store.setGoal(HydrationGoal(kind: isLimit ? .limit : .target, ml: min(6000, max(100, ml))))
                    store.setEnabled(true)
                    route.screen = .main
                }
                .keyboardShortcut(.defaultAction)
                .disabled(ml < 100)
                Button(L("Just log, no goal")) {
                    store.setGoal(.unset)
                    store.setEnabled(true)
                    route.screen = .main
                }
            }
            Text("Notchy is not a medical tool and does not replace professional advice.")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
        .onAppear {
            if store.goal.kind == .target || store.goal.kind == .limit {
                text = String(store.goal.ml)
                isLimit = store.goal.kind == .limit
            }
        }
    }
}

/// The references behind the numbers, what each one measures, and what was
/// left out — said in the app, where the estimate is, rather than in a README.
struct HydrationSourcesView: View {
    @ObservedObject private var route = HydrationRoute.shared

    private struct Source: Identifiable {
        let id = UUID()
        let name: String
        let note: String
        let measures: String
        let women: String
        let men: String
        let url: String
    }

    private var sources: [Source] {
        let a = HydrationText.amount
        return [
            Source(name: "EFSA, Europe",
                   note: "2010 opinion, read in the 2017 summary report. For mild weather and moderate activity.",
                   measures: "Total water: drinks and food", women: a(2000), men: a(2500),
                   url: "https://www.efsa.europa.eu/sites/default/files/2017_09_DRVs_summary_report.pdf"),
            Source(name: "National Academies, USA",
                   note: "Dietary Reference Intakes, 2005. Total water is 2.7 L and 3.7 L.",
                   measures: "Drinks only, within total water", women: a(2200), men: a(3000),
                   url: "https://www.nationalacademies.org/read/10925/chapter/6"),
            Source(name: "NHMRC, Australia and New Zealand",
                   note: "2006 values, checked in two secondary sources; the original page did not open.",
                   measures: "Fluids, without food", women: a(2100), men: a(2600),
                   url: "https://www.healthdirect.gov.au/drinking-water-and-your-health"),
            Source(name: "NHS, United Kingdom",
                   note: "Reviewed in 2023. The page itself calls the number “just a guide”.",
                   measures: "Drinks: water, milk, tea, coffee", women: L("6 to 8 glasses"), men: "",
                   url: "https://www.nhs.uk/live-well/eat-well/food-guidelines-and-food-labels/water-drinks-nutrition/"),
            Source(name: "Guia Alimentar, Brazil's Ministry of Health",
                   note: "2014. It says the need varies a lot and asks you to heed the first signs of thirst.",
                   measures: "Water, with no fixed recommendation", women: L("2 L for some; 3 to 4 L or more for others"), men: "",
                   url: "https://bvsms.saude.gov.br/bvs/publicacoes/guia_alimentar_populacao_brasileira_2ed.pdf"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BackRow { route.screen = .main }
            Text("Where the numbers come from").font(.system(size: 20, weight: .semibold))
            Text("There is no single number of water per day. These are the public references behind the estimate, with what each one measures: some also count the water in food, others only what you drink.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("Reference").frame(maxWidth: .infinity, alignment: .leading)
                        Text("What it measures").frame(width: 150, alignment: .leading)
                        Text("Women").frame(width: 56, alignment: .trailing)
                        Text("Men").frame(width: 56, alignment: .trailing)
                    }
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    ForEach(sources) { s in
                        Divider()
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                if let url = URL(string: s.url) {
                                    Link(destination: url) { Text(loc: s.name).multilineTextAlignment(.leading) }
                                }
                                Text(loc: s.note).font(.system(size: 11)).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(loc: s.measures).font(.system(size: 12)).foregroundColor(.secondary)
                                .frame(width: 150, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            if s.men.isEmpty {
                                Text(verbatim: s.women).font(.system(size: 12)).multilineTextAlignment(.trailing)
                                    .frame(width: 124, alignment: .trailing).fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(verbatim: s.women).font(.system(size: 12).monospacedDigit()).frame(width: 56, alignment: .trailing)
                                Text(verbatim: s.men).font(.system(size: 12).monospacedDigit()).frame(width: 56, alignment: .trailing)
                            }
                        }
                    }
                }
                .padding(6)
            }

            bullets("Where they agree", [
                "The need varies from person to person, and heat, activity, pregnancy and breastfeeding raise it.",
                "The “8 glasses” rule has no study behind it for healthy, sedentary adults in mild weather (Valtin, 2002).",
                "Pale-yellow urine is the everyday sign (NHS), with limits: medicines, supplements and food change the colour, and older people may feel less thirst.",
                "Too much is harmful too. EFSA and the National Academies point to risk when intake goes past what the kidneys clear, about 0.7 to 1 L an hour.",
            ])
            bullets("How Notchy uses this", [
                "The starting point is for drinks: 1.8 L on the female reference, 2.3 L on the male one and 2.0 L with no answer. With training a few times a week the estimate reaches 2.1 L and 2.6 L, where NHMRC and the National Academies place fluids.",
                "The additions for activity, sweat and weather (up to 800 ml together) are a product heuristic. The sources say the need rises, but give no table for day-to-day life.",
                "The largest portion is 500 ml and reminders are never less than 30 minutes apart, far below the limit of 0.7 to 1 L an hour. There is no “catching up”.",
                "No automatic estimate for kidney, heart or liver disease or for diuretics, cases where healthdirect, the NHS and the American Heart Association say to talk to a professional. The same goes for pregnancy and breastfeeding, where each reference gives a different addition.",
            ])
            bullets("Limits of this review", [
                "The WHO was left out. The text usually cited (Grandjean, 2004) is a background draft marked “not for citation”, not a recommendation by the organisation.",
                "On exercise, the 2017 NATA position was read (do not drink more than you lose in training) and only the summary of the 2007 ACSM position.",
                "These numbers are a product heuristic and have not been reviewed by a health professional.",
            ])
        }
    }

    private func bullets(_ title: String, _ items: [String]) -> some View {
        GroupBox(L(key: title)) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Color.secondary).frame(width: 4, height: 4).offset(y: -2)
                        Text(loc: item).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
