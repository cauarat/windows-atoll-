//
//  AgendaRules.swift
//  Notchy
//
//  Which of the commercial panel's meetings are yours today, and when the
//  notch should say one is coming.
//

import Foundation

// MARK: - Model

/// The two processes the panel's agenda has.
///
/// A meeting's process is its stage's, not the list it was read from: the
/// Backoffice list carries the Onboarding connections of its cases too, and
/// the panel itself decides with `stageKey === "contact"`.
enum AgendaDepartment: String, CaseIterable, Codable, Sendable {
    case onboarding, backoffice

    init(stageKey: String) {
        self = stageKey == "contact" ? .backoffice : .onboarding
    }

    /// English catalogue key — translated where it is drawn.
    var title: String { self == .onboarding ? "Onboarding" : "Backoffice" }
}

/// One meeting on your agenda today: one effective attempt of one meeting.
///
/// Keyed by the attempt rather than the meeting. A remarcação is a new attempt,
/// so a moved meeting comes back as a new row with a new reminder, and the old
/// time is simply gone.
struct AgendaMeeting: Equatable, Codable, Identifiable, Sendable {
    var id: String { attemptID }

    let attemptID: String
    let meetingID: String
    let caseID: String
    let department: AgendaDepartment
    let stageKey: String
    let start: Date
    let end: Date
    /// The customer, as the panel titles the card.
    let title: String
    /// The case code the panel shows as a chip ("GM3941"), when there is one.
    let publicID: String?
    let attemptSequence: Int
    let attemptState: String
    let meetingState: String

    /// Held and recorded: still listed, dimmed, never announced.
    var isClosed: Bool { ["attended", "completed"].contains(meetingState) }

    /// What the reminder set remembers. The start is in it so that an attempt
    /// whose time was edited in place is announced again at its new time.
    var reminderKey: String { "\(attemptID)@\(Int(start.timeIntervalSince1970))" }
}

/// Where a meeting stands against the clock, for the row's right-hand label.
enum AgendaPhase: Equatable, Sendable {
    case upcoming(minutes: Int)
    case now
    case ended
    case done
}

struct AgendaReminder: Equatable, Sendable {
    let meeting: AgendaMeeting
    let fireAt: Date
}

// MARK: - Rules

/// Everything about the agenda that can be decided without the network.
///
/// Built from the panel's own code and checked against what its Agenda drew
/// on 2026-11-19 (`tests/fixtures/agenda/`): a meeting is on someone's agenda
/// when its *effective* attempt starts that day and the meeting's responsible
/// person is them. The other attempts are history — "remarcada" — and are not
/// drawn.
enum AgendaRules {

    // MARK: Endpoints

    /// The panel's sign-in is Actuar's user service, the one Ato uses, but
    /// with the panel's `AppSource`: a token minted for `actuar` alone is not
    /// what the panel's gateway is used to seeing.
    static let userService = URL(string: "https://userservice-api.prd.o.actuar.cloud")!
    static let gateway = URL(string: "https://query-gateway.actuar.group")!
    static let panel = URL(string: "https://dash-comercial.pages.dev")!
    static let appSource = "Actuar,FacilFit,Ediz"

    static func rpcURL(_ name: String) -> URL {
        gateway.appendingPathComponent("rest/v1/rpc").appendingPathComponent(name)
    }

    /// Where a click on a meeting goes: the panel's agenda for its process.
    static func agendaURL(_ department: AgendaDepartment) -> URL {
        URL(string: "\(panel.absoluteString)/agenda?process=\(department.rawValue)")!
    }

    static func loginBody(email: String, passwordDigest: String) -> [String: Any] {
        ["Email": email, "Password": passwordDigest, "AppSource": appSource]
    }

    static func refreshBody(tokenID: String) -> [String: Any] {
        ["TokenId": tokenID, "AppSource": appSource]
    }

    static let organizationContextRPC = "get_current_organization_context"

