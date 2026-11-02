import Foundation

/// The reported bug, written down: clicking Mattermost and then Now Playing
/// left Now Playing's character — a red heart with a sprout, which reads as an
/// apple — sitting inside Mattermost's message list. Focus had moved and the
/// view had not, and the one Mochi took his position from one and his face
/// from the other.
@main
enum IslandOwnerTests {
    static var failures = 0

    static func check(_ label: String, _ got: CGFloat, _ expected: CGFloat) {
        if got == expected { print("  ✓ \(label)") }
        else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            failures += 1
        }
    }

    static func check(_ label: String, _ got: IslandOwner.Owner, _ expected: IslandOwner.Owner) {
        if got == expected { print("  ✓ \(label)") }
        else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            failures += 1
        }
    }

    static let mattermost = "integration_mattermost"
    static let clickMassa = "integration_clickmassa"
    static let music = "integration_music"

    /// The message card's heights, for the TypeScript twin to check itself
    /// against. `core/layout.ts` carries a hand-kept copy of every number in
    /// here, the cap included — and a cap that drifts is an island that grows
    /// past the window it is drawn in on one platform and not the other.
    static func dump() {
        for attachments in [0, 1, 3] {
            for notice in [false, true] {
                for overflow in [CGFloat(0), 40, 200, 10_000] {
                    let h = IslandView.messageHeight(attachmentCount: attachments,
                                                     notice: notice,
                                                     bodyOverflow: overflow)
                    print("\(attachments)\t\(notice)\t\(Int(overflow))\t\(Int(h))")
                }
            }
        }
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") { dump(); return }

        print("")
        print("A message list wears the service it is showing")
        check("Mattermost's list is Mattermost's, whoever holds focus",
              IslandOwner.owner(view: .messages, listSource: mattermost,
                                listShowsAll: false, activeMessageSource: nil,
                                focusID: music),
              .pill(mattermost))
        check("and ClickMassa's is ClickMassa's",
              IslandOwner.owner(view: .messages, listSource: clickMassa,
                                listShowsAll: false, activeMessageSource: nil,
                                focusID: music),
              .pill(clickMassa))
        check("focus agreeing with the list changes nothing",
              IslandOwner.owner(view: .messages, listSource: mattermost,
                                listShowsAll: false, activeMessageSource: nil,
                                focusID: mattermost),
              .pill(mattermost))

        print("")
        print("The queue over both services wears its own face")
        check("listShowsAll belongs to nobody in particular",
              IslandOwner.owner(view: .messages, listSource: nil,
                                listShowsAll: true, activeMessageSource: nil,
                                focusID: mattermost),
              .everyService)
        check("and it wins even when a list source is somehow still set",
              IslandOwner.owner(view: .messages, listSource: mattermost,
                                listShowsAll: true, activeMessageSource: nil,
                                focusID: music),
              .everyService)

        print("")
        print("A message card wears the sender's service")
        check("the open message decides, not focus",
              IslandOwner.owner(view: .message, listSource: nil,
                                listShowsAll: false, activeMessageSource: clickMassa,
                                focusID: music),
              .pill(clickMassa))
        check("with no message open it falls back to focus",
              IslandOwner.owner(view: .message, listSource: nil,
                                listShowsAll: false, activeMessageSource: nil,
                                focusID: music),
              .pill(music))

        print("")
        print("Views that speak for nobody fall back to focus")
        for view in [IslandView.overview, .timer, .note, .approval] {
            check("\(view.rawValue) follows focus, ignoring any open list",
                  IslandOwner.owner(view: view, listSource: mattermost,
                                    listShowsAll: true, activeMessageSource: clickMassa,
                                    focusID: music),
                  .pill(music))
        }

        print("")
        print("With nothing to go on, nobody owns it")
        check("no list and no focus is the default character",
              IslandOwner.owner(view: .messages, listSource: nil,
                                listShowsAll: false, activeMessageSource: nil,
                                focusID: nil),
              .none)
        check("a list with no source falls back to focus",
              IslandOwner.owner(view: .messages, listSource: nil,
                                listShowsAll: false, activeMessageSource: nil,
                                focusID: clickMassa),
              .pill(clickMassa))
        check("an empty focus id is not a pill",
              IslandOwner.owner(view: .overview, listSource: nil,
                                listShowsAll: false, activeMessageSource: nil,
                                focusID: ""),
              .none)

        print("")
        print("How tall the message card has to be")
        let base = IslandConst.viewLayouts[.message]!.height
        check("nothing staged and a body inside its two lines is the card that ships",
              IslandView.messageHeight(attachmentCount: 0, notice: false), base)
        check("a body that fits needs nothing either",
              IslandView.messageHeight(attachmentCount: 0, notice: false, bodyOverflow: 0), base)
        check("a file adds its chip row",
              IslandView.messageHeight(attachmentCount: 1, notice: false),
              base + IslandView.chipRowHeight)
        check("and a refusal adds its line",
              IslandView.messageHeight(attachmentCount: 1, notice: true),
              base + IslandView.chipRowHeight + IslandView.noticeHeight)
        check("a longer message grows the card by exactly what it overruns",
              IslandView.messageHeight(attachmentCount: 0, notice: false, bodyOverflow: 40),
              base + 40)
        check("a negative overflow is not a shorter card",
              IslandView.messageHeight(attachmentCount: 0, notice: false, bodyOverflow: -40), base)
        // The island is not allowed to grow into a window, so past the cap the
        // body scrolls instead. Checked here because three files read this
        // number and only one of them computes it.
        check("and it stops at the ChatGPT view's height",
              IslandView.messageHeight(attachmentCount: 0, notice: false, bodyOverflow: 10_000),
              IslandView.fullBodyCap)
        check("files on a capped card do not push it past the cap either",
              IslandView.messageHeight(attachmentCount: 3, notice: true, bodyOverflow: 10_000),
              IslandView.fullBodyCap)

        print("")
        if failures == 0 { print("All island owner tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }
}
