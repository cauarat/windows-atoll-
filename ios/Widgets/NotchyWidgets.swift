import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - The Live Activity: Mochi on the Lock Screen and in the Dynamic Island

@main
struct NotchyWidgets: WidgetBundle {
    var body: some Widget {
        MochiLiveActivity()
    }
}

struct MochiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MochiActivityAttributes.self) { context in
            LockScreenView(state: context.state, computer: context.attributes.computer)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(Color(hex: "#F5F6F8"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StillMochi(state: s, size: 52)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if s.stepCount > 1 {
                        Text(verbatim: "\(min(s.stepIndex + 1, s.stepCount))/\(s.stepCount)")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundColor(Color(hex: "#8E939C"))
                            .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: s.project ?? s.agent)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1)
                        Text(verbatim: s.detail)
                            .font(.system(size: 12.5))
                            .foregroundColor(s.waiting ? Color(hex: "#F5A524") : Color(hex: "#9398A1"))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if s.waiting {
                        Text("Open Notchy to answer")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#0B0C0E"))
                            .padding(.horizontal, 13).padding(.vertical, 6)
                            .background(Capsule().fill(Color(hex: "#F5F6F8")))
                    }
                }
            } compactLeading: {
                StillMochi(state: s, size: 22)
            } compactTrailing: {
                StateGlyph(state: s)
            } minimal: {
                StillMochi(state: s, size: 20)
            }
            .keylineTint(BotGlowColor.color(s.state))
        }
    }
}

struct LockScreenView: View {
    let state: MochiActivityAttributes.ContentState
    let computer: String

    var body: some View {
        HStack(spacing: 14) {
            StillMochi(state: state, size: 58)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: state.color ?? "#C0C4CC")).frame(width: 7, height: 7)
                    Text(verbatim: state.project ?? state.agent)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if state.stepCount > 1 {
                        Text(verbatim: "\(min(state.stepIndex + 1, state.stepCount))/\(state.stepCount)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                }
                Text(verbatim: state.detail.isEmpty ? state.agent : state.detail)
                    .font(.system(size: 13))
                    .foregroundColor(state.waiting ? Color(hex: "#F5A524") : Color(hex: "#9398A1"))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(verbatim: computer)
                    if state.others > 0 { Text("· \(state.others) more busy") }
                }
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .lineLimit(1)
            }
        }
        .padding(16)
    }
}

/// A small mark of what Mochi is doing, for the compact island.
struct StateGlyph: View {
    let state: MochiActivityAttributes.ContentState

    var body: some View {
        let s = BotState(rawValue: state.state) ?? .idle
        Image(systemName: {
            switch s {
            case .approval: return "hand.raised.fill"
            case .question: return "questionmark.bubble.fill"
            case .finished: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .thinking: return "sparkles"
            case .searching: return "magnifyingglass"
            default: return "ellipsis"
            }
        }())
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(BotGlowColor.color(state.state))
    }
}

enum BotGlowColor {
    static func color(_ raw: String) -> Color {
        switch BotState(rawValue: raw) ?? .idle {
        case .working:   return Color(hex: "#3B9EFF")
        case .thinking:  return Color(hex: "#A78BFA")
        case .searching: return Color(hex: "#6366F1")
        case .approval:  return Color(hex: "#F5A524")
        case .question:  return Color(hex: "#22D3EE")
        case .error:     return Color(hex: "#F4505E")
        case .finished:  return Color(hex: "#34D399")
        case .ratelimit: return Color(hex: "#F59E0B")
        default:         return Color.white
        }
    }
}

/// One frame of Mochi, drawn by the same engine as the island, rendered to an image: a Live Activity
/// is a snapshot, it does not animate.
struct StillMochi: View {
    let state: MochiActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        if let image = MochiSnapshot.image(state: state, size: size) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Circle().fill(Color.white).frame(width: size * 0.6, height: size * 0.6)
        }
    }
}

@MainActor
enum MochiSnapshot {
    static func image(state: MochiActivityAttributes.ContentState, size: CGFloat) -> UIImage? {
        let engine = BotEngine()
        engine.isMini = size < 40
        engine.bodyColor = state.color.flatMap(cgColorFromHex)
        engine.character = MochiCharacter(accessory: state.accessory.flatMap(MochiAccessory.init(rawValue:)),
                                          eye: state.eye.flatMap(MochiEye.init(rawValue:)),
                                          shape: state.shape.flatMap(MochiShape.init(rawValue:)))
        engine.setState(BotState(rawValue: state.state) ?? .idle, force: true)
        // Let the state's colour and pose settle, as the island would a moment after the change.
        for _ in 0..<40 { engine.update(dt: 0.03) }
        let canvas = Canvas { context, sz in
            engine.drawHandsBehind(context: context, size: sz)
            engine.draw(context: context, size: sz)
            engine.drawHandsAndExtras(context: context, size: sz)
        }
        .frame(width: size, height: size)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 3
        return renderer.uiImage
    }
}
