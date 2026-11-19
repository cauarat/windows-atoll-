// The welcome, and the name Mochi greets you by: what they promise, and the inputs
// tests/welcome-parity.ts replays through the TypeScript twins
// (windows/src/core/greetingName.ts and windows/src/core/onboarding.ts).
//
// Run with scripts/test-welcome.sh. `--dump` prints every case as JSON instead
// of checking anything.

import Foundation

@main
enum WelcomeTests {

    static var failures = 0

    static func check(_ condition: Bool, _ what: String) {
        print("  \(condition ? "\u{2713}" : "\u{2717}") \(what)")
        if !condition { failures += 1 }
    }

    /// Names as somebody might type them into the field, odd ones included.
    static let typed: [String] = [
        "João", "  João  ", "", "   ", "\n\t", "Ana   Maria", "Ana\u{00A0}Maria", " ana maria ",
        "João Silva", "Jean-Luc", "O'Brien", "Line\none",
        String(repeating: "a", count: 41),
        "Maria " + String(repeating: "b", count: 40),
        String(repeating: "x", count: 39) + " y",
        "Joa\u{0303}o",   // an "ã" typed as a + combining tilde: one character, kept whole
    ]

    /// Account names as the system reports them.
    static let accounts: [String] = [
        "Théodore Riant", "theodoreriant", "t.riant2", "João Silva", "João", "joaos",
        "CAUA", "Jean-Luc Picard", "O'Brien", "  Ana Maria  ", "", "Admin1", "J.R. Smith",
        "someone@host", String(repeating: "Abc ", count: 9), "Ana2 Maria", "Zoë",
    ]

    static func json(_ s: String?) -> Any { s.map { $0 as Any } ?? NSNull() }

    static func dump() {
        var out: [String: Any] = [:]
        out["periods"] = (0..<24).map { ["hour": $0, "period": DayPeriod.at(hour: $0).rawValue] }
        out["typed"] = typed.map { ["input": $0, "output": json(cleanedUserName($0))] }
        out["accounts"] = accounts.map { ["input": $0, "output": json(firstName(fromFullName: $0))] }
        var names: [[String: Any]] = []
        for t in ["João", "", "   ", "  Ana   Maria "] {
            for a in ["Théodore Riant", "joaos", ""] {
                let output = userGreetingName(typed: t, system: firstName(fromFullName: a))
                names.append(["typed": t, "account": a, "output": json(output)])
            }
        }
        out["names"] = names
        out["steps"] = OnboardingFlow.steps.map(\.rawValue)
        out["progress"] = OnboardingFlow.steps.map { step -> [String: Any] in
            let p = OnboardingFlow(start: step).progress
            return ["step": step.rawValue,
                    "current": p.map { $0.current as Any } ?? NSNull(),
                    "total": p.map { $0.total as Any } ?? NSNull()]
        }
        out["gate"] = [0, 1, 2].flatMap { seen in [true, false].map { enabled in
            ["seen": seen, "enabled": enabled,
             "show": OnboardingGate.shouldShow(seen: seen, enabled: enabled)] as [String: Any]
        } }
        out["version"] = OnboardingGate.version
        out["maxTyped"] = maxTypedUserNameLength
        let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func main() {
        if CommandLine.arguments.contains("--dump") { dump(); return }

        print("Time of day")
        let periods = (0..<24).map { DayPeriod.at(hour: $0) }
        check(periods[0...4].allSatisfy { $0 == .evening }, "midnight to 4 is still evening — \"boa noite\"")
        check(periods[5...11].allSatisfy { $0 == .morning }, "5 to 11 is morning")
        check(periods[12...17].allSatisfy { $0 == .afternoon }, "noon to 17 is afternoon")
        check(periods[18...23].allSatisfy { $0 == .evening }, "18 to 23 is evening")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        let ten = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 10))!
        check(DayPeriod.at(ten, calendar: calendar) == .morning, "a date is read in the calendar's own time zone")

        print("The name the user typed")
        check(cleanedUserName("  João  ") == "João", "spaces at either end go")
        check(cleanedUserName("") == nil && cleanedUserName("   ") == nil && cleanedUserName("\n\t") == nil,
              "nothing but whitespace is no name at all")
        check(cleanedUserName(nil) == nil, "no value is no name")
        check(cleanedUserName("Ana   Maria") == "Ana Maria", "runs of spaces become one")
        check(cleanedUserName("Ana\u{00A0}Maria") == "Ana Maria", "a no-break space counts as a space")
        check(cleanedUserName("Line\none") == "Line one", "a newline pasted in becomes a space")
        check(cleanedUserName(String(repeating: "a", count: 41)) == String(repeating: "a", count: 40),
              "capped at \(maxTypedUserNameLength) characters")
        check(cleanedUserName(String(repeating: "x", count: 39) + " y") == String(repeating: "x", count: 39),
              "a cut that lands on a space does not leave it dangling")
        check(cleanedUserName("Joa\u{0303}o")?.count == 4, "an accent typed as a combining mark stays on its letter")

        print("The account's first name")
        check(firstName(fromFullName: "Théodore Riant") == "Théodore", "the first of a full name")
        check(firstName(fromFullName: "theodoreriant") == nil, "a lowercase login handle is no name")
        check(firstName(fromFullName: "t.riant2") == nil, "a handle with dots or digits is no name")
        check(firstName(fromFullName: "João") == "João", "a single capitalised word is a name")
        check(firstName(fromFullName: "Jean-Luc Picard") == "Jean-Luc", "hyphens belong to names")
        check(firstName(fromFullName: "O'Brien") == "O'Brien", "so do apostrophes")
        check(firstName(fromFullName: "Ana2 Maria") == nil, "a first word with a digit in it is no name")
        check(firstName(fromFullName: String(repeating: "Abc ", count: 9)) == nil, "too long to be a name")

        print("Which name wins")
        check(userGreetingName(typed: "João", system: "Théodore") == "João", "what was typed beats the account")
        check(userGreetingName(typed: "  ", system: "Théodore") == "Théodore", "an empty field falls back to the account")
        check(userGreetingName(typed: "", system: nil) == nil, "and with neither there is no name")

        print("The welcome's screens")
        var flow = OnboardingFlow()
        check(flow.step == .welcome && flow.isFirst, "it opens on the hello")
        flow.back()
        check(flow.step == .welcome, "Back on the first screen goes nowhere")
        check(flow.progress == nil, "the hello carries no progress row")
        flow.advance()
        check(flow.step == .name && flow.progress.map { $0 == (1, 5) } == true, "the name is question 1 of 5")
        for _ in 0..<10 { flow.advance() }
        check(flow.step == .ready && flow.isLast, "Continue stops on the last screen")
        check(flow.progress == nil, "the last screen carries no progress row")
        check(OnboardingFlow(start: .startup).progress.map { $0 == (5, 5) } == true, "the startup screen is 5 of 5")
        check(OnboardingFlow.steps.count == 7, "seven screens")

        print("Whether it shows")
        check(OnboardingGate.shouldShow(seen: 0, enabled: true), "never seen: shown")
        check(!OnboardingGate.shouldShow(seen: OnboardingGate.version, enabled: true), "seen: not shown again")
        check(!OnboardingGate.shouldShow(seen: 0, enabled: false), "not while Notchy is off")

        print("")
        if failures == 0 {
            print("All welcome checks passed.")
        } else {
            print("\(failures) failed.")
            exit(1)
        }
    }
}
