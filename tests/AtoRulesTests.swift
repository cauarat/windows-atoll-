import Foundation

/// Which Ato updates reach the notch.
///
/// The frames below were captured off the real `SupportHub` on 2026-11-15,
/// during one test conversation (#323): a customer writing in, the bot
/// answering, the customer picking a queue, the AI's internal summary, and
/// the out-of-hours reply. Ids are the real shapes; the contact's name and
/// number are not in them. Get this rule wrong and the notch is either silent
/// or shows the whole company's WhatsApp.
@main
enum AtoRulesTests {
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

    static let workspace = "019fcd42-9db6-7e62-88b1-ffa24983e487"
    static let me = "01a17db4-ee0d-7819-b69a-0569e6ab2c67"
    static let myQueue = "01a1d1ba-c280-73ae-b633-e87c4460c83d"      // Backoffice
    static let otherQueue = "01a1d1bb-0619-7fee-928a-8d114ad49c8e"   // Sistema
    static let colleague = "01a17db4-f2ee-7929-88e7-d5fc396a50bd"

    static let memberships = [
        AtoMembership(AgentId: me, WorkspaceId: workspace, WorkspaceName: "Atendimento WhatsApp",
                      DisplayName: "Caua Toledo", QueueIds: [myQueue]),
    ]

    /// An `onConversationUpdated` argument, trimmed to the fields that decide.
    static func frame(status: Int = 1, assigned: String? = nil, queue: String? = nil,
                      sender: Int = 1, at: String = "2026-11-15T19:33:53Z",
                      preview: String? = "Oi", workspace: String = workspace) -> AtoConversationUpdate {
        var object: [String: Any] = [
            "conversationId": "052278c9-80c1-4b5c-8b16-35ad0966cb14",
            "number": 323,
            "workspaceId": workspace,
            "contactId": "6b31de8c-a7f2-4789-a3f2-3956090a830e",
            "channelType": 2,
            "statusType": status,
            "lastMessageOnUtc": at,
            "lastMessageSenderType": sender,
            "lastMessageSenderId": "6b31de8c-a7f2-4789-a3f2-3956090a830e",
            // Fields the client does not read, present as they are on the wire.
            "unansweredCount": 82, "inAutomation": false, "windowIsOpen": true,
            "validationResult": ["isValid": true, "errors": []],
        ]
        object["assignedToAgentId"] = assigned ?? NSNull()
        object["queueId"] = queue ?? NSNull()
        object["lastMessagePreview"] = preview ?? NSNull()
        let data = try! JSONSerialization.data(withJSONObject: object)
        return try! JSONDecoder().decode(AtoConversationUpdate.self, from: data)
    }

    static func notifies(_ update: AtoConversationUpdate) -> String {
        AtoRules.shouldNotify(update, memberships: memberships) ? "notify" : "quiet"
    }

