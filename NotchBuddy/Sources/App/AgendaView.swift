//
//  AgendaView.swift
//  Notchy
//
//  The Agenda tab: today's meetings from the commercial panel.
//

import SwiftUI

/// Today's meetings, in the order the day runs.
///
/// Laid out like the messages list it sits beside: no Mochi gutter, the rows
/// run the full width and Mochi rides the header line. The meeting a heads-up
/// opened the island for is the one marked; otherwise the one on now or next.
struct AgendaView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var client = AgendaClient.shared

    /// The countdowns tick only while this is the view on screen: the island
    /// builds every view at once, and a hidden one must cost nothing.
    private var isVisible: Bool { state.view == .agenda && state.mode == .expanded }

    var body: some View {
        ZStack {
            CardBackground(wash: .cyan)

            VStack(alignment: .leading, spacing: 4) {
                header
                if isVisible {
                    TimelineView(.periodic(from: .now, by: 20)) { context in
                        content(now: context.date)
                    }
                } else {
                    content(now: .now)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .contentShape(Rectangle())
        // Opening the tab reads the panel again unless the last read is fresh.
        // Gated on the view, not on appearing: everything appears at once.
        .onChange(of: state.view) { _, view in
            if view == .agenda { client.tabOpened() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            // Mochi's seat, as in the messages list.
            if !state.hideCharacters {
                Color.clear.frame(width: 26, height: 24)
            }
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: Self.accent))
            Text("Agenda · today")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1)
            Spacer(minLength: 6)
            if let updated = client.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .fixedSize()
            }
            Button(action: { client.refresh(force: true) }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Refresh"))
            Button(action: { NSWorkspace.shared.open(AgendaRules.agendaURL(.onboarding)) }) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Open the commercial panel"))
        }
        .frame(height: 24)
    }

    // MARK: Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        if client.meetings.isEmpty {
            emptyState
            Spacer(minLength: 0)
        } else {
            let focus = state.agendaHighlight.flatMap { id in client.meetings.first { $0.id == id } }
                ?? AgendaRules.focus(client.meetings, now: now)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(client.meetings) { meeting in
                            AgendaRow(meeting: meeting, now: now,
                                      isFocus: meeting.id == focus?.id,
                                      isHeadsUp: meeting.id == state.agendaHighlight)
                                .id(meeting.id)
                        }
                    }
                }
                .onAppear { if let focus { proxy.scrollTo(focus.id, anchor: .top) } }
                .onChange(of: state.agendaHighlight) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .top) } }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let (text, isProblem) = emptyText
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: isProblem ? "#FF8D97" : "#8E939C"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if isProblem {
                Button(action: {
                    NotificationCenter.default.post(name: .openFullSettings, object: nil)
                }) {
                    Text("Settings…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private var emptyText: (String, Bool) {
        switch client.status {
        case .off:            return (L("Turn the Agenda on in Settings."), true)
        case .signedOut:      return (L("Sign in with your Actuar account in Settings."), true)
        case .loading:        return (L("Reading the commercial panel…"), false)
        case .noPanelAccess:  return (L("This Actuar account has no access to the commercial panel"), true)
        case .failed(let why): return (why, true)
        case .ready:          return (L("No meetings today."), false)
        }
    }

    static let accent = "#38BDF8"
}

/// One meeting: when, who, the case chip, what kind of meeting it is, and how
/// long until it starts. The whole row opens the panel's agenda for it.
struct AgendaRow: View {
    let meeting: AgendaMeeting
    let now: Date
    let isFocus: Bool
    let isHeadsUp: Bool

    @State private var hovering = false

    private var phase: AgendaPhase { AgendaRules.phase(of: meeting, now: now) }

    private var isPast: Bool {
        switch phase {
        case .ended, .done: return true
        default: return false
        }
    }

    private var accent: Color {
        Color(hex: meeting.department == .onboarding ? "#A78BFA" : "#22D3EE")
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Self.clock.string(from: meeting.start))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(Color(hex: isPast ? "#6B7079" : "#F5F6F8"))
                Text(Self.clock.string(from: meeting.end))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(Color(hex: "#6B7079"))
            }
            .frame(width: 38, alignment: .leading)

            RoundedRectangle(cornerRadius: 1)
                .fill(accent.opacity(isPast ? 0.35 : 1))
                .frame(width: 2, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Group {
                        if meeting.title.isEmpty { Text("Unnamed customer") }
                        else { Text(verbatim: meeting.title) }
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(hex: isPast ? "#8E939C" : "#E6E8EB"))
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                    if let code = meeting.publicID {
                        Text(verbatim: code)
                            .font(.system(size: 9, weight: .bold).monospaced())
                            .foregroundColor(Color(hex: "#C5C8CD"))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                            .fixedSize()
                    }
                }
                Text(verbatim: subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#7D828B"))
                    .lineLimit(1).truncationMode(.tail)
            }

            Spacer(minLength: 4)

            Text(verbatim: phaseText)
                .font(.system(size: 10.5, weight: phase == .now || isHeadsUp ? .semibold : .regular))
                .foregroundColor(Color(hex: phaseHex))
                .fixedSize()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(hovering ? 0.16 : (isFocus ? 0.12 : 0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(accent.opacity(isHeadsUp ? 0.8 : 0), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(AgendaRules.agendaURL(meeting.department)) }
        .onHover { hovering = $0 }
        .help(L("Open in the commercial panel"))
    }

    /// "Onboarding · 1ª conexão · Confirmada · 2ª tent." — the panel's own words.
    private var subtitle: String {
        var parts = [L(key: meeting.department.title), L(key: AgendaRules.stageLabel(meeting.stageKey))]
        if let state = AgendaRules.attemptStateLabel(meeting.attemptState) { parts.append(L(key: state)) }
        if meeting.attemptSequence > 1 { parts.append(L("attempt \(meeting.attemptSequence)")) }
        return parts.joined(separator: " · ")
    }

    private var phaseText: String {
        switch phase {
        case .upcoming(let minutes) where minutes >= 60:
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? L("in \(hours) h") : L("in \(hours) h \(rest) min")
        case .upcoming(let minutes): return L("in \(minutes) min")
        case .now:   return L("now")
        case .ended: return L("ended")
        case .done:  return L("held")
        }
    }

    private var phaseHex: String {
        switch phase {
        case .now: return "#34D399"
        case .upcoming(let minutes) where minutes <= 15: return "#FBBF24"
        case .upcoming: return "#C5C8CD"
        case .ended, .done: return "#6B7079"
        }
    }
}
