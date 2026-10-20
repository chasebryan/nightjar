import AVFoundation
import Foundation

/// Chirp: messages carried by sound.
///
/// The fourth transport, after wire, radio, and knock order:
/// a payload sung as tones, speaker to microphone. The framing
/// is borrowed from mawkbox — four tones (1200/1600/2000/2400
/// Hz), two bits per symbol — and the payload is a Knocktalk
/// sealed box, byte for byte, so a chirp is exactly as
/// encrypted as a knock: the pairing key seals it, and only
/// the pairing key opens it. What crosses the air is ciphertext
/// with a haircut.
///
/// Sound is a narrow pipe: 60 ms symbols move about 33 bits a
/// second, so chirps are capped short on purpose. In exchange
/// the channel needs no network, no radio, and no permission
/// from the spectrum — it works in airplane mode, under full
/// EMCON, in a room where everything else is watched.
///
/// Chirp mail is the same song, stored: render it to a .wav
/// and it travels by any carrier that moves audio — a message,
/// an email, a voicemail — and decodes from the file on
/// arrival, through the very same decoder the live listener
/// runs. One modem, two postures: sing it now, or mail it.
enum ChirpModem {
    static let tones = [1200.0, 1600.0, 2000.0, 2400.0]
    static let symbolSeconds = 0.06
    /// Sealed-byte ceiling for one chirp (about 35 s of song).
    static let maxPayload = 120
    static let magic: [UInt8] = [0x4E, 0x4A]
    static let wavRate = 44100.0

    static func etaSeconds(payloadBytes: Int) -> Int {
        let symbols = 8 + (3 + payloadBytes + 2) * 4
        return Int(Double(symbols) * symbolSeconds) + 1
    }

    /// Frame layout: an alternating preamble for the listener
    /// to lock onto, then magic, length, payload, and a CRC-16
    /// (frame sync only — the AEAD tag inside the payload is
    /// the real integrity check).
    static func symbols(forPayload payload: Data) -> [Int] {
        // The frame's length byte is one byte and
        // the protocol caps a payload at maxPayload;
        // an over-long payload gets silence, never
        // a trapping conversion.
        guard payload.count <= maxPayload else {
            return []
        }
        var body: [UInt8] = [UInt8(payload.count)]
        body.append(contentsOf: payload)
        let crc = crc16(body)
        var frame = magic + body
        frame.append(UInt8(crc >> 8))
        frame.append(UInt8(crc & 0xFF))
        var out = [0, 3, 0, 3, 0, 3, 0, 3]
        for byte in frame {
            out.append(Int(byte >> 6) & 3)
            out.append(Int(byte >> 4) & 3)
            out.append(Int(byte >> 2) & 3)
            out.append(Int(byte) & 3)
        }
        return out
    }

    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0
                    ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }

    /// The song as samples — 44.1 kHz mono, each symbol a sine
    /// with raised-cosine edges so the tones don't click into
    /// each other's windows. The live singer plays these; the
    /// mail writer files them.
    static func renderSamples(payload: Data) -> [Float] {
        let symbols = symbols(forPayload: payload)
        let symN = Int(symbolSeconds * wavRate)
        var out = [Float](repeating: 0,
                          count: symN * symbols.count)
        let ramp = Int(0.008 * wavRate)
        for (index, symbol) in symbols.enumerated() {
            let freq = tones[symbol]
            for i in 0..<symN {
                let t = Double(i) / wavRate
                var amp = 0.5
                if i < ramp { amp *= Double(i) / Double(ramp) }
                if i > symN - ramp {
                    amp *= Double(symN - i) / Double(ramp)
                }
                out[index * symN + i] =
                    Float(sin(2 * Double.pi * freq * t) * amp)
            }
        }
        return out
    }

    /// A plain 16-bit PCM WAV of the samples — the chirp as a
    /// file any audio carrier will move without asking what
    /// it is.
    static func writeWav(samples: [Float], to url: URL) throws {
        var data = Data()
        func u32(_ v: UInt32) {
            var x = v.littleEndian
            data.append(Data(bytes: &x, count: 4))
        }
        func u16(_ v: UInt16) {
            var x = v.littleEndian
            data.append(Data(bytes: &x, count: 2))
        }
        data.append(Data("RIFF".utf8))
        u32(UInt32(36 + samples.count * 2))
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        u32(16)
        u16(1)                       // PCM
        u16(1)                       // mono
        u32(UInt32(wavRate))
        u32(UInt32(wavRate) * 2)     // byte rate
        u16(2)                       // block align
        u16(16)                      // bits per sample
        data.append(Data("data".utf8))
        u32(UInt32(samples.count * 2))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var x = Int16(clamped * 32767).littleEndian
            data.append(Data(bytes: &x, count: 2))
        }
        try data.write(to: url, options: .atomic)
    }
}

/// The decoder: a preamble hunter and frame assembler fed
/// samples from anywhere — the microphone tap, or a file.
/// Feed it audio; it hands back a payload the moment a whole
/// chirp has been heard, and reports its lock state as it goes.
final class ChirpDecoder {
    var onStatus: ((String) -> Void)?