    /// The RPC and body the panel sends for one page of one process's cases,
    /// narrowed to one responsible person — the panel's own "Eu" filter.
    ///
    /// Open carry-over stays on: a case opened weeks ago is exactly the kind
    /// that has a connection today.
    static func casesRequest(_ department: AgendaDepartment, personID: String,
                             day: DateInterval, page: Int) -> (rpc: String, body: [String: Any]) {
        let from = isoMillis(day.start)
        let to = isoMillis(day.end.addingTimeInterval(-0.001))
        switch department {
        case .onboarding:
            return ("get_onboarding_board_cards_v1", [
                "p_date_from": from,
                "p_date_to": to,
                "p_include_open_carryover": true,
                "p_products": NSNull(),
                "p_search": NSNull(),
                "p_scope": "all",
                "p_responsible_person_id": personID,
                "p_unassigned_only": false,
                "p_include_scheduled_pre_release": true,
                "p_entry_from": NSNull(),
                "p_entry_to": NSNull(),
                "p_page": page,
                "p_page_size": 200,
            ])
        case .backoffice:
            return ("get_backoffice_cases", [
                "p_date_from": from,
                "p_date_to": to,
                "p_include_open_carryover": true,
                "p_status": "all",
                "p_department": "all",
                "p_pipeline_id": NSNull(),
                "p_products": NSNull(),
                "p_search": NSNull(),
                "p_scope": "all",
                "p_responsible_person_id": personID,
                "p_unassigned_only": false,
                "p_page": page,
                "p_page_size": 50,
                "p_entry_from": NSNull(),
                "p_entry_to": NSNull(),
            ])
        }
    }

    /// The page after `page`, or nil when that was the last.
    ///
    /// The Onboarding board says `has_more`; the Backoffice list only gives a
    /// total. Capped, so a server that keeps saying "more" cannot keep us
    /// paging forever.
    static func nextPage(after data: Data, page: Int) -> Int? {
        guard page < maxPages,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let more = object["has_more"] as? Bool { return more ? page + 1 : nil }
        guard let total = object["total_count"] as? Int,
              let size = object["page_size"] as? Int, size > 0
        else { return nil }
        return page * size < total ? page + 1 : nil
    }

    static let maxPages = 40

    // MARK: Who you are

    /// `person_id` out of `get_current_organization_context`. Nil for an
    /// account with no person behind it — a legacy admin — which has no
    /// agenda of its own.
    static func personID(fromOrganizationContext data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let object = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first
        guard let id = (object?["person_id"] as? String)?.trimmingCharacters(in: .whitespaces),
              !id.isEmpty
        else { return nil }
        return id
    }

    // MARK: Meetings

    /// Your meetings today out of one page of cases, from either list.
    ///
    /// Read loosely, field by field: a case the parser does not understand is
    /// skipped rather than taking the whole page down with it.
    static func meetings(fromCases data: Data, personID: String, day: DateInterval) -> [AgendaMeeting] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let cases = ((json as? [String: Any])?["data"] as? [[String: Any]])
            ?? (json as? [[String: Any]]) ?? []
        let me = personID.lowercased()

