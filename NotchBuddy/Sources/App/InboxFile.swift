//
//  InboxFile.swift
//  Notchy
//
//  A file that came with a message — a PDF, a spreadsheet, a photo, a voice
//  note: enough to fetch it and hand it on under the name it was sent with.
//
//  Foundation only and its own file, so the test scripts that compile the
//  Mattermost and Ato rules and the copy rule can each take it alone.
//

import Foundation

struct InboxFile: Equatable, Sendable {
    /// What the service is asked for to get the file: a Mattermost file id,
    /// an Ato storage file id.
    let fileID: String
    /// As the sender's machine named it. Possibly empty, possibly a path.
    let name: String
    let mimeType: String
    /// As the service measured it; zero when it did not say.
    let byteCount: Int
}
