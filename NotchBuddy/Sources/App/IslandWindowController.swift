import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandWindowController: NSWindowController {
    /// Views that can take a keystroke. The panel is non-activating, so it never
    /// becomes key on its own and a TextField in one of these would sit there
    /// looking focused while swallowing everything typed into it.
    /// Views whose field may hold the keyboard once the user has clicked into it.
    /// Not "views that take the keyboard when they appear" — see `wireFSM`.
    /// Views whose field may hold the keyboard once the user has clicked into it.
    /// Not "views that take the keyboard when they appear" — see `wireFSM`.
    /// Home is here because it can hold a message with a reply box.
    #if APPSTORE
    static let viewsWithTextFields: Set<IslandView> = [.prompt, .message, .overview, .web]
    #else
    static let viewsWithTextFields: Set<IslandView> = [.prompt, .message, .overview, .web, .webchat]
    #endif

    /// Whether a drag arriving now should land on a reply rather than in the
    /// bin. Asked on the way in and again on drop, because a drag can begin
    /// before the card is showing and finish after it is.
    @MainActor
    static var replyIsCatching: Bool {
        MessageInbox.shared.replyAcceptsFiles(for: AppState.shared.view)
    }


    private var islandPanel: IslandPanel!
    private var state: AppState { AppState.shared }

    // State machine (replaces all hover/absence/auto-close timers)
    let fsm = IslandStateMachine()

    /// Mouse is over the island or the buttons on its edge. Drives the FSM,
    /// so reaching for a button does not start the island's collapse countdown.
    private var wasHovering = false
    /// Mouse is over the island itself. Guards the click monitor, so a click
    /// on an edge button is that button's alone and does not also expand the
    /// island to its default view.
    private var wasInIsland = false

    /// A card that arrived while the greeting was still playing.
    ///
    /// The greeting owns the island until it has run its course, so `notify(_:)`
    /// parks the view here instead of expanding onto it; the `.coucou` → `.petit`
    /// arm of `onTransition` hands it on once the canvas has folded.
    private var pendingNotifyView: IslandView?

    /// Slack around the island that still counts as reaching it.
    private static let enterMargin: CGFloat = 6
    /// Slack around an open island that still counts as being on it.
    private static let stayMargin: CGFloat = 20
    private var frameTimer: Timer?
    private var keyMonitor: Any?
    /// Separate from `keyMonitor` because this one is local: it can consume the
    /// event, which is the only way a pasted screenshot reaches the reply.
    private var pasteMonitor: Any?
    private var viewSubscription: AnyCancellable?
    private var modeSubscription: AnyCancellable?

    // Confused recovery timer (set by handleDizzy)
    private var confusedRecoveryTimer: DispatchWorkItem?

    // Suppress peek sound on next reveal (e.g. musicReveal)
    var silentNextReveal = false

    // Finished-pin timer
    private var finishedPinTimer: DispatchWorkItem?

    // Bot-head hover (love emote — mirrors prototype botHover())
    private var hoverTimer: DispatchWorkItem?
    private var botHoverTimer: DispatchWorkItem?
    private var botHovering: Bool = false
    private var lastLoveTime: Double = 0
    private var botHoverStartPos: CGPoint = .zero

    // Holding the island to move it
    /// Set while a press on the resting island might still become a drag.
    private var grabStart: NSPoint? = nil
    private var grabTimer: DispatchWorkItem?
    /// True from the moment the island comes unstuck until it is put down.
    private var movingIsland = false
    /// The pointer's offset from the panel's origin when it came unstuck.
    private var grabOffset: CGSize = .zero

    /// How long the resting island must be held before it comes unstuck.
    ///
    /// Long, deliberately. The island is one click away from opening and it
    /// sits where the pointer passes on its way to the menu bar: anything quick
    /// enough to feel like a shortcut would be short enough to trip over.
    static let holdToMove: TimeInterval = 2.0

    /// How far the pointer may wander during that hold, in points.
    static let holdSlop: CGFloat = 6

    // Window attach drag (M8)
    private var attachDragStart: NSPoint? = nil
    private var pendingIslandClick = false   // any island click → expand on mouseUp
    private var inAttachDrag = false
    private var dropView: FileDropNSView?
    private var dragGhostPanel: NSPanel? = nil
    private var dragGhostSize: CGFloat = 0
    private var ghostCurrentOrigin: NSPoint = .zero
    private var highlightPanel: NSPanel? = nil
    private var highlightWindowPid: pid_t = 0

    // Notch real dimensions (set on init)
    private var notchW: CGFloat = IslandConst.notchWidth
    private var notchH: CGFloat = IslandConst.notchHeight
    private var hasNotch = true

    /// The panel's size. The island is drawn inside it.
    ///
    /// Large enough for the biggest island plus the buttons hung off its edges.
    /// Costs nothing to oversize: `ignoresMouseEvents` starts true and is only
    /// cleared while the pointer is inside the chrome rect, so the panel's own
    /// size has never decided what it swallows.
    static let panelWidth: CGFloat = 1200
    static let panelHeight: CGFloat = 820

    /// Consecutive ticks the panel has accepted the mouse while the pointer was
    /// nowhere near it. See the watchdog in `pollFrame`.
    private var clickThroughStuckTicks = 0

    /// The island's shape follows its view, so a view change is a resize. These
    /// remember the last one, and where the pointer was when it happened, so
    /// the chrome sliding out from under a still cursor is not read as the
    /// user leaving — see the hover computation in `pollFrame`.
    private var lastPolledView: IslandView?
    private var reshapedAt: Date?
    private var pointerWhenReshaped: CGPoint?

    /// The screen the panel is on, so a move that changes nothing costs nothing.
    /// The runtime id, not the stored one — see `IslandDisplays.runtimeID`.
    private var currentScreenID: CGDirectDisplayID?

    convenience init(screen: NSScreen) {
        let panel = IslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        self.init(window: panel)
        self.islandPanel = panel
        move(to: screen)
        setupPanel(screen: screen)
    }

    /// Puts the island on `screen`, measuring that screen's own notch.
    ///
    /// The frame used to be set once, in `init`, and never again — so plugging a
    /// display in left Mochi where she was, and closing the lid in clamshell
    /// stranded her on a screen that no longer existed. `constrainFrameRect`
    /// returns the rect untouched, so AppKit never pulled her back either.
    func move(to screen: NSScreen) {
        guard let panel = window as? IslandPanel else { return }
        let id = IslandDisplays.runtimeID(for: screen)
        let geometry = Self.screenGeometry(for: screen)

        notchW = geometry.width
        notchH = geometry.height
        hasNotch = geometry.hasNotch
        panel.notchWidth = notchW
        panel.notchHeight = notchH

        // Publishing this is what makes the views redraw at the new size.
        AppState.shared.screenGeometry = geometry

        panel.anchor = Self.anchor(on: screen, geometry: geometry)
        panel.metrics = Self.metrics(for: geometry)
        panel.setFrame(Self.panelFrame(on: screen, anchor: panel.anchor), display: false)
        currentScreenID = id

        // Moving a window between displays does not reliably leave it above the
        // menu bar on the new one.
        if panel.isVisible { panel.orderFrontRegardless() }

        // Which display the island thinks it is on, and at what size. Two rounds
        // of this went on guesswork about behaviour that cannot be seen from a
        // build machine; one line in ~/Library/Logs/Notchy/island.log is cheaper.
        appendAppLog("island.log",
                     "→ \(IslandDisplays.localizedName(for: screen)) "
                     + "[\(id.map(String.init) ?? "?")] "
                     + "\(Int(geometry.width))×\(Int(geometry.height)) "
                     + "notch=\(geometry.hasNotch)")
    }

    /// The island's resting footprint and the panel's size, for `IslandAnchor`.
    ///
    /// The resting footprint is the compact bar — what a hand is actually
    /// holding when it picks the island up — which on a Mac is the notch plus
    /// its tail, measured per display.
    static func metrics(for geometry: IslandScreenGeometry) -> IslandAnchor.Metrics {
        IslandAnchor.Metrics(
            rest: CGSize(width: geometry.width + 160, height: geometry.height),
            panel: CGSize(width: panelWidth, height: panelHeight))
    }

    /// The stored position, resolved against a screen's own work area.
    ///
    /// `visibleFrame` is the Mac's work area: a dropped island keeps clear of
    /// the Dock and the menu bar, where one in the notch deliberately does not.
    static func anchor(on screen: NSScreen, geometry: IslandScreenGeometry) -> IslandAnchor.Resolved {
        let vf = screen.visibleFrame
        return IslandAnchor.resolve(
            AppState.shared.islandPosition,
            areaW: vf.width, areaH: vf.height, metrics: metrics(for: geometry))
    }

    /// Where the panel goes on `screen` for that anchor.
    ///
    /// The rectangle a named position is placed inside follows the same split as
    /// `placement_area` in windows/src-tauri/src/island.rs: at the top it is the
    /// whole screen, so the island sits against the very edge over the menu bar,
    /// which is what being in the notch means; at the bottom it is the visible
    /// frame, so the island rests on the Dock instead of behind it.
    ///
    /// This has to agree with `IslandPanel.islandFrame`, which places the island
    /// *inside* the panel from the same anchor. While it did not — while every
    /// named position came back as this one top-centre rect — choosing any of
    /// them but top centre drew the island in a corner of a panel that was still
    /// at the top of the screen, which is to say nowhere near where it said.
    ///
    /// The y flip is here because `IslandAnchor` counts down from the top, like
    /// the web port it has to agree with, while AppKit counts up from the bottom.
    static func panelFrame(on screen: NSScreen, anchor: IslandAnchor.Resolved) -> NSRect {
        let size = NSSize(width: panelWidth, height: panelHeight)
        if let free = anchor.free {
            let vf = screen.visibleFrame
            return NSRect(x: vf.minX + free.winX,
                          y: vf.maxY - free.winY - panelHeight,
                          width: size.width, height: size.height)
        }
        let area = anchor.edge == .top ? screen.frame : screen.visibleFrame
        let x: CGFloat
        switch anchor.align {
        case .left:   x = area.minX
        case .centre: x = area.midX - panelWidth / 2
        case .right:  x = area.maxX - panelWidth
        }
        let y = anchor.edge == .top ? area.maxY - panelHeight : area.minY
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Picking the island up
    //
    // Settings can put the island in one of six places; holding it puts it
    // anywhere. A press on the resting island that lasts `holdToMove` without
    // wandering unsticks it, and from there the panel follows the pointer —
    // across displays and all — until the button comes back up.

    /// A press on the resting island that might still become a drag.
    private func armGrab(at mouse: NSPoint) {
        cancelGrab()
        guard state.mode != .expanded else { return }
        grabStart = mouse
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.liftIsland() }
        }
        grabTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdToMove, execute: work)
    }

    /// Lets a press go. Anything short of a lift is the click it always was.
    private func cancelGrab() {
        grabTimer?.cancel()
        grabTimer = nil
        grabStart = nil
    }

    /// The pointer wandered while a press was being held: a hand that is moving
    /// was never waiting, so the press goes back to being an ordinary click.
    private func checkGrabSlop(_ mouse: NSPoint) {
        guard let start = grabStart else { return }
        if hypot(mouse.x - start.x, mouse.y - start.y) > Self.holdSlop { cancelGrab() }
    }

    /// Held long enough: the island comes unstuck and takes the pointer with it.
    private func liftIsland() {
        guard grabStart != nil, let panel = window as? IslandPanel else { return }
        cancelGrab()
        guard state.mode != .expanded else { return }
        let mouse = NSEvent.mouseLocation
        grabOffset = CGSize(width: mouse.x - panel.frame.minX, height: mouse.y - panel.frame.minY)
        movingIsland = true
        // The press that would have opened the island on mouse-up is spent: it
        // turned into this instead.
        pendingIslandClick = false
        attachDragStart = nil
        if !silentNextReveal { SoundEngine.shared.play("peek") }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
    }

    /// Puts the island down: works out where it landed and writes it to the
    /// preference, which places the panel properly through `islandPositionChanged`.
    ///
    /// Dropped on another display, it is simply stored against that display's
    /// work area. The point is kept as a fraction, so the island turns up in
    /// the same spot on whichever screen it is shown on next — which is what
    /// dropping it over there was asking for.
    private func dropIsland() {
        movingIsland = false
        guard let panel = window as? IslandPanel else { return }
        let centre = panel.restingCentre()
        let onScreen = CGPoint(x: panel.frame.minX + centre.x, y: panel.frame.minY + centre.y)
        let screen = NSScreen.screens.first { $0.frame.contains(onScreen) }
            ?? panel.screen ?? NSScreen.main
        guard let screen else { return }
        let vf = screen.visibleFrame
        AppState.shared.islandPosition = IslandAnchor.positionForDrop(
            centre: CGPoint(x: onScreen.x - vf.minX, y: vf.maxY - onScreen.y),
            areaW: vf.width,
            areaH: vf.height,
            metrics: Self.metrics(for: Self.screenGeometry(for: screen)))
        move(to: screen)
        SoundEngine.shared.play("approve")
    }

    /// The island's own rectangle in screen coordinates, or nil while there is
    /// no panel. What anything that has to sit beside the island reads.
    func islandScreenFrame() -> CGRect? {
        guard let panel = window as? IslandPanel else { return nil }
        let r = panel.currentIslandFrame(nw: notchW, nh: notchH)
        return r.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }

    /// Places the panel again after the position changed — dragged, or picked
    /// from the list in Settings.
    func reposition() {
        guard let screen = window?.screen ?? NSScreen.main else { return }
        move(to: screen)
    }

    /// Whether the island is already on this screen.
    func isOn(_ screen: NSScreen) -> Bool {
        guard let id = IslandDisplays.runtimeID(for: screen) else { return false }
        return id == currentScreenID
    }

    private func setupPanel(screen: NSScreen) {
        guard let panel = window as? IslandPanel else { return }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        // Apple-recommended pattern: put NSHostingView and drag destination as siblings
        // inside a common superview, rather than embedding one inside the other.
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: Localizing { IslandRootView().environmentObject(AppState.shared) })
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        // FileDropNSView sits below the hosting view (hitTest returns nil → no mouse interference).
        // AppKit routes NSDraggingDestination events to registered views independently of hitTest.
        let dropView = FileDropNSView(frame: NSRect(origin: .zero, size: contentSize))
        // Only over the island itself, never the panel's empty acres.
        dropView.dropRegion = { [weak panel] in
            guard let panel else { return .zero }
            return panel.currentIslandFrame(nw: panel.notchWidth, nh: panel.notchHeight)
                .insetBy(dx: -24, dy: -24)
        }
        self.dropView = dropView
        dropView.autoresizingMask = [.width, .height]
        dropView.onDragEntered = { [weak self] loc in
            Task { @MainActor in
                // A reply box that can take the file catches it instead: no bin
                // morph, no view switch, because the card the user is writing in
                // must stay exactly where it is.
                guard !Self.replyIsCatching else {
                    AppState.shared.replyDragOver = true
                    return
                }
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                AppState.shared.fileDragOver = true
                // enterZone sets isActive=true BEFORE hookExpand triggers re-render,
                // so IslandContainer sees isActive=true when state.view becomes .upload.
                UploadSequenceEngine.shared.enterZone(x: iLoc.x, y: iLoc.y)
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(1))
            }
        }
        dropView.onDragUpdated = { [weak self] loc in
            Task { @MainActor in
                guard !AppState.shared.replyDragOver else { return }
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                UploadSequenceEngine.shared.updateCursor(x: iLoc.x, y: iLoc.y)
            }
        }
        dropView.onDragExited = {
            Task { @MainActor in
                guard !AppState.shared.replyDragOver else {
                    AppState.shared.replyDragOver = false
                    return
                }
                AppState.shared.fileDragOver = false
                // Do NOT collapse — drag session still active; island stays open.
                NotificationCenter.default.post(name: .botMorphTo, object: CGFloat(0))
                UploadSequenceEngine.shared.exitZone()
            }
        }
        dropView.onFilesDropped = { urls in
            Task { @MainActor in
                if AppState.shared.replyDragOver || Self.replyIsCatching {
                    AppState.shared.replyDragOver = false
                    ReplyAttachmentStore.attach(urls: urls, state: AppState.shared)
                    return
                }
                await FileDropHandler.handle(urls: urls, state: AppState.shared)
            }
        }

        container.addSubview(hosting)    // z-bottom: SwiftUI + mouse events
        container.addSubview(dropView)   // z-top: drag only (hitTest→nil, transparent to mouse)
        panel.contentView = container

        startPolling()
        startKeyMonitor()
        wireFSM()

        modeSubscription = state.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMode in
                guard let self else { return }
                #if !APPSTORE
                // The view sink alone never fires on a collapse and re-expand that stays
                // on the same view.
                if newMode != .expanded {
                    WebChatController.shared.deactivate()
                } else if self.state.view == .webchat {
                    self.islandPanel.makeKey()
                }
                #endif
            }

        // The chat is opened by clicking the chat tab, so taking the keyboard
        // when it appears is answering a request. Nothing else may.
        //
        // This used to fire for every view with a text field, which included the
        // message card — and that card appears because somebody else sent you
        // something. The island took the keyboard mid-sentence, and the next
        // keystrokes went to a panel instead of to whatever was being typed in.
        // That is the freeze: not the Mac stalling, the keys going elsewhere.
        viewSubscription = state.$view
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newView in
                guard let self else { return }
                #if !APPSTORE
                if newView != .webchat { WebChatController.shared.deactivate() }
                // With the website on screen a dropped file means "attach it to ChatGPT".
                // Coucou's drop view sits in front of everything, so it has to stand down
                // for the page to ever see the file.
                self.dropView?.setDropEnabled(newView != .webchat)
                guard newView == .prompt || newView == .webchat else { return }
                #else
                guard newView == .prompt else { return }
                #endif
                self.islandPanel.makeKey()
            }

        // Clicking into the reply field is a request, and the panel has to be key
        // before the field can take a keystroke. Posted from the field itself and
        // delivered synchronously, so the window is key by the time SwiftUI makes
        // it first responder.
        NotificationCenter.default.addObserver(
            forName: .islandWantsKeyboard, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.islandPanel.makeKey() }
        }
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        // How long a notification holds the island open is the user's setting,
        // and nothing used to carry it across: the machine kept its own literal
        // and every Mac held cards for five seconds whatever the field said.
        // `notify(_:)` refreshes this before each card, so a change in Settings
        // applies to the very next one without anything to observe or tear down.
        fsm.notificationHoldDelay = state.autoCloseInterval

        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            switch to {
            case .hidden:
                self.setMode(.hidden)

            case .petit:
                // A notification that folded away leaves `view` on `.message`,
                // so the next peek showed a card nobody asked for again. Home is
                // where it belongs, and Home is now what holds the last message.
                if from == .home && self.state.view == .message {
                    self.state.view = .overview
                }
                if from == .coucou {
                    // The greeting has played out; this is what starts the
                    // canvas folding, and it goes first so that collapse is
                    // under way before the mode change resizes the window.
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
                } else if from == .hidden {
                    if self.silentNextReveal {
                        self.silentNextReveal = false
                    } else {
                        SoundEngine.shared.play("peek")
                    }
                }
                // setMode BEFORE changing view: onChange(of: state.view) guards on .expanded,
                // so setting view while already compact won't trigger a spurious open animation.
                self.setMode(.compact)
                if from == .coucou { self.state.view = self.defaultView() }
                // Start the 60 s hide timer if the pointer is not on the island.
                //
                // `fsm.pointerInside`, never `wasInIsland`: this runs
                // synchronously inside the transition, and `wasInIsland` is only
                // updated at the end of the poll tick — so during a hover-open it
                // still reads false and this would schedule a collapse under a
                // pointer that never moved.
                if !self.fsm.pointerInside { self.fsm.mouseLeft() }

                // A card that waited for the greeting. It goes out after the
                // canvas has folded — delivered any sooner it would be fighting
                // the collapse animation for the same island.
                if from == .coucou, let pending = self.pendingNotifyView {
                    self.pendingNotifyView = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
                        self?.notify(pending)
                    }
                }

            case .home:
                // No leave-collapse here. An island opened with nobody on it
                // folds away on the hold `openedExternally()` armed, which is the
                // whole point of the hold; scheduling the grace as well closed it
                // instantly.
                //
                // An island already open keeps the view it is open on. The FSM
                // can reach `.home` from `.petit` while the panel is expanded —
                // anything that expanded it without going through the machine
                // leaves exactly that — and `defaultView()` there threw away
                // whatever the user had opened the moment the pointer arrived.
                let landing = self.state.mode == .expanded ? self.state.view
                                                           : self.defaultView()
                self.expand(to: landing)

            case .coucou:
                // The greeting is nothing but Mochi saying hello, so with the
                // characters off there is no hello to play. Report it finished
                // instead of expanding onto an empty island: the machine then
                // folds to `.petit` on its own timer, exactly as it would have
                // once the animation ended.
                if self.state.hideCharacters {
                    self.fsm.greetComplete()
                } else {
                    self.expand(to: .greeting)
                }
            }
        }

        // FSM observes greetComplete notification
        NotificationCenter.default.addObserver(
            forName: .greetComplete, object: nil, queue: .main
        ) { [weak self] _ in
            self?.fsm.greetComplete()
        }

        // A reply being typed holds the island open exactly as a pending
        // approval does: both are the user mid-answer, and closing on a timer
        // would throw the answer away.
        // Deliberately not `pendingApproval`: an alert waiting for an answer now
        // folds away with everything else when its hold runs out, and Claude
        // Code falls back to asking in the terminal. A half-written reply is the
        // one thing a timer must never take away mid-word.
        // Staged files and an open file picker hold the card for the same
        // reason a half-written sentence does. The picker is the sharper case:
        // it takes the keyboard, so `isReplying` goes false the instant it
        // opens, and without this the card would fold away behind it.
        // A screen — the site, the ChatGPT page — is held on the same terms: it
        // is somewhere the user went, and the pointer wandering off is not them
        // asking to leave. `viewHoldsIslandOpen` is what both now go through.
        fsm.isHeldOpen = { () -> Bool in
            let state = AppState.shared
            return state.isReplying || state.viewHoldsIslandOpen
                || state.isPickingFile || !state.replyAttachments.isEmpty
        }

        // The built-in chat, while something is typed in it or an answer is on
        // its way. Blocks only the pointer-leave timer, never an explicit
        // collapse — which is the whole reason this hook is separate from
        // `isHeldOpen`: Escape and the tabs have to keep working on a card.
        fsm.holdsHomeOpen = { AppState.shared.chatHoldsIsland }
    }

    // MARK: - 60 Hz polling loop

    private func startPolling() {
        // setRunning(true) can call this again; without the guard the old timer
        // is leaked and two of them drive the island at once.
        guard frameTimer == nil else { return }
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.pollFrame() }
        }
        RunLoop.main.add(frameTimer!, forMode: .common)
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }

        let mouse = NSEvent.mouseLocation

        // A picked-up island is carried by the pointer, so the pointer is on it
        // in every frame. Letting the rest of this run would be the island
        // telling itself it is being hovered all the way across the screen,
        // which is how a drag would end with a card open under the hand that
        // was moving it.
        if movingIsland {
            panel.setFrameOrigin(NSPoint(x: mouse.x - grabOffset.width,
                                         y: mouse.y - grabOffset.height))
            return
        }
        checkGrabSlop(mouse)

        // Convert mouse to panel-local coords (macOS: origin bottom-left)
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        // Island rect in panel coords
        let islandRect = panel.currentIslandFrame(nw: notchW, nh: notchH)

        // Two rects, because hovering and clicking want opposite things.
        //
        // Hovering wants to be easy: on a screen without a notch the resting bar
        // is a small target with nothing to aim at, and it used to be given no
        // slack at all — which is what made Mochi feel unreachable there.
        //
        // Taking clicks wants to be exact: the window swallowing the mouse just
        // under the menu bar would steal clicks from whatever is behind it. So
        // the generous rect drives the state machine only, and the tight one
        // decides when the panel stops being click-through. Hover detection does
        // not need the window's events — it reads NSEvent.mouseLocation — so the
        // two can disagree safely.
        //
        // Asymmetric on purpose: opening asks the pointer to arrive somewhere
        // specific, closing asks it to clearly leave. Without the gap a cursor
        // resting on the boundary crosses it several times a second and the
        // island chatters.
        let slack: CGFloat = state.mode == .expanded ? Self.stayMargin : Self.enterMargin
        let chromeRect = panel.currentChromeFrame(nw: notchW, nh: notchH)

        // Which rect holds the island open is not the same question as which
        // one opens it. Reaching for a button must not *open* a closed island —
        // the point of the ring is getting at a pill without opening anything —
        // but once it is open, moving onto a button must not close it either,
        // or the island folds away under a pointer on its way to the thing it
        // is aiming at. So: the island opens it, the chrome keeps it.
        let stayBase = state.mode == .expanded ? chromeRect : islandRect
        let hoverRect = stayBase.insetBy(dx: -slack, dy: -slack)
        let inIsland = hoverRect.contains(local)

        // The island moved; the pointer did not.
        //
        // A view that makes the island *shorter* pulls the chrome up from
        // under a cursor that never went anywhere, and this poll reads that
        // as the user leaving. The bottom edge buttons are where it bites:
        // the whole height change lands there, so clicking Now Playing with
        // the message list open (240 pt → 190) leaves the pointer 33 pt below
        // the new chrome, and the island folds in the same breath as it opens.
        //
        // So a leave only counts once the pointer has actually moved since
        // the island last changed shape. Movement, or the window passing,
        // ends the grace — it cannot wedge the island open.
        if state.view != lastPolledView {
            lastPolledView = state.view
            reshapedAt = Date()
            pointerWhenReshaped = local
        }
        let pointerStill = pointerWhenReshaped.map {
            abs($0.x - local.x) < 2 && abs($0.y - local.y) < 2
        } ?? false
        let justReshaped = reshapedAt.map { Date().timeIntervalSince($0) < 0.5 } ?? false

        let hovering = inIsland || (state.mode == .expanded && justReshaped && pointerStill)

        // Click-through covers the buttons in every mode, open or not.
        let clickRect = !hasNotch && state.mode != .expanded
            ? islandRect.union(chromeRect)
            : hoverRect.union(chromeRect)
        var shouldAcceptMouse = clickRect.contains(local)
            || inAttachDrag || attachDragStart != nil
        #if !APPSTORE
        // A drag or momentum scroll that leaves the island would otherwise lose its mouseUp
        // to the 60 Hz flip, stranding WebKit mid-gesture. The watchdog below is unaffected:
        // while the hold is on, shouldAcceptMouse is true and its counter stays at zero.
        shouldAcceptMouse = shouldAcceptMouse || WebChatController.shared.holdsMouse
        #endif

        // A panel this size that got stuck accepting the mouse would eat clicks
        // across most of the display, and the pointer would never come back to
        // clear it. Cheap to check, and it turns a hang into a log line.
        if !shouldAcceptMouse && !panel.ignoresMouseEvents {
            clickThroughStuckTicks += 1
            if clickThroughStuckTicks > 30 {
                panel.ignoresMouseEvents = true
                clickThroughStuckTicks = 0
                appendAppLog("island.log", "click-through watchdog fired")
            }
        } else {
            clickThroughStuckTicks = 0
        }
        if panel.ignoresMouseEvents == shouldAcceptMouse {
            panel.ignoresMouseEvents = !shouldAcceptMouse
            if shouldAcceptMouse, let cv = panel.contentView {
                panel.invalidateCursorRects(for: cv)
            }
        }

        // Mouse in screen coords (Y flipped, origin top-left) for Bot look-at
        let screenH = panel.screen?.frame.height ?? NSScreen.main!.frame.height
        let newPos = CGPoint(x: mouse.x - (panel.screen?.frame.minX ?? 0), y: screenH - mouse.y)
        let cur = AppState.shared.mousePosition
        if abs(newPos.x - cur.x) > 1 || abs(newPos.y - cur.y) > 1 {
            AppState.shared.mousePosition = newPos
        }

        // Where the island really is, for Mochi's eyes. Screen-local, like
        // `mousePosition` just above, so the two can be subtracted.
        let minX = panel.frame.minX + islandRect.minX - (panel.screen?.frame.minX ?? 0)
        if abs(minX - AppState.shared.islandScreenMinX) > 1 {
            AppState.shared.islandScreenMinX = minX
        }

        // AppState can hide the island by itself (last task ended): keep the FSM in step.
        if state.mode == .hidden && fsm.state == .petit { fsm.hiddenExternally() }

        // The island went, so the click that opened it is spent. The ring only
        // exists while the island is open, which is what makes this the end of
        // the pair: without it the memory of a pill click would sit there for
        // as long as the app ran, and the next first click on that pill would
        // read as a second one.
        if state.mode != .expanded { forgetPillClick() }

        // Follow the cursor between displays. Not while a card is open — that
        // would teleport it out from under the pointer — but the compact bar
        // follows too, or a single work event left the island stuck on whatever
        // display it happened to be on.
        if state.mode != .expanded { followCursorAcrossDisplays(mouse) }

        // Feed FSM hover enter/leave
        if hovering && !wasHovering {
            guard !inAttachDrag else { wasHovering = hovering; wasInIsland = inIsland; return }
            // Whatever was counting down is off: the island stays until the
            // pointer leaves.
            state.holdingUntil = nil
            fsm.mouseEntered()
        }
        if !hovering && wasHovering {
            // Leaving no longer starts a countdown worth drawing — the island is
            // on its way out within the grace period. The chrome is inside the
            // stay rect once open, so a pointer on its way to a button does not
            // start the countdown either.
            state.holdingUntil = nil
            fsm.mouseLeft()
        }
        wasHovering  = hovering
        wasInIsland  = inIsland

        // Bot-head hover (love emote)
        let overBot = state.mode == .expanded && state.stateOverride == nil && isBotHit(local)
        if overBot && !botHovering { botHoverIn(mousePos: NSEvent.mouseLocation) }
        if !overBot && botHovering { botHoverOut() }
        botHovering = overBot
        if botHovering {
            let m = NSEvent.mouseLocation
            let dist = hypot(m.x - botHoverStartPos.x, m.y - botHoverStartPos.y)
            if dist > 40 {
                botHoverStartPos = m
                botHoverTimer?.cancel()
                scheduleLoveTimer()
            }
        }

        // Ghost Mochi follows cursor + window highlight during drag (60 Hz, no throttle)
        if inAttachDrag {
            updateDragGhost()
            updateWindowHighlight()
        }
    }

    private var lastMouse: CGPoint = .zero

    // MARK: - Bot-head hover (love emote — mirrors prototype botHover())

    private func botHoverIn(mousePos: CGPoint) {
        guard state.mode == .expanded, state.stateOverride == nil else { return }
        guard CACurrentMediaTime() - lastLoveTime > 6 else { return }
        botHoverStartPos = mousePos
        NotificationCenter.default.post(name: .botBlink, object: nil)
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1.08))
        SoundEngine.shared.play("hover")
        scheduleLoveTimer()
    }

    private func botHoverOut() {
        botHoverTimer?.cancel()
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1))
    }

    /// Hands the island to whichever chosen display the cursor is on.
    ///
    /// Throttled to the screen *changing*, not to every tick: `NSScreen.screens`
    /// and the ColorSync UUID lookup are cheap but not free at 60 Hz.
    private func followCursorAcrossDisplays(_ mouse: NSPoint) {
        guard let panelScreen = window?.screen else { return }
        if panelScreen.frame.contains(mouse) { return }
        // The cursor being elsewhere is not enough: parked on a display Mochi is
        // not allowed on, the island has nowhere to go, and asking every tick
        // would run the screen scan at 60 Hz for nothing.
        let chosen = IslandDisplays.chosenScreens(NSScreen.screens,
                                                  selection: state.displaySelection)
        guard chosen.contains(where: { $0.frame.contains(mouse) }) else { return }
        AppDelegate.shared?.refreshIslands()
    }

    private func scheduleLoveTimer() {
        botHoverTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.botHovering, self.state.stateOverride == nil else { return }
            guard CACurrentMediaTime() - self.lastLoveTime > 6 else { return }
            self.lastLoveTime = CACurrentMediaTime()
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
            SoundEngine.shared.play("love")
        }
        botHoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: item)
    }

    private func scheduleHover(after delay: TimeInterval, action: @escaping () -> Void) {
        hoverTimer?.cancel()
        let item = DispatchWorkItem(block: action)
        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Mode transitions

    private func modeLevel(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }

    func setMode(_ mode: IslandMode) {
        // Off, the only mode anything may ask for is hidden. Every path that
        // could put the island on screen -- a hook, music, the hotkey, a dizzy
        // bot, the mouse monitors -- ends up in here or in expand(to:).
        guard state.isEnabled || mode == .hidden else { return }
        let prev = state.mode
        guard mode != prev else { return }
        let shrinking = modeLevel(mode) < modeLevel(prev)
        withAnimation(IslandMotion.forGrowing(!shrinking)) { state.mode = mode }
        // Nothing keeps a web view alive behind a folded island. After the
        // mode change, not before: `onChange(of: state.view)` guards on
        // `.expanded`, so this way the island shrinks once instead of twice.
        //
        // Faded rather than dropped. Unanimated, the page went out in a single
        // frame and left an empty island to fold on its own, which read as two
        // events where there was one. Short on purpose: the view is sized to
        // the island, so every frame it survives is another WKWebView resize,
        // and it is gone long before the island finishes closing.
        //
        // Every screen, not only the site: a folded island that still said
        // `.webchat` went on holding itself open through `viewHoldsIslandOpen`
        // while showing nothing at all.
        if shrinking && state.view.isScreen {
            withAnimation(.easeOut(duration: 0.12)) { state.view = defaultView() }
        }
        if mode == .expanded { SoundEngine.shared.play("open") }
        if prev == .expanded {
            SoundEngine.shared.play("close")
            if fsm.isHeldOpen?() != true { state.isPinned = false }
        }
    }

    /// Folds the screen on the island away — the site, the ChatGPT page.
    /// `collapse()` cannot do it: a screen holds the island open, which is
    /// exactly what that guard refuses to override.
    ///
    /// Back to `.compact`, the resting bar, rather than straight to `.hidden`.
    /// Hiding outright had nothing to travel to: the island left the screen
    /// instead of folding, and the way out stopped resembling the way in.
    /// From the bar it then hides on the same terms as any other view, which
    /// is the point — closing a screen is not its own kind of event.
    ///
    /// Unless something is waiting to be answered. An approval that arrived
    /// while the page had the island was deliberately not shown then; folding
    /// the island now would bury it instead of handing it over, so the card
    /// takes the screen's place and the island stays open on it.
    func closeScreen() {
        guard state.view.isScreen else { return }
        if state.pendingApproval != nil { expand(to: .approval); return }
        if state.pendingQuestion != nil { expand(to: .question); return }
        fsm.collapse()
        setMode(.compact)          // resets state.view through the guard above
    }

    /// The master switch, applied to the window and the 60 Hz loop.
    ///
    /// Note it leaves the panel click-through: the next poll tick clears that
    /// if the pointer is actually on the island. Turning it on here would make
    /// the whole panel live for up to a frame, which was harmless when the
    /// panel was a strip at the top of the screen and is not now that it is
    /// most of one.
    ///
    /// `orderOut` is what makes this an off switch: the panel is not merely
    /// driven to its hidden mode, it leaves the screen, so nothing on it can be
    /// hovered or clicked back into life.
    func setRunning(_ on: Bool) {
        if on {
            // Click-through until the poll says otherwise. See the note above.
            islandPanel.ignoresMouseEvents = true
            islandPanel.orderFrontRegardless()
            startPolling()
            fsm.reveal()
        } else {
            fsm.cancelTimers()
            fsm.hiddenExternally()
            state.isPinned = false
            state.isReplying = false
            setMode(.hidden)
            frameTimer?.invalidate()
            frameTimer = nil
            islandPanel.ignoresMouseEvents = true
            islandPanel.orderOut(nil)
            #if !APPSTORE
            // "Off" has to mean nothing of ours is running, and a live WebContent process
            // holding a chatgpt.com socket would contradict that loudest of all.
            WebChatController.shared.goCold(reason: "master off")
            #endif
        }
    }

    /// A notification arrived: open on this view and start its hold, so it folds
    /// itself away instead of staying up until somebody touches it.
    ///
    /// Safe to call again while one is already up — `openedExternally()` replaces
    /// the running hold rather than adding a second one, so a burst of
    /// notifications leaves exactly one timer.
    ///
    /// Never over a screen. A card arriving there replaced the page the user
    /// was working in and then folded the island away on its own hold a second
    /// later, which is what "it closes by itself while I am talking to it"
    /// was. Nothing is lost by waiting: the pill carries the alert, and a
    /// pending approval is what `closeScreen()` hands over on the way out.
    func notify(_ view: IslandView) {
        guard !state.viewHoldsIslandOpen else { return }
        // The greeting plays to the end. A card arriving mid-animation used to
        // replace it on the spot — `expand(to:)` below swaps the island's view
        // out from under it — so it waits for the island to settle instead. The
        // `.petit` arm of `onTransition` delivers it.
        if fsm.state == .coucou {
            pendingNotifyView = view
            return
        }
        // The user's setting, read fresh: a card is held for as long as the
        // field in Settings says, not for the machine's own default.
        fsm.notificationHoldDelay = state.autoCloseInterval
        fsm.openedExternally()
        expand(to: view)
        // The FSM skips the hold when the pointer is already on the island or a
        // reply is half-written; the hairline has to agree with it.
        state.holdingUntil = fsm.holdRunning ? Date.now + fsm.holdDuration : nil
    }

    func expand(to view: IslandView) {
        guard state.isEnabled else { return }
        // Anything but the card forgets who asked, so the request cannot
        // outlive the view it was for.
        state.view = view
        if state.mode == .expanded {
            // Already expanded — just switch view
        } else {
            setMode(.expanded)
        }
        state.lastActivity = .now
    }

    func collapse() {
        guard fsm.isHeldOpen?() != true else { return }
        state.holdingUntil = nil
        // Whatever list was open is finished with. Without this, the next
        // message to arrive would be answered back into a stale one.
        MessageInbox.shared.closeList()
        state.isPinned = false
        finishedPinTimer?.cancel()
        // Keep the FSM in step with what is on screen (home/coucou → petit now).
        fsm.collapse()
        setMode(.compact)
        window?.resignKey()
    }

    // MARK: - Keyboard (Escape closes)

    private func startKeyMonitor() {
        #if !APPSTORE
        // The monitor below is global, and a global monitor by definition never sees events
        // delivered to our own app. Once the panel is key for .webchat, Escape would reach
        // the page and the island would have no keyboard exit at all. In a borderless panel
        // Escape has to keep working, so this one swallows it.
        //
        // `closeScreen()`, not `collapse()`: the page now holds the island open, and
        // collapse is the one call that refuses to override that hold.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53,
                  self.state.mode == .expanded, self.state.view == .webchat else { return event }
            self.islandPanel.makeFirstResponder(nil)
            self.islandPanel.resignKey()
            self.closeScreen()
            return nil
        }
        #endif

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                if event.keyCode == 53 { // Escape
                    if self.state.viewHoldsIslandOpen {
                        self.closeScreen()
                    } else if self.state.mode == .expanded && !self.state.isPinned {
                        self.collapse()
                    }
                }
            }
        }

        // A screen makes the panel key, so its Escape arrives locally and the
        // global monitor above never sees it.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            var handled = false
            MainActor.assumeIsolated {
                guard self.state.viewHoldsIslandOpen else { return }
                self.closeScreen()
                handled = true
            }
            return handled ? nil : event
        }

        // ⌘V into an open reply box, when the pasteboard holds something a
        // reply can carry.
        //
        // Local, not global, because this one has to be able to swallow the
        // event: a screenshot pasted into a text field would otherwise do
        // nothing at all and look broken. A pasteboard holding plain text is
        // let through untouched, so ordinary pasting still reaches the field.
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isPaste = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "v"
            guard isPaste else { return event }

            // Only a Bool crosses the isolation boundary: NSEvent is not
            // Sendable, so the event itself stays out here.
            let handled = MainActor.assumeIsolated { () -> Bool in
                let state = AppState.shared
                guard state.isReplying,
                      MessageInbox.shared.replyAcceptsFiles(for: state.view),
                      ReplyAttachmentStore.pasteboardHasFiles()
                else { return false }

                ReplyAttachmentStore.attachPasteboard(state: state)
                return true
            }
            return handled ? nil : event
        }

        // Hook server expand requests (alerts only)
        NotificationCenter.default.addObserver(forName: .hookExpand, object: nil, queue: .main) { [weak self] note in
            guard let self, let view = note.object as? IslandView else { return }
            self.notify(view)
        }

        // The AI dashboard button on the ring: open it in the island. Goes
        // through the FSM so this counts as a deliberate open, not a hover.
        #if !APPSTORE
        NotificationCenter.default.addObserver(forName: .openAgentsDashboard, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.state.mode == .expanded && self.state.view == .agents {
                self.collapse()          // second click on the icon closes it again
            } else {
                self.fsm.openedExternally()
                self.expand(to: .agents)
            }
        }
        #endif

        // Hook server compact reveal (non-alert work events: session start, tool use, etc.)
        NotificationCenter.default.addObserver(forName: .hookReveal, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.fsm.reveal()
        }

        // Music started playing: reveal silently (no peek sound)
        NotificationCenter.default.addObserver(forName: .musicReveal, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.silentNextReveal = true
            self.fsm.reveal()
            self.silentNextReveal = false
        }

        // A focus or break ran out: open on the timer so the end is visible, not
        // just audible. `notify` gives it the same hold every notification gets.
        NotificationCenter.default.addObserver(
            forName: .focusTimerFinished, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.notify(.timer) }
        }

        // Collapse requests from views (OK button, etc.)
        NotificationCenter.default.addObserver(forName: .islandCollapse, object: nil, queue: .main) { [weak self] _ in
            self?.collapse()
        }

        // The close button on a screen — the site's, the ChatGPT page's.
        NotificationCenter.default.addObserver(forName: .closeNotchSite, object: nil, queue: .main) { [weak self] _ in
            self?.closeScreen()
        }

        // The island was put somewhere else: dragged there, or picked from the
        // list in Settings. Either way the panel has to be placed again.
        NotificationCenter.default.addObserver(
            forName: .islandPositionChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }

        // A Mattermost or ClickMassa message arrived: show the card.
        //
        // Not while someone is already typing a reply — the new one is still
        // taken in, counted and badged by the inbox, and comes up when they are
        // done with the card in front of them.
        // Nor over a screen, nor over a chat with something typed in it: the
        // inbox counts it and badges the pill either way, and the card comes up
        // once the island is free.
        NotificationCenter.default.addObserver(forName: .inboxMessageArrived, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.state.isReplying, !self.state.chatHoldsIsland else { return }
                SoundEngine.shared.play("question")
                // What just arrived outranks whatever was asked for earlier.
                self.notify(.message)
            }
        }

        // Asked for from a pill's button. `expand` rather than `notify`: the
        // island is already open -- the button only exists while it is -- and
        // nobody wants the card they just asked for to time out and leave.
        NotificationCenter.default.addObserver(forName: .showMessageCard, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // The list when a pill opened one, the single card when a
                // particular message is what was asked for.
                //
                // `listShowsAll` counts as an open list: the Notifications
                // pill leaves `listSource` nil on purpose, so that answering
                // walks through every service instead of stopping at the end
                // of one. Testing the source alone sent the pill that stands
                // for the whole queue to a single card.
                let open = MessageInbox.shared.listSource != nil
                    || MessageInbox.shared.listShowsAll
                self?.expand(to: open ? .messages : .message)
            }
        }

        // .botDizzy — posted by BotEngine.slap() on 3rd hit; show confused view + recover after 3.3s
        NotificationCenter.default.addObserver(forName: .botDizzy, object: nil, queue: .main) { [weak self] _ in
            self?.handleDizzy()
        }

        // Window attach drag.
        // Uses MainActor.assumeIsolated (synchronous) to avoid race with pollFrame().
        // Global mouseUp is the reliable fallback when cursor is outside our panel frame.
        #if !APPSTORE
        // Scrolling the page with momentum, or dragging a selection, routinely carries the
        // cursor past the island edge. Without a hold the 60 Hz poll makes the panel
        // click-through mid-gesture and WebKit never sees the end of it.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                if WebChatController.shared.isLive { WebChatController.shared.holdMouseBriefly() }
            }
            return event
        }
        #endif

        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                // The second click of a pair, wherever it landed. A pill's own
                // button answers its own clicks, but opening a view resizes
                // the island and the ring moves with it, so the disc can be
                // gone by the time the second click arrives. Asked before the
                // rect guard below, because a view that makes the island
                // *smaller* can leave the pointer outside it as well as off
                // the button — and this is still a click our own panel was
                // handed, not one we are taking from anyone else.
                pillClickLandedOnIsland(at: NSEvent.mouseLocation)
                guard self.wasInIsland else { return }
                self.pendingIslandClick = true
                // A press that stays put is how the island is picked up. Which
                // of the two this was is only known when it comes back up, or
                // when the hold runs out.
                self.armGrab(at: NSEvent.mouseLocation)
                self.hoverTimer?.cancel()
                self.botHoverTimer?.cancel()
                self.botHovering = false
                // Drag only starts when clicking directly on the bot head
                guard self.isBotHit(event.locationInWindow) else { return }
                self.attachDragStart = NSEvent.mouseLocation
                // Post slap only when expanded
                guard self.state.mode == .expanded else { return }
                NotificationCenter.default.post(name: .triggerSlap, object: nil)
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                self.checkGrabSlop(NSEvent.mouseLocation)
                guard let start = self.attachDragStart, !self.inAttachDrag else { return }
                let m = NSEvent.mouseLocation
                guard hypot(m.x - start.x, m.y - start.y) > 3 else { return }
                self.inAttachDrag = true
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
                self.showDragGhost()
            }
            return event
        }

        // mouseUp — local (cursor still in panel) + global (cursor moved outside panel frame)
        let finishDrag: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, self.inAttachDrag else { return }
                let mouse = NSEvent.mouseLocation
                self.inAttachDrag = false
                self.attachDragStart = nil
                self.state.stateOverride = nil
                self.hideDragGhost()
                #if !APPSTORE
                if let ctx = self.windowContextAtPoint(mouse) {
                    self.state.promptContext = ctx
                    SoundEngine.shared.play("approve")
                    NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                    self.expand(to: .prompt)
                }
                #endif
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                #if !APPSTORE
                WebChatController.shared.holdsMouse = false
                #endif
                let hadPendingClick = self.pendingIslandClick
                let wasDragging     = self.inAttachDrag
                self.pendingIslandClick = false
                self.cancelGrab()
                if self.movingIsland {
                    self.dropIsland()
                    return
                }
                if wasDragging {
                    finishDrag()
                } else {
                    self.attachDragStart = nil
                    if hadPendingClick && self.state.mode != .expanded {
                        if self.fsm.state == .home {
                            // FSM already thinks it's open (e.g. the view folded it): just reopen.
                            self.expand(to: self.defaultView())
                        } else {
                            self.fsm.click()   // FSM petit/hidden→home; onTransition calls expand(to:)
                        }
                    }
                }
            }
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.cancelGrab()
                if self.movingIsland { self.dropIsland() }
            }
            finishDrag()
        }

        // Global hotkey to show island
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, self.state.hotkeyEnabled else { return }
                let pressed = event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue
                guard pressed == self.state.hotkeyFlags, event.keyCode == self.state.hotkeyCode else { return }
                if self.state.mode == .hidden || self.state.mode == .compact {
                    self.expand(to: .overview)
                }
            }
        }

        // Track last external app for window context capture
        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != ourBundle {
                self.state.lastExternalApp = app
            }
        }
    }

    // MARK: - Drag ghost window (Mochi follows cursor during drag)

    private func showDragGhost() {
        guard dragGhostPanel == nil else { return }
        // Same size as compact bot: diameter=20 → canvasSize≈33, scale 2× for grab comfort
        let canvasSize: CGFloat = 40 / 0.6      // ~67
        dragGhostSize = canvasSize

        let mouse = NSEvent.mouseLocation
        let s = dragGhostSize
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)

        let panel = NSPanel(
            contentRect: NSRect(x: ghostCurrentOrigin.x, y: ghostCurrentOrigin.y, width: s, height: s),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: GhostBotView(canvasSize: canvasSize)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: s, height: s)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFront(nil)
        dragGhostPanel = panel
        AppState.shared.isDraggingBot = true

        // Fade + scale-in handled by GhostBotView SwiftUI animation;
        // also fade in the window itself for extra smoothness
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideDragGhost() {
        dragGhostPanel?.close()
        dragGhostPanel = nil
        highlightPanel?.close()
        highlightPanel = nil
        highlightWindowPid = 0
        AppState.shared.isDraggingBot = false
    }

    private func updateDragGhost() {
        guard let panel = dragGhostPanel else { return }
        let s = dragGhostSize
        let mouse = NSEvent.mouseLocation
        // Direct follow — bot is "held", no trailing lag
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)
        panel.setFrameOrigin(ghostCurrentOrigin)
    }

    // MARK: - Window highlight overlay (white border on target window during drag)

    private func updateWindowHighlight() {
        let mouse = NSEvent.mouseLocation
        guard let (appKitBounds, pid) = windowBoundsAtScreenPoint(mouse) else {
            // Fade out + close if no window under cursor
            if let old = highlightPanel {
                let captured = old
                highlightPanel = nil
                highlightWindowPid = 0
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.12
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    captured.animator().alphaValue = 0
                }, completionHandler: { captured.close() })
            }
            return
        }

        if pid == highlightWindowPid, let existing = highlightPanel {
            // Same window — just track position (windows rarely move, instant is fine)
            existing.setFrame(appKitBounds, display: false)
        } else {
            // New window — close old immediately, fade-in new
            highlightPanel?.close()
            highlightPanel = nil
            highlightWindowPid = pid

            let panel = NSPanel(
                contentRect: appKitBounds,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true

            let hosting = NSHostingView(rootView:
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.75), lineWidth: 3)
                    .shadow(color: Color.white.opacity(0.5), radius: 16)
                    .padding(2)
                    .ignoresSafeArea()
            )
            hosting.frame = CGRect(origin: .zero, size: appKitBounds.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.alphaValue = 0
            panel.orderFront(nil)
            highlightPanel = panel

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    private func windowBoundsAtScreenPoint(_ screenPoint: NSPoint) -> (CGRect, pid_t)? {
        guard let screen = window?.screen ?? NSScreen.main else { return nil }
        let screenMaxY = screen.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        for info in list {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }
            // CG → AppKit: flip Y
            return (CGRect(x: x, y: screenMaxY - y - h, width: w, height: h), pid)
        }
        return nil
    }

    // MARK: - Window context at screen point (for drag-attach)

    private func windowContextAtPoint(_ screenPoint: NSPoint) -> PromptContext? {
        let screen = window?.screen ?? NSScreen.main
        // CGWindowList uses top-left origin; NSEvent.mouseLocation uses bottom-left
        let screenMaxY = screen?.frame.maxY ?? NSScreen.main!.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""

        for info in windowList {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }

            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }

            return WindowContextCapture.captureActive(from: app)
        }
        return nil
    }

    // MARK: - Coordinate conversion: window (AppKit, y-up) → island coords (y-down, 0,0 = island top-left)

    func windowToIsland(_ loc: CGPoint) -> CGPoint {
        let panelH = window?.frame.height ?? Self.panelHeight
        guard let panel = window as? IslandPanel else {
            return CGPoint(x: loc.x - (Self.panelWidth - IslandConst.expandedWidth) / 2,
                           y: panelH - loc.y)
        }
        // Measured off the island itself rather than the middle of the panel's
        // top edge: once the island can be dropped anywhere, those stopped
        // being the same place. For one of the six names they still are, so
        // this is the same answer it has always given.
        let island = panel.currentIslandFrame(nw: panel.notchWidth, nh: panel.notchHeight)
        return CGPoint(x: loc.x - island.minX, y: island.maxY - loc.y)
    }

    // MARK: - Helpers

    func defaultView() -> IslandView {
        if state.pendingApproval != nil { return .approval }
        return state.tasks.isEmpty ? .empty : .overview
    }

    func baseMode() -> IslandMode {
        guard state.isPresent else { return .hidden }
        return state.tasks.isEmpty ? .hidden : .compact
    }

    // MARK: - Activity reset (call on any user interaction in island)

    func resetActivity() {
        state.lastActivity = .now
    }

    // MARK: - Finished task pin (5.2s)

    func pinForFinished(taskId: String) {
        state.isPinned = true
        finishedPinTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.removeTask(id: taskId)
            self.state.isPinned = false
            self.collapse()
        }
        finishedPinTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2, execute: item)
    }

    // MARK: - Dizzy recovery (triggered by BotEngine.slap via .botDizzy)

    private func handleDizzy() {
        let prevView = state.view
        state.stateOverride = .dizzy
        expand(to: .confused)
        confusedRecoveryTimer?.cancel()
        let recovery = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.stateOverride = nil
            if self.state.view == .confused {
                let fallback = self.state.tasks.isEmpty ? IslandView.empty : .overview
                self.state.view = (prevView == .confused) ? fallback : prevView
            }
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }
        confusedRecoveryTimer = recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3, execute: recovery)
    }

    // MARK: - Bot hit test (for slap trigger)

    private func isBotHit(_ windowPoint: CGPoint) -> Bool {
        let s = AppState.shared
        // Nothing to slap, hover or pick up where nothing is drawn. The drop
        // keeps its Mochi, and so keeps answering here; so does the compact
        // bar, which this never reaches anyway — a slap wants expanded.
        if s.hideCharacters && s.mode == .expanded
            && s.view != .upload && s.view != .uploading && s.view != .choose {
            return false
        }
        let panelH = window?.frame.height ?? Self.panelHeight
        let panelW = window?.frame.width  ?? Self.panelWidth
        let (islandW, fixedH) = islandSize(mode: s.mode, view: s.view,
                                            progress: s.uploadProgress, nw: notchW, nh: notchH,
                                            home: s.homeContent, player: s.homeShowsPlayer,
                                                                   large: s.largeIslandSize,
                                                                   attachments: s.replyAttachments.count,
                                                                   notice: s.replyNotice != nil)
        // Chat view resizes dynamically — must match IslandContainer.chatPromptHeight
        let islandH: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            let base: CGFloat = 240
            let perMsg: CGFloat = 40
            islandH = min(300, base + CGFloat(s.chatHistory.count) * perMsg)
        } else {
            islandH = fixedH
        }
        // Where the island actually is, which for one of the six names is still
        // the middle of the panel's top edge and for a dropped one is not.
        let island = (window as? IslandPanel)?.islandFrame(w: islandW, h: islandH)
            ?? CGRect(x: (panelW - islandW) / 2, y: panelH - islandH,
                      width: islandW, height: islandH)
        let (cx, cy, diameter, _) = botPosition(mode: s.mode, view: s.view,
                                                  islandW: islandW, islandH: islandH,
                                                  uploadProgress: s.uploadProgress, hasNotch: s.hasNotch,
                                                  home: s.homeContent, player: s.homeShowsPlayer)
        let radius = (diameter / 0.6) / 2
        // botPosition cy is from the island's TOP; AppKit counts up from the
        // bottom, so the island's own top edge is what cy is measured off.
        let botX = island.minX + cx
        let botY = island.maxY - cy
        let dx = windowPoint.x - botX
        let dy = windowPoint.y - botY
        return dx*dx + dy*dy <= radius * radius
    }

    // MARK: - Notch detection (static)

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    static func screenGeometry(for screen: NSScreen) -> IslandScreenGeometry {
        let visibleMenuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        // visibleFrame includes the menu bar only while it is visible. Keep a
        // small resting bar when menus auto-hide or the app is in full screen.
        let menuBarHeight = visibleMenuBarHeight > 0
            ? visibleMenuBarHeight : NSStatusBar.system.thickness
        return IslandScreenGeometry(
            screenWidth: screen.frame.width, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: menuBarHeight,
            notchHeightOverride: AppState.shared.notchDisplayHeight,
            plainHeightOverride: AppState.shared.plainDisplayHeight
        )
    }

    nonisolated func cleanup() {
        // Called explicitly before release if needed
    }
}

