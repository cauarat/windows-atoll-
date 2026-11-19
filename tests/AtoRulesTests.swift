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
                      preview: String? = "Oi", workspace: String = workspace,
                      senderId: String = "6b31de8c-a7f2-4789-a3f2-3956090a830e") -> AtoConversationUpdate {
        var object: [String: Any] = [
            "conversationId": "052278c9-80c1-4b5c-8b16-35ad0966cb14",
            "number": 323,
            "workspaceId": workspace,
            "contactId": "6b31de8c-a7f2-4789-a3f2-3956090a830e",
            "channelType": 2,
            "statusType": status,
            "lastMessageOnUtc": at,
            "lastMessageSenderType": sender,
            "lastMessageSenderId": senderId,
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

        print("Ato — a conversation you are answering")
        // #323 on 2026-11-16: unassigned, in Sistema, and answered by you.
        let answering: Set<String> = ["052278c9-80c1-4b5c-8b16-35ad0966cb14"]
        check("the customer writing back after your reply, unassigned in another queue",
              AtoRules.shouldNotify(frame(queue: otherQueue), memberships: memberships,
                                    engaged: answering) ? "notify" : "quiet", "notify")
        check("the same conversation without your reply stays quiet",
              notifies(frame(queue: otherQueue)), "quiet")
        check("a colleague taking it wins over your reply",
              AtoRules.shouldNotify(frame(assigned: colleague, queue: otherQueue), memberships: memberships,
                                    engaged: answering) ? "notify" : "quiet", "quiet")
        check("your own reply engages you",
              "\(AtoRules.engagement(after: frame(queue: otherQueue, sender: 2, senderId: me), memberships: memberships))",
              "engage")
        check("a colleague's reply does not",
              "\(AtoRules.engagement(after: frame(queue: otherQueue, sender: 2, senderId: colleague), memberships: memberships))",
              "keep")
        check("a colleague being assigned releases you",
              "\(AtoRules.engagement(after: frame(assigned: colleague), memberships: memberships))", "release")
        check("closing releases you",
              "\(AtoRules.engagement(after: frame(status: 4), memberships: memberships))", "release")
        check("the customer writing changes nothing",
              "\(AtoRules.engagement(after: frame(queue: otherQueue), memberships: memberships))", "keep")
        func lookup(_ u: AtoConversationUpdate, engaged: Set<String> = [], checked: Set<String> = []) -> String {
            AtoRules.needsAnswererLookup(u, memberships: memberships, engaged: engaged, checked: checked) ? "ask" : "skip"
        }
        let c323: Set<String> = ["052278c9-80c1-4b5c-8b16-35ad0966cb14"]
        check("an unclaimed customer message outside your queues is worth asking about",
              lookup(frame(queue: otherQueue)), "ask")
        check("not once it has been asked", lookup(frame(queue: otherQueue), checked: c323), "skip")
        check("not when it is already yours", lookup(frame(queue: otherQueue), engaged: c323), "skip")
        check("not in your own queue", lookup(frame(queue: myQueue)), "skip")
        check("not when someone is assigned", lookup(frame(assigned: colleague)), "skip")
        check("not for the bot or an agent", lookup(frame(queue: otherQueue, sender: 3)), "skip")
        check("not when it is closed", lookup(frame(status: 4, queue: otherQueue)), "skip")
        let old = Date(timeIntervalSinceNow: -8 * 24 * 3600), fresh = Date(timeIntervalSinceNow: -3600)
        check("a week without a reply forgets it",
              AtoRules.pruned(["a": old, "b": fresh]).keys.sorted().joined(), "b")

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

        print("Ato — voice messages")
        check("[anexo] stands in for a file", AtoRules.isAttachmentPreview("[anexo]") ? "file" : "words", "file")
        check("so does no preview at all", AtoRules.isAttachmentPreview(nil) ? "file" : "words", "file")
        check("words are words", AtoRules.isAttachmentPreview("Oi, tudo bem?") ? "file" : "words", "words")
        check("a sentence in brackets is still words",
              AtoRules.isAttachmentPreview("[urgente] o sistema caiu e ninguém consegue entrar") ? "file" : "words",
              "words")
        check("the lookup is the newest customer message, with its files",
              AtoRules.latestCustomerMessageQuery(conversationID: "052278c9")
                  .map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"),
              "$filter=ConversationId eq 052278c9 and SenderType eq 'Customer'"
                  + "&$orderby=AddedOnUtc desc&$top=1&$expand=Attachments")
        check("audio/ogg is audio", AtoRules.isAudio(contentType: "audio/ogg; codecs=opus", fileName: "x") ? "audio" : "not", "audio")
        check("an image is not", AtoRules.isAudio(contentType: "image/jpeg", fileName: "a.ogg") ? "audio" : "not", "not")
        check("octet-stream goes by the name",
              AtoRules.isAudio(contentType: "application/octet-stream", fileName: "PTT-2026.opus") ? "audio" : "not", "audio")
        check("no type goes by the name", AtoRules.isAudio(contentType: nil, fileName: "voz.mp3") ? "audio" : "not", "audio")
        check("a pdf with no type is not", AtoRules.isAudio(contentType: nil, fileName: "nota.pdf") ? "audio" : "not", "not")

        // The OData shape the console reads, enums spelled out.
        let page = Data(#"""
        {"value":[{"MessageId":"m1","Body":null,"AddedOnUtc":"2026-11-19T12:00:00Z","Attachments":[
          {"MessageAttachmentId":"a0","FileName":"foto.jpg","ContentType":"image/jpeg","StorageFileId":"s0"},
          {"MessageAttachmentId":"a1","FileName":"audio.ogg","ContentType":"audio/ogg","SizeBytes":5120,
           "StorageFileId":"s1","DurationSeconds":12.4,"TranscriptionStatusType":"Completed",
           "TranscriptText":"  Oi, meu acesso não abre  ","TranscriptionFailureReason":null}]}]}
        """#.utf8)
        let row = AtoRules.firstMessage(inPage: page)
        let note = row.flatMap(AtoRules.voiceNote(in:))
        check("the voice note is the audio file, not the photo", note?.storageFileID ?? "nil", "s1")
        check("its transcript is the trimmed text", note?.transcript.text ?? "nil", "Oi, meu acesso não abre")
        check("its length comes along", note?.duration.map { String($0) } ?? "nil", "12.4")
        check("a message with no audio has no voice note",
              AtoRules.voiceNote(in: AtoMessageRow(MessageId: "m", Body: "x", AddedOnUtc: nil, Attachments: [])) == nil
                  ? "nil" : "note", "nil")

        func status(_ json: String) -> String {
            let file = try! JSONDecoder().decode(AtoMessageAttachment.self, from: Data(json.utf8))
            switch AtoRules.transcript(status: file.TranscriptionStatusType, text: file.TranscriptText) {
            case .none: return "none"
            case .pending: return "pending"
            case .ready(let text): return "ready:\(text)"
            case .failed: return "failed"
            case .skipped: return "skipped"
            }
        }
        check("the hub's number reads the same as OData's name",
              status(#"{"TranscriptionStatusType":2,"TranscriptText":"oi"}"#), "ready:oi")
        check("pending is pending", status(#"{"TranscriptionStatusType":"Pending"}"#), "pending")
        check("a completed transcript with no words is none",
              status(#"{"TranscriptionStatusType":"Completed","TranscriptText":"  "}"#), "none")
        check("an unknown status is none", status(#"{"TranscriptionStatusType":"Later"}"#), "none")
        check("transcription off is none", status(#"{"TranscriptionStatusType":null}"#), "none")

        let pending = InboxAudio(attachmentID: "A1", storageFileID: "s1", fileName: "audio.ogg",
                                 contentType: "audio/ogg", duration: nil, transcript: .pending)
        let event = try! JSONDecoder().decode(AtoMessageTranscribed.self, from: Data(#"""
        {"conversationId":"c","messageId":"m1","messageAttachmentId":"a1",
         "transcriptionStatusType":2,"transcriptText":"Pode me ligar?","durationSeconds":7}
        """#.utf8))
        let applied = AtoRules.applying(event, to: pending)
        check("a transcript event lands on its attachment, whatever the case of the id",
              applied?.transcript.text ?? "nil", "Pode me ligar?")
        check("and brings the length", applied?.duration.map { String($0) } ?? "nil", "7.0")
        let other = InboxAudio(attachmentID: "a2", storageFileID: "s2", fileName: "", contentType: "",
                               duration: nil, transcript: .pending)
        check("but not on another one", AtoRules.applying(event, to: other) == nil ? "nil" : "applied", "nil")

        check("the storage service answers where the file is",
              AtoRules.objectURL(fromStorageObject: Data(#"{"Url":"https://cdn.example/x.ogg?sig=1"}"#.utf8))?
                  .absoluteString ?? "nil", "https://cdn.example/x.ogg?sig=1")
        check("an answer without a url has none",
              AtoRules.objectURL(fromStorageObject: Data(#"{"Url":null}"#.utf8)) == nil ? "nil" : "url", "nil")
        check("nor one that is not a web address",
              AtoRules.objectURL(fromStorageObject: Data(#"{"Url":"file:///etc/passwd"}"#.utf8)) == nil ? "nil" : "url",
              "nil")
        // payload {"TenantId":"t-1","exp":1}
        check("the tenant comes from the token when it says",
              AtoRules.tenantID(ofJWT: "x." + "eyJUZW5hbnRJZCI6InQtMSIsImV4cCI6MX0" + ".s") ?? "nil", "t-1")
        check("and is nil when it does not", AtoRules.tenantID(ofJWT: jwt) ?? "nil", "nil")

        print("Ato — SignalR records")
        check("a frame splits on the record separator",
              SignalRConnection.records(in: "{}\u{1E}{\"type\":6}\u{1E}").joined(separator: "|"),
              "{}|{\"type\":6}")

        print("")
        if failures == 0 { print("All Ato tests passed.") }
        else { print("\(failures) failure(s)."); exit(1) }
    }
}
