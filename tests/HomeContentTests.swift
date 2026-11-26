import Foundation

/// Which source Home draws.
///
/// The rule that matters is `.automatic`: Ato and Mattermost take turns,
/// so Home follows whichever spoke last — and keeps following it after the
/// notification has folded away, which is why the caller reads a "last by
/// source" map rather than the unread queue.
///
/// `--dump` writes the choices as tab-separated rows for
/// tests/home-content-parity.ts, which holds windows/src/core/state.ts to them:
/// the same choices in the same order, the same labels and hints, the same
/// default and the same source for each.
@main
enum HomeContentTests {

    static var failures = 0

    static func dump() {
        for content in HomeContent.allCases {
            print(["case", content.rawValue, content.label, content.hint].joined(separator: "\t"))
        }
        print(["default", HomeContent.defaultChoice.rawValue].joined(separator: "\t"))
        // Which source each choice draws, with every source having spoken last
        // in turn and with nobody having spoken yet.
        for content in HomeContent.allCases {
            let row = [nil as MessageSource?] + MessageSource.allCases.map { Optional($0) }
            print((["source", content.rawValue] + row.map {
                "\($0?.rawValue ?? "none")=\(source(content, $0))"
            }).joined(separator: "\t"))
        }
    }

    static func check(_ label: String, _ got: String, _ expected: String) {
        if got == expected { print("  ✓ \(label)") }
        else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            failures += 1
        }
    }

    static func source(_ content: HomeContent, _ lastSource: MessageSource?) -> String {
        content.source(lastSource: lastSource)?.rawValue ?? "none"
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") { dump(); return }

        print("HomeContent — what a fresh install shows")

        // Every message service as one queue, kept while something plays —
        // the Mac's default, and the one Windows starts from too.
        check("Home starts on Notifications", HomeContent.defaultChoice.rawValue, "notifications")
        check("listed first, where the picker shows it first",
              HomeContent.allCases.first?.rawValue ?? "none", HomeContent.defaultChoice.rawValue)

        print("HomeContent — taking turns")

        check("whoever spoke last wins", source(.automatic, .ato), "ato")
        check("…and the other one when it speaks", source(.automatic, .mattermost), "mattermost")
        check("…and WhatsApp when it does", source(.automatic, .whatsapp), "whatsapp")
        check("nobody has spoken", source(.automatic, nil), "none")

        print("HomeContent — pinned to one source")

        check("Ato ignores who spoke last", source(.ato, .mattermost), "ato")
        check("Mattermost ignores who spoke last", source(.mattermost, .ato), "mattermost")
        check("…and still itself when nobody has spoken", source(.mattermost, nil), "mattermost")
        check("WhatsApp ignores who spoke last", source(.whatsapp, .ato), "whatsapp")

        print("HomeContent — the choices that are not messages")

        check("the timer draws no message", source(.timer, .ato), "none")

        print("HomeContent — stored choices that are gone")

        check("a Home pinned to ClickMassa is pinned to Ato",
              HomeContent.migratedRawValue("clickMassa"), "ato")
        check("a Home pinned to Claude Code starts again from the default",
              HomeContent.migratedRawValue("claudeCode"), HomeContent.defaultChoice.rawValue)
        check("a choice that still exists is left alone",
              HomeContent.migratedRawValue("whatsapp"), "whatsapp")

        print("HomeContent — every case is covered")

        // A new case added without a rule would fall out here rather than
        // silently drawing nothing.
        for content in HomeContent.allCases {
            let withOne = content.source(lastSource: .mattermost)
            let isMessageChoice = content != .timer
            if isMessageChoice && withOne == nil {
                print("  ✗ \(content.rawValue) draws nothing with a source available")
                failures += 1
            }
            if !content.label.isEmpty && !content.hint.isEmpty { continue }
            print("  ✗ \(content.rawValue) has no label or hint")
            failures += 1
        }
        if failures == 0 { print("  ✓ all \(HomeContent.allCases.count) choices resolve and are described") }

        // MARK: – Music takes Home while it plays

        check("automatic hands Home to whatever is playing",
              "\(HomeContent.automatic.showsMusic(hasTrack: true))", "true")
        check("and takes it back when the music stops",
              "\(HomeContent.automatic.showsMusic(hasTrack: false))", "false")
        for pinned in HomeContent.allCases where pinned != .automatic {
            check("\(pinned.label) was chosen on purpose, so music does not take it",
                  "\(pinned.showsMusic(hasTrack: true))", "false")
        }
        check("nothing shows a player when nothing is playing",
              "\(HomeContent.allCases.filter { $0.showsMusic(hasTrack: false) }.count)", "0")

        // MARK: – The one question the card and the geometry both ask
        //
        // Home once drew the pinned message card at the player's height with
        // no character in it, because the content asked `showsMusic` and the
        // geometry asked something that had grown a second route. Anything
        // that answers one of these has to answer the other.

        let music = "integration_music"
        check("clicking Now Playing reaches the player from a pinned Home",
              "\(HomeContent.notifications.playerTakesHome(hasTrack: true, focusedPillID: music))",
              "true")
        check("and from automatic, which would have shown it anyway",
              "\(HomeContent.automatic.playerTakesHome(hasTrack: true, focusedPillID: music))",
              "true")
        for pinned in HomeContent.allCases where pinned != .automatic {
            check("\(pinned.label) keeps what it was pinned to while another pill holds focus",
                  "\(pinned.playerTakesHome(hasTrack: true, focusedPillID: "integration_mattermost"))",
                  "false")
        }
        check("an empty player is nobody's Home, even with its pill focused",
              "\(HomeContent.notifications.playerTakesHome(hasTrack: false, focusedPillID: music))",
              "false")
        check("nor on automatic",
              "\(HomeContent.automatic.playerTakesHome(hasTrack: false, focusedPillID: music))",
              "false")
        check("no focus at all is no second route",
              "\(HomeContent.notifications.playerTakesHome(hasTrack: true, focusedPillID: nil))",
              "false")

        print("")
        if failures == 0 { print("All home content tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }
}
