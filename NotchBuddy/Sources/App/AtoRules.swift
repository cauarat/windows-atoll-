//
//  AtoRules.swift
//  Notchy
//
//  What Ato sends, and which of it deserves the notch. Pure, so
//  scripts/test-ato-rules.sh can hold it to frames captured off the real hub.
//

import Foundation

// MARK: - Addresses

/// Where Ato lives. Fixed rather than typed in: Ato is one Actuar product,
/// not a panel each customer hosts, and these are the hosts the
/// novo.actuar.com console itself is built against.
enum AtoEndpoints {
    /// Sign-in and token refresh.
    static let userService = URL(string: "https://userservice-api.prd.o.actuar.cloud")!
    /// The inbox: agents, conversations, messages, and the `SupportHub`.
    static let supportService = URL(string: "https://supportservice-api.prd.o.actuar.cloud")!
    /// Where a file goes before a message can carry it: `FileUpload/Upload`
    /// answers a `StorageObjectId`, and the message names it.
    static let storageService = URL(string: "https://storageservice-api.prd.o.actuar.cloud")!
    /// The storage folder the agent console uploads chat files to — the
    /// `Chat` case of its folder enum.
    static let chatUploadFolder = "19"
    /// The console refuses a file over 25 MB before uploading it; so does this.
    static let maxUploadBytes = 26_214_400
    /// The console people actually open.
    static let app = URL(string: "https://novo.actuar.com")!
    /// The page the sign-in requests come from, for `Origin`/`Referer`.
    static let accounts = URL(string: "https://accounts.actuar.com")!

    /// `wss://…/SupportHub?access_token=…` — the console's own route, with the
    /// token in the query because a WebSocket cannot carry headers.
    static func hubURL(token: String) -> URL? {
        guard var components = URLComponents(url: supportService, resolvingAgainstBaseURL: false)
        else { return nil }
        components.scheme = "wss"
        components.path = "/SupportHub"
        components.queryItems = [URLQueryItem(name: "access_token", value: token)]
        return components.url
    }

    /// The console, opened on one conversation.
    static func conversationLink(_ conversationID: String?) -> URL {
        var components = URLComponents(url: app, resolvingAgainstBaseURL: false)!
        components.path = "/support/workspace"
        if let conversationID, !conversationID.isEmpty {
            components.queryItems = [URLQueryItem(name: "conversation", value: conversationID)]
        }
        return components.url!
    }
}

// MARK: - Wire format

/// Ato's enums arrive as numbers on the hub. Values read off the console's
/// own definitions (`It`, `St` in its bundle), not guessed.
enum AtoSenderType: Int {
    case customer = 1, agent = 2, system = 3, ai = 4
}

enum AtoStatusType: Int {
    case open = 1, waitingCustomer = 2, waitingAgent = 3, closed = 4, archived = 5
}

/// The `onConversationUpdated` payload — the event that carries a customer's
/// message to everyone in the workspace.
///
/// Not `onMessagePosted`: that one only reaches connections that have joined
/// the conversation, which is what the console does when you open one. A
/// listener that has joined nothing sees a customer write only as this
/// update, with the text in `lastMessagePreview`. That is also the event the
/// console itself rings its bell on.
struct AtoConversationUpdate: Decodable, Equatable {
    let conversationId: String
    let number: Int?
    let workspaceId: String?
    let contactId: String?
    let channelType: Int?
    let statusType: Int?
    /// Nil while nobody has picked the conversation up.
    let assignedToAgentId: String?
    let queueId: String?
    let lastMessageOnUtc: String?
    let lastMessagePreview: String?
    let lastMessageSenderType: Int?
    let lastMessageSenderId: String?
}