    static func main() {
        print("Ato — which messages are yours")

        check("a customer on a conversation assigned to you",
              notifies(frame(assigned: me, queue: otherQueue)), "notify")
        check("a customer waiting unassigned in your queue",
              notifies(frame(queue: myQueue)), "notify")
        check("a customer waiting in someone else's queue (the captured #323)",
              notifies(frame(queue: otherQueue)), "quiet")
        check("a customer on a colleague's conversation, even in your queue",
              notifies(frame(assigned: colleague, queue: myQueue)), "quiet")
        check("a customer still in the bot's triage, no queue yet",
              notifies(frame(queue: nil)), "quiet")
        check("ids compare without regard to case",
              notifies(frame(assigned: me.uppercased())), "notify")

        print("Ato — who spoke last")
        check("the bot (System) answering in your queue",
              notifies(frame(queue: myQueue, sender: 3)), "quiet")
        check("you or a colleague (Agent)",
              notifies(frame(assigned: me, sender: 2)), "quiet")
        check("the AI's internal note",
              notifies(frame(assigned: me, sender: 4)), "quiet")

        print("Ato — conversations that are over, or not ours")
        check("closed", notifies(frame(status: 4, assigned: me)), "quiet")
        check("archived", notifies(frame(status: 5, assigned: me)), "quiet")
        check("waiting on the agent is still open",
              notifies(frame(status: 3, assigned: me)), "notify")
        check("another workspace entirely",
              notifies(frame(assigned: me, workspace: "11111111-1111-1111-1111-111111111111")), "quiet")
        check("nobody signed in means nothing is mine",
              AtoRules.shouldNotify(frame(assigned: me), memberships: []) ? "notify" : "quiet", "quiet")

        print("Ato — one card per message")
        check("repeats of the same message share an id",
              AtoRules.messageID(frame(queue: myQueue)) == AtoRules.messageID(frame(assigned: me))
                  ? "same" : "different", "same")
        check("the next message gets its own",
              AtoRules.messageID(frame(at: "2026-11-15T19:33:53Z"))
                  == AtoRules.messageID(frame(at: "2026-11-15T19:40:00Z")) ? "same" : "different",
              "different")

        print("Ato — what the card says")
        check("the preview is the text", AtoRules.body(frame(preview: "  Oi  ")) ?? "nil", "Oi")
        check("no preview means a file", AtoRules.body(frame(preview: nil)) ?? "nil", "nil")
        check("WhatsApp's tilde is dropped", AtoRules.displayName("~cato") ?? "nil", "cato")
        check("a blank name is no name", AtoRules.displayName(" ~ ") ?? "nil", "nil")
        check(".NET's seven fractional digits still parse",
              AtoRules.date("2026-11-15T19:33:54.8855382Z").map { String(Int($0.timeIntervalSince1970)) } ?? "nil",
              "1794771234")
        check("whole seconds parse too",
              AtoRules.date("2026-11-15T19:33:53Z").map { String(Int($0.timeIntervalSince1970)) } ?? "nil",
              "1794771233")

        print("Ato — tokens and addresses")
        // header.payload.signature, payload {"exp":1794778000}
        let jwt = "eyJhbGciOiJIUzI1NiJ9." + "eyJleHAiOjE3OTQ3NzgwMDB9" + ".sig"
        check("a token's expiry comes from its exp claim",
              AtoRules.expiry(ofJWT: jwt).map { String(Int($0.timeIntervalSince1970)) } ?? "nil",
              "1794778000")
        check("something that is not a JWT has none", AtoRules.expiry(ofJWT: "opaque") == nil ? "nil" : "date", "nil")
        check("the hub carries the token in the query",
              AtoEndpoints.hubURL(token: "abc")?.absoluteString ?? "nil",
              "wss://supportservice-api.prd.o.actuar.cloud/SupportHub?access_token=abc")
        check("a conversation opens in the console",
              AtoEndpoints.conversationLink("052278c9").absoluteString,
              "https://novo.actuar.com/support/workspace?conversation=052278c9")

        print("Ato — sending a file, the console's way")
        check("an upload answers the id a message names",
              AtoRules.storageObjectID(fromUpload: Data(#"{"StorageObjectId":"0f3c-9a","Url":null}"#.utf8)) ?? "nil",
              "0f3c-9a")
        check("an upload that answers no id has failed",
              AtoRules.storageObjectID(fromUpload: Data(#"{"StorageObjectId":""}"#.utf8)) ?? "nil", "nil")
        check("nor does one that answers something else",
              AtoRules.storageObjectID(fromUpload: Data("<html>".utf8)) ?? "nil", "nil")
        let entry = AtoRules.attachment(storageFileID: "0f3c-9a", fileName: "Voice message.m4a",
                                        contentType: "audio/mp4", sizeBytes: 4096)
        check("the attachment entry carries the four fields the console posts",
              entry.keys.sorted().joined(separator: ","),
              "ContentType,FileName,SizeBytes,StorageFileId")
        check("the upload goes to the chat folder",
              AtoEndpoints.storageService.appendingPathComponent("FileUpload/Upload").absoluteString
                  + "?folder=" + AtoEndpoints.chatUploadFolder,
              "https://storageservice-api.prd.o.actuar.cloud/FileUpload/Upload?folder=19")

        print("Ato — SignalR records")
        check("a frame splits on the record separator",
              SignalRConnection.records(in: "{}\u{1E}{\"type\":6}\u{1E}").joined(separator: "|"),
              "{}|{\"type\":6}")

        print("")
        if failures == 0 { print("All Ato tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }
}
