#if !APPSTORE

import SwiftUI

/// "Version x.y.z is here" — the updater's notification card.
///
/// Built like the hydration reminder: the 108 pt gutter for Mochi, a who line,
/// one title, one grey line, the buttons, and a mark on the right — an arrow
/// in a ring, with the jump from this version to the new one under it. Indigo,
/// a wash no other notification uses, so it is not mistaken for a finished
/// task (green) or a reminder (cyan).
///
/// Everything here reads `Updater`; nothing starts from `onAppear`, because the
/// island builds every view whenever it opens.
struct UpdateCardView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        ZStack {
            CardBackground(wash: .indigo)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    who
                    if let offer = updater.offer { content(offer) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let offer = updater.offer {
                    mark(offer.version).frame(minWidth: 84)
                }
            }
            .padding(.leading, IslandConst.lead(108, flush: 18, hidden: state.hideCharacters))
            .padding(.trailing, 18)
        }
    }

    private var who: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(hex: "#818CF8")).frame(width: 7, height: 7)
            Text(verbatim: "Notchy").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            Text("new version").font(.system(size: 12)).foregroundColor(Color(hex: "#9398A1"))
        }
    }

    @ViewBuilder private func content(_ offer: Updater.Offer) -> some View {
        switch offer {
        case .ready(let version), .available(let version):
            lines(title: Text("Version \(version) is here"),
                  sub: Text("It takes a few seconds, and Notchy comes right back."))
            HStack(spacing: 7) {
                PrimaryButton(L("Update now")) { updater.install() }
                SecondaryButton(L("Later")) { updater.later() }
            }
            .padding(.top, 8)
        case .restarting(let version):
            lines(title: Text("Restarting…"),
                  sub: Text("Back in a moment, on \(version)."))
        }
    }

    private func mark(_ version: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color(hex: "#6366F1").opacity(0.16))
                Circle().strokeBorder(Color(hex: "#818CF8").opacity(0.7), lineWidth: 1.5)
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color(hex: "#C7D2FE"))
            }
            .frame(width: 46, height: 46)
            Text(verbatim: "\(updater.currentVersion) → \(version)")
                .font(.system(size: 11).monospacedDigit()).foregroundColor(Color(hex: "#9398A1"))
                .lineLimit(1).fixedSize()
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func lines(title: Text, sub: Text) -> some View {
        title.font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8).padding(.top, 4)
        sub.font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1")).lineLimit(1).minimumScaleFactor(0.85).padding(.top, 1)
    }
}

#endif