/// The `onMentionCreated` payload: a colleague named you in an internal note.
///
/// Reaches every agent in the workspace — the console rings its bell only
/// when `mentionedAgentId` is its own, and so does this. Every field is
/// optional: the shape is read off what the console uses, not captured, and a
/// mention that does not say whom it is for is nobody's.
struct AtoMentionCreated: Decodable, Equatable {
    let conversationId: String?
    let workspaceId: String?
    let mentionedAgentId: String?
    let messageId: String?
    let messageMentionId: String?
}

/// The `onNotificationCreated` / `onNotificationUpdated` payload: one entry
/// of an agent's own bell — an assignment, a Reclame AQUI case, a reminder.
struct AtoNotificationEvent: Decodable, Equatable {
    let notificationId: String?
    let workspaceId: String?
    let agentId: String?
    let type: Int?
    let conversationId: String?
    let detailsJson: String?
    let lastEventOnUtc: String?
}

/// The `onConversationFollowersChanged` payload: who follows a conversation
/// now — the whole list, not the change.
struct AtoFollowersChanged: Decodable, Equatable {
    struct Follower: Decodable, Equatable { let agentId: String? }
    let conversationId: String?
    let followers: [Follower]?
}

/// The lists the console's inbox splits conversations into — the ones a
/// person can choose to be told about. Raw values are what is stored, on both
/// platforms: never rename one.
enum AtoInboxView: String, CaseIterable, Sendable {
    /// Minha caixa: assigned to you — and, here, the unassigned ones you
    /// have been answering.
    case mine
    /// Pendentes: nobody's yet, waiting in a team you are in. Everyone in
    /// that team sees the same ones.
    case pending
    /// Menções: a colleague named you in an internal note.
    case mentions
    /// Reclame AQUI: the bell's complaint notices addressed to you.
    case reclameAqui
    /// Acompanhando (under Mais visões): conversations you follow, whoever
    /// has them.
    case following

    /// What someone who never chose gets: what is theirs, not their team's.
    static let defaults: Set<AtoInboxView> = [.mine, .mentions]
}

/// One row of `OData/MessageMentions?$expand=Message` — the note a mention
/// was made in, and who wrote it.
struct AtoMentionRow: Decodable {
    struct Note: Decodable { let Body: String?; let SenderId: String? }
    struct Conversation: Decodable { let ContactId: String? }
    let MessageMentionId: String?
    let MessageId: String?
    let Message: Note?
    let Conversation: Conversation?
}

/// A Reclame AQUI notice off the bell, ready to word.
struct AtoComplaintNotice: Equatable {
    /// The console's `NotificationType`s for a complaint, the ones its own
    /// alert rings for. 22 (nobody can take a case) is an admin's problem
    /// and 18 (backlog import) is history, so neither is here.
    enum Kind: Int, Equatable {
        case new = 17
        case returnedToTriage = 19
        case deadlineAtRisk = 20
        case deadlineLate = 21
        case consumerReplied = 23
    }

    let kind: Kind
    let conversationID: String
    /// The case's number on Reclame AQUI itself, when the notice says.
    let externalID: String?
}

/// One row of `GET /Agents/me`: who you are in one workspace.
struct AtoMembership: Decodable, Equatable {
    let AgentId: String
    let WorkspaceId: String
    let WorkspaceName: String?
    let DisplayName: String?
    let QueueIds: [String]?
}

/// One message off `OData/Messages?$expand=Attachments` — the console's own
/// thread query, trimmed to what a card needs.
struct AtoMessageRow: Decodable {
    let MessageId: String?
    let Body: String?
    let AddedOnUtc: String?
    let Attachments: [AtoMessageAttachment]?
}

/// One file on a message. The transcript fields are the console's: it shows
/// the text only when the status is `Completed`.
struct AtoMessageAttachment: Decodable {
    let MessageAttachmentId: String?
    let FileName: String?
    let ContentType: String?
    let SizeBytes: Int?
    let StorageFileId: String?
    let DurationSeconds: Double?
    let TranscriptionStatusType: AtoTranscriptionStatus?
    let TranscriptText: String?
    let TranscriptionFailureReason: String?
}

