import Combine
import SwiftUI

/// The Drip (Chase's commission, 2026-10-23): one
/// room that watches the whole device think. Every
/// organ in the house is always analysing something
/// — the ears grading the air, the bench mid-knock,
/// the tap counting frames, Skelli's hands on a
/// process — and until this room each of those
/// truths lived only in its own room. The Drip
/// gathers them: active bars across the top carry
/// the important numbers live, and beneath them the
/// house's own sealed ledger falls, event by event,
/// newest first — a drip, not a dashboard. It reads
/// only what the organs already publish and what
/// the Journal already seals; it starts nothing,
/// stops nothing, and sends nothing.
struct DripView: View {
    @EnvironmentObject private var post: ListeningPost
    @EnvironmentObject private var mouth: Mouth
    @EnvironmentObject private var emcon: Emcon
    @ObservedObject private var board =
        ProcessBoard.shared
    @ObservedObject private var wardrive =
        WardriveCenter.shared
    @ObservedObject private var themes =
        ThemeCenter.shared

    @State private var events: [NightEvent] = []
    @State private var exposure = 0.0
    @State private var exposureBand = ""
    @State private var tapFrames = 0
    @State private var now = Date()
    @State private var pulse: [Int] = Array(
        repeating: 0, count: 24)

    private let clock = Timer.publish(
        every: 2, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading,
                       spacing: 16) {
                    bars
                    pulseStrip
                    nowBoard
                    feed
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle(L("Drip"))
            .navigationBarTitleDisplayMode(.inline)
            .houseToolbarColorScheme()
        }
        .onAppear { refresh() }
        .onReceive(clock) { _ in refresh() }
    }

    private func refresh() {
        now = Date()
        events = Journal.events(limit: 60)
        let score = emcon.currentScore(mouth: mouth)
        exposure = score.value
        exposureBand = score.band
        tapFrames = BetafischTap.shared
            .snapshot().frames
        pulse = Self.pulseBuckets(
            events: events, now: now)
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: 10) {
            meter(
                label: L("Analyzing"),
                value: board.active.isEmpty
                    ? L("idle")
                    : String(format: L("%lld running"),
                             Int64(board.active.count)),
                detail: board.active.first?.label,
                fraction: min(1, Double(
                    board.active.count) / 6),
                tint: themes.current.accent)
            meter(
                label: L("Exposure"),
                value: String(format: "%.1f · %@",
                              exposure, exposureBand),
                detail: nil,
                fraction: min(1, exposure / 100),
                tint: exposure >= 60 ? .red
                    : exposure >= 30 ? .orange
                    : .green)
            meter(
                label: L("Ears"),
                value: post.session == nil
                    ? L("not listening")
                    : String(format: L("%lld heard · %lld sightings"),
                             Int64(post.deviceCount),
                             Int64(post.sightingCount)),
                detail: nil,
                fraction: min(1, Double(
                    post.deviceCount) / 40),
                tint: .teal)
            meter(
                label: L("Tap"),
                value: BetafischTap.shared.enabled
                    ? String(format: L("%lld frames"),
                             Int64(tapFrames))
                    : L("off"),
                detail: nil,
                fraction: min(1, Double(tapFrames)
                    / Double(
                        BetafischTap.frameCap)),
                tint: .purple)
            meter(
                label: L("Mouth"),
                value: mouthLine,
                detail: nil,
                fraction: mouthFraction,
                tint: .pink)
            if wardrive.running {
                meter(
                    label: L("Wardrive"),
                    value: String(
                        format: L("%lld records · %lld devices"),
                        Int64(wardrive.recordCount),
                        Int64(wardrive.uniqueDevices)),
                    detail: nil,
                    fraction: min(1, Double(
                        wardrive.recordCount) / 200),
                    tint: .indigo)
            }
        }
    }

    private var mouthLine: String {
        var organs: [String] = []
        if mouth.serveRunning { organs.append(L("serving")) }
        if mouth.gattHostOn { organs.append(L("GATT host")) }
        if mouth.beaconOn { organs.append(L("beacon")) }
        if mouth.writeScanning { organs.append(L("scanning")) }
        if !mouth.inbox.isEmpty {
            organs.append(String(
                format: L("%lld in the inbox"),
                Int64(mouth.inbox.count)))
        }
        return organs.isEmpty ? L("quiet") : organs.joined(separator: " · ")
    }

    private var mouthFraction: Double {
        var live = 0.0
        if mouth.serveRunning { live += 1 }
        if mouth.gattHostOn { live += 1 }
        if mouth.beaconOn { live += 1 }
        if mouth.writeScanning { live += 1 }
        return live / 4
    }

    private func meter(label: String, value: String,
                       detail: String?,
                       fraction: Double,
                       tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(0.92))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: max(2, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 3)
            if let detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var pulseStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("THE DRIP — LAST FOUR MINUTES").uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            let peak = max(1, pulse.max() ?? 0)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(pulse.enumerated()),
                        id: \.offset) { _, count in
                    RoundedRectangle(
                        cornerRadius: 1.5)
                        .fill(themes.current.accent
                            .opacity(count == 0
                                ? 0.15 : 0.9))
                        .frame(height: 3 + 21
                            * CGFloat(count)
                            / CGFloat(peak))
                }
            }
            .frame(height: 26, alignment: .bottom)
        }
    }

    private var nowBoard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !board.active.isEmpty {
                Text(L("NOW").uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                ForEach(board.active) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 7, height: 7)
                        Text(entry.label)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.organ)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(elapsed(entry.started))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func elapsed(_ start: Date) -> String {
        let seconds = max(0, Int(
            now.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m "
            + "\(seconds % 60)s"
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("THE STREAM").uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            if events.isEmpty {
                Text(L("Nothing in the ledger yet — the house has been quiet."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                HStack(alignment: .top, spacing: 8) {
                    Text(event.module)
                        .font(.caption2
                            .weight(.semibold))
                        .monospaced()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                themes.current.accent
                                    .opacity(0.16)))
                    VStack(alignment: .leading,
                           spacing: 1) {
                        Text(event.text)
                            .font(.callout)
                            .lineLimit(3)
                        Text(Self.clock.string(
                            from: event.when))
                            .font(.caption2)
                            .foregroundStyle(
                                .secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func pulseBuckets(
        events: [NightEvent], now: Date
    ) -> [Int] {
        var buckets = Array(repeating: 0, count: 24)
        for event in events {
            let age = now.timeIntervalSince(event.when)
            if age >= 0, age < 240 {
                buckets[min(23, Int(age) / 10)] += 1
            }
        }
        return Array(buckets.reversed())
    }
}
