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

    private let onFinish: () -> Void

    init(start: OnboardingStep, onFinish: @escaping () -> Void) {
        flow = OnboardingFlow(start: start)
        let typed = AppState.shared.userName
        name = typed.isEmpty ? (systemUserFirstName ?? "") : typed
        self.onFinish = onFinish
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

    static let size = CGSize(width: 520, height: 620)

    var body: some View {
        // The hello and the last screen ask nothing: Mochi is bigger there and
        // the words sit in the middle. The five questions keep him small and
        // start at the top, under their progress row.
        let isQuestion = model.flow.progress != nil
        VStack(spacing: 0) {
            topBar
            OnboardingMochiView(engine: model.engine, state: state, diameter: isQuestion ? 56 : 84)
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
        case .look:     look
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

    private var look: some View {
        let current = state.defaultCharacter
        // A tile is "the one" only while nothing is worn over it: under a Santa
        // hat the matching face is not what anybody sees.
        let bare = current.festive == nil
        return VStack(spacing: 14) {
            heading(Text("Pick my look"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                // A tile becomes the whole look: its face, the body kept, and the
                // Christmas outfit taken off — a hat sits where the accessory
                // goes and festive eyes replace the eyes, so keeping it made a
                // click change nothing you could see, here or on the island.
                // (Settings' grid keeps the outfit; it has its own Christmas block.)
                CharacterTile(character: MochiCharacter(shape: current.shape),
                              colorHex: "#F5F6F8", name: "Classic",
                              chosen: bare && current.accessory == nil && current.eye == nil,
                              size: 34) {
                    pick(MochiCharacter(shape: current.shape))
                }
                ForEach(CharacterCatalog.presets, id: \.id) { preset in
                    CharacterTile(character: MochiCharacter(accessory: preset.character.accessory,
                                                            eye: preset.character.eye,
                                                            shape: current.shape),
                                  colorHex: "#F5F6F8", name: preset.name,
                                  chosen: bare
                                       && preset.character.accessory == current.accessory
                                       && preset.character.eye == current.eye,
                                  size: 34) {
                        pick(MochiCharacter(accessory: preset.character.accessory,
                                            eye: preset.character.eye,
                                            shape: current.shape))
                    }
                }
            }
            Text("There is more under Settings › Characters: shapes, eyes and a look for each pill.")
                .font(.system(size: 11.5))
                .foregroundColor(Ink.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pick(_ character: MochiCharacter) {
        guard character != state.defaultCharacter else { return }
        state.defaultCharacter = character
        model.picked()
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

/// Mochi, alive, at the top of the welcome: whatever character the user has
/// right now, so the look screen changes him under their eyes.
///
/// The island's drawing sequence (`BotCanvasView`) without the island: no owner,
/// no pointer, no dance — his own engine, ticking only while the window is open.
struct OnboardingMochiView: View {
    let engine: BotEngine
    @ObservedObject var state: AppState
    var diameter: CGFloat = 56
    /// Headroom above him for hearts and stars, as `BotPlacement` leaves.
    private let overhang: CGFloat = 34
    private let white = cgColorFromHex("#F5F6F8")

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                // `BotCanvasView`'s own expression, kept as is so he moves at the
                // island's pace: `lastTime` is media time, so this clamps to 0.05.
                let dt = min(0.05, now - engine.lastTime)
                // The island's white, as Claude Code's pill gives him — left
                // nil, the engine falls back to its grey state gradient.
                engine.bodyColor = white
                engine.character = state.defaultCharacter
                engine.particleOverhang = overhang
                engine.update(dt: dt)
                var ctx = context
                engine.applyDance(&ctx, size: size)
                engine.drawHandsBehind(context: ctx, size: size)
                engine.draw(context: ctx, size: size)
                engine.drawHandsAndExtras(context: ctx, size: size)
            }
        }
        .frame(width: diameter / 0.6, height: diameter / 0.6 + overhang)
        .allowsHitTesting(false)
    }
}