/// The `onMessageTranscribed` payload: one attachment's transcript, landing
/// after the message that carried it.
struct AtoMessageTranscribed: Decodable {
    let conversationId: String?
    let messageId: String?
    let messageAttachmentId: String?
    let transcriptionStatusType: AtoTranscriptionStatus?
    let transcriptText: String?
    let durationSeconds: Double?
}

/// `TranscriptionStatusType`. OData spells enums out (`"Completed"`), the
/// hub sends their numbers — the console reads both, and so does this.
/// Values from the console's own table: None 0, Pending 1, Completed 2,
/// Failed 3, Skipped 4.
enum AtoTranscriptionStatus: Int, Decodable {
    case none = 0, pending = 1, completed = 2, failed = 3, skipped = 4

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            self = AtoTranscriptionStatus(rawValue: number) ?? .none
        } else if let name = try? container.decode(String.self) {
            switch name.lowercased() {
            case "pending":   self = .pending
            case "completed": self = .completed
            case "failed":    self = .failed
            case "skipped":   self = .skipped
            default:          self = .none
            }
        } else {
            self = .none
        }
    }
}

/// What `/Auth/Login` and `/Auth/Refresh` answer with.
struct AtoAuthorization: Decodable {
    let Token: String?
    let TokenId: String?
    let PersonId: String?
    let TenantId: String?
    let IsValid: Bool?
}

// MARK: - Rules

enum AtoRules {
    /// The `StorageObjectId` an upload answered, or nil when it answered none.
    /// The console treats a missing one as a failed upload; so does this.
    static func storageObjectID(fromUpload data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["StorageObjectId"] as? String,
              !id.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return id
    }

    /// One entry of a message's `Attachments`, as the console posts it.
    static func attachment(storageFileID: String, fileName: String,
                           contentType: String, sizeBytes: Int) -> [String: Any] {
        ["StorageFileId": storageFileID, "FileName": fileName,
         "ContentType": contentType, "SizeBytes": sizeBytes]
    }

    /// Whether an update is a customer's new message that belongs to you.
    ///
    /// The hub streams the whole workspace — every conversation, every agent,
    /// and the bot talking to customers before anyone is assigned. Notifying
    /// on all of it would open the notch for the whole company's WhatsApp. So,
    /// the same rule the console uses for its own alerts and the same one
    /// Notchy applied to ClickMassa before it:
    ///
    /// - the customer spoke last (not you, a colleague, the bot or the AI);
    /// - the conversation is still open;
    /// - and it is yours: assigned to you, unassigned and waiting in one of
    ///   your queues, or unassigned and one you have been answering — see
    ///   ``engagement(after:memberships:)``.
    ///
    /// That last way in is the one Ato's own rule lacks, and its absence is
    /// what made the notch go quiet on a live conversation. Each time a
    /// customer writes after a pause the bot triages them again, files the
    /// conversation into whichever queue they pick and leaves it unassigned —
    /// so an agent can be in the middle of answering someone whose
    /// conversation is, by Ato's books, nobody's and in a queue they are not
    /// in. Being the last agent who replied is what "yours" means then.
    ///
    /// Which of those ways counts is the person's choice (`enabled`): the
    /// queue is the team's, and a team of ten does not all want the bell for
    /// each other's customers. Left out, every way counts.
    static func shouldNotify(_ update: AtoConversationUpdate,
                             memberships: [AtoMembership],
                             engaged: Set<String> = [],
                             following: Set<String> = [],
                             enabled: Set<AtoInboxView> = Set(AtoInboxView.allCases)) -> Bool {
        !views(of: update, memberships: memberships, engaged: engaged, following: following)
            .isDisjoint(with: enabled)
    }

