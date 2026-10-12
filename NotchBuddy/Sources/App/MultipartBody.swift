import Foundation

/// A `multipart/form-data` body, built by hand.
///
/// Written rather than pulled in: the app has no third-party dependencies, and
/// URLSession offers no multipart of its own. It is small, and being a value
/// over plain bytes means the exact wire format is testable without a server —
/// which matters, because a stray newline in a boundary is the kind of bug that
/// only ever shows up as a 400 from someone else's machine.
///
/// RFC 7578. Lines end CRLF, every part opens with `--boundary`, and the body
/// closes with `--boundary--`.
struct MultipartBody {
    let boundary: String
    private var body = Data()

    /// A boundary no file content will contain by accident.
    init(boundary: String = "coucou.\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(name: String, filename: String, mimeType: String, contents: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(Self.escape(filename))\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(contents)
        append("\r\n")
    }

    /// The finished body. Call once; the closing boundary is what makes it
    /// valid, and a server will hang waiting for it otherwise.
    func finished() -> Data {
        var out = body
        out.append(Data("--\(boundary)--\r\n".utf8))
        return out
    }

    /// A quote or a newline in a filename would end the header early and let
    /// the rest be read as something else. Both are stripped rather than
    /// encoded, because no server agrees on how they should be encoded.
    static func escape(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}
