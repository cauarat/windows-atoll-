import SwiftUI
import ServiceManagement

// The welcome a first run shows before the island opens: seven screens in a dark
// window that hangs under the notch, with Mochi alive at the top of each.
//
// Which screens, in what order, and when it shows are Onboarding.swift's rules;
// this is how they look. Every choice goes straight into the stores Settings
// writes, so skipping or closing halfway keeps whatever was already picked.

// MARK: - Model

/// What the welcome remembers while it is open.
///
/// Owned by the window, outside `Localizing`: that view's `.id(language)` rebuilds
/// everything under it — and every `@State` with it — the moment a language is
/// picked, which would otherwise send the user back to the first screen.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var flow: OnboardingFlow

    /// The name field. Saved to `AppState.userName` when its screen is left, and
    /// started on whatever Mochi would call the user today, so most people only
    /// have to press Continue.
    @Published var name: String

    /// Whether Notchy opens with the Mac, as the system has it now.
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// Mochi in the header, here so a screen can make him react.
    let engine = BotEngine()

    /// Whose Mochi the look screen is dressing: "" for everyone else, or a pill id.
    /// The header shows that one while the look screen is up.
    @Published var editing = ""

    /// The look screen's tab.
    @Published var lookTab: LookTab = .face

    enum LookTab: Hashable { case face, body, christmas }

    // The pointer, the way the island tracks it for its own Mochi. Plain stored
    // values, not published: the header reads them every frame anyway, and a
    // published pointer would rebuild the whole window on every mouse move.

    /// Where the pointer is over the window, in its top-left coordinates; nil
    /// once it has left.
    private(set) var pointer: CGPoint?
    /// The header Mochi's body centre and radius, in the same coordinates —
    /// written by the header as it draws.
    var mochiCentre: CGPoint = .zero
    var mochiRadius: CGFloat = 0

    /// Where his eyes are actually aimed, eased toward the pointer frame by frame
    /// (`gaze(towards:now:)`), and when that was last done.
    private var gazeNow: CGPoint = .zero
    private var gazeTime: Double = 0

    private var hovering = false
    private var hoverStart: CGPoint = .zero
    private var lastLoveTime: CFTimeInterval = -.greatestFiniteMagnitude
    private var loveWork: DispatchWorkItem?

    private let onFinish: () -> Void

    init(start: OnboardingStep, onFinish: @escaping () -> Void) {
        flow = OnboardingFlow(start: start)
        let typed = AppState.shared.userName
        name = typed.isEmpty ? (systemUserFirstName ?? "") : typed
        self.onFinish = onFinish
        // Three slaps make *him* dizzy. Without this the engine tells the island,
        // which would open its confused view behind the welcome.
        engine.onDizzy = { [weak engine] in
            engine?.setState(.dizzy, force: true)
            // The island's recovery: back after 3.3 s, pleased about it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) { [weak engine] in
                engine?.setState(.idle, force: true)
                engine?.triggerEmote(.happy)
            }
        }
    }

    // MARK: The pointer — the island's own rules (IslandWindowController)

    /// The pointer moved over the window, or left it.
    ///
    /// Over his head: a blink, wider eyes and the hover sound, then — held still
    /// for 1.9 s — a love emote and its sound, once every 6 s at most; a move of
    /// more than 40 pt starts the wait again. The island's `botHoverIn`,
    /// `botHoverOut` and `scheduleLoveTimer`, run on this engine directly rather
    /// than through the island's notifications, which would move its Mochi too.
    func pointerMoved(_ point: CGPoint?) {
        pointer = point
        let over = engine.state != .dizzy
            && (point.map { hypot($0.x - mochiCentre.x, $0.y - mochiCentre.y) <= mochiRadius } ?? false)
        if over && !hovering, let point { hoverIn(at: point) }
        if !over && hovering { hoverOut() }
        hovering = over
        if over, let point, hypot(point.x - hoverStart.x, point.y - hoverStart.y) > 40 {
            hoverStart = point
            scheduleLove()
        }
    }

    /// Where the pointer pulls him this frame, eased: x and y in −1…1, from the
    /// island's own curves (`tanh(dx / 260)`, `−tanh(dy / 200)`), following the
    /// pointer with a quarter-second of lag rather than snapping to it, and
    /// settling back to the middle when it leaves.
    ///
    /// The header turns this into a lean of his whole body and only a small turn
    /// of his eyes (`OnboardingMochiView`). At the island's full strength the
    /// eyes swing past his own face — the pointer is a hand's width away here,
    /// not across the screen — and slide off the nose, beard and hat, which do
    /// not turn with them.
    func gaze(towards centre: CGPoint, now: Double) -> CGPoint {
        let target = pointer.map {
            CGPoint(x: tanh(($0.x - centre.x) / 260), y: -tanh(($0.y - centre.y) / 200))
        } ?? .zero
        let dt = gazeTime == 0 ? 0 : min(0.1, max(0, now - gazeTime))
        gazeTime = now
        let k = 1 - exp(-dt / 0.28)
        gazeNow.x += (target.x - gazeNow.x) * k
        gazeNow.y += (target.y - gazeNow.y) * k
        return gazeNow
    }

    /// Whether a press at `point` (window, top-left) lands on him — the island's
    /// `isBotHit`: a circle half the canvas wide, a little more than his body.
    func isOnMochi(_ point: CGPoint) -> Bool {
        hypot(point.x - mochiCentre.x, point.y - mochiCentre.y) <= mochiRadius
    }

    /// A press on him: the island's slap — squash, a look, and dizzy on the third.
    /// As on the island the love wait is dropped and the hover starts over at
    /// once, which the island does on its next tick.
    func slap() {
        loveWork?.cancel()
        loveWork = nil
        hovering = false
        engine.slap()
        pointerMoved(pointer)
    }

    private func hoverIn(at point: CGPoint) {
        guard CACurrentMediaTime() - lastLoveTime > 6 else { return }
        hoverStart = point
        engine.blink()
        engine.tgEs = 1.08
        SoundEngine.shared.play("hover")
        scheduleLove()
    }

    private func hoverOut() {
        loveWork?.cancel()
        loveWork = nil
        engine.tgEs = 1
    }

    private func scheduleLove() {
        loveWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.hovering, CACurrentMediaTime() - self.lastLoveTime > 6 else { return }
            self.lastLoveTime = CACurrentMediaTime()
            self.engine.triggerEmote(.love)
            SoundEngine.shared.play("love")
        }
        loveWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: item)
    }

    /// The window is up: say hello.
    func start() {
        engine.setState(.idle, force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.react()
        }
    }

    /// Continue — or, on the last screen, Open Notchy.
    func advance() {
        leaveStep()
        if flow.isLast { onFinish(); return }
        flow.advance()
        react()
    }

    func back() {
        leaveStep()
        flow.back()
        react()
    }

    /// Skip: the welcome is over, with whatever was already chosen.
    func skip() {
        leaveStep()
        onFinish()
    }

    /// Saves what the current screen holds that is not saved as it changes —
    /// the name, which is only written once its screen is left, so a name
    /// half-typed is never what the greeting says.
    func leaveStep() {
        guard flow.step == .name else { return }
        AppState.shared.userName = name
    }

    /// A look was picked: Mochi likes it.
    func picked() {
        engine.triggerEmote(.love, silent: true)
    }

    func setLaunchAtLogin(_ on: Bool) {
        // The calls Settings' Startup switch makes. On a refusal the switch goes
        // back to what the system says rather than claiming something untrue.
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            launchAtLogin = on
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func react() {
        switch flow.step {
        case .welcome: engine.greet()
        case .ready:   engine.triggerEmote(.proud, silent: true)
        default:       engine.triggerEmote(.happy, silent: true)
        }
    }
}

