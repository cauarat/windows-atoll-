import AVFoundation
import Foundation

/// Where a dictation's audio comes from: the microphone, or — in Debug builds —
/// a WAV file, for checking the card without a voice.
///
/// The handlers run on the audio thread, never the main one: a frame goes
/// straight to the socket, and the level is the caller's to bring to the main
/// thread.
protocol DictationAudioSource: AnyObject, Sendable {
    func start(onFrame: @escaping @Sendable (Data) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void,
               onInterrupted: @escaping @Sendable () -> Void) throws
    /// Stops. The last frame, shorter than 100 ms, is delivered before this
    /// returns: it is the end of the last word.
    func stop()
}

enum DictationCaptureError: Error {
    case noMicrophone
    case unsupportedFormat
    case unreadableFile
}

/// The microphone, as 16 kHz mono PCM16 in 100 ms frames.
///
/// AVAudioEngine's input tap hands over buffers in the hardware's format (often
/// 48 kHz float, sometimes stereo); AVAudioConverter brings them to what the
/// service reads. Nothing is written to disk. The engine only runs between
/// `start` and `stop`, so the microphone indicator is on exactly while a
/// dictation listens.
final class DictationAudioCapture: DictationAudioSource, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: DictationProtocol.sampleRate,
                                       channels: 1, interleaved: true)!
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var framer = DictationPCM.Framer()
    private var onFrame: (@Sendable (Data) -> Void)?
    private var onLevel: (@Sendable (Float) -> Void)?
    private var onInterrupted: (@Sendable () -> Void)?
    private var levelPeak: Float = 0
    private var levelSamples = 0
    private var configurationObserver: NSObjectProtocol?

    /// About twelve level updates a second: enough for the meter to look
    /// alive, not a redraw per audio buffer.
    private static let samplesPerLevel = Int(DictationProtocol.sampleRate) / 12

    func start(onFrame: @escaping @Sendable (Data) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void,
               onInterrupted: @escaping @Sendable () -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationCaptureError.noMicrophone }
        guard let converter = AVAudioConverter(from: format, to: target) else {
            throw DictationCaptureError.unsupportedFormat
        }
        lock.lock()
        self.converter = converter
        self.framer = DictationPCM.Framer()
        self.onFrame = onFrame
        self.onLevel = onLevel
        self.onInterrupted = onInterrupted
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.convert(buffer)
        }
        // A headset plugged in or taken off mid-sentence stops the engine;
        // what was heard so far is still worth transcribing.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.interrupted()
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            removeObserver()
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        removeObserver()
        lock.lock()
        // Sent under the lock, like every frame, so the tail can never
        // overtake a frame still being converted.
        if let tail = framer.flush() { onFrame?(tail) }
        onFrame = nil
        onLevel = nil
        onInterrupted = nil
        converter = nil
        lock.unlock()
    }

    private func convert(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0, let channel = out.int16ChannelData?[0] else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(out.frameLength))
        for frame in framer.push(Data(buffer: samples)) { onFrame?(frame) }

        levelPeak = max(levelPeak, DictationPCM.level(of: samples))
        levelSamples += samples.count
        if levelSamples >= Self.samplesPerLevel {
            onLevel?(levelPeak)
            levelPeak = 0
            levelSamples = 0
        }
    }

    private func interrupted() {
        lock.lock()
        let handler = onInterrupted
        lock.unlock()
        handler?()
    }

    private func removeObserver() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
    }
}

#if DEBUG
/// Debug builds only: a WAV file played as if it were the microphone, at the
/// pace of speech, then the end of the dictation. `NOTCHY_DICTATION_FILE` names
/// it — 16 kHz mono PCM16, as
/// `say -v Luciana -o x.wav --file-format=WAVE --data-format=LEI16@16000 "…"`
/// writes — which is how the card is checked against the real service with
/// nobody speaking.
final class DictationFileSource: DictationAudioSource, @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "fr.notchy.dictation.file")
    private let lock = NSLock()
    private var pending = Data()
    private var timer: DispatchSourceTimer?
    private var onFrame: (@Sendable (Data) -> Void)?
    private var onLevel: (@Sendable (Float) -> Void)?
    private var onInterrupted: (@Sendable () -> Void)?

    init(url: URL) {
        self.url = url
    }

    func start(onFrame: @escaping @Sendable (Data) -> Void,
               onLevel: @escaping @Sendable (Float) -> Void,
               onInterrupted: @escaping @Sendable () -> Void) throws {
        guard let data = try? Data(contentsOf: url), let pcm = Self.pcm16(fromWAV: data) else {
            throw DictationCaptureError.unreadableFile
        }
        lock.lock()
        pending = pcm
        self.onFrame = onFrame
        self.onLevel = onLevel
        self.onInterrupted = onInterrupted
        lock.unlock()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(DictationProtocol.frameMilliseconds))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        lock.lock()
        pending = Data()
        onFrame = nil
        onLevel = nil
        onInterrupted = nil
        lock.unlock()
    }

    private func tick() {
        lock.lock()
        guard !pending.isEmpty else {
            let done = onInterrupted
            onInterrupted = nil
            lock.unlock()
            done?()  // the file is over: the person has stopped talking
            return
        }
        let frame = pending.prefix(DictationPCM.frameBytes)
        pending.removeFirst(frame.count)
        onFrame?(Data(frame))
        let samples = frame.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        onLevel?(DictationPCM.level(of: samples))
        lock.unlock()
    }

    /// The `data` chunk of a 16 kHz mono 16-bit PCM WAV, or nil.
    static func pcm16(fromWAV data: Data) -> Data? {
        func u32(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 | Int(data[at + 2]) << 16 | Int(data[at + 3]) << 24 }
        func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
        guard data.count > 12, data.prefix(4) == Data("RIFF".utf8), data[8..<12] == Data("WAVE".utf8) else { return nil }
        var offset = 12
        var formatOK = false
        while offset + 8 <= data.count {
            let id = data[offset..<offset + 4]
            let size = u32(offset + 4)
            let body = offset + 8
            if id == Data("fmt ".utf8), body + 16 <= data.count {
                formatOK = u16(body) == 1 && u16(body + 2) == 1 && u32(body + 4) == 16_000 && u16(body + 14) == 16
            } else if id == Data("data".utf8) {
                guard formatOK else { return nil }
                return data.subdata(in: body..<min(data.count, body + size))
            }
            offset = body + size + (size & 1)
        }
        return nil
    }
}
#endif