    private let rate: Double
    private var symbolSamples: Int {
        Int(ChirpModem.symbolSeconds * rate)
    }
    private var samples: [Float] = []

    private enum State { case hunting, receiving }
    private var state: State = .hunting
    private var consumed = 0
    private var symbols: [Int] = []
    private var nextWindow = 0
    private var huntTrail: [Int] = []

    init(rate: Double) {
        self.rate = rate
    }

    /// Feed audio; returns the payload when a chirp completes.
    func append(_ new: [Float]) -> Data? {
        samples.append(contentsOf: new)
        let cap = Int(rate) * 45
        if samples.count > cap {
            let drop = samples.count - cap
            samples.removeFirst(drop)
            consumed = max(0, consumed - drop)
            nextWindow = max(0, nextWindow - drop)
        }
        return process()
    }

    private func process() -> Data? {
        let sym = symbolSamples
        switch state {
        case .hunting:
            var i = consumed
            while i + sym <= samples.count {
                let probe = classify(start: i)
                if probe.power <= 0.015 {
                    huntTrail = []
                } else if probe.margin > 1.8 {
                    huntTrail.append(probe.symbol)
                    let tail = Array(huntTrail.suffix(6))
                    if tail == [0, 3, 0, 3, 0, 3]
                        || tail == [3, 0, 3, 0, 3, 0] {
                        state = .receiving
                        symbols = []
                        nextWindow = i + sym
                        huntTrail = []
                        onStatus?(L("locked — receiving…"))
                        consumed = i
                        return processReceiving()
                    }
                }
                i += sym / 2
            }
            consumed = i
            return nil
        case .receiving:
            return processReceiving()
        }
    }

    private func processReceiving() -> Data? {
        let sym = symbolSamples
        while nextWindow + sym <= samples.count {
            let probe = classify(start: nextWindow)
            guard probe.power > 0.008, probe.margin > 1.5
            else {
                state = .hunting
                consumed = nextWindow
                symbols = []
                onStatus?(L("lost that chirp mid-frame"))
                return nil
            }
            symbols.append(probe.symbol)
            nextWindow += sym
            if symbols.count % 4 == 0 {
                let attempt = assemble()
                if attempt.abort {
                    state = .hunting
                    consumed = nextWindow
                    symbols = []
                    onStatus?(L("that was not a chirp"))
                    return nil
                }
                if let payload = attempt.payload {
                    state = .hunting
                    consumed = nextWindow
                    symbols = []
                    return payload
                }
            }
        }
        return nil
    }

    /// Assemble whole bytes; report a finished payload, an
    /// invalid frame, or neither yet.
    private func assemble() -> (payload: Data?, abort: Bool) {
        var bytes: [UInt8] = []
        var i = 0
        while i + 3 < symbols.count {
            bytes.append(UInt8(symbols[i] << 6
                               | symbols[i + 1] << 4
                               | symbols[i + 2] << 2
                               | symbols[i + 3]))
            i += 4
        }
        guard bytes.count >= 3 else { return (nil, false) }
        guard bytes[0] == ChirpModem.magic[0],
              bytes[1] == ChirpModem.magic[1]
        else { return (nil, true) }
        let length = Int(bytes[2])
        guard length <= ChirpModem.maxPayload
        else { return (nil, true) }
        let total = 3 + length + 2
        guard bytes.count >= total else { return (nil, false) }
        let body = Array(bytes[2..<(3 + length)])
        let carried = UInt16(bytes[3 + length]) << 8
            | UInt16(bytes[3 + length + 1])
        guard ChirpModem.crc16(body) == carried
        else { return (nil, true) }
        return (Data(bytes[3..<(3 + length)]), false)
    }

    private func classify(start: Int)
        -> (symbol: Int, power: Double, margin: Double) {
        let sym = symbolSamples
        let inset = sym / 6
        let begin = start + inset
        let count = sym - inset * 2
        var powers: [Double] = []
        for freq in ChirpModem.tones {
            powers.append(goertzel(start: begin, count: count,
                                   freq: freq))
        }
        let ranked = powers.sorted(by: >)
        let winner = powers.firstIndex(of: ranked[0]) ?? 0
        let normalized = ranked[0] / Double(count * count)
        let margin = ranked[0] / max(ranked[1], 1e-9)
        return (winner, normalized, margin)
    }

    private func goertzel(start: Int, count: Int,
                          freq: Double) -> Double {
        let coeff = 2 * cos(2 * Double.pi * freq / rate)
        var s0 = 0.0, s1 = 0.0, s2 = 0.0
        let end = min(start + count, samples.count)
        guard start < end else { return 0 }
        for i in start..<end {
            s0 = Double(samples[i]) + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }
        return s1 * s1 + s2 * s2 - coeff * s1 * s2
    }
}