        var out: [AgendaMeeting] = []
        for item in cases {
            guard let caseID = item["id"] as? String,
                  let kanban = item["operational_meeting_kanban"] as? [String: Any],
                  let stages = kanban["stages"] as? [[String: Any]]
            else { continue }
            let customer = (item["customer_name"] as? String) ?? ""
            let code = publicID(customerName: customer, opportunityID: item["opportunity_id"] as? String)

            for stage in stages {
                guard let stageKey = stage["stageKey"] as? String else { continue }
                for meeting in meetingsOf(stage: stage) {
                    guard let meetingID = meeting["id"] as? String,
                          (meeting["responsiblePersonId"] as? String)?.lowercased() == me
                    else { continue }
                    let meetingState = (meeting["state"] as? String) ?? "open"
                    guard meetingState != "cancelled" else { continue }

                    for attempt in (meeting["attempts"] as? [[String: Any]]) ?? [] {
                        guard (attempt["isEffective"] as? Bool) == true,
                              let attemptID = attempt["id"] as? String,
                              (attempt["state"] as? String) != "cancelled",
                              attempt["cancelledAt"] == nil || attempt["cancelledAt"] is NSNull,
                              let startText = attempt["startAt"] as? String,
                              let start = date(fromISO: startText),
                              start >= day.start, start < day.end
                        else { continue }
                        let end = (attempt["endAt"] as? String).flatMap(date(fromISO:))
                            .flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(3600)
                        out.append(AgendaMeeting(
                            attemptID: attemptID,
                            meetingID: meetingID,
                            caseID: caseID,
                            department: AgendaDepartment(stageKey: stageKey),
                            stageKey: stageKey,
                            start: start,
                            end: end,
                            title: attendeeName(customerName: customer, publicID: code,
                                                displayName: meeting["displayAttendeeName"] as? String),
                            publicID: code,
                            attemptSequence: (attempt["sequence"] as? Int) ?? 1,
                            attemptState: (attempt["state"] as? String) ?? "",
                            meetingState: meetingState
                        ))
                    }
                }
            }
        }
        return merged([out])
    }

    /// A stage's meetings with their attempts. Canonical stages list them in
    /// `meetings`; a stage that has only ever had one keeps it in `meeting`,
    /// with the attempts beside it on the stage.
    private static func meetingsOf(stage: [String: Any]) -> [[String: Any]] {
        if let list = stage["meetings"] as? [[String: Any]], !list.isEmpty { return list }
        guard var single = stage["meeting"] as? [String: Any] else { return [] }
        if single["attempts"] == nil, let attempts = stage["attempts"] { single["attempts"] = attempts }
        return [single]
    }

    /// Several lists made into one: the same attempt read from both lists is
    /// one meeting, and the day reads in order.
    static func merged(_ lists: [[AgendaMeeting]]) -> [AgendaMeeting] {
        var seen = Set<String>()
        var out: [AgendaMeeting] = []
        for meeting in lists.joined() where seen.insert(meeting.attemptID).inserted {
            out.append(meeting)
        }
        return out.sorted {
            $0.start != $1.start ? $0.start < $1.start
                : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    // MARK: Titles

    private static let publicIDPattern = try! NSRegularExpression(
        pattern: #"(?:^|[^\p{L}\p{N}])((?:[A-Z][A-Z0-9]*-)?[A-Z]{2}\d{4})(?=$|[^\p{L}\p{N}])"#,
        options: [.caseInsensitive]
    )
    private static let wholePublicID = try! NSRegularExpression(
        pattern: #"^(?:[A-Z][A-Z0-9]*-)?[A-Z]{2}\d{4}$"#, options: [.caseInsensitive]
    )

    /// The case code the panel shows as a chip: an opportunity id that is one,
    /// or else the last code in the customer's name ("… Actuar GM3941").
    static func publicID(customerName: String, opportunityID: String?) -> String? {
        if let opportunity = opportunityID?.trimmingCharacters(in: .whitespaces), !opportunity.isEmpty,
           wholePublicID.firstMatch(in: opportunity, range: NSRange(opportunity.startIndex..., in: opportunity)) != nil {
            return opportunity.uppercased()
        }
        let text = customerName
        let matches = publicIDPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last, let range = Range(last.range(at: 1), in: text) else { return nil }
        return String(text[range]).uppercased()
    }

    /// The card's title: the attendee's display name when the meeting has one,
    /// else the customer's name without the code the chip already shows.
    /// Empty when there is no name at all; the view says so in words.
    static func attendeeName(customerName: String, publicID: String?, displayName: String?) -> String {
        if let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty {
            return display
        }
        let original = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let publicID, !publicID.isEmpty else { return original }
        let separators = #"[\s|·\-–,:]"#
        let escaped = NSRegularExpression.escapedPattern(for: publicID)
        var text = replace(#"\#(separators)*\#(escaped)\#(separators)*"#, in: original, with: " ",
                           caseInsensitive: true)
        text = replace(#"\s*[|·\-–,:]+$"#, in: text, with: "")
        text = replace(#"^[|·\-–,:]+\s*"#, in: text, with: "")
        text = replace(#"\s+"#, in: text, with: " ").trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? original : text
    }

    private static func replace(_ pattern: String, in text: String, with template: String,
                                caseInsensitive: Bool = false) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern,
                                                   options: caseInsensitive ? [.caseInsensitive] : [])
        else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                              withTemplate: template)
    }

    // MARK: Labels (English catalogue keys)

    /// The panel's names for its stages.
    static func stageLabel(_ stageKey: String) -> String {
        switch stageKey {
        case "contact":            return "Contact"
        case "connection":         return "1st connection"
        case "connection_2":       return "2nd connection"
        case "connection_3":       return "3rd connection"
        case "follow_up":          return "Follow-up"
        case "turnstile":          return "Turnstile setup"
        case "go_live_validation": return "Go-live validation"
        default:                   return stageKey
        }
    }

    static func attemptStateLabel(_ state: String) -> String? {
        switch state {
        case "confirmed": return "Confirmed"
        case "scheduled": return "Scheduled"
        case "pending":   return "Pending"
        default:          return nil
        }
    }

    // MARK: Time

    static func phase(of meeting: AgendaMeeting, now: Date) -> AgendaPhase {
        if meeting.isClosed { return .done }
        if now < meeting.start {
            return .upcoming(minutes: Int((meeting.start.timeIntervalSince(now) / 60).rounded(.up)))
        }
        return now < meeting.end ? .now : .ended
    }

    /// The meeting the list leads with: the one on now, else the next one.
    static func focus(_ meetings: [AgendaMeeting], now: Date) -> AgendaMeeting? {
        meetings.first {
            switch phase(of: $0, now: now) {
            case .upcoming, .now: return true
            default: return false
            }
        }
    }

    /// The next heads-up to give, and when.
    ///
    /// A meeting whose heads-up time has already gone by — Notchy was off, the
    /// Mac was asleep, it was booked ten minutes out — is announced at once,
    /// as long as it has not started.
    static func nextReminder(_ meetings: [AgendaMeeting], now: Date, lead: TimeInterval,
                             notified: Set<String>,
                             departments: Set<AgendaDepartment>) -> AgendaReminder? {
        meetings
            .filter {
                !$0.isClosed && $0.start > now
                    && departments.contains($0.department)
                    && !notified.contains($0.reminderKey)
            }
            .map { AgendaReminder(meeting: $0, fireAt: max($0.start.addingTimeInterval(-lead), now)) }
            .min {
                $0.fireAt != $1.fireAt ? $0.fireAt < $1.fireAt : $0.meeting.start < $1.meeting.start
            }
    }

    /// The local day `now` falls in.
    static func day(containing now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// "2026-11-19": what the remembered reminders are filed under, so they
    /// are forgotten when the day turns.
    static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static let leadChoices = [5, 10, 15, 30, 60]
    static let defaultLeadMinutes = 15

    // MARK: ISO 8601

    /// `2026-11-19T03:00:00.000Z` — the panel's window bounds, to the millisecond.
    static func isoMillis(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Postgres timestamps: `+00:00` offsets, and fractions of any length.
    static func date(fromISO raw: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if let dot = text.firstIndex(of: "."),
           let zone = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            var fraction = String(text[text.index(after: dot)..<zone].prefix(3))
            while fraction.count < 3 { fraction += "0" }
            text = String(text[..<dot]) + "." + fraction + String(text[zone...])
        }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
