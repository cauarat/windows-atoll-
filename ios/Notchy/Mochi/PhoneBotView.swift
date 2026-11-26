import SwiftUI

// MARK: - Mochi on the phone
//
// The island's BotCanvasView without AppState: a TimelineView drives a Canvas that calls the very
// same BotEngine. The eyes follow a finger instead of the mouse, and a tap is a poke (too many and he
// gets dizzy, as on the Mac).

struct PhoneBotView: View {
    var state: BotState
    var particleOverhang: CGFloat = 0
    var mini = false
    var interactive = true
    var paused = false

    @StateObject private var engine = BotEngine()
    @State private var look: CGPoint = .zero
    @State private var greeted = false

    var body: some View {
        TimelineView(.animation(paused: paused)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let dt = min(0.05, now - engine.lastTime)
                engine.isMini = mini
                engine.lookX = look.x
                engine.lookY = look.y
                engine.particleOverhang = particleOverhang
                engine.update(dt: dt)
                var ctx = context
                engine.applyDance(&ctx, size: size)
                if mini {
                    engine.draw(context: ctx, size: size)
                } else {
                    engine.drawHandsBehind(context: ctx, size: size)
                    engine.draw(context: ctx, size: size)
                    engine.drawHandsAndExtras(context: ctx, size: size)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(interactive ? drag : nil)
        .simultaneousGesture(interactive ? TapGesture().onEnded { engine.slap() } : nil)
        .onChange(of: state) { _, new in engine.setState(new) }
        .onAppear {
            engine.isMini = mini
            engine.setState(state, force: true)
            if !mini && !greeted {
                greeted = true
                engine.greet()
            }
        }
    }

    /// The eyes follow the finger while it is down, and drift back when it lifts.
    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                look = CGPoint(x: tanh(value.translation.width / 120), y: -tanh(value.translation.height / 100))
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.4)) { look = .zero }
            }
    }
}

/// The soft light behind Mochi on the island (BotPlacement), by state.
struct BotGlow: View {
    var state: BotState
    var diameter: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(gradient: Gradient(stops: [
                .init(color: Self.color(state), location: 0),
                .init(color: .clear, location: 0.62),
            ]), center: .center, startRadius: 0, endRadius: diameter * 1.1))
            .frame(width: diameter * 2.2, height: diameter * 2.2)
            .blur(radius: 6)
            .opacity(Self.opacity(state))
            .animation(.easeInOut(duration: 0.4), value: state)
            .allowsHitTesting(false)
    }

    static func color(_ s: BotState) -> Color {
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

    static func opacity(_ s: BotState) -> Double {
        switch s {
        case .idle, .sleeping: return 0.15
        case .dizzy:           return 0.0
        default:               return 0.65
        }
    }
}

/// Mochi at the size the island draws him: `diameter` is his body, the canvas around him is what the
/// engine needs for hands, hats and particles.
struct SizedMochi: View {
    var state: BotState
    var diameter: CGFloat
    var glow = true
    var interactive = true

    var body: some View {
        let canvas = diameter / 0.6
        let overhang: CGFloat = 40
        ZStack {
            if glow { BotGlow(state: state, diameter: diameter) }
            PhoneBotView(state: state, particleOverhang: overhang, interactive: interactive)
                .frame(width: canvas, height: canvas + overhang)
                .offset(y: -overhang / 2)
        }
        .frame(width: canvas, height: canvas)
    }
}

/// A little Mochi, as the island draws one (MiniBotCanvasView).
struct MiniMochi: View {
    var state: BotState
    var size: CGFloat = 30

    var body: some View {
        PhoneBotView(state: state, mini: true, interactive: false)
            .frame(width: size, height: size)
    }
}
