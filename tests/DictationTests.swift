import Foundation

/// The Mac's corner of tests/fixtures/dictation.json: the protocol constants,
/// the transcript the card shows as messages arrive, and the hold-to-talk
/// gesture. The service (dictation-service/tests) and the Windows twin
/// (tests/dictation.ts, dictation_keys.rs) are held to the same file.
///
/// Run by scripts/test-dictation.sh, with the fixture's path.
@main @MainActor
enum DictationTests {
    static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("  ✓ \(label)") }
        else {
            print("  ✗ \(label)\(detail.isEmpty ? "" : " — \(detail)")")
            failures += 1
        }
    }

    static func main() {
        guard let path = CommandLine.arguments.dropFirst().first,
              let data = FileManager.default.contents(atPath: path),
              let fixture = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            print("usage: dictation-tests <tests/fixtures/dictation.json>")
            exit(2)
        }
        protocolConstants(fixture["protocol"] as? [String: Any] ?? [:])
        sessions(fixture["sessions"] as? [[String: Any]] ?? [])
        hold(fixture["hold"] as? [String: Any] ?? [:])
        addresses(fixture["addresses"] as? [[Any]] ?? [])
        framing()

        if failures > 0 {
            print("\n\(failures) failed")
            exit(1)
        }
        print("\nAll dictation checks passed")
    }

    static func protocolConstants(_ p: [String: Any]) {
        print("Dictation — the protocol, as the service speaks it")
        check("version", p["version"] as? Int == DictationProtocol.version)
        check("path", p["path"] as? String == DictationProtocol.path)
        check("health path", p["healthPath"] as? String == DictationProtocol.healthPath)
        check("default address", p["defaultServiceURL"] as? String == DictationProtocol.defaultServiceURL)
        check("16 kHz", (p["sampleRate"] as? Double) == DictationProtocol.sampleRate)
        check("PCM16", p["encoding"] as? String == DictationProtocol.encoding)
        check("100 ms frames", p["frameMs"] as? Int == DictationProtocol.frameMilliseconds)
        check("250 ms tail", p["tailMs"] as? Int == DictationProtocol.tailMilliseconds)
        check("pt-BR", p["language"] as? String == DictationProtocol.language)
        check("its label", p["languageLabel"] as? String == DictationProtocol.languageLabel)
        check("error codes, in order", (p["errorCodes"] as? [String]) == DictationProtocol.errorCodes)

        // The start message the app sends is the fixture's, field for field.
        let sent = (try? JSONSerialization.jsonObject(with: Data(DictationProtocol.startMessage().utf8))) as? NSDictionary
        check("start message", sent == (p["start"] as? NSDictionary), "\(DictationProtocol.startMessage())")
        let stop = (try? JSONSerialization.jsonObject(with: Data(DictationProtocol.stopMessage.utf8))) as? NSDictionary
        check("stop message", stop == (p["stop"] as? NSDictionary))
        let cancel = (try? JSONSerialization.jsonObject(with: Data(DictationProtocol.cancelMessage.utf8))) as? NSDictionary
        check("cancel message", cancel == (p["cancel"] as? NSDictionary))
    }

    static func sessions(_ cases: [[String: Any]]) {
        print("Dictation — what the card shows as the messages arrive")
        for c in cases {
            let name = c["name"] as? String ?? "?"
            var transcript = DictationTranscript()
            var shown: [String] = []
            var decoded = true
            for message in c["messages"] as? [[String: Any]] ?? [] {
                guard let data = try? JSONSerialization.data(withJSONObject: message),
                      let text = String(data: data, encoding: .utf8),
                      let m = DictationServerMessage.decode(text) else {
                    decoded = false
                    continue
                }
                transcript.apply(m)
                shown.append(transcript.text)
            }
            check("\(name): every message decodes", decoded)
            check("\(name): text after each message", shown == (c["shown"] as? [String] ?? []), "\(shown)")
            check("\(name): ends \(c["phase"] as? String ?? "?")", transcript.phase.rawValue == c["phase"] as? String,
                  transcript.phase.rawValue)
            check("\(name): streaming \(c["streaming"] as? Bool ?? false)",
                  transcript.streaming == (c["streaming"] as? Bool ?? false))
            if let code = c["errorCode"] as? String {
                check("\(name): error \(code)", transcript.errorCode == code, transcript.errorCode ?? "none")
            }
        }

        // A partial that arrives after the final is late, not newer.
        var t = DictationTranscript()
        t.apply(.final(text: "Pronto.", audioMs: 1000, processingMs: 10, truncated: false))
        t.apply(.partial(text: "Pron", seq: 9))
        check("a late partial does not undo the final", t.text == "Pronto.")
    }

    static func hold(_ h: [String: Any]) {
        print("Dictation — hold to talk")
        check("minimum hold", (h["minimumHoldMs"] as? Double).map { $0 / 1000 } == DictationHoldGesture.minimumHold)
        check("maximum hold", (h["maximumHoldMs"] as? Double).map { $0 / 1000 } == DictationHoldGesture.maximumHold)
        for c in h["cases"] as? [[String: Any]] ?? [] {
            let name = c["name"] as? String ?? "?"
            var gesture = DictationHoldGesture()
            var actions: [String] = []
            for event in c["events"] as? [[Any]] ?? [] {
                guard event.count == 2, let kind = event[0] as? String,
                      let input = DictationHoldGesture.Input(rawValue: kind),
                      let ms = (event[1] as? NSNumber)?.doubleValue else {
                    check("\(name): readable event \(event)", false)
                    continue
                }
                actions += gesture.handle(input, at: ms / 1000).map(\.rawValue)
            }
            let want = c["actions"] as? [String] ?? []
            check(name, actions == want, "got \(actions), want \(want)")
        }
    }

    static func addresses(_ cases: [[Any]]) {
        print("Dictation — the address typed in Settings")
        check("the fixture lists addresses", !cases.isEmpty)
        for c in cases {
            guard c.count == 2, let typed = c[0] as? String else { continue }
            let want = c[1] as? String
            let got = DictationProtocol.socketURL(service: typed)?.absoluteString
            check("“\(typed)” → \(want ?? "nothing")", got == want, got ?? "nil")
        }
        check("health", DictationProtocol.healthURL(service: "http://127.0.0.1:8765")?.absoluteString
              == "http://127.0.0.1:8765/health")
    }

    static func framing() {
        print("Dictation — 100 ms frames, nothing dropped")
        check("a frame is 3200 bytes", DictationPCM.frameBytes == 3200)
        var framer = DictationPCM.Framer()
        var frames = framer.push(Data(count: 1000))
        frames += framer.push(Data(count: 6000))
        let tail = framer.flush()
        check("whole frames come out in order", frames.map(\.count) == [3200, 3200], "\(frames.map(\.count))")
        check("the tail is kept, not dropped", tail?.count == 600, "\(tail?.count ?? 0)")
        check("and only once", framer.flush() == nil)
        check("silence is level 0", DictationPCM.level(of: [Int16](repeating: 0, count: 160)) == 0)
        let loud = DictationPCM.level(of: [Int16](repeating: 32767, count: 160))
        check("full scale is level 1", abs(loud - 1) < 0.001, "\(loud)")
        let quiet = DictationPCM.level(of: [Int16](repeating: 100, count: 160))
        check("-50 dBFS and below is 0", quiet == 0, "\(quiet)")
    }
}
