import SwiftUI
import UIKit

// MARK: - The island's building blocks, on the phone
//
// The Mac draws these in IslandViewContent.swift and IslandRootView.swift, files that also hold the
// island's AppKit plumbing, so they cannot be compiled here as they are. These are the same views
// with the same values (sizes, colours, radii, washes): a change to one of them on the Mac belongs
// here too. Where the phone needs more room for a finger, the hit area grows, never the drawing.

enum IslandPalette {
    static let card = Color(hex: "#000000")
    static let text = Color(hex: "#F5F6F8")
    static let secondary = Color(hex: "#8E939C")
    static let tertiary = Color(hex: "#6B7079")
    static let faint = Color(hex: "#454850")
    static let tabOn = Color(hex: "#1D1F23")
    static let added = Color(hex: "#22C55E")
    static let removed = Color(hex: "#F4505E")
}

/// The island's outline: flat across the top where it meets the screen edge, rounded below.
/// (IslandShape, expanded: convex top corners of radius `topRadius`.)
struct IslandShape: Shape {
    var cornerRadius: CGFloat
    var topRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height
        let cr = max(0, min(cornerRadius, min(width / 2, height / 2)))
        let tr = max(0, min(topRadius, min(width / 2, height / 2)))
        var p = Path()
        p.move(to: CGPoint(x: tr, y: 0))
        p.addLine(to: CGPoint(x: width - tr, y: 0))
        p.addArc(center: CGPoint(x: width - tr, y: tr), radius: tr, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: width, y: height - cr))
        p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: cr, y: height))
        p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: tr))
        p.addArc(center: CGPoint(x: tr, y: tr), radius: tr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// CardBackground: black, rounded 20, a coloured wash rising from below, a hairline edge.
struct CardBackground: View {
    enum Wash { case red, green, pink, amber, cyan, indigo, soft }
    let wash: Wash?

    var washColor: Color {
        switch wash {
        case .red:    return Color(hex: "#F4505E").opacity(0.55)
        case .green:  return Color(hex: "#34D399").opacity(0.5)
        case .pink:   return Color(hex: "#F472B6").opacity(0.55)
        case .amber:  return Color(hex: "#F5A524").opacity(0.42)
        case .cyan:   return Color(hex: "#22D3EE").opacity(0.38)
        case .indigo: return Color(hex: "#6366F1").opacity(0.5)
        case .soft:   return Color.white.opacity(0.08)
        case nil:     return Color.clear
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(IslandPalette.card)
            .overlay(
                RadialGradient(gradient: Gradient(stops: [
                    .init(color: washColor, location: 0),
                    .init(color: .clear, location: 0.7),
                ]), center: UnitPoint(x: 0.5, y: 1.3), startRadius: 0, endRadius: 280)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            )
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.035), lineWidth: 1))
    }
}

/// AgentWho: the pill's dot, its name, and what it is doing.
struct AgentWho: View {
    var name: String?
    var color: String?
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            if let name {
                Circle().fill(Color(hex: color ?? "#C0C4CC")).frame(width: 8, height: 8)
                Text(verbatim: name).font(.system(size: 12, weight: .semibold)).foregroundColor(IslandPalette.text)
            }
            Text(label).font(.system(size: 12)).foregroundColor(IslandPalette.secondary)
        }
        .lineLimit(1)
    }
}

/// CodeBlock: the command, monospaced, in a faint rounded box.
struct CodeBlock: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundColor(Color(hex: "#E8E9EC"))
            .textSelection(.enabled)
    }
}

/// PrimaryButton: the light capsule (Allow, Send).
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Color(hex: "#F5F6F8"))
            .foregroundColor(Color(hex: "#0B0C0E"))
            .clipShape(Capsule())
            .padding(.vertical, 6)          // a finger needs more than the drawing
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// SecondaryButton: the dark capsule (Deny, an option).
struct SecondaryButton: View {
    let title: Text
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = Text(title); self.action = action
    }

    init(verbatim title: String, action: @escaping () -> Void) {
        self.title = Text(verbatim: title); self.action = action
    }

    var body: some View {
        Button(action: action) {
            title.font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(Color.white.opacity(0.09))
                .foregroundColor(Color(hex: "#F1F2F4"))
                .clipShape(Capsule())
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// The phone's stand-in for hover: a press dims and shrinks a little.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// TabButton: the header's capsule tabs.
struct TabButton<Mark: View>: View {
    let mark: Mark
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            mark
                .font(.system(size: 13))
                .foregroundColor(isOn ? IslandPalette.text : IslandPalette.secondary)
                .frame(width: 30, height: 22)
                .background(isOn ? IslandPalette.tabOn : Color.clear)
                .clipShape(Capsule())
                .padding(.horizontal, 4).padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// ChipFlowLayout: wraps chips onto as many lines as they need.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        rows(maxW: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let r = rows(maxW: bounds.width, subviews: subviews)
        for (idx, pt) in r.placements.enumerated() {
            subviews[idx].place(at: CGPoint(x: bounds.minX + pt.x, y: bounds.minY + pt.y), proposal: .unspecified)
        }
    }

    private func rows(maxW: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [(x: CGFloat, y: CGFloat)]) {
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        var pts: [(x: CGFloat, y: CGFloat)] = []
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            pts.append((x: x, y: y))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: max(maxX, 0), height: y + lineH), pts)
    }
}