// MARK: - Palette

/// The island's own colours, so the welcome reads as part of it.
private enum Ink {
    static let primary   = Color(hex: "#F5F6F8")
    static let body      = Color(hex: "#B8BCC4")
    static let secondary = Color(hex: "#8E939C")
    static let accent    = Color(hex: "#3B9EFF")
    static let field     = Color.white.opacity(0.07)
    static let row       = Color.white.opacity(0.06)
    static let edge      = Color.white.opacity(0.10)
}

// MARK: - The window's content

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var state = AppState.shared

    static let size = CGSize(width: 520, height: 660)

    var body: some View {
        // The hello and the last screen ask nothing: Mochi is bigger there and
        // the words sit in the middle. The five questions keep him small and
        // start at the top, under their progress row.
        let isQuestion = model.flow.progress != nil
        VStack(spacing: 0) {
            topBar
            OnboardingMochiView(model: model, state: state, diameter: isQuestion ? 56 : 84)
            if let progress = model.flow.progress {
                progressRow(progress)
            }
            screen
                .id(model.flow.step)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: isQuestion ? .top : .center)
                .padding(.top, 16)
            footer
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 26)
        // Whatever the window is — its size is set there, once. A fixed height
        // here made the hosting view grow the window by the title bar, asking
        // for the full height *below* it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        // Up into the title bar, so Skip lines up with the close button.
        .ignoresSafeArea()
        // The pointer anywhere over the window, for Mochi's eyes and his head —
        // in the same top-left coordinates his own position is read in.
        .onContinuousHover(coordinateSpace: .global) { phase in
            switch phase {
            case .active(let point): model.pointerMoved(point)
            case .ended:             model.pointerMoved(nil)
            }
        }
        .foregroundColor(Ink.primary)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: model.flow.step)
    }

    // MARK: Chrome

    /// Skip, across from the close button the title bar keeps.
    private var topBar: some View {
        HStack {
            Spacer()
            if !model.flow.isLast {
                Button(action: model.skip) {
                    Text("Skip").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(Ink.secondary)
            }
        }
        .frame(height: 22)
        .padding(.top, 10)
    }

    /// The hydration questionnaire's row: Back, a bar, and "2 of 5".
    private func progressRow(_ progress: (current: Int, total: Int)) -> some View {
        HStack(spacing: 10) {
            Button(action: model.back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text("Back")
                }
            }
            .buttonStyle(.link)
            ProgressView(value: Double(progress.current), total: Double(progress.total))
                .tint(Ink.accent)
                .frame(maxWidth: .infinity)
            Text("\(progress.current) of \(progress.total)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(Ink.secondary)
        }
        .padding(.top, 2)
    }

    private var footer: some View {
        Button(action: model.advance) {
            primaryTitle
                .font(.system(size: 13.5, weight: .semibold))
                .frame(minWidth: 190)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Ink.accent)
        .keyboardShortcut(.defaultAction)
    }

    private var primaryTitle: Text {
        switch model.flow.step {
        case .welcome: return Text("Begin")
        case .ready:   return Text("Open Notchy")
        default:       return Text("Continue")
        }
    }

    // MARK: Screens

    @ViewBuilder private var screen: some View {
        switch model.flow.step {
        case .welcome:  welcome
        case .name:     OnboardingNameScreen(model: model)
        case .language: language
        case .look:     OnboardingLookScreen(model: model, state: state)
        case .tools:    tools
        case .startup:  startup
        case .ready:    ready
        }
    }

    private func heading(_ title: Text, hint: Text? = nil) -> some View {
        VStack(spacing: 6) {
            title
                .font(.system(size: 19, weight: .semibold))
                .multilineTextAlignment(.center)
            if let hint {
                hint
                    .font(.system(size: 12.5))
                    .foregroundColor(Ink.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Text("Hi, I'm Mochi!")
                .font(.system(size: 26, weight: .bold))
            Text("I live in your Mac's notch. I keep an eye on your AI agents, your messages and your music, and you answer them without leaving what you are doing.")
                .font(.system(size: 13.5))
                .foregroundColor(Ink.body)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Let's set me up for you. It takes about a minute.")
                .font(.system(size: 13.5))
                .foregroundColor(Ink.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 410)
        .padding(.top, 12)
    }

    private var language: some View {
        VStack(spacing: 16) {
            heading(Text("Which language should I speak?"),
                    hint: Text("Everywhere: the island, Settings and the notifications."))
            VStack(spacing: 6) {
                ForEach(AppLanguage.allCases) { lang in
                    // Each language names itself; only "Same as system" is a
                    // sentence, and `label` has already translated it.
                    OnboardingOption(selected: state.language == lang) {
                        state.language = lang
                    } label: {
                        Text(verbatim: lang.label)
                    }
                }
            }
            .frame(maxWidth: 360)
        }
    }

    private var tools: some View {
        let services = PillCatalog.available.filter { $0.category == .service }
        let used = state.activeIntegrations.count
        return VStack(spacing: 12) {
            heading(Text("What should I keep an eye on?"),
                    hint: Text("Up to four. Mattermost, Ato and WhatsApp ask you to sign in, under Settings › Integrations."))
            // Services only. Claude Code is reached and switched in Settings,
            // never from the welcome.
            VStack(spacing: 5) {
                ForEach(services, id: \.id) { def in
                    let on = state.activeIntegrations.contains(def.id)
                    pillRow(def, on: on, full: used >= 4 && !on)
                }
            }
            Text("\(used)/4 slots used")
                .font(.system(size: 11))
                .foregroundColor(used >= 4 ? .orange : Ink.secondary)
        }
    }

    /// A pill and its switch. Through `toggleIntegration`, the way Settings does
    /// it, so the island's pills follow and a fifth one is refused.
    private func pillRow(_ def: PillDefinition, on: Bool, full: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: def.color))
                .frame(width: 10, height: 10)
            Text(loc: def.name)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: Binding(
                get: { on },
                set: { _ in state.toggleIntegration(def.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(full)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.row))
        .opacity(full ? 0.5 : 1)
    }

    private var startup: some View {
        VStack(spacing: 16) {
            heading(Text("Almost there"),
                    hint: Text("Two last things. Both can be changed in Settings."))
            VStack(spacing: 6) {
                switchRow(Text("Launch at Mac startup"),
                          isOn: Binding(get: { model.launchAtLogin },
                                        set: { model.setLaunchAtLogin($0) }))
                switchRow(Text("Enable sounds"), isOn: $state.soundEnabled)
            }
            .frame(maxWidth: 360)
        }
    }

    private func switchRow(_ label: Text, isOn: Binding<Bool>) -> some View {
        HStack {
            label.font(.system(size: 13))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.row))
    }

    private var ready: some View {
        let name = userGreetingName(typed: state.userName, system: systemUserFirstName)
        return VStack(spacing: 18) {
            (name.map { Text("All set, \($0)!") } ?? Text("All set!"))
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                tip("cursorarrow.rays", Text("Move the pointer to the notch whenever you want to see me."))
                tip("menubar.rectangle", Text("Settings are in the menu bar icon."))
                tip("slider.horizontal.3", Text("Everything you picked here can be changed there."))
            }
            .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(.top, 8)
    }

    private func tip(_ symbol: String, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundColor(Ink.accent)
                .frame(width: 20)
            text
                .font(.system(size: 13))
                .foregroundColor(Ink.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The name screen

/// Its own view for the field's focus, which only lives as long as the screen.
private struct OnboardingNameScreen: View {
    @ObservedObject var model: OnboardingModel
    @FocusState private var focused: Bool
    /// The greeting the next launch will actually say, by today's clock.
    @State private var period = DayPeriod.at(Date())

    var body: some View {
        VStack(spacing: 14) {
            Text("What should I call you?")
                .font(.system(size: 19, weight: .semibold))
            TextField("Your name", text: $model.name, prompt: Text("Your first name"))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .frame(width: 300, height: 42)
                .background(RoundedRectangle(cornerRadius: 10).fill(Ink.field))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(focused ? Ink.accent : Ink.edge, lineWidth: 1)
                )
                .focused($focused)
            VStack(spacing: 9) {
                Text("I'll greet you like this every time Notchy starts:")
                    .font(.system(size: 12))
                    .foregroundColor(Ink.secondary)
                // The island's own line, on a sliver of island.
                greetingLineText(period, name: userGreetingName(typed: model.name,
                                                                system: systemUserFirstName))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 20)
                    .frame(height: 36)
                    .background(Capsule().fill(Color(hex: "#101113")))
                    .overlay(Capsule().stroke(Ink.edge, lineWidth: 1))
            }
            .padding(.top, 8)
        }
        .onAppear {
            // After the screen's transition, or the focus lands on nothing.
            DispatchQueue.main.async { focused = true }
        }
    }
}

// MARK: - Pieces

/// One answer among several: the hydration questionnaire's option row.
private struct OnboardingOption<Label: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack {
                label().font(.system(size: 13))
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Ink.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selected ? Color.accentColor.opacity(0.25) : Ink.row)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Mochi, alive, at the top of the welcome — and as lively as the island's.
///
/// The island's drawing sequence (`BotCanvasView`) with the island's reactions:
/// his eyes follow the pointer by the island's formula, the pointer over his head
/// and a click on him are handled by the model by the island's rules, and he is
/// whoever the look screen is dressing, in that pill's colour — Ato as Ato.
struct OnboardingMochiView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var state: AppState
    var diameter: CGFloat = 56
    /// Headroom above him for hearts and stars, as `BotPlacement` leaves.
    private let overhang: CGFloat = 34
    /// Ato's orb, for while the look screen is dressing Ato.
    @StateObject private var ato = AtoBotDriver(lively: true)

    /// Whoever is on show: the Mochi being dressed on the look screen, everyone
    /// else's everywhere else.
    private var who: String { model.flow.step == .look ? model.editing : "" }

    var body: some View {
        let side = diameter / 0.6
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let engine = model.engine
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    // `BotCanvasView`'s own expression, kept as is so he moves at
                    // the island's pace: `lastTime` is media time, so this clamps
                    // to 0.05.
                    let dt = min(0.05, now - engine.lastTime)

                    // Where his body is, in the window — the engine draws it at
                    // half the width down from the headroom.
                    let frame = proxy.frame(in: .global)
                    let centre = CGPoint(x: frame.midX, y: frame.minY + size.width / 2 + overhang)
                    model.mochiCentre = centre
                    model.mochiRadius = size.width / 2
                    // Toward the pointer, eased (see `gaze`): a third of the
                    // island's turn for the eyes, so they stay on his face, and
                    // the rest as a lean of everything he wears, below.
                    let pull = model.gaze(towards: centre, now: now)
                    engine.lookX = pull.x * 0.3
                    engine.lookY = pull.y * 0.24

                    // A pill's Mochi wears its pill's colour, as on the island;
                    // everyone else's is the island's white.
                    let id = who
                    engine.bodyColor = cgColorFromHex(PillCatalog.definition(for: id)?.color ?? "#F5F6F8")
                    engine.character = id.isEmpty ? state.defaultCharacter : state.character(for: id)
                    engine.particleOverhang = overhang
                    engine.update(dt: dt)

                    // He leans into the pointer as one piece — body, face, hat
                    // and beard together — turning a few degrees about his
                    // middle and drifting a few points toward it.
                    var ctx = context
                    let middle = CGPoint(x: size.width / 2, y: size.width / 2 + overhang)
                    ctx.translateBy(x: middle.x + pull.x * 3, y: middle.y - pull.y * 2.5)
                    ctx.rotate(by: .radians(pull.x * 0.07))
                    ctx.translateBy(x: -middle.x, y: -middle.y)
                    engine.applyDance(&ctx, size: size)
                    if id == MessageSource.ato.pillID {
                        // Ato wears its own mascot, moved by this engine's
                        // reactions, as `BotCanvasView` draws it on the island.
                        let frame = ato.frame(now: now, state: AtoState.current(.idle),
                                              reaction: AtoReaction.from(engine))
                        AtoBotView.draw(frame, in: ctx, size: size, overhang: overhang,
                                        festive: engine.character.festive, time: now)
                        engine.drawParticlesOnly(context: ctx, size: size)
                        return
                    }
                    engine.drawHandsBehind(context: ctx, size: size)
                    engine.draw(context: ctx, size: size)
                    engine.drawHandsAndExtras(context: ctx, size: size)
                }
            }
        }
        .frame(width: side, height: side + overhang)
        // Presses on him are caught by the window (`OnboardingWindowController`),
        // on mouse-down as the island does — before the window's background drag
        // could take them.
        .allowsHitTesting(false)
    }
}