/// Chirp mail: the song as a file, both directions.
enum ChirpMail {
    /// Render a sealed payload to a shareable .wav.
    static func export(payload: Data) -> URL? {
        let samples = ChirpModem.renderSamples(payload: payload)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "chirp-\(Int(Date().timeIntervalSince1970)).wav")
        do {
            try ChirpModem.writeWav(samples: samples, to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Decode the first complete chirp in an audio file.
    /// Compressed carriers (a voice memo, an .m4a) smear the
    /// tones somewhat; the modem's margins forgive a lot, but
    /// a lossless .wav is the honest carrier.
    static func decode(fileURL: URL) -> Data? {
        guard let (samples, rate) = readSamples(fileURL)
        else { return nil }
        let decoder = ChirpDecoder(rate: rate)
        return decoder.append(samples)
    }

    private static func readSamples(_ url: URL)
        -> (samples: [Float], rate: Double)? {
        guard let file = try? AVAudioFile(forReading: url)
        else { return nil }
        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inFormat.sampleRate, channels: 1,
                interleaved: false),
              let converter = AVAudioConverter(
                from: inFormat, to: outFormat)
        else { return nil }
        let wanted = min(
            file.length,
            AVAudioFramePosition(inFormat.sampleRate * 180))
        guard wanted > 0,
              let inBuffer = AVAudioPCMBuffer(
                pcmFormat: inFormat,
                frameCapacity: AVAudioFrameCount(wanted)),
              let outBuffer = AVAudioPCMBuffer(
                pcmFormat: outFormat,
                frameCapacity: AVAudioFrameCount(wanted))
        else { return nil }
        do {
            try file.read(into: inBuffer,
                          frameCount: AVAudioFrameCount(wanted))
        } catch {
            return nil
        }
        var fed = false
        var convertError: NSError?
        converter.convert(to: outBuffer, error: &convertError) {
            _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        guard convertError == nil,
              let channel = outBuffer.floatChannelData?[0]
        else { return nil }
        let count = Int(outBuffer.frameLength)
        guard count > 0 else { return nil }
        return (Array(UnsafeBufferPointer(
            start: channel, count: count)), inFormat.sampleRate)
    }
}

final class ChirpSender: ObservableObject {
    @Published private(set) var singing = false
    @Published private(set) var progress = 0.0

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var timer: Timer?
    private var attached = false

    func sing(payload: Data) {
        stop()
        let samples = ChirpModem.renderSamples(payload: payload)
        let rate = ChirpModem.wavRate
        guard let format = AVAudioFormat(
                standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)),
              let data = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            data[index] = sample
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        try? session.setActive(true)
        if !attached {
            engine.attach(player)
            attached = true
        }
        engine.connect(player, to: engine.mainMixerNode,
                       format: format)
        guard (try? engine.start()) != nil else { return }
        singing = true
        progress = 0
        let started = Date()
        let airtime = Double(samples.count) / rate
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.progress = min(
                1, Date().timeIntervalSince(started) / airtime)
            if self.progress >= 1 { self.finish() }
        }
        player.scheduleBuffer(buffer)
        player.play()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if singing || engine.isRunning {
            player.stop()
            engine.stop()
        }
        singing = false
        progress = 0
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        player.stop()
        engine.stop()
        singing = false
        progress = 0
    }
}

/// The live listener: a microphone tap feeding the shared
/// decoder. All the hearing lives in ChirpDecoder now; this
/// owns the audio session, the tap, and the status line.
final class ChirpListener: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var status = "idle"
    /// Return true when the payload opened — the listener
    /// reports the outcome in its own status line.
    var onPayload: ((Data) -> Bool)?

    private let engine = AVAudioEngine()
    private var decoder: ChirpDecoder?
    private var pending: [Float] = []
    private let lock = NSLock()
    private var processTimer: Timer?

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission {
            [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.begin()
                } else {
                    self.status = L("microphone permission denied — iOS Settings is where that changes")
                }
            }
        }
    }

    private func begin() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record)
        try? session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let decoder = ChirpDecoder(rate: format.sampleRate)
        decoder.onStatus = { [weak self] text in
            self?.status = String(format: L("%@ — still listening"), text)
        }
        self.decoder = decoder
        lock.lock()
        pending = []
        lock.unlock()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048,
                         format: format) { [weak self] buffer, _ in
            guard let self = self,
                  let channel = buffer.floatChannelData?[0]
            else { return }
            let count = Int(buffer.frameLength)
            self.lock.lock()
            self.pending.append(contentsOf: UnsafeBufferPointer(
                start: channel, count: count))
            self.lock.unlock()
        }
        guard (try? engine.start()) != nil else {
            status = L("microphone would not start")
            return
        }
        listening = true
        status = L("listening — hold the phones near each other")
        processTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.drain()
        }
    }

    func stop() {
        processTimer?.invalidate()
        processTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        decoder = nil
        listening = false
        status = "idle"
    }

    private func drain() {
        guard let decoder = decoder else { return }
        lock.lock()
        let chunk = pending
        pending = []
        lock.unlock()
        guard !chunk.isEmpty else { return }
        if let payload = decoder.append(chunk) {
            let opened = onPayload?(payload) ?? false
            status = opened
                ? L("decoded — filed in the Chirp thread below")
                : L("heard a chirp that does not open with your pairing key")
        }
    }
}
