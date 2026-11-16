import Foundation

/// What the WhatsApp Web bridge (`shared/whatsapp-bridge.js`) sends, read back.
///
/// The payloads are the shapes `post(...)` builds in the bridge, as they arrive
/// through `WKScriptMessage.body`: dictionaries of strings and NSNumbers.
@main
enum WhatsAppRulesTests {
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

    static func describe(_ event: WhatsAppRules.Event?) -> String {
        guard let event else { return "nil" }
        switch event {
        case .message(let m):
            return "message \(m.key) \(m.chat) | \(m.body) @\(Int(m.timestamp.timeIntervalSince1970))"
        case .state(let s): return "state \(s.rawValue)"
        case .sent(let id): return "sent \(id ?? "-")"
        case .sendFailed(let id, let reason): return "sendFailed \(id ?? "-") \(reason)"
        }
    }

    static func main() {
        print("Events from the bridge")

        check("a message reads back whole",
              describe(WhatsAppRules.event(from: [
                  "type": "message", "key": "nabc-1", "chat": "Maria",
                  "body": "Oi, tudo bem?", "tag": NSNull(), "ts": NSNumber(value: 1_763_200_000_000.0),
              ] as [String: Any])),
              "message nabc-1 Maria | Oi, tudo bem? @1763200000")
        check("a message with no key is not a message",
              describe(WhatsAppRules.event(from: ["type": "message", "chat": "Maria", "body": "x"])),
              "nil")
        check("nor one with no conversation",
              describe(WhatsAppRules.event(from: ["type": "message", "key": "k", "chat": "  ", "body": "x"])),
              "nil")
        check("the QR state",
              describe(WhatsAppRules.event(from: ["type": "state", "state": "qr"])), "state qr")
        check("signed in",
              describe(WhatsAppRules.event(from: ["type": "state", "state": "connected"])), "state connected")
        check("an unknown state is ignored, not guessed",
              describe(WhatsAppRules.event(from: ["type": "state", "state": "banned"])), "nil")
        check("a reply that went",
              describe(WhatsAppRules.event(from: ["type": "sent", "requestId": "r1"])), "sent r1")
        check("a reply that did not, with why",
              describe(WhatsAppRules.event(from: ["type": "sendFailed", "requestId": "r2",
                                                  "reason": "could not open Maria"])),
              "sendFailed r2 could not open Maria")
        check("something that is not ours",
              describe(WhatsAppRules.event(from: ["hello": "world"])), "nil")
        check("not even a dictionary",
              describe(WhatsAppRules.event(from: "message")), "nil")

        print("What the card says")

        check("a name outside the contacts loses its tilde",
              WhatsAppRules.displayName("~cato") ?? "nil", "cato")
        check("a number stays a number",
              WhatsAppRules.displayName(" +55 11 98888-7777 ") ?? "nil", "+55 11 98888-7777")
        check("a blank name is no name", WhatsAppRules.displayName(" ~ ") ?? "nil", "nil")
        check("a caption-less photo has no body", WhatsAppRules.body("  ") ?? "nil", "nil")
        check("a group's notification keeps who said it",
              WhatsAppRules.body("João: chego às 10") ?? "nil", "João: chego às 10")
        check("WhatsApp's own summary is not a conversation",
              "\(WhatsAppRules.isSummary(chat: "WhatsApp"))", "true")
        check("a person called WhatsApp Suporte is",
              "\(WhatsAppRules.isSummary(chat: "WhatsApp Suporte"))", "false")

        print("Ids carry the key a reply needs")

        let id = WhatsAppRules.messageID(key: "nabc-1")
        check("the id", id, "whatsapp:nabc-1")
        check("and back", WhatsAppRules.key(fromMessageID: id) ?? "nil", "nabc-1")
        check("another source's id has no key",
              WhatsAppRules.key(fromMessageID: "ato:123") ?? "nil", "nil")
        check("an empty key is none", WhatsAppRules.key(fromMessageID: "whatsapp:") ?? "nil", "nil")

        print("Where the hidden page may go")

        let keeps: (String) -> String = { "\(WhatsAppRules.keepsInWebView(URL(string: $0)))" }
        check("WhatsApp Web", keeps("https://web.whatsapp.com/"), "true")
        check("its media hosts", keeps("https://mmg.whatsapp.net/v/t62/abc"), "true")
        check("whatsapp.com itself", keeps("https://www.whatsapp.com/download"), "true")
        check("not plain http", keeps("http://web.whatsapp.com/"), "false")
        check("not a lookalike", keeps("https://web.whatsapp.com.evil.net/"), "false")
        check("not a suffix trick", keeps("https://notwhatsapp.com/"), "false")
        check("not a link in a message", keeps("https://example.com/"), "false")
        check("blob URLs the page makes for media", keeps("blob:https://web.whatsapp.com/1234"), "true")
        check("about:blank", keeps("about:blank"), "true")

        print("")
        if failures == 0 { print("All WhatsApp rules tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }
}
