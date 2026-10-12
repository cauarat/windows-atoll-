import SwiftUI

/// Top-level SwiftUI view rendered inside the transparent island panel.
/// The island is drawn at the top-center; everything else is transparent and click-through.
/// Note: drag-drop is handled at the AppKit level in IslandWindowController (FileDropNSView),
/// not in SwiftUI, to avoid interfering with SwiftUI hit-testing.
struct IslandRootView: View {
    @EnvironmentObject var state: AppState

    /// The island's animated size, owned here rather than in `IslandContainer`.
    ///
    /// The edge buttons are drawn outside the island, so they cannot live
    /// inside the container and still be reliably clickable — but they have to
    /// move on exactly the same spring, or they trail the edge they are
    /// attached to. One `@State`, read by both, is what makes them read as one
    /// object rather than two things that happen to animate together.
    @State private var islandBounds = CGSize(width: IslandConst.notchWidth,
                                           height: IslandConst.notchHeight)

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IslandEdgeRingView(state: state, islandSize: islandBounds)
                .frame(maxWidth: .infinity, alignment: .center)
            IslandContainer(state: state, islandBounds: $islandBounds)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Island container

struct IslandContainer: View {
    @ObservedObject var state: AppState
    @Binding var islandBounds: CGSize
    @State private var cornerRadius: CGFloat = IslandConst.roundedCorner
    // topRadius > 0 → convex expanded corners; < 0 → concave ear cutouts
    @State private var islandTopRadius: CGFloat = 0
    @State private var greetNotif: Bool = false

    private let openSpring = IslandMotion.open

    private var islandWidth:  CGFloat {
        get { islandBounds.width }
        nonmutating set { islandBounds.width = newValue }
    }
    private var islandHeight: CGFloat {
        get { islandBounds.height }
        nonmutating set { islandBounds.height = newValue }
    }

    private var chatPromptHeight: CGFloat {
        let base: CGFloat = 240
        let perMsg: CGFloat = 40
        return min(300, base + CGFloat(state.chatHistory.count) * perMsg)
    }

    /// Springs the card to whatever its staged files now need.
    ///
    /// Goes through `islandSize` rather than computing a height here, so the
    /// window frame and Mochi's placement cannot disagree with the card — the
    /// drift `.prompt` has four copies of.
    private func resizeForAttachments() {
        guard state.mode == .expanded,
              state.view == .message || state.view == .overview else { return }
        let (_, h) = islandSize(mode: .expanded, view: state.view,
                                progress: state.uploadProgress,
                                nw: state.notchWidth, nh: state.notchHeight,
                                home: state.homeContent, player: state.homeShowsPlayer,
                                attachments: state.replyAttachments.count,
                                notice: state.replyNotice != nil)
        withAnimation(openSpring) { islandHeight = h }
    }

    /// Pixels the content must be pushed down to clear the concave ear transparent area.
    /// = 0 in expanded mode (no ears), = earRadius in compact/notch mode.
    private var earOffset: CGFloat { max(0, -islandTopRadius) }

    var body: some View {
        // Canvas active during drag-over (.upload), post-drop animation (.uploading),
        // AND choose overlay (.choose) — canvas handles the full sequence through user action.
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        let uploadActive = state.mode == .expanded
            && UploadSequenceEngine.shared.isActive
            && (state.view == .upload || state.view == .uploading || state.view == .choose)

        let greetingActive = state.mode == .expanded && state.view == .greeting

        return ZStack(alignment: .topLeading) {
            // Black island shape
            IslandShape(width: islandWidth, height: islandHeight,
                        cornerRadius: cornerRadius, topRadius: islandTopRadius)
                .fill(Color.black)

            // Content
            if state.mode == .expanded {
                if greetingActive {
                    // Greeting canvas: fixed 640-wide, centered by offset so x=320 aligns with island center
                    GreetingCanvasView(state: state)
                        .frame(width: IslandConst.expandedWidth, height: 150)
                        .offset(x: (islandWidth - IslandConst.expandedWidth) / 2)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                } else if uploadActive {
                    ZStack(alignment: .topLeading) {
                        UploadCanvasView(state: state)
                            .frame(width: islandWidth, height: islandHeight)
                            .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                                  cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        // Header overlaid: canvas CARD_Y=42 aligns exactly with header bottom,
                        // matching normal view proportions (8pt top + 34pt header + card + 10pt bottom).
                        IslandHeader(state: state)
                            .frame(width: islandWidth, height: 34)
                            .offset(y: 8)
                    }
                    .transition(.opacity)
                } else {
                    IslandContentView(state: state)
                        .frame(width: islandWidth, height: islandHeight - earOffset)
                        .offset(y: earOffset)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                }
            }

            // Single BotPlacement — always alive in the view tree so spring animations
            // fire from the current position (e.g. choose at 60,101) when canvas deactivates.
            // Hidden during upload canvas or greeting (both draw their own Mochi).
            BotPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                // Keep idle animations inside the resting strip. Expanded views
                // retain the panel's full height for particles and hands.
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
                                      height: state.mode == .expanded
                                          ? IslandWindowController.panelHeight : islandHeight)
                }
                .opacity(uploadActive || greetingActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)

