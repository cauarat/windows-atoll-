import AppKit

/// The display-picking rules, over made-up values: these run on a machine with
/// one screen, or none, and still cover the multi-display cases.
@main
enum IslandDisplaysTests {

    static var failures = 0

    static func check(_ label: String, _ got: Any, _ expected: Any) {
        let g = String(describing: got), e = String(describing: expected)
        if g == e {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(g)")
            print("    expected: \(e)")
            failures += 1
        }
    }

    typealias Info = IslandDisplays.DisplayInfo

    /// Laptop at the origin, two externals to the right of it.
    static let laptop  = Info(id: "builtin", frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    static let left    = Info(id: "dell",    frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
    static let right   = Info(id: "lg",      frame: CGRect(x: 4072, y: 0, width: 1920, height: 1080))
    static let all     = [laptop, left, right]

    static func ids(_ infos: [Info]) -> String { infos.map { $0.id ?? "–" }.joined(separator: ",") }

    static func main() {
        print("IslandDisplays.chosen")

        check("nothing selected means every display",
              ids(IslandDisplays.chosen(from: all, selection: [])), "builtin,dell,lg")

        check("a selection picks exactly those, in screen order",
              ids(IslandDisplays.chosen(from: all, selection: ["lg", "builtin"])), "builtin,lg")

        check("one selected display",
              ids(IslandDisplays.chosen(from: all, selection: ["dell"])), "dell")

        // Unplugging the only display somebody picked must not leave Mochi with
        // nowhere to be — an app that silently disappears reads as broken.
        check("a selection matching nothing attached falls back to all",
              ids(IslandDisplays.chosen(from: all, selection: ["a-display-that-went-away"])),
              "builtin,dell,lg")

        check("…and the preference is not consulted when only one screen is left",
              ids(IslandDisplays.chosen(from: [laptop], selection: ["dell"])), "builtin")

        // A display macOS gives no UUID for can never be *selected*, but it must
        // still come through when everything does.
        let anonymous = Info(id: nil, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        check("a display with no id survives 'all'",
              ids(IslandDisplays.chosen(from: [anonymous], selection: [])), "–")
        check("…and is skipped when a real selection exists",
              ids(IslandDisplays.chosen(from: [laptop, anonymous], selection: ["builtin"])), "builtin")

        // Two identical monitors with no serial number get the same ColorSync
        // UUID from macOS. They are still two displays, and `chosen` must keep
        // both — this Mac has exactly that pair, and conflating them is what
        // stopped the island ever moving between them.
        let twinA = Info(id: "samsung", frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        let twinB = Info(id: "samsung", frame: CGRect(x: 3432, y: 0, width: 1920, height: 1080))
        let withTwins = [laptop, twinA, twinB]
        check("a shared id still describes two displays",
              IslandDisplays.chosen(from: withTwins, selection: ["samsung"]).count, 2)
        check("…and selecting it takes both, not one",
              ids(IslandDisplays.chosen(from: withTwins, selection: ["samsung"])), "samsung,samsung")
        check("…while the laptop stays out of it",
              IslandDisplays.chosen(from: withTwins, selection: ["samsung"])
                  .contains(laptop), false)

        print("IslandDisplays.active")

        check("the cursor's display wins",
              IslandDisplays.active(in: all, cursor: CGPoint(x: 2000, y: 400))?.id ?? "nil", "dell")
        check("…on the far screen too",
              IslandDisplays.active(in: all, cursor: CGPoint(x: 5000, y: 100))?.id ?? "nil", "lg")
        check("…and on the laptop",
              IslandDisplays.active(in: all, cursor: CGPoint(x: 10, y: 10))?.id ?? "nil", "builtin")

        // The cursor sitting on a display Mochi is not allowed on still has to
        // produce an answer, or the island would have no home.
        let allowed = IslandDisplays.chosen(from: all, selection: ["builtin"])
        check("a cursor on an unselected display falls back to the first allowed",
              IslandDisplays.active(in: allowed, cursor: CGPoint(x: 2000, y: 400))?.id ?? "nil",
              "builtin")

        // Which twin the cursor is on is a question about position, not identity,
        // so it still has a right answer despite the shared id.
        check("the cursor tells the twins apart",
              IslandDisplays.active(in: withTwins, cursor: CGPoint(x: 4000, y: 500))?.frame.minX ?? -1,
              CGFloat(3432))
        check("…and the other one",
              IslandDisplays.active(in: withTwins, cursor: CGPoint(x: 2000, y: 500))?.frame.minX ?? -1,
              CGFloat(1512))

        check("no displays at all is nil, not a crash",
              IslandDisplays.active(in: [], cursor: .zero)?.id ?? "nil", "nil")

        // Coordinates between two screens of different heights: the cursor is
        // off the top of the laptop but on the taller display beside it.
        check("a point above the shorter screen belongs to the taller one",
              IslandDisplays.active(in: all, cursor: CGPoint(x: 2000, y: 1200))?.id ?? "nil", "dell")

        print("")
        if failures == 0 {
            print("All island display tests passed.")
        } else {
            print("\(failures) failure(s).")
            exit(1)
        }
    }
}
