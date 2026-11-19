//
//  InboxAudio.swift
//  Notchy
//
//  A voice message on an inbox card: enough to fetch it, say how long it is,
//  and show what was said once the service has transcribed it.
//
//  Foundation only and its own file, so scripts/test-ato-rules.sh can compile
//  it beside AtoRules without dragging in the inbox behind it.
//

import Foundation

struct InboxAudio: Equatable, Sendable {
    /// Where the transcript stands — Ato's `TranscriptionStatusType`, with the
    /// text carried by the one state that has any.
    enum Transcript: Equatable, Sendable {
        /// Transcription is off for the workspace, or this file is not one it
        /// transcribes.
        case none
        /// On its way: Ato transcribes after the message has arrived.
        case pending
        case ready(String)
        case failed
        /// Ato decided not to — too long, too short, no speech.
        case skipped

        var text: String? {
            if case .ready(let text) = self { return text }
            return nil
        }

        /// Still worth asking about again.
        var isPending: Bool { self == .pending }
    }

    /// Ato's `MessageAttachmentId` — what `onMessageTranscribed` names.
    let attachmentID: String
    /// What the storage service is asked for to get the file itself.
    let storageFileID: String
    let fileName: String
    let contentType: String
    /// Ato measures it while transcribing, so it can arrive after the message.
    var duration: TimeInterval?
    var transcript: Transcript
}