            // The site draws itself over the island: it is a web view, not a
            // card, and it wants the whole of the space.
            if state.mode == .expanded && state.view == .web {
                NotchSiteView(state: state)
                    .frame(width: islandWidth, height: islandHeight)
                    .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                           cornerRadius: cornerRadius, topRadius: islandTopRadius))
                    .transition(.opacity)
            }

            CountdownBar(state: state, islandW: islandWidth)

            Group {
                if state.mode == .compact {
                    // A running timer takes the right-hand slot from the mini
                    // grid. Both sides of the compact bar are spoken for —
                    // Mochi on the left, this on the right — and the middle is
                    // the physical notch, where nothing can be drawn.
                    if FocusTimer.shared.isActive {
                        CompactTimerBadge()
                            .position(x: islandWidth - 44, y: islandHeight / 2)
                            .transition(.opacity)
                    } else {
                        CompactMiniGrid(state: state)
                            .scaleEffect(IslandRestingLayout(width: islandWidth, height: islandHeight).miniGridScale)
                            .position(x: islandWidth - 40, y: islandHeight / 2)
                            .transition(.opacity)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state.mode == .compact)
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
        .onChange(of: state.mode) { oldMode, newMode in
            let shrinking = modeOrder(newMode) < modeOrder(oldMode)
            let (w, h) = islandSize(mode: newMode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight,
                                    home: state.homeContent, player: state.homeShowsPlayer,
                                                           large: state.largeIslandSize,
                                                           attachments: state.replyAttachments.count,
                                                           notice: state.replyNotice != nil)
            let cr  = newMode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            let tr: CGFloat = 0
            // Opening is left exactly as it was. Only the close is given the
            // distance, so folding a full screen away stops being the same
            // 0.22 s as a card giving back sixteen points.
            let anim = shrinking
                ? IslandMotion.shrink(travel: max(abs(w - islandWidth), abs(h - islandHeight)))
                : openSpring
            withAnimation(anim) {
                islandWidth      = w
                islandHeight     = (newMode == .expanded && state.view == .prompt) ? chatPromptHeight : h
                cornerRadius     = cr
                islandTopRadius  = tr
            }
        }
        // The island changed size without changing state: it moved to a display
        // that measures differently, or a height preference was dragged. Nothing
        // else here watches for that, which is why the sliders did nothing and a
        // moved island kept the previous screen's size.
        .onChange(of: state.screenGeometry) { _, _ in
            let (w, h) = islandSize(mode: state.mode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight,
                                    home: state.homeContent, player: state.homeShowsPlayer,
                                                           large: state.largeIslandSize,
                                                           attachments: state.replyAttachments.count,
                                                           notice: state.replyNotice != nil)
            withAnimation(openSpring) {
                islandWidth  = w
                islandHeight = (state.mode == .expanded && state.view == .prompt)
                    ? chatPromptHeight : h
            }
        }
        .onChange(of: state.view) { _, newView in
            guard state.mode == .expanded else { return }
            // Deactivate engine if user navigates outside the upload flow
            let uploadViews: Set<IslandView> = [.upload, .uploading, .choose]
            if UploadSequenceEngine.shared.isActive && !uploadViews.contains(newView) {
                UploadSequenceEngine.shared.deactivate()
            }
            let (w, h) = islandSize(mode: .expanded, view: newView,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight,
                                    home: state.homeContent, player: state.homeShowsPlayer,
                                                           large: state.largeIslandSize,
                                                           attachments: state.replyAttachments.count,
                                                           notice: state.replyNotice != nil)
            withAnimation(IslandMotion.grow(travel: max(abs(w - islandWidth), abs(h - islandHeight)))) {
                islandWidth  = w
                islandHeight = newView == .prompt ? chatPromptHeight : h
            }
        }
        .onChange(of: state.chatHistory.count) { _, _ in
            guard state.mode == .expanded, state.view == .prompt else { return }
            withAnimation(openSpring) { islandHeight = chatPromptHeight }
        }
        // Attaching or removing a file is the only thing that changes a reply
        // card's height, and nothing else here watches for it.
        .onChange(of: state.replyAttachments.count) { _, _ in resizeForAttachments() }
        .onChange(of: state.replyNotice) { _, _ in resizeForAttachments() }
        .onAppear {
            let (w, h) = islandSize(mode: state.mode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight,
                                    home: state.homeContent, player: state.homeShowsPlayer,
                                                           large: state.largeIslandSize,
                                                           attachments: state.replyAttachments.count,
                                                           notice: state.replyNotice != nil)
            islandWidth      = w
            islandHeight     = state.view == .prompt ? chatPromptHeight : h
            cornerRadius     = state.mode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            islandTopRadius  = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            greetNotif.toggle()
        }
    }

    private func modeOrder(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }
}