    /// The inbox lists a customer's new message lands in, as the console
    /// files them (its `$filter` per view): empty when it is not a customer's
    /// message, the conversation is over, or none of it is yours.
    ///
    /// Only the conversation lists — a mention and a Reclame AQUI notice come
    /// on events of their own.
    static func views(of update: AtoConversationUpdate,
                      memberships: [AtoMembership],
                      engaged: Set<String> = [],
                      following: Set<String> = []) -> Set<AtoInboxView> {
        guard update.lastMessageSenderType == AtoSenderType.customer.rawValue else { return [] }

        if let status = update.statusType.flatMap(AtoStatusType.init(rawValue:)),
           status == .closed || status == .archived {
            return []
        }

        // Without knowing who we are there is no "mine", and notifying on
        // everything would be worse than notifying on nothing.
        guard let workspace = update.workspaceId?.lowercased(),
              let membership = memberships.first(where: { $0.WorkspaceId.lowercased() == workspace })
        else { return [] }

        let key = update.conversationId.lowercased()
        var views: Set<AtoInboxView> = following.contains(key) ? [.following] : []

        if let assigned = update.assignedToAgentId {
            if assigned.lowercased() == membership.AgentId.lowercased() { views.insert(.mine) }
            return views
        }

        if let queue = update.queueId?.lowercased(),
           (membership.QueueIds ?? []).contains(where: { $0.lowercased() == queue }) {
            views.insert(.pending)
        }
        if engaged.contains(key) { views.insert(.mine) }
        return views
    }

    // MARK: Mentions, complaints, followers

    /// Whether a mention names you — in the workspace it was made in, when
    /// it says which.
    static func isForMe(_ mention: AtoMentionCreated, memberships: [AtoMembership]) -> Bool {
        guard let agent = mention.mentionedAgentId?.lowercased(), !agent.isEmpty,
              let conversation = mention.conversationId, !conversation.isEmpty
        else { return false }
        return memberships.contains { membership in
            membership.AgentId.lowercased() == agent
                && (mention.workspaceId.map { $0.lowercased() == membership.WorkspaceId.lowercased() } ?? true)
        }
    }

    /// The complaint notice in a bell entry addressed to you, or nil — for
    /// someone else's bell, for any other kind of entry, or one that names no
    /// conversation to open.
    static func complaintNotice(_ event: AtoNotificationEvent,
                                memberships: [AtoMembership]) -> AtoComplaintNotice? {
        guard let kind = event.type.flatMap(AtoComplaintNotice.Kind.init(rawValue:)),
              let agent = event.agentId?.lowercased(),
              let conversation = event.conversationId, !conversation.isEmpty,
              memberships.contains(where: { membership in
                  membership.AgentId.lowercased() == agent
                      && (event.workspaceId.map { $0.lowercased() == membership.WorkspaceId.lowercased() } ?? true)
              })
        else { return nil }
        return AtoComplaintNotice(kind: kind, conversationID: conversation,
                                  externalID: externalID(inDetails: event.detailsJson))
    }