// MARK: - The look screen

/// Every Mochi, dressed here: everyone else's, and each service pill's own, with
/// a face, a body and — while there is Christmas — something to wear.
///
/// The Characters page's rules (`CharacterSettingsView`) in the welcome's size:
/// who is listed, what a tile writes and where. Two differences, both decided:
/// Claude Code is not offered (it is Settings' business, like its pill), and a
/// face takes the Christmas outfit off, so the face picked is the face seen.
private struct OnboardingLookScreen: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var state: AppState

    private let ato = MessageSource.ato.pillID
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let tileSize: CGFloat = 30

    /// Whether Christmas is on offer today — always in a debug build, as on the
    /// Characters page.
    private var christmasOpen: Bool {
        #if DEBUG
        return true
        #else
        return MochiFestive.isInSeason(Date())
        #endif
    }

    /// The service pills, in the catalogue's order. Ato only while there is
    /// Christmas for it — the one thing it can wear — as the Characters page.
    private var pills: [PillDefinition] {
        PillCatalog.available.filter { def in
            guard def.category == .service, !def.comingSoon else { return false }
            guard def.id == ato else { return true }
            return model.editing == ato || christmasOpen
                || !(state.character(for: ato).festive?.isEmpty ?? true)
        }
    }

    private var isAto: Bool { model.editing == ato }

    /// What the island shows for the one being dressed — a pill's own face, the
    /// face it ships with, or everyone else's.
    private var current: MochiCharacter {
        model.editing.isEmpty ? state.defaultCharacter : state.character(for: model.editing)
    }

    private var colour: String { PillCatalog.definition(for: model.editing)?.color ?? "#F5F6F8" }
    private var festive: MochiFestive { current.festive ?? MochiFestive() }
    private var showsChristmas: Bool { christmasOpen || !festive.isEmpty }

    /// The tab on show: Ato has only Christmas, and Christmas only while it is on offer.
    private var tab: OnboardingModel.LookTab {
        if isAto { return .christmas }
        if model.lookTab == .christmas && !showsChristmas { return .face }
        return model.lookTab
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Pick a look for each Mochi")
                    .font(.system(size: 19, weight: .semibold))
                Text(loc: "Give each pill its own face. The colour still comes from the pill, "
                     + "so you always know who is talking.")
                    .font(.system(size: 12.5))
                    .foregroundColor(Ink.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            chips.padding(.top, 12)

            // One line kept for it either way, so nothing below jumps.
            Group {
                if !model.editing.isEmpty && state.pillCharacters[model.editing] != nil {
                    Button("Use the default for this one") {
                        state.pillCharacters.removeValue(forKey: model.editing)
                        model.picked()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Ink.accent)
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 11))
            .frame(height: 18)
            .padding(.top, 2)

            tabs.padding(.top, 6)

            ScrollView(.vertical) {
                Group {
                    switch tab {
                    case .face:      faces
                    case .body:      bodies
                    case .christmas: christmas
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: .infinity)
            .padding(.top, 10)
        }
    }

    // MARK: Who

    private var chips: some View {
        HStack(spacing: 6) {
            OnboardingChip(name: "Everyone", chosen: model.editing.isEmpty) {
                model.editing = ""
            } preview: {
                CharacterPreviewView(character: state.defaultCharacter, colorHex: "#F5F6F8", size: 20)
            }
            ForEach(pills, id: \.id) { def in
                OnboardingChip(name: def.name, chosen: model.editing == def.id) {
                    model.editing = def.id
                } preview: {
                    if def.id == ato {
                        AtoCharacterPreviewView(festive: state.character(for: ato).festive, size: 20)
                    } else {
                        CharacterPreviewView(character: state.character(for: def.id),
                                             colorHex: def.color, size: 20)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Tabs

    private var tabs: some View {
        Picker("", selection: Binding(get: { tab }, set: { model.lookTab = $0 })) {
            if !isAto {
                Text("Face").tag(OnboardingModel.LookTab.face)
                Text("Body").tag(OnboardingModel.LookTab.body)
            }
            if showsChristmas {
                Text("Christmas").tag(OnboardingModel.LookTab.christmas)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    // MARK: Face

    private var faces: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            // A face is the whole look: its accessory and eyes, the body kept, and
            // the Christmas outfit taken off — a hat sits where the accessory
            // goes and festive eyes replace the eyes, so keeping it would make a
            // pick change nothing anyone could see.
            CharacterTile(character: MochiCharacter(shape: current.shape),
                          colorHex: colour, name: "Classic",
                          chosen: festive.isEmpty && current.accessory == nil && current.eye == nil,
                          size: tileSize, shrinksName: true) {
                write(MochiCharacter(shape: current.shape))
            }
            ForEach(CharacterCatalog.presets, id: \.id) { preset in
                CharacterTile(character: MochiCharacter(accessory: preset.character.accessory,
                                                        eye: preset.character.eye,
                                                        shape: current.shape),
                              colorHex: colour, name: preset.name,
                              chosen: festive.isEmpty
                                   && preset.character.accessory == current.accessory
                                   && preset.character.eye == current.eye,
                              size: tileSize, shrinksName: true) {
                    write(MochiCharacter(accessory: preset.character.accessory,
                                         eye: preset.character.eye,
                                         shape: current.shape))
                }
            }
        }
    }

    // MARK: Body

    private var bodies: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(([nil] + MochiShape.allCases.map(Optional.some)).enumerated()), id: \.offset) { _, shape in
                CharacterTile(character: MochiCharacter(accessory: current.accessory,
                                                        eye: current.eye, shape: shape),
                              colorHex: colour, name: shape?.label ?? "Classic",
                              chosen: current.shape == shape,
                              size: tileSize, shrinksName: true) {
                    write(MochiCharacter(accessory: current.accessory, eye: current.eye,
                                         shape: shape, festive: current.festive))
                }
            }
        }
    }

    // MARK: Christmas

    private var christmas: some View {
        VStack(alignment: .leading, spacing: 10) {
            if christmasOpen {
                Text("Until January 6")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color(hex: "#CFE3F7"))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color(hex: "#16222E")))
                    .overlay(Capsule().stroke(Color(hex: "#3B9EFF").opacity(0.55), lineWidth: 1))
                    .frame(maxWidth: .infinity)
            }
            section("Ready-made") {
                festiveTile("None", wearing: MochiFestive(), chosen: festive.isEmpty)
                ForEach(MochiFestiveArt.catalog.presets, id: \.id) { preset in
                    festiveTile(preset.name, wearing: preset.festive, chosen: festive == preset.festive)
                }
            }
            part("Head", MochiFestiveArt.catalog.heads, \.head)
            part("Eyes", MochiFestiveArt.catalog.eyes, \.eyes)
            part("Texture", MochiFestiveArt.catalog.textures, \.texture)
            part("Extra", MochiFestiveArt.catalog.extras, \.extra)
        }
    }

    private func section<Tiles: View>(_ title: String, @ViewBuilder tiles: () -> Tiles) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(loc: title)
                .font(.system(size: 10.5))
                .foregroundColor(Ink.secondary.opacity(0.8))
            LazyVGrid(columns: columns, spacing: 6) { tiles() }
        }
    }

    /// One of the four parts: nothing, then the catalogue's options. Each tile
    /// changes that part and keeps the other three, as on the Characters page.
    private func part(_ title: String, _ options: [[String]],
                      _ key: WritableKeyPath<MochiFestive, String?>) -> some View {
        section(title) {
            festiveTile("None", wearing: with(key, nil), chosen: (festive[keyPath: key] ?? "").isEmpty)
            ForEach(options.filter { $0.count == 2 }, id: \.first) { option in
                festiveTile(option[1], wearing: with(key, option[0]),
                            chosen: festive[keyPath: key] == option[0])
            }
        }
    }

    private func with(_ key: WritableKeyPath<MochiFestive, String?>, _ id: String?) -> MochiFestive {
        var changed = festive
        changed[keyPath: key] = id
        return changed
    }

    private func festiveTile(_ name: String, wearing worn: MochiFestive, chosen: Bool) -> some View {
        CharacterTile(name: name, chosen: chosen, shrinksName: true) {
            var character = current
            character.festive = worn.orNil
            write(character)
        } preview: {
            if isAto {
                AtoCharacterPreviewView(festive: worn.orNil, size: tileSize)
            } else {
                CharacterPreviewView(character: MochiCharacter(accessory: current.accessory,
                                                               eye: current.eye,
                                                               shape: current.shape,
                                                               festive: worn.orNil),
                                     colorHex: colour, size: tileSize)
            }
        }
    }

    // MARK: Writing

    /// Where the Characters page writes it: everyone else's, or the pill's own.
    private func write(_ character: MochiCharacter) {
        guard character != current else { return }
        if model.editing.isEmpty {
            state.defaultCharacter = character
        } else {
            state.pillCharacters[model.editing] = character
        }
        model.picked()
    }
}

/// Whose Mochi the look screen dresses: a still of each, in the tile style.
private struct OnboardingChip<Preview: View>: View {
    /// A catalogue key, or a pill's name, translated where it is drawn.
    let name: String
    let chosen: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                preview()
                Text(loc: name)
                    .font(.system(size: 9.5))
                    .foregroundColor(chosen ? Color(hex: "#CFE3F7") : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .padding(.horizontal, 2)
            }
            .padding(.vertical, 3)
            .frame(width: 66)
            .background(chosen ? Color(hex: "#16222E") : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(chosen ? Color(hex: "#3B9EFF") : Color.white.opacity(0.08),
                            lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