// MARK: - Island shape
//
// topRadius > 0  → convex rounded top corners (expanded mode)
// topRadius < 0  → concave ear cutouts, |topRadius| = ear radius (compact/notch mode)
// topRadius = 0  → sharp top corners (transient during animation)

struct IslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat   // bottom corners
    var topRadius: CGFloat      // see above

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>, CGFloat> {
        get { .init(.init(.init(width, height), cornerRadius), topRadius) }
        set {
            width        = newValue.first.first.first
            height       = newValue.first.first.second
            cornerRadius = newValue.first.second
            topRadius    = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let cr = max(0, cornerRadius)
        var p  = Path()

        if topRadius >= 0 {
            // ── Convex rounded top corners (expanded) ──────────────────────────
            let tr = min(topRadius, min(width / 2, height / 2))
            p.move(to: CGPoint(x: tr, y: 0))
            p.addLine(to: CGPoint(x: width - tr, y: 0))
            // Top-right convex corner
            p.addArc(center: CGPoint(x: width - tr, y: tr), radius: tr,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge
            p.addLine(to: CGPoint(x: 0, y: tr))
            // Top-left convex corner
            p.addArc(center: CGPoint(x: tr, y: tr), radius: tr,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // ── Concave ear cutouts (compact / notch) ─────────────────────────
            let er = -topRadius   // positive ear radius
            p.move(to: CGPoint(x: 0, y: 0))
            // Top-left ear
            p.addArc(center: CGPoint(x: 0, y: er), radius: er,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Top edge
            p.addLine(to: CGPoint(x: width - er, y: er))
            // Top-right ear
            p.addArc(center: CGPoint(x: width, y: er), radius: er,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge back to top-left corner
            p.addLine(to: CGPoint(x: 0, y: 0))
        }

        p.closeSubpath()
        return p
    }
}

// MARK: - Bot placement helper

struct BotPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: state.uploadProgress, hasNotch: state.hasNotch, home: state.homeContent, player: state.homeShowsPlayer)
        let canvasSize = diameter / 0.6
        let overhang: CGFloat = 40
        let isUploading = state.view == .uploading

        Group {
            // No glow in uploading mode — the tiny dot doesn't need it
            if state.mode == .expanded && !isUploading {
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: botGlowColor(state.effectiveState), location: 0),
                            .init(color: .clear, location: 0.62)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 1.1
                    ))
                    .frame(width: diameter * 2.2, height: diameter * 2.2)
                    .blur(radius: 6)
                    .opacity(botGlowOpacity(state.effectiveState))
                    .position(x: cx, y: cy)
                    .animation(.easeInOut(duration: 0.4), value: state.effectiveState)
            }

            // Uploading: no particle overhang (no hearts during upload), positioned directly at cy.
            // BotEngine cy = H/2 + 0 + oy*R + R*0.06 ≈ H/2 (body centered in canvas).
            // With .position(x:y:) placing the frame center at (uploadCx, cy), bot is at cy ✓.
            //
            // Normal: extra 40pt canvas at top for heart particles; position offset up by 20pt;
            // BotEngine compensates with cy = H/2 + particleOverhang/2 + oy*R + R*0.06.
            if isUploading {
                TimelineView(.animation) { tl in
                    let elapsed: Double = {
                        guard let start = state.uploadStartTime else { return 0 }
                        return tl.date.timeIntervalSince(start)
                    }()
                    let t = min(1.0, max(0, elapsed / state.uploadDuration))
                    // cx = 36 + 526*t: bot center at fill right edge (bar left=36, width=526)
                    let uploadCx = 36 + CGFloat(t * (2 - t)) * 526
                    BotCanvasView(state: state, particleOverhang: 0)
                        .frame(width: canvasSize, height: canvasSize)
                        .opacity(state.isDraggingBot ? 0 : opacity)
                        .position(x: uploadCx, y: cy)
                }
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            } else {
                BotCanvasView(state: state, particleOverhang: overhang)
                    .frame(width: canvasSize, height: canvasSize + overhang)
                    .opacity(state.isDraggingBot ? 0 : opacity)
                    .position(x: cx, y: cy - overhang / 2)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cx)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cy)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: canvasSize)
                    .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            }
        }
        // Branch switch (uploading ↔ normal) animates with a fast spring: uploading dot
        // scales out at bar-end while normal bot scales in at choose position.
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isUploading)
        // Slap, drag, and hover are handled by the AppKit NSEvent monitor in
        // IslandWindowController — not SwiftUI gestures — so this is safe.
        .allowsHitTesting(false)
    }

    private func botGlowColor(_ s: BotState) -> Color {
        switch s {
        case .working:   return Color(hex: "#3B9EFF")
        case .thinking:  return Color(hex: "#A78BFA")
        case .searching: return Color(hex: "#6366F1")
        case .approval:  return Color(hex: "#F5A524")
        case .error:     return Color(hex: "#F4505E")
        case .finished:  return Color(hex: "#34D399")
        case .ratelimit: return Color(hex: "#F59E0B")
        default:         return Color.white
        }
    }

    private func botGlowOpacity(_ s: BotState) -> Double {
        switch s {
        case .idle, .sleeping: return 0.15
        case .dizzy:           return 0.0
        default:               return 0.65
        }
    }
}

