import Foundation

/// Which source Home draws.
///
/// The rule that matters is `.automatic`: ClickMassa and Mattermost take turns,
/// so Home follows whichever spoke last — and keeps following it after the
/// notification has folded away, which is why the caller reads a "last by
/// source" map rather than the unread queue.
@main
enum HomeContentTests {

    static var failures = 0

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
        print("HomeContent — taking turns")

        check("whoever spoke last wins", source(.automatic, .clickMassa), "clickmassa")
        check("…and the other one when it speaks", source(.automatic, .mattermost), "mattermost")
        check("nobody has spoken", source(.automatic, nil), "none")

        print("HomeContent — pinned to one source")

        check("ClickMassa ignores who spoke last", source(.clickMassa, .mattermost), "clickmassa")
        check("Mattermost ignores who spoke last", source(.mattermost, .clickMassa), "mattermost")
        check("…and still itself when nobody has spoken", source(.mattermost, nil), "mattermost")

        print("HomeContent — the choices that are not messages")

        check("the timer draws no message", source(.timer, .clickMassa), "none")
        check("Claude Code draws no message", source(.claudeCode, .clickMassa), "none")

        print("HomeContent — every case is covered")

        // A new case added without a rule would fall out here rather than
        // silently drawing nothing.
        for content in HomeContent.allCases {
            let withOne = content.source(lastSource: .mattermost)
            let isMessageChoice = content != .timer && content != .claudeCode
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