// MARK: - IslandPanel

final class IslandPanel: NSPanel {
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight

    /// Where the island sits, resolved against the screen this panel is on.
    /// The controller keeps it current; everything here reads it.
    var anchor = IslandAnchor.Resolved(
        edge: .top, align: .centre, hug: .top, free: nil)
    var metrics = IslandAnchor.Metrics(
        rest: CGSize(width: IslandConst.notchWidth + 160, height: IslandConst.notchHeight),
        panel: CGSize(width: 1200, height: 820))

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    /// Allow panel to sit in the menu bar / notch area — don't let macOS push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    func currentIslandFrame(nw: CGFloat, nh: CGFloat) -> CGRect {
        let s = AppState.shared
        let (w, fixedH) = islandSize(mode: s.mode, view: s.view,
                                      progress: s.uploadProgress, nw: nw, nh: nh,
                                      home: s.homeContent, player: s.homeShowsPlayer,
                                                             large: s.largeIslandSize,
                                                             attachments: s.replyAttachments.count,
                                                             notice: s.replyNotice != nil)
        let h: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            let base: CGFloat = 240
            let perMsg: CGFloat = 40
            h = min(300, base + CGFloat(s.chatHistory.count) * perMsg)
        } else {
            h = fixedH
        }
        return islandFrame(w: w, h: h)
    }

    /// An island of this size, placed by the anchor, in AppKit panel coordinates.
    ///
    /// `IslandAnchor` counts y down from the panel's top, because it is the same
    /// arithmetic the web port runs; AppKit counts up from the bottom. The one
    /// flip lives here rather than in three ports of the rules.
    func islandFrame(w: CGFloat, h: CGFloat) -> CGRect {
        let x = IslandAnchor.islandX(anchor, w: w, metrics: metrics)
        let top = IslandAnchor.islandY(anchor, h: h, metrics: metrics)
        return CGRect(x: x, y: frame.height - top - h, width: w, height: h)
    }

    /// The resting island's centre in panel coordinates — what a drop stores.
    func restingCentre() -> CGPoint {
        let r = islandFrame(w: metrics.rest.width, h: metrics.rest.height)
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// The island plus whatever is hung off its edges — what the pointer can hit.
    ///
    /// Only click-through uses this. Hover stays on the island rect, so the
    /// pointer resting on a button does not open the island: being able to
    /// reach a pill without opening anything is the whole point of the ring.
    func currentChromeFrame(nw: CGFloat, nh: CGFloat) -> CGRect {
        let s = AppState.shared
        return IslandEdgeLayout.chromeFrame(
            islandFrame: currentIslandFrame(nw: nw, nh: nh),
            buttons: IslandEdgeLayout.visible(s.edgeButtons, expanded: s.mode == .expanded))
    }
}