func botPosition(mode: IslandMode, view rawView: IslandView, islandW: CGFloat, islandH: CGFloat, uploadProgress: Double, hasNotch: Bool = true, home: HomeContent = .automatic, player: Bool = false) -> (CGFloat, CGFloat, CGFloat, Double) {
    let view = rawView.layoutTwin(home: home, player: player)
    let resting = IslandRestingLayout(width: islandW, height: islandH)
    switch mode {
    case .hidden:
        return hasNotch ? (46, 16, 6, 0)
            : (islandW / 2, resting.botCenterY, resting.botDiameter, 1)
    case .compact: return (40, resting.botCenterY, resting.botDiameter, 1)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
        let diameter = layout.botDiameter
        // Uploading: Mochi dot rides the leading edge of the progress fill.
        // Bar in island coords: left=36, width=526. cx = 36 + progress*526 (dot center at fill right edge).
        // cy comes from ViewLayout.botY (bar center in island coords).
        if view == .uploading {
            let cx = 36 + CGFloat(uploadProgress) * 526
            return (cx, layout.botY ?? 103, diameter, 1)
        }
        let cx = layout.botX
        let cy: CGFloat
        if let fixedY = layout.botY {
            cy = fixedY
        } else {
            // Center of the fixed 84pt card (VStack top=8, header=34 → content starts at y=42)
            let headerBottom: CGFloat = 42
            let cardH: CGFloat = 84
            cy = headerBottom + (islandH - headerBottom - cardH) / 2 + cardH / 2
        }
        return (cx, cy, diameter, 1)
    }
}

// MARK: - Countdown bar

struct CountdownBar: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    @State private var barWidth: CGFloat = 0
    @State private var timer: Timer? = nil

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: barWidth, height: 2)
                .cornerRadius(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateBar()
        }
    }

    /// The hairline that drains while a notification is holding itself open.
    ///
    /// Driven by `holdingUntil`, which the controller sets when a notification
    /// opens and clears the moment the pointer arrives — so the bar is on screen
    /// exactly when a timer is really running, and never while someone is
    /// reading the card with the cursor on it.
    private func updateBar() {
        guard state.mode == .expanded, !state.isReplying, !state.viewHoldsIslandOpen,
              let until = state.holdingUntil else {
            barWidth = 0
            return
        }
        let total = state.autoCloseInterval + IslandMotion.openResponse
        let window = min(10.0, total * 0.6)
        let remaining = until.timeIntervalSince(.now)
        if remaining <= 0 {
            barWidth = 0
        } else if remaining < window {
            barWidth = max(0, CGFloat(remaining / window) * 160)
        } else {
            barWidth = 0
        }
    }
}

