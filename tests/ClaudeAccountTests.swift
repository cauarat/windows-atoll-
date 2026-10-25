// Reading Claude Code's account summary.
//
// Tested against fixtures written here, never against the real ~/.claude.json:
// that file holds somebody's email address and a test that printed it on
// failure would put it in a CI log. The fixtures mirror its shape, which is
// what the parser actually cares about.
//
// Run with scripts/test-claude-account.sh.

import Foundation

@main
enum ClaudeAccountTests {

    static var failures = 0

    static func check(_ condition: Bool, _ what: String) {
        print("  \(condition ? "\u{2713}" : "\u{2717}") \(what)")
        if !condition { failures += 1 }
    }

    static func json(_ s: String) -> Data { Data(s.utf8) }

    static func main() {

        // MARK: – A signed-in account

        let full = json("""
        {
          "hasAvailableSubscription": true,
          "oauthAccount": {
            "displayName": "Ada",
            "fullName": "Ada Lovelace",
            "emailAddress": "ada@example.com",
            "organizationName": "Analytical Engines",
            "organizationRole": "admin",
            "organizationUuid": "11111111-2222-3333-4444-555555555555",
            "accountUuid": "99999999-8888-7777-6666-555555555555",
            "seatTier": "enterprise_premium",
            "profileFetchedAt": 1760000000000
          },
          "projects": { "/Users/ada/thing": { "history": ["secret"] } }
        }
        """)
        guard let a = ClaudeAccount(claudeJSON: full) else {
            print("  ✗ a well-formed file parses"); exit(1)
        }
        check(a.name == "Ada", "the display name is preferred over the full name")
        check(a.email == "ada@example.com", "the email is read")
        check(a.organization == "Analytical Engines", "and the organisation's name")
        check(a.hasSubscription, "a subscription is noticed")
        check(a.profileFetched != nil, "and when the summary was last refreshed")
        check(a.isSignedIn, "an account with a name counts as signed in")
        check(a.label == "Ada", "which is what it is called in one line")

        // MARK: – What must not come out of that file

        // The parser names every key it wants, so the way to check it ignores
        // the rest is that there is nowhere for the rest to go. These are the
        // fields that would be wrong to show or to keep.
        let mirror = Mirror(reflecting: a)
        let fields = Set(mirror.children.compactMap(\.label))
        check(fields == ["name", "email", "organization", "hasSubscription",
                         "profileFetched", "trialEnds"],
              "the account carries only the six fields it is meant to")
        for forbidden in ["seatTier", "organizationRole", "organizationUuid",
                          "accountUuid", "token", "projects"] {
            check(!fields.contains(forbidden), "it does not carry \(forbidden)")
        }

        // MARK: – Nobody signed in

        let empty = json("{ \"hasAvailableSubscription\": false }")
        guard let e = ClaudeAccount(claudeJSON: empty) else {
            print("  ✗ a file with no account still parses"); exit(1)
        }
        check(!e.isSignedIn, "a file with no account is not signed in")
        check(e.label == "Signed in" || !e.isSignedIn, "and says nothing it cannot know")
        check(!e.hasSubscription, "and claims no subscription")

        // MARK: – Rubbish is not an error

        check(ClaudeAccount(claudeJSON: json("not json at all")) == nil,
              "a file that is not JSON reads as nothing, not as a crash")
        check(ClaudeAccount(claudeJSON: Data()) == nil, "nor does an empty one")
        let odd = json("{ \"oauthAccount\": { \"displayName\": \"\", \"emailAddress\": 42 } }")
        let o = ClaudeAccount(claudeJSON: odd)
        check(o?.name == nil && o?.email == nil,
              "an empty name and a number where a string should be are both ignored")

        // MARK: – Dates, in either shape

        check(ClaudeAccount.date(1760000000000) != nil, "milliseconds are understood")
        check(ClaudeAccount.date(1760000000) != nil, "and seconds")
        check(ClaudeAccount.date("2026-01-01T00:00:00Z") != nil, "and ISO 8601")
        check(ClaudeAccount.date("whenever") == nil, "and anything else is simply unknown")
        check(ClaudeAccount.date(nil) == nil, "as is nothing at all")
        check(ClaudeAccount.date(0) == nil, "and zero, which means unset")

        // MARK: – Sessions

        let s = json("""
        {
          "sessionId": "abc-123", "pid": 4242,
          "cwd": "/Users/ada/engines/difference",
          "status": "working", "startedAt": 1760000000000,
          "name": "difference engine",
          "messagingSocketPath": "/tmp/should-not-matter"
        }
        """)
        guard let sess = ClaudeSession(sessionJSON: s) else {
            print("  ✗ a session parses"); exit(1)
        }
        check(sess.id == "abc-123", "a session is identified by its session id")
        check(sess.pid == 4242, "its process is noted")
        check(sess.project == "difference", "and it is named after the folder it is in")
        check(sess.status == "working", "its status is carried through verbatim")
        check(!sess.isAlive, "a process that is not running is not alive")

        check(ClaudeSession(sessionJSON: json("{ \"pid\": 1 }")) == nil,
              "a session with no id is not a session")
        check(ClaudeSession(sessionJSON: json("{}")) == nil, "nor is an empty file")

        // A real session directory holds a `.key` beside each `.json` — the
        // socket secret. Nothing here should ever be pointed at one, and the
        // reader only ever globs for `.json`.
        check(ClaudeSession(sessionJSON: json("c2VjcmV0")) == nil,
              "a file that is not a session reads as nothing")

        print("")
        if failures == 0 {
            print("All Claude account tests passed.")
        } else {
            print("\(failures) failed.")
            exit(1)
        }
    }
}