    /// `detailsJson.externalId` — the case's number on Reclame AQUI, which
    /// the console shows as "RA 12345". A number or a string, as it comes.
    static func externalID(inDetails json: String?) -> String? {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let value = object["externalId"] ?? object["ExternalId"]
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// One id per bell event: an entry the hub sends again unchanged keeps
    /// it, and a new event on the same entry gets its own.
    static func complaintMessageID(_ event: AtoNotificationEvent) -> String {
        let entry = event.notificationId ?? event.conversationId ?? ""
        return "ato-ra:\(entry):\(event.type ?? 0):\(event.lastEventOnUtc ?? "")"
    }

    /// Whether you are among a conversation's followers, after a change.
    static func follows(_ change: AtoFollowersChanged, memberships: [AtoMembership]) -> Bool {
        let mine = Set(memberships.map { $0.AgentId.lowercased() })
        return (change.followers ?? []).contains { follower in
            follower.agentId.map { mine.contains($0.lowercased()) } ?? false
        }
    }

    /// The console's own query for the open conversations you follow in one
    /// workspace — its "Acompanhando" view, ids only.
    static func followingQuery(workspaceID: String, agentID: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "$filter",
                         value: "WorkspaceId eq \(workspaceID)"
                             + " and StatusType ne 'Closed' and StatusType ne 'Archived'"
                             + " and AgentStates/any(s: s/AgentId eq \(agentID) and s/FollowingSinceUtc ne null)"),
            URLQueryItem(name: "$select", value: "ConversationId"),
            URLQueryItem(name: "$top", value: "500"),
        ]
    }

    /// The console's query for the newest mention of you in one
    /// conversation, with the note it was made in.
    static func mentionQuery(agentID: String, conversationID: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "$filter",
                         value: "MentionedAgentId eq \(agentID) and ConversationId eq \(conversationID)"),
            URLQueryItem(name: "$orderby", value: "AddedOnUtc desc"),
            URLQueryItem(name: "$top", value: "1"),
            URLQueryItem(name: "$expand", value: "Message($select=Body,SenderId),Conversation($select=ContactId)"),
        ]
    }

    /// The first row of an OData page of mentions, if it decodes.
    static func firstMention(inPage data: Data) -> AtoMentionRow? {
        struct Page: Decodable { let value: [AtoMentionRow] }
        return (try? JSONDecoder().decode(Page.self, from: data))?.value.first
    }

    /// One card per mention, stable across a repeat of the event.
    static func mentionMessageID(_ mention: AtoMentionCreated, row: AtoMentionRow?) -> String {
        let id = mention.messageMentionId ?? row?.MessageMentionId
            ?? mention.messageId ?? row?.MessageId ?? mention.conversationId ?? ""
        return "ato-mention:\(id.lowercased())"
    }


    /// What an update says about whether you are answering this conversation.
    enum Engagement: Equatable {
        /// You just replied: it is yours until someone else takes it.
        case engage
        /// A colleague took it, or it is over: no longer yours this way.
        case release
        /// Nothing either way.
        case keep
    }

    /// Read off every update, the customer's or not — your own reply arrives
    /// as an update whose last sender is an agent with your id.
    static func engagement(after update: AtoConversationUpdate,
                           memberships: [AtoMembership]) -> Engagement {
        guard let workspace = update.workspaceId?.lowercased(),
              let membership = memberships.first(where: { $0.WorkspaceId.lowercased() == workspace })
        else { return .keep }
        let me = membership.AgentId.lowercased()

        if let status = update.statusType.flatMap(AtoStatusType.init(rawValue:)),
           status == .closed || status == .archived {
            return .release
        }
        if let assigned = update.assignedToAgentId?.lowercased(), assigned != me {
            return .release
        }
        if update.lastMessageSenderType == AtoSenderType.agent.rawValue,
           update.lastMessageSenderId?.lowercased() == me {
            return .engage
        }
        return .keep
    }

    /// Whether it is worth asking Ato who answered this conversation last.
    ///
    /// Your reply is seen on the hub only while Notchy is running. One sent
    /// before it started, or from the console on another machine, would leave
    /// the customer's answer looking like nobody's — so for exactly the case
    /// the other rules cannot settle (a customer, an open conversation in your
    /// workspace, nobody assigned, not your queue, not already known to be
    /// yours or not), the client looks once.
    ///
    /// Only worth it while Minha caixa is chosen: the answer can only make a
    /// conversation yours, and yours is not wanted then.
    static func needsAnswererLookup(_ update: AtoConversationUpdate,
                                    memberships: [AtoMembership],
                                    engaged: Set<String>,
                                    checked: Set<String>,
                                    mineEnabled: Bool = true) -> Bool {
        guard mineEnabled,
              update.lastMessageSenderType == AtoSenderType.customer.rawValue,
              update.assignedToAgentId == nil
        else { return false }
        if let status = update.statusType.flatMap(AtoStatusType.init(rawValue:)),
           status == .closed || status == .archived {
            return false
        }
        guard let workspace = update.workspaceId?.lowercased(),
              let membership = memberships.first(where: { $0.WorkspaceId.lowercased() == workspace })
        else { return false }
        if let queue = update.queueId?.lowercased(),
           (membership.QueueIds ?? []).contains(where: { $0.lowercased() == queue }) {
            return false
        }
        let key = update.conversationId.lowercased()
        return !engaged.contains(key) && !checked.contains(key)
    }

    /// How long an answered conversation stays yours without another reply.
    /// A week covers a customer who comes back days later, and keeps the list
    /// from growing for ever.
    static let engagementLifetime: TimeInterval = 7 * 24 * 3600

    /// Drops what has gone past ``engagementLifetime``.
    static func pruned(_ engaged: [String: Date], now: Date = Date()) -> [String: Date] {
        engaged.filter { now.timeIntervalSince($0.value) < engagementLifetime }
    }

    /// One id per customer message, stable across the repeats.
    ///
    /// The hub sends an update for every change to a conversation — the bot
    /// answering, a queue being set — and several can carry the same last
    /// message. The time of that message is what tells a new one from a
    /// repeat, so it is half of the id ``MessageInbox`` deduplicates on.
    static func messageID(_ update: AtoConversationUpdate) -> String {
        "ato:\(update.conversationId):\(update.lastMessageOnUtc ?? "")"
    }

    /// The card's text, or nil when there is none — a file carries no
    /// preview, and the caller says so in words rather than drawing a blank
    /// card.
    static func body(_ update: AtoConversationUpdate) -> String? {
        let text = (update.lastMessagePreview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: Voice messages

    /// Whether a preview stands in for a file rather than saying anything.
    ///
    /// Ato previews a message that is only a file as a bracketed word —
    /// `[anexo]` — or not at all. Either is the cue to fetch the message and
    /// see what it carries; a preview with words in it is the words.
    static func isAttachmentPreview(_ preview: String?) -> Bool {
        let text = (preview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return true }
        guard text.hasPrefix("["), text.hasSuffix("]"), text.count <= 32 else { return false }
        return !text.dropFirst().dropLast().contains("[")
    }

    /// The query for the newest thing the customer said in a conversation,
    /// with its files — the console's thread query, narrowed to one row.
    static func latestCustomerMessageQuery(conversationID: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "$filter",
                         value: "ConversationId eq \(conversationID) and SenderType eq 'Customer'"),
            URLQueryItem(name: "$orderby", value: "AddedOnUtc desc"),
            URLQueryItem(name: "$top", value: "1"),
            URLQueryItem(name: "$expand", value: "Attachments"),
        ]
    }

    /// Extensions WhatsApp and browsers record voice in, for a file whose
    /// content type did not come through.
    private static let audioExtensions: Set<String> = [
        "ogg", "oga", "opus", "mp3", "m4a", "aac", "wav", "amr", "weba", "caf", "flac",
    ]

    static func isAudio(contentType: String?, fileName: String?) -> Bool {
        let type = (contentType ?? "").lowercased()
        if type.hasPrefix("audio/") { return true }
        // A WhatsApp voice note has been seen as `video/ogg`, and some
        // gateways send everything as octet-stream: the name decides then.
        if !type.isEmpty, !type.hasSuffix("/ogg"), type != "application/octet-stream" {
            return false
        }
        let ext = (fileName ?? "").split(separator: ".").last.map { $0.lowercased() } ?? ""
        return audioExtensions.contains(ext)
    }

    /// The console's rule for what a transcript shows: the text only once it
    /// is `Completed`, and a completed one with no words is no transcript.
    static func transcript(status: AtoTranscriptionStatus?, text: String?) -> InboxAudio.Transcript {
        switch status ?? .none {
        case .none:    return .none
        case .pending: return .pending
        case .failed:  return .failed
        case .skipped: return .skipped
        case .completed:
            let words = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return words.isEmpty ? .none : .ready(words)
        }
    }

    /// The first audio file on a message, or nil when it carries none.
    static func voiceNote(in row: AtoMessageRow) -> InboxAudio? {
        for file in row.Attachments ?? [] {
            guard isAudio(contentType: file.ContentType, fileName: file.FileName),
                  let storage = file.StorageFileId, !storage.isEmpty
            else { continue }
            return InboxAudio(
                attachmentID: file.MessageAttachmentId ?? storage,
                storageFileID: storage,
                fileName: file.FileName ?? "",
                contentType: file.ContentType ?? "",
                duration: file.DurationSeconds.flatMap { $0 > 0 ? $0 : nil },
                transcript: transcript(status: file.TranscriptionStatusType, text: file.TranscriptText)
            )
        }
        return nil
    }

    /// Every file on a message, the voice note included — what Copy hands
    /// on. One with no storage id cannot be fetched and is left out.
    static func files(in row: AtoMessageRow) -> [InboxFile] {
        (row.Attachments ?? []).compactMap { file in
            guard let storage = file.StorageFileId, !storage.isEmpty else { return nil }
            return InboxFile(fileID: storage, name: file.FileName ?? "",
                             mimeType: file.ContentType ?? "", byteCount: max(0, file.SizeBytes ?? 0))
        }
    }

    /// The first row of an OData page of messages, if it decodes.
    static func firstMessage(inPage data: Data) -> AtoMessageRow? {
        struct Page: Decodable { let value: [AtoMessageRow] }
        return (try? JSONDecoder().decode(Page.self, from: data))?.value.first
    }

    /// A voice note with a transcript event applied, or nil when the event is
    /// about some other file.
    static func applying(_ event: AtoMessageTranscribed, to audio: InboxAudio) -> InboxAudio? {
        guard let attachment = event.messageAttachmentId,
              attachment.lowercased() == audio.attachmentID.lowercased()
        else { return nil }
        var updated = audio
        updated.transcript = transcript(status: event.transcriptionStatusType, text: event.transcriptText)
        if let seconds = event.durationSeconds, seconds > 0 { updated.duration = seconds }
        return updated
    }

    /// Where `StorageObject/GetObject` says the file can be downloaded from.
    static func objectURL(fromStorageObject data: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["Url"] as? String,
              let url = URL(string: text.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    /// The tenant a token was issued for, when the token says. The storage
    /// service asks for it beside a file's id.
    static func tenantID(ofJWT token: String) -> String? {
        guard let claims = jwtClaims(token) else { return nil }
        for key in ["TenantId", "tenantId", "tenant_id", "tenant", "tid"] {
            if let value = claims[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// The tenant on `UserProfile/GetByAuthPersonAsync` — where the console
    /// reads it for its own storage requests.
    static func tenantID(fromProfile data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tenant = object["TenantId"] as? String,
              !tenant.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return tenant
    }

    /// WhatsApp push names arrive as Ato stores them: `~cato`. The tilde is
    /// WhatsApp saying "not in your contacts", which is noise on a card.
    static func displayName(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        while name.hasPrefix("~") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// `2026-11-15T19:33:53Z` and `2026-11-15T19:33:54.8855382Z` both occur —
    /// .NET writes up to seven fractional digits, which `ISO8601DateFormatter`
    /// will not read. Trimmed to milliseconds first.
    static func date(_ text: String?) -> Date? {
        guard var text, !text.isEmpty else { return nil }
        if let dot = text.firstIndex(of: "."),
           let zone = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let fraction = text[text.index(after: dot)..<zone].prefix(3)
            text = String(text[..<dot]) + "." + fraction + String(text[zone...])
        }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = precise.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    /// When a bearer token stops working, from its own `exp` claim.
    static func expiry(ofJWT token: String) -> Date? {
        guard let exp = jwtClaims(token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private static func jwtClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
