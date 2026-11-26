import Foundation

/// The arithmetic of the microphone's side of dictation: cutting PCM16 into the
/// 100 ms frames the service expects, and a level for the meter.
///
/// Foundation only, so scripts/test-dictation.sh can compile it alone.
enum DictationPCM {
    /// Bytes in one frame: 100 ms of 16 kHz mono 16-bit audio.
    static let frameBytes = Int(DictationProtocol.sampleRate) * DictationProtocol.frameMilliseconds / 1000 * 2

    /// Collects bytes and hands them back in whole frames, in order.
    struct Framer {
        private(set) var pending = Data()
        let frameBytes: Int

        init(frameBytes: Int = DictationPCM.frameBytes) {
            self.frameBytes = frameBytes
        }

        mutating func push(_ data: Data) -> [Data] {
            pending.append(data)
            var frames: [Data] = []
            while pending.count >= frameBytes {
                frames.append(pending.prefix(frameBytes))
                pending.removeFirst(frameBytes)
            }
            return frames
        }

        /// What is left, shorter than a frame, or nil. The tail of a dictation
        /// is the end of a word; it is sent rather than dropped.
        mutating func flush() -> Data? {
            guard !pending.isEmpty else { return nil }
            defer { pending = Data() }
            return pending
        }
    }

    /// 0…1 for the meter: the RMS in dBFS, -50 dB and quieter at 0, 0 dB at 1 —
    /// the same mapping as the voice message recorder.
    static func level<C: Collection>(of samples: C) -> Float where C.Element == Int16 {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for s in samples {
            let x = Double(s) / 32768
            sum += x * x
        }
        let rms = (sum / Double(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return Float(min(1, max(0, (db + 50) / 50)))
    }
}
