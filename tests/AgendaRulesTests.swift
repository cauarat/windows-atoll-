import Foundation

/// Which of the commercial panel's meetings reach the notch, and when.
///
/// The fixtures in `tests/fixtures/agenda/` are pages the panel's own Agenda
/// read on 2026-11-19, with every name and id replaced: "Ana Souza" (1111…)
/// stands for an Onboarding person with three connections that day, "Bruno
/// Lima" (2222…) for a Backoffice person with three contacts. On the real
/// page those were exactly the cards in their columns — and a connection that
/// was remarcada away from that morning was not one of them.
///
/// The Rust twin (`windows/src-tauri/src/agenda_proto.rs`) asserts the same
/// things over the same files.
@main
enum AgendaRulesTests {
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

    static let ana = "11111111-1111-4111-8111-111111111111"
    static let bruno = "22222222-2222-4222-8222-222222222222"
    static let pessoa7 = "00000000-0000-4000-8000-000000000038"
    static let pessoa8 = "00000000-0000-4000-8000-000000000048"

    static let saoPaulo: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }()

    static func at(_ iso: String) -> Date { AgendaRules.date(fromISO: iso)! }
    static let nov19 = AgendaRules.day(containing: at("2026-11-19T15:00:00Z"), calendar: saoPaulo)

    static func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: "tests/fixtures/agenda/\(name)")
        guard let data = try? Data(contentsOf: url) else {
            print("  ✗ missing fixture \(name)"); failures += 1; return Data()
        }
        return data
    }

    static let local: DateFormatter = {
        let f = DateFormatter()
        f.calendar = saoPaulo
        f.timeZone = saoPaulo.timeZone
        f.dateFormat = "HH:mm"
        return f
    }()

    /// One line per meeting, the way the tab would read it.
    static func describe(_ meetings: [AgendaMeeting]) -> String {
        meetings.map {
            "\(local.string(from: $0.start))-\(local.string(from: $0.end)) \($0.title)"
                + " [\($0.publicID ?? "-")] \($0.department.rawValue) \($0.stageKey)"
                + " #\($0.attemptSequence) \($0.attemptState)"
        }.joined(separator: " | ")
    }

    static func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    static func main() {
        print("Agenda: who you are")
        check("person id from the context object",
              AgendaRules.personID(fromOrganizationContext: Data(#"{"person_id":"\#(ana)","scope":"own"}"#.utf8)) ?? "nil", ana)
        check("person id from a one-row array",
              AgendaRules.personID(fromOrganizationContext: Data(#"[{"person_id":"\#(bruno)"}]"#.utf8)) ?? "nil", bruno)
        check("a legacy admin has no person",
              AgendaRules.personID(fromOrganizationContext: Data(#"{"person_id":null}"#.utf8)) ?? "nil", "nil")
        check("garbage is nobody",
              AgendaRules.personID(fromOrganizationContext: Data("<html>".utf8)) ?? "nil", "nil")

        print("Agenda: the Onboarding board")
        let board = fixture("onboarding-board-cards.json")
        check("Ana's three connections, in order, the remarcada attempt gone",
              describe(AgendaRules.meetings(fromCases: board, personID: ana, day: nov19)),
              "09:00-10:30 Studio 2 / actuar [ZQ1002] onboarding connection #2 confirmed"
              + " | 10:30-12:00 Cliente 3 [-] onboarding connection_2 #1 confirmed"
              + " | 14:30-16:00 Academia 1 | TOLETUS [ZQ1001] onboarding connection_2 #1 confirmed")
        check("upper-case ids match too",
              String(AgendaRules.meetings(fromCases: board, personID: ana.uppercased(), day: nov19).count), "3")
        check("Bruno's contact on that board was in August",
              describe(AgendaRules.meetings(fromCases: board, personID: bruno, day: nov19)), "")
        let nov12 = AgendaRules.day(containing: at("2026-11-12T15:00:00Z"), calendar: saoPaulo)
        check("a day whose attempts are all history shows nothing",
              describe(AgendaRules.meetings(fromCases: board, personID: ana, day: nov12)), "")

        print("Agenda: the Backoffice list")
        let cases = fixture("backoffice-cases.json")
        check("Bruno's three contacts are Backoffice",
              describe(AgendaRules.meetings(fromCases: cases, personID: bruno, day: nov19)),
              "11:00-12:00 Studio 6 / actuar [ZQ1006] backoffice contact #1 confirmed"
              + " | 15:00-16:00 Cliente 7 [-] backoffice contact #1 confirmed"
              + " | 16:00-17:00 cliente 8 da silva - Toletus AB4008 - Actuar [ZQ1008] backoffice contact #1 confirmed")
        check("the same list carries someone else's Onboarding connection, by its stage",
              describe(AgendaRules.meetings(fromCases: cases, personID: pessoa7, day: nov19)),
              "11:00-12:00 Academia 9 | TOLETUS [ZQ1009] onboarding connection #1 confirmed")
        check("an attempt remarcada away from today is not on today",
              describe(AgendaRules.meetings(fromCases: cases, personID: pessoa8, day: nov19)), "")
        let nov24 = AgendaRules.day(containing: at("2026-11-24T15:00:00Z"), calendar: saoPaulo)
        check("it is on the day it moved to",
              describe(AgendaRules.meetings(fromCases: cases, personID: pessoa8, day: nov24)),
              "09:30-11:00 cliente 12 da silva - Toletus AB4012 - Actuar [ZQ1012] onboarding connection #2 confirmed")

        print("Agenda: odd payloads")
        check("not JSON", String(AgendaRules.meetings(fromCases: Data("nope".utf8), personID: ana, day: nov19).count), "0")
        check("a bare array of cases is read too",
              String(AgendaRules.meetings(fromCases: Data(bareArray(board)), personID: ana, day: nov19).count), "3")
        let cancelled = #"{"data":[{"id":"c1","customer_name":"X","operational_meeting_kanban":{"stages":[{"stageKey":"connection","meeting":{"id":"m1","state":"cancelled","responsiblePersonId":"\#(ana)"},"attempts":[{"id":"a1","isEffective":true,"state":"confirmed","startAt":"2026-11-19T12:00:00+00:00","endAt":"2026-11-19T13:00:00+00:00"}]}]}}]}"#
        check("a cancelled meeting is not listed",
              String(AgendaRules.meetings(fromCases: Data(cancelled.utf8), personID: ana, day: nov19).count), "0")
        let noEnd = #"{"data":[{"id":"c1","customer_name":"","operational_meeting_kanban":{"stages":[{"stageKey":"follow_up","meeting":{"id":"m1","state":"open","responsiblePersonId":"\#(ana)"},"attempts":[{"id":"a1","isEffective":true,"state":"pending","startAt":"2026-11-19T20:00:00Z","endAt":null}]}]}}]}"#
        check("no end means an hour; no name stays empty for the view to word",
              describe(AgendaRules.meetings(fromCases: Data(noEnd.utf8), personID: ana, day: nov19)),
              "17:00-18:00  [-] onboarding follow_up #1 pending")
        let a = AgendaRules.meetings(fromCases: board, personID: ana, day: nov19)
        check("the same attempt from both lists is one meeting",
              String(AgendaRules.merged([a, a, AgendaRules.meetings(fromCases: cases, personID: ana, day: nov19)]).count), "3")

        print("Agenda: titles and chips")
        let welber = "welber vieira freire santos - Toletus GK7045 - Actuar GM3941"
        check("the last code is the chip", AgendaRules.publicID(customerName: welber, opportunityID: "lHdlnPydN7xCZvivRkCi") ?? "nil", "GM3941")
        check("and leaves the title",
              AgendaRules.attendeeName(customerName: welber, publicID: "GM3941", displayName: nil),
              "welber vieira freire santos - Toletus GK7045 - Actuar")
        check("slash-separated",
              AgendaRules.attendeeName(customerName: "géssika milliane toletus PA4083 / actuar GB5940",
                                       publicID: AgendaRules.publicID(customerName: "géssika milliane toletus PA4083 / actuar GB5940", opportunityID: nil),
                                       displayName: nil),
              "géssika milliane toletus PA4083 / actuar")
        check("a code in front", AgendaRules.attendeeName(customerName: "gm3941 - Fulano", publicID: "GM3941", displayName: nil), "Fulano")
        check("no code, no chip", AgendaRules.publicID(customerName: "L.A. Esportes", opportunityID: nil) ?? "nil", "nil")
        check("a code glued to letters is not one", AgendaRules.publicID(customerName: "TOLETUSGM3941", opportunityID: nil) ?? "nil", "nil")
        check("an opportunity id that is a code wins", AgendaRules.publicID(customerName: welber, opportunityID: "ab1234") ?? "nil", "AB1234")
        check("a display name wins", AgendaRules.attendeeName(customerName: welber, publicID: "GM3941", displayName: " Welber "), "Welber")

        print("Agenda: what the panel is asked")
        let onboarding = AgendaRules.casesRequest(.onboarding, personID: ana, day: nov19, page: 1)
        check("onboarding RPC", onboarding.rpc, "get_onboarding_board_cards_v1")
        check("onboarding body", json(onboarding.body),
              #"{"p_date_from":"2026-11-19T03:00:00.000Z","p_date_to":"2026-11-20T02:59:59.999Z","p_entry_from":null,"p_entry_to":null,"p_include_open_carryover":true,"p_include_scheduled_pre_release":true,"p_page":1,"p_page_size":200,"p_products":null,"p_responsible_person_id":"11111111-1111-4111-8111-111111111111","p_scope":"all","p_search":null,"p_unassigned_only":false}"#)
        let backoffice = AgendaRules.casesRequest(.backoffice, personID: bruno, day: nov19, page: 2)
        check("backoffice RPC", backoffice.rpc, "get_backoffice_cases")
        check("backoffice body", json(backoffice.body),
              #"{"p_date_from":"2026-11-19T03:00:00.000Z","p_date_to":"2026-11-20T02:59:59.999Z","p_department":"all","p_entry_from":null,"p_entry_to":null,"p_include_open_carryover":true,"p_page":2,"p_page_size":50,"p_pipeline_id":null,"p_products":null,"p_responsible_person_id":"22222222-2222-4222-8222-222222222222","p_scope":"all","p_search":null,"p_status":"all","p_unassigned_only":false}"#)
        check("login body", json(AgendaRules.loginBody(email: "a@b.c", passwordDigest: "d41d")),
              #"{"AppSource":"Actuar,FacilFit,Ediz","Email":"a@b.c","Password":"d41d"}"#)
        check("rpc url", AgendaRules.rpcURL("get_current_organization_context").absoluteString,
              "https://query-gateway.actuar.group/rest/v1/rpc/get_current_organization_context")

        print("Agenda: paging")
        check("the board says when it is done", String(describing: AgendaRules.nextPage(after: board, page: 1)), "nil")
        check("has_more", String(describing: AgendaRules.nextPage(after: Data(#"{"has_more":true}"#.utf8), page: 1)), "Optional(2)")
        check("a total of 103 by 50 has a second page",
              String(describing: AgendaRules.nextPage(after: Data(#"{"total_count":103,"page_size":50}"#.utf8), page: 1)), "Optional(2)")
        check("and stops after the third",
              String(describing: AgendaRules.nextPage(after: Data(#"{"total_count":103,"page_size":50}"#.utf8), page: 3)), "nil")
        check("never past the cap",
              String(describing: AgendaRules.nextPage(after: Data(#"{"has_more":true}"#.utf8), page: AgendaRules.maxPages)), "nil")

        print("Agenda: the clock")
        let studio = a[0]  // 09:00-10:30
        check("16 minutes out", String(describing: AgendaRules.phase(of: studio, now: at("2026-11-19T11:44:00Z"))), "upcoming(minutes: 16)")
        check("half a minute out rounds up", String(describing: AgendaRules.phase(of: studio, now: at("2026-11-19T11:59:30Z"))), "upcoming(minutes: 1)")
        check("on the minute it starts", String(describing: AgendaRules.phase(of: studio, now: at("2026-11-19T12:00:00Z"))), "now")
        check("after it ends", String(describing: AgendaRules.phase(of: studio, now: at("2026-11-19T13:30:00Z"))), "ended")
        check("focus is the next one", AgendaRules.focus(a, now: at("2026-11-19T13:31:00Z"))?.title ?? "nil", "Cliente 3")
        check("nothing left to focus", AgendaRules.focus(a, now: at("2026-11-19T20:00:00Z"))?.title ?? "nil", "nil")

        print("Agenda: heads-up")
        let lead: TimeInterval = 15 * 60
        let both = Set(AgendaDepartment.allCases)
        func reminder(_ now: String, notified: Set<String> = [], departments: Set<AgendaDepartment> = both,
                      _ meetings: [AgendaMeeting] = a) -> String {
            guard let r = AgendaRules.nextReminder(meetings, now: at(now), lead: lead,
                                                   notified: notified, departments: departments)
            else { return "nil" }
            return "\(r.meeting.title) at \(local.string(from: r.fireAt))"
        }
        check("15 minutes before the first", reminder("2026-11-19T11:00:00Z"), "Studio 2 / actuar at 08:45")
        check("late but not started: right away", reminder("2026-11-19T11:50:00Z"), "Studio 2 / actuar at 08:50")
        check("once announced, the next one", reminder("2026-11-19T11:50:00Z", notified: [a[0].reminderKey]), "Cliente 3 at 10:15")
        check("a started meeting is never announced", reminder("2026-11-19T12:00:00Z"), "Cliente 3 at 10:15")
        check("a process switched off is quiet", reminder("2026-11-19T11:00:00Z", departments: [.backoffice]), "nil")
        check("after the last one, nothing", reminder("2026-11-19T17:31:00Z"), "nil")
        let contacts = AgendaRules.meetings(fromCases: cases, personID: bruno, day: nov19)
        check("Backoffice alone still rings for contacts",
              reminder("2026-11-19T12:00:00Z", departments: [.backoffice], contacts), "Studio 6 / actuar at 10:45")
        let moved = AgendaMeeting(attemptID: a[0].attemptID, meetingID: a[0].meetingID, caseID: a[0].caseID,
                                  department: a[0].department, stageKey: a[0].stageKey,
                                  start: a[0].start.addingTimeInterval(3600), end: a[0].end.addingTimeInterval(3600),
                                  title: a[0].title, publicID: a[0].publicID, attemptSequence: 2,
                                  attemptState: "confirmed", meetingState: "open")
        check("an attempt moved in place is announced again",
              reminder("2026-11-19T11:50:00Z", notified: [a[0].reminderKey], [moved]), "Studio 2 / actuar at 09:45")

        print("Agenda: days")
        check("day stamp", AgendaRules.dayStamp(at("2026-11-20T02:30:00Z"), calendar: saoPaulo), "2026-11-19")
        check("day start", AgendaRules.isoMillis(nov19.start), "2026-11-19T03:00:00.000Z")
        check("long fractions parse", AgendaRules.isoMillis(at("2026-11-16T11:19:53.30099+00:00")), "2026-11-16T11:19:53.300Z")

        print(failures == 0 ? "All agenda checks passed." : "\(failures) agenda check(s) failed.")
        if failures > 0 { exit(1) }
    }

    /// The board's `data`, without the envelope.
    static func bareArray(_ page: Data) -> Data {
        let object = try! JSONSerialization.jsonObject(with: page) as! [String: Any]
        return try! JSONSerialization.data(withJSONObject: object["data"]!)
    }
}
