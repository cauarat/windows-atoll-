import SwiftUI
import UIKit

// MARK: - The island's building blocks, on the phone
//
// The Mac draws these in IslandViewContent.swift and IslandRootView.swift, files that also hold the
// island's AppKit plumbing, so they cannot be compiled here as they are. These are the same views
// with the same values (sizes, colours, radii): a change to one of them on the Mac belongs
// here too. Where the phone needs more room for a finger, the hit area grows, never the drawing.

enum IslandPalette {
    static let card = Color(hex: "#000000")
    static let text = Color(hex: "#F5F6F8")
    static let secondary = Color(hex: "#8E939C")
    static let tertiary = Color(hex: "#6B7079")
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

/// CardBackground, without a wash: black, rounded 20, a hairline edge.
struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(IslandPalette.card)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.035), lineWidth: 1))
    }
}

/// PrimaryButton: the light capsule (Scan the pairing code).
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

/// SecondaryButton: the dark capsule (Try again, Paste the link).
struct SecondaryButton: View {
    let title: Text
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = Text(title); self.action = action
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
