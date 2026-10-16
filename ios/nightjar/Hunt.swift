import AVFoundation
import SwiftUI
import UIKit

/// A short sine beep with a smooth envelope — the hunt's voice.
final class HuntTone {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    func beep(frequency: Double) {
        if !started {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode,
                           format: nil)
            try? engine.start()
            player.play()
            started = true
        }
        let sampleRate = 44100.0
        let duration = 0.07
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let envelope = sin(Double.pi * Double(i)
                               / Double(frames))
            data[i] = Float(sin(2 * Double.pi * frequency * t)
                            * envelope * 0.35)
        }
        player.scheduleBuffer(buffer)
    }

    func stop() {
        guard started else { return }
        player.stop()
        engine.stop()
        started = false
    }
}

/// Tracker hunt: a Geiger counter for one advertiser.
///
/// Listen hears; this walks you onto the signal. Pick a device
/// — the tag in the car, the unknown regular in the house — and
/// the hunt reads its smoothed RSSI aloud: beeps that quicken
/// and rise as you close in, a haptic thump when you're near,
/// and the honest counters (closest ever, seconds since last
/// heard) underneath. The ears were already there; this is the
/// needle.
struct HuntView: View {
    @EnvironmentObject private var post: ListeningPost
    @Environment(\.dismiss) private var dismiss
    let targetID: String

    @State private var tone = HuntTone()
    @State private var haptics = UIImpactFeedbackGenerator(
        style: .medium)
    @State private var lastBeep = Date.distantPast
    @State private var now = Date()

    private let tick = Timer.publish(every: 0.2, on: .main,
                                     in: .common).autoconnect()

    private var row: DeviceRow? {
        post.rows.first { $0.id == targetID }
    }
    private var rssi: Double? {
        row?.rssiSmooth ?? row?.rssiLast.map(Double.init)
    }
    private var strength: Double {
        guard let rssi = rssi else { return 0 }
        return min(1, max(0, (rssi + 95) / 60))
    }
    private var age: TimeInterval? {
        row.map { now.timeIntervalSince1970 - $0.lastSeen }
    }
    private var fresh: Bool {
        guard let age = age else { return false }
        return age < 3
    }
    private var proximity: String {
        guard let rssi = rssi else { return "NOT HEARD" }
        switch rssi {
        case -45...0: return "ON TOP OF IT"
        case -60 ..< -45: return "CLOSE"
        case -72 ..< -60: return "NEAR"
        case -85 ..< -72: return "FAR"
        default: return "EDGE OF EARSHOT"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(row?.label ?? "Unknown device")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(row?.kind ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !post.isListening {
                    Text("The hunt needs live ears.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Start listening") {
                        post.start(label: "hunt")
                    }
                    .buttonStyle(.borderedProminent)
                } else if row == nil {
                    Text("Not heard in this session yet. It may "
                         + "be asleep, out of range — or, if it "
                         + "rotates its address, gone under a new "
                         + "one.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text(rssi.map {
                        String(format: "%.0f dBm", $0) } ?? "—")
                        .font(.system(size: 56, weight: .bold,
                                      design: .monospaced))
                    Text(proximity)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(
                            fresh ? Color.green : Color.secondary)
                    ProgressView(value: strength)
                        .progressViewStyle(.linear)
                        .tint(fresh ? .green : .gray)
                    Grid(alignment: .leading, horizontalSpacing: 16,
                         verticalSpacing: 4) {
                        GridRow {
                            Text("Closest ever").foregroundStyle(.secondary)
                            Text(row?.rssiClosest.map {
                                "\($0) dBm" } ?? "—")
                        }
                        GridRow {
                            Text("Sightings").foregroundStyle(.secondary)
                            Text("\(row?.sightings ?? 0)")
                        }
                        GridRow {
                            Text("Last heard").foregroundStyle(.secondary)
                            Text(age.map {
                                String(format: "%.0f s ago", $0) }
                                ?? "—")
                        }
                    }
                    .font(.callout)
                    if row?.rotatingAddress == true {
                        Text("This advertiser rotates its address "
                             + "— if it goes quiet mid-hunt, it "
                             + "may have stepped sideways into a "
                             + "new identity rather than away.")
                            .font(.caption).foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer()
                Text("Beeps quicken and rise as the signal "
                     + "strengthens; a thump means you're near. "
                     + "Walk slow — RSSI is a compass that "
                     + "points in loudness, not direction.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Hunt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onReceive(tick) { stamp in
                now = stamp
                step()
            }
            .onDisappear { tone.stop() }
        }
    }

    private func step() {
        guard post.isListening, fresh, let rssi = rssi
        else { return }
        let interval = 1.3 - strength * 1.15
        guard Date().timeIntervalSince(lastBeep) >= interval
        else { return }
        lastBeep = Date()
        tone.beep(frequency: 550 + strength * 750)
        if strength > 0.7 {
            haptics.impactOccurred(intensity: strength)
        }
        _ = rssi
    }
}