// MARK: - Island content (header + views, only in expanded mode)

struct IslandContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // `.confused` hides this row; the site replaces it. `NotchSiteView`
            // brings a bar of its own, and two of them in one 34 pt band is
            // what made the top read as two applications at once.
            //
            // Hiding is not enough for the site: invisible, these buttons would
            // still take the clicks meant for its own. Kept in the tree rather
            // than removed so the stack below keeps the height it was laid out
            // against.
            let headerHidden = state.view == .confused || state.view == .web
            IslandHeader(state: state)
                .frame(height: 34)
                .opacity(headerHidden ? 0 : 1)
                .allowsHitTesting(!headerHidden)
                .animation(.easeInOut(duration: 0.2), value: headerHidden)

            ZStack {
                ForEach(IslandView.allCases, id: \.self) { v in
                    let active = state.view == v
                    // Views that fill available height instead of the fixed 98pt content frame:
                    // chat (prompt) is always flexible; mail is flexible only when active so
                    // it doesn't push the ZStack taller when inactive.
                    // A reply card with files on it needs the room the 98 pt
                    // content frame does not have; with none it is the card it
                    // has always been, so this is conditional rather than a
                    // new permanent member of the set.
                    let replyHasFiles = !state.replyAttachments.isEmpty
                        && (v == .message || v == .overview)
                    // A screen fills its island the way the tall cards do; the
                    // hand-written list below stays for the ones that are tall
                    // for their own reasons.
                    let isTall = IslandConst.viewLayouts[v]?.sizeClass == .large
                        || v == .prompt || v == .timer
                        || ((v == .mail || v == .agents) && active)
                        || (v == .overview && state.homeContent == .timer)
                        || (v == .overview && state.homeShowsPlayer)
                        || replyHasFiles
                    let anim: Animation = active
                        ? .spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
                        : .easeIn(duration: 0.16)
                    IslandViewContent(view: v, state: state)
                        .frame(maxWidth: .infinity)
                        .frame(height: isTall ? nil : 98)
                        .frame(minHeight: (isTall && !active) ? 0 : nil, maxHeight: isTall ? .infinity : nil)
                        .opacity(active ? 1 : 0)
                        .scaleEffect(active ? 1 : 0.97)
                        .allowsHitTesting(active)
                        .animation(anim, value: state.view)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .foregroundColor(Color(hex: "#F5F6F8"))
    }
}

/// The time left, in the compact bar, while the island is closed.
///
/// Its own ticker rather than the card's: this is on screen precisely when the
/// timer tab is not, so the one that gates on `state.view == .timer` would never
/// run here. Gated on a timer actually counting, so an idle island still costs
/// nothing.
struct CompactTimerBadge: View {
    @ObservedObject private var timer = FocusTimer.shared
    @State private var tick = Date.now

    var body: some View {
        let _ = tick
        Text(timer.clock)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundColor(Color(hex: timer.isPaused ? "#8E939C" : timer.kind.hex))
            .background(
                Group {
                    if timer.isRunning {
                        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                            Color.clear.onChange(of: ctx.date) { _, d in tick = d }
                        }
                    }
                }
            )
    }
}

// MARK: - Island header (tabs + icons)