/// TickerShimmerText: the current step, with the island's light sweeping across it.
struct TickerShimmerText: View {
    let text: String

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let p = CGFloat(t.truncatingRemainder(dividingBy: 2.2) / 2.2)
            let phase = p * 1.2 - 0.1
            Text(verbatim: text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(LinearGradient(stops: [
                    .init(color: Color(hex: "#7c818a"), location: max(0, phase - 0.3)),
                    .init(color: Color(hex: "#F2F3F5"), location: max(0, min(1, phase))),
                    .init(color: Color(hex: "#7c818a"), location: min(1, phase + 0.3)),
                ], startPoint: .leading, endPoint: .trailing))
        }
    }
}

/// TickerRowView: a step — a chevron and a shimmer while it runs, a check once it is done.
struct TickerRow: View {
    let text: String
    var current: Bool

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(IslandPalette.secondary)
                    .opacity(current ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundColor(IslandPalette.faint)
                    .opacity(current ? 0 : 1)
            }
            .frame(width: 12, alignment: .center)
            if current {
                TickerShimmerText(text: text)
            } else {
                Text(verbatim: text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(IslandPalette.tertiary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .frame(height: 22, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The +N −M of a file, in the island's colours.
struct LineCounts: View {
    let added: Int
    let removed: Int
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: 3) {
            if added > 0 {
                Text(verbatim: "+\(added)").font(.system(size: size, weight: .medium).monospaced()).foregroundColor(IslandPalette.added)
            }
            if removed > 0 {
                Text(verbatim: "−\(removed)").font(.system(size: size, weight: .medium).monospaced()).foregroundColor(IslandPalette.removed)
            }
        }
        .fixedSize()
    }
}

/// DiffLineRowView: one line of a diff.
struct DiffLineRow: View {
    let row: DiffRow

    var body: some View {
        if row.kind == "@" {
            Text(verbatim: row.text)
                .font(.system(size: 10.5).monospaced())
                .foregroundColor(Color(hex: "#7DA2D6"))
                .lineLimit(1)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                Text(verbatim: row.kind == "+" ? "+" : row.kind == "-" ? "−" : " ")
                    .font(.system(size: 10.5).monospaced())
                    .foregroundColor(row.kind == "+" ? IslandPalette.added : row.kind == "-" ? IslandPalette.removed : IslandPalette.faint)
                    .frame(width: 12, alignment: .leading)
                Text(verbatim: row.text)
                    .font(.system(size: 10.5).monospaced())
                    .foregroundColor(row.kind == "+" ? Color(hex: "#86EFAC") : row.kind == "-" ? Color(hex: "#FCA5A5") : IslandPalette.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(row.kind == "+" ? IslandPalette.added.opacity(0.12) : row.kind == "-" ? IslandPalette.removed.opacity(0.12) : Color.clear)
        }
    }
}

/// TypingDotsView: Mochi is writing.
struct TypingDots: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(IslandPalette.tertiary)
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1.2 : 0.6)
                    .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14), value: phase)
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 4)
        .onAppear { phase = true }
    }
}

extension BotState {
    /// What a pill is doing, in the island's words.
    var phoneLabel: LocalizedStringKey {
        switch self {
        case .idle:      return "idle"
        case .working:   return "working"
        case .thinking:  return "thinking"
        case .searching: return "searching"
        case .approval:  return "needs permission"
        case .question:  return "is asking"
        case .error:     return "error"
        case .finished:  return "finished"
        case .ratelimit: return "rate limited"
        case .sleeping:  return "sleeping"
        case .dizzy:     return "dizzy"
        }
    }
}
