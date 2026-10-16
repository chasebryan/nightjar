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
enum ChirpModem {
    static let tones = [1200.0, 1600.0, 2000.0, 2400.0]
    static let symbolSeconds = 0.06
    /// Sealed-byte ceiling for one chirp (about 35 s of song).
    static let maxPayload = 120
    static let magic: [UInt8] = [0x4E, 0x4A]

    static func etaSeconds(payloadBytes: Int) -> Int {
        let symbols = 8 + (3 + payloadBytes + 2) * 4
        return Int(Double(symbols) * symbolSeconds) + 1
    }

    /// Frame layout: an alternating preamble for the listener
    /// to lock onto, then magic, length, payload, and a CRC-16
    /// (frame sync only — the AEAD tag inside the payload is
    /// the real integrity check).
    static func symbols(forPayload payload: Data) -> [Int] {
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
        let symbols = ChirpModem.symbols(forPayload: payload)
        let rate = 44100.0
        let symN = Int(ChirpModem.symbolSeconds * rate)
        let total = symN * symbols.count
        guard let format = AVAudioFormat(
                standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(total)),
              let data = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = AVAudioFrameCount(total)
        let ramp = Int(0.008 * rate)
        for (index, symbol) in symbols.enumerated() {
            let freq = ChirpModem.tones[symbol]
            for i in 0..<symN {
                let t = Double(i) / rate
                var amp = 0.5
                if i < ramp { amp *= Double(i) / Double(ramp) }
                if i > symN - ramp {
                    amp *= Double(symN - i) / Double(ramp)
                }
                data[index * symN + i] =
                    Float(sin(2 * Double.pi * freq * t) * amp)
            }
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
        let airtime = Double(symbols.count)
            * ChirpModem.symbolSeconds
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

final class ChirpListener: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var status = "idle"
    /// Return true when the payload opened — the listener
    /// reports the outcome in its own status line.
    var onPayload: ((Data) -> Bool)?

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    private var processTimer: Timer?
    private var rate = 44100.0
    private var symbolSamples: Int {
        Int(ChirpModem.symbolSeconds * rate)
    }

    private enum State { case hunting, receiving }
    private var state: State = .hunting
    private var consumed = 0
    private var symbols: [Int] = []
    private var nextWindow = 0
    private var huntTrail: [Int] = []

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission {
            [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.begin()
                } else {
                    self.status = "microphone permission denied — "
                        + "iOS Settings is where that changes"
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
        rate = format.sampleRate
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048,
                         format: format) { [weak self] buffer, _ in
            guard let self = self,
                  let channel = buffer.floatChannelData?[0]
            else { return }
            let count = Int(buffer.frameLength)
            self.lock.lock()
            self.samples.append(contentsOf: UnsafeBufferPointer(
                start: channel, count: count))
            let cap = Int(self.rate) * 30
            if self.samples.count > cap {
                let drop = self.samples.count - cap
                self.samples.removeFirst(drop)
                self.consumed = max(0, self.consumed - drop)
                self.nextWindow = max(0, self.nextWindow - drop)
            }
            self.lock.unlock()
        }
        guard (try? engine.start()) != nil else {
            status = "microphone would not start"
            return
        }
        state = .hunting
        consumed = 0
        symbols = []
        huntTrail = []
        listening = true
        status = "listening — hold the phones near each other"
        processTimer = Timer.scheduledTimer(
            withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.process()
        }
    }

    func stop() {
        processTimer?.invalidate()
        processTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        listening = false
        status = "idle"
    }

    // MARK: - decode

    private func process() {
        lock.lock()
        let snapshot = samples
        lock.unlock()
        let sym = symbolSamples
        switch state {
        case .hunting:
            var i = consumed
            while i + sym <= snapshot.count {
                let probe = classify(snapshot, start: i)
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
                        status = "locked — receiving…"
                        consumed = i
                        return
                    }
                }
                i += sym / 2
            }
            consumed = i
        case .receiving:
            while nextWindow + sym <= snapshot.count {
                let probe = classify(snapshot, start: nextWindow)
                guard probe.power > 0.008, probe.margin > 1.5
                else {
                    state = .hunting
                    consumed = nextWindow
                    symbols = []
                    status = "lost that chirp mid-frame — "
                        + "still listening"
                    return
                }
                symbols.append(probe.symbol)
                nextWindow += sym
                if symbols.count % 4 == 0 {
                    let attempt = assemble()
                    if attempt.abort {
                        state = .hunting
                        consumed = nextWindow
                        symbols = []
                        status = "that was not a chirp — "
                            + "still listening"
                        return
                    }
                    if let payload = attempt.payload {
                        state = .hunting
                        consumed = nextWindow
                        symbols = []
                        let opened = onPayload?(payload) ?? false
                        status = opened
                            ? "decoded — filed in the Chirp "
                                + "thread below"
                            : "heard a chirp that does not open "
                                + "with your pairing key"
                        return
                    }
                }
            }
        }
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

    private func classify(_ samples: [Float], start: Int)
        -> (symbol: Int, power: Double, margin: Double) {
        let sym = symbolSamples
        let inset = sym / 6
        let begin = start + inset
        let count = sym - inset * 2
        var powers: [Double] = []
        for freq in ChirpModem.tones {
            powers.append(goertzel(samples, start: begin,
                                   count: count, freq: freq,
                                   rate: rate))
        }
        let ranked = powers.sorted(by: >)
        let winner = powers.firstIndex(of: ranked[0]) ?? 0
        let normalized = ranked[0] / Double(count * count)
        let margin = ranked[0] / max(ranked[1], 1e-9)
        return (winner, normalized, margin)
    }

    private func goertzel(_ samples: [Float], start: Int,
                          count: Int, freq: Double,
                          rate: Double) -> Double {
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