struct IslandHeader: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Split either side of the notch rather than piled on the left: the
            // four you reach for to do something, then the rest.
            HStack(spacing: 5) {
                TabButton(icon: "house.fill", view: .overview, state: state)
                TabButton(mark: ChatSparkleIcon(), view: state.chatTabView, state: state, preAction: {
                    #if !APPSTORE
                    // Only the built-in chat can consume a window context, and reading the
                    // frontmost window title is an accessibility call worth skipping when
                    // the user asked for a website.
                    if state.chatTabView == .prompt, state.promptContext == nil {
                        state.promptContext = WindowContextCapture.captureActive(from: state.lastExternalApp)
                    }
                    #endif
                })
                TabButton(icon: "plus", view: .upload, state: state)
            }
            .padding(.leading, 14)

            Spacer()

            HStack(spacing: 5) {
                TabButton(icon: "timer", view: .timer, state: state)
                // Not a TabButton: the clipboard is a window of its own, so this
                // opens it rather than changing which view the island shows.
                ClipboardTabButton()
            }
            .padding(.trailing, 6)

            // Right: plan pill (GitHub build, home view only) + action icons
            HStack(spacing: 8) {
                #if !APPSTORE
                if state.view == .overview && state.showPlanInNotch && state.planRelayInstalled {
                    ClaudePlanHeaderPill(state: state)
                }
                #endif
                HStack(spacing: 14) {
                    // The real Settings window, not the cut-down card the island
                    // used to show. Same notification the integration card's
                    // "Settings…" already posts, so there is one way in.
                    Button(action: {
                        NotificationCenter.default.post(name: .openFullSettings, object: nil)
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)

                    Button(action: { state.soundEnabled.toggle() }) {
                        Image(systemName: state.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 16)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Opens the Clipboard Manager window. Shaped like a `TabButton` so the row
/// reads as one set of controls, but it toggles a window rather than a view.
struct ClipboardTabButton: View {
    @State private var isHovered = false
    @State private var isOpen = ClipboardPanelController.shared.isOpen

    var body: some View {
        Button(action: {
            ClipboardPanelController.shared.toggle()
            isOpen = ClipboardPanelController.shared.isOpen
        }) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13))
                .foregroundColor(isOpen ? Color(hex: "#F5F6F8")
                                 : (isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C")))
                .frame(width: 30, height: 22)
                .background(
                    isOpen ? Color(hex: "#1D1F23") :
                    isHovered ? Color.white.opacity(0.07) : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // The window can be dismissed from elsewhere — Escape, a click outside —
        // so the lit state is re-read rather than remembered.
        .onAppear { isOpen = ClipboardPanelController.shared.isOpen }
    }
}

/// One tab in the island header.
///
/// Generic over its mark because the chat's is drawn rather than named: every
/// other tab is an SF Symbol, and `TabButton(icon:)` is still how those are
/// written.
struct TabButton<Mark: View>: View {
    let mark: Mark
    let view: IslandView
    @ObservedObject var state: AppState
    var preAction: (() -> Void)? = nil
    @State private var isHovered = false

    private var isOn: Bool {
        if view == .overview { return state.view == .overview || state.view == .empty }
        #if !APPSTORE
        if view == .webchat || view == .prompt {
            return state.view == .webchat || state.view == .prompt
        }
        #endif
        return state.view == view
    }

    var body: some View {
        Button(action: {
            preAction?()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.view = view
            }
        }) {
            mark
                // The symbols take their size from this; a drawn mark brings
                // its own frame and ignores it.
                .font(.system(size: 13))
                .foregroundColor(isOn ? Color(hex: "#F5F6F8") : (isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C")))
                .frame(width: 30, height: 22)
                .background(
                    isOn ? Color(hex: "#1D1F23") :
                    isHovered ? Color.white.opacity(0.07) : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension TabButton where Mark == Image {
    init(icon: String, view: IslandView, state: AppState, preAction: (() -> Void)? = nil) {
        self.init(mark: Image(systemName: icon), view: view, state: state, preAction: preAction)
    }
}

// MARK: - Claude Plan header pill (GitHub build only)

#if !APPSTORE
struct ClaudePlanHeaderPill: View {
    @ObservedObject var state: AppState
    @State private var isHovered = false

    private var effectiveColor: String {
        ClaudePlanGauge.color(for: state.claudePlanUsage.flatMap { ClaudePlanGauge.dominantPct($0) })
    }

    private var label: String {
        guard let usage = state.claudePlanUsage,
              let pct = ClaudePlanGauge.dominantPct(usage) else { return "Claude —" }
        return "Claude \(Int(pct.rounded()))%"
    }

    private var isActive: Bool { state.showingPlanDetail || isHovered }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                state.showingPlanDetail.toggle()
            }
        }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: effectiveColor))
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isActive
                                     ? Color(hex: effectiveColor).lighter(by: 0.3)
                                     : Color(hex: "#6B7079"))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive
                          ? Color(hex: effectiveColor).opacity(0.18)
                          : Color(hex: "#0E0F11"))
            )
            .overlay(
                Capsule()
                    .stroke(Color(hex: effectiveColor).opacity(isActive ? 0.55 : 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = h }
        }
    }
}
#endif

// MARK: - Compact mini mochi grid (2×2 to the right of the notch)

struct CompactMiniGrid: View {
    @ObservedObject var state: AppState

    private var others: [AgentTask] {
        Array(state.tasks.filter { $0.id != state.focusId }.prefix(4))
    }

    var body: some View {
        let cols = [GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)]
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(others) { task in
                MiniBotCanvasView(task: task)
                    .frame(width: 12 / 0.6, height: 12 / 0.6)
                    .frame(width: 12, height: 12, alignment: .center)
            }
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