// MARK: - Ghost bot view (animated scale-in on appear)

struct GhostBotView: View {
    let canvasSize: CGFloat
    @State private var scale: CGFloat = 0.35

    var body: some View {
        BotCanvasView(state: AppState.shared)
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Puts the screen on the island away — the site, the ChatGPT page: its
    /// close button, or Escape. Named for the site because that is what posted
    /// it first, and the id is what already ships.
    static let closeNotchSite = Notification.Name("notchBuddy.closeNotchSite")

    /// Somebody put the cursor in a field inside the island. Posted before the
    /// focus is requested, so the panel is key in time to receive the keys.
    static let islandWantsKeyboard = Notification.Name("islandWantsKeyboard")

    static let triggerEmote     = Notification.Name("notchBuddy.triggerEmote")
    /// The island was put somewhere else — dragged there, or picked from the
    /// list in Settings. The controller places the panel again.
    static let islandPositionChanged = Notification.Name("notchBuddy.islandPositionChanged")

    static let triggerSlap      = Notification.Name("notchBuddy.triggerSlap")
    static let botDizzy         = Notification.Name("notchBuddy.botDizzy")
    static let botGreet         = Notification.Name("notchBuddy.botGreet")
    static let botBlink         = Notification.Name("notchBuddy.botBlink")
    static let botSetTgEs       = Notification.Name("notchBuddy.botSetTgEs")
    static let botGulp          = Notification.Name("notchBuddy.botGulp")
    static let botMorphTo       = Notification.Name("notchBuddy.botMorphTo")
    static let islandAction     = Notification.Name("notchBuddy.islandAction")
    static let islandCollapse   = Notification.Name("notchBuddy.islandCollapse")
    static let openFullSettings = Notification.Name("notchBuddy.openFullSettings")
    static let hookReveal       = Notification.Name("notchBuddy.hookReveal")
    static let openAgentsDashboard = Notification.Name("notchBuddy.openAgentsDashboard")
    static let musicReveal      = Notification.Name("notchBuddy.musicReveal")
    // Greeting ↔ IslandWindowController
    static let greetComplete    = Notification.Name("notchBuddy.greetComplete")
    static let greetingInterrupt = Notification.Name("notchBuddy.greetingInterrupt")
}

// MARK: - islandSize (takes real notch dimensions)

func islandSize(mode: IslandMode, view: IslandView,
                progress: Double = 0,
                nw: CGFloat = IslandConst.notchWidth,
                nh: CGFloat = IslandConst.notchHeight,
                home: HomeContent = .automatic,
                player: Bool = false,
                large: CGSize = IslandConst.defaultLargeSize,
                attachments: Int = 0,
                notice: Bool = false) -> (CGFloat, CGFloat) {
    switch mode {
    case .hidden:   return (nw, nh)
    case .compact:  return (nw + 160, nh)
    case .expanded:
        let twin = view.layoutTwin(home: home, player: player)
        let layout = IslandConst.viewLayouts[twin]!
        // A reply card with files on it is the one non-chat view that is not
        // its table height. Asked here so every caller of islandSize gets the
        // same answer without knowing why.
        if twin == .message || (twin == .overview && attachments > 0) {
            return (layout.width,
                    IslandView.messageHeight(attachmentCount: attachments, notice: notice))
        }
        switch layout.sizeClass {
        case .standard: return (layout.width, layout.height)
        case .large:    return (max(layout.width, large.width),
                                max(layout.height, large.height))
        }
    }
}
