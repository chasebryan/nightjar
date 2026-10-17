import Foundation

/// Cadence Seal: the second factor made of timing.
///
/// A knock sequence carries more than ports — it carries the
/// rhythm of whatever knocked it: the sender's pacing, its
/// pauses, its hurry. Two devices running the same sender at
/// the same nominal pace still differ in the small statistics
/// of their timing, and a foreign sender — a script, a
/// different hand, a different machine — differs plainly.
/// Cadence Seal profiles a peer's knock timing from the
/// messages it sends (three samples enroll a peer), then
/// grades every later message: these hands, or foreign ones.
///
/// The seal never blocks a message. The pairing key decides
/// what opens; cadence decides what is *believed*. A message
/// that opens under the right key but arrives in a foreign
/// cadence is shown flagged, and the night log remembers —
/// because the day a paired device is cloned, the key will
/// still be right, and the hands will be wrong.
struct CadenceSample {
    /// Length-independent timing features (see CadenceMath).
    let features: [Double]
    let knocks: Int
    let when: Date
}

enum CadenceMath {
    /// Six features of a knock train, comparable across
    /// messages of different lengths:
    /// [0] mean gap (s)            [3] longest gap / median
    /// [1] gap stdev / mean        [4] second-half / first-half mean
    /// [2] shortest gap / median   [5] hesitation share (gaps > 2.5x median)
    static func sample(times: [Date]) -> CadenceSample? {
        guard times.count >= 8 else { return nil }
        let sorted = times.sorted()
        var gaps: [Double] = []
        for i in 1..<sorted.count {
            gaps.append(sorted[i].timeIntervalSince(sorted[i - 1]))
        }
        guard !gaps.isEmpty else { return nil }
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        guard mean > 0.01 else { return nil }
        let variance = gaps.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(gaps.count)
        let median = gaps.sorted()[gaps.count / 2]
        guard median > 0.01 else { return nil }
        let half = gaps.count / 2
        let firstMean = half > 0
            ? gaps[..<half].reduce(0, +) / Double(half) : mean
        let secondMean = half > 0
            ? gaps[half...].reduce(0, +) / Double(gaps.count - half)
            : mean
        let hesitations = gaps.filter { $0 > 2.5 * median }.count
        let features: [Double] = [
            mean,
            sqrt(variance) / mean,
            (gaps.min() ?? median) / median,
            (gaps.max() ?? median) / median,
            firstMean > 0.01 ? secondMean / firstMean : 1.0,
            Double(hesitations) / Double(gaps.count),
        ]
        return CadenceSample(features: features,
                             knocks: sorted.count, when: sorted.last!)
    }
}

enum CadenceSeal {
    struct Profile: Codable {
        var peer: String
        var samples: Int
        var mean: [Double]
        var m2: [Double]   // Welford sum of squares per feature

        mutating func learn(_ f: [Double]) {
            samples += 1
            if mean.isEmpty {
                mean = f
                m2 = [Double](repeating: 0, count: f.count)
                return
            }
            for i in f.indices {
                let delta = f[i] - mean[i]
                mean[i] += delta / Double(samples)
                m2[i] += delta * (f[i] - mean[i])
            }
        }

        func std(_ i: Int) -> Double {
            guard samples > 1, m2.indices.contains(i) else {
                return 0.25
            }
            return sqrt(max(m2[i] / Double(samples - 1), 0.0004))
        }
    }

    enum Verdict {
        case unenrolled
        case learning(have: Int, need: Int)
        case match(score: Double)
        case foreign(score: Double)
    }

    static let enrollSamples = 3
    /// Z-distance under which hands are called the same.
    static let matchThreshold = 2.2

    private static let storeKey = "cadence.profiles"

    static var enabled: Bool {
        // Default on: the seal only annotates; it never blocks.
        UserDefaults.standard.object(forKey: "cadenceSealOn") == nil
            || UserDefaults.standard.bool(forKey: "cadenceSealOn")
    }

    private static func load() -> [String: Profile] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode(
                  [String: Profile].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func save(_ profiles: [String: Profile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    static func profile(for peer: String) -> Profile? {
        load()[peer]
    }

    static func reset(peer: String) {
        var profiles = load()
        profiles[peer] = nil
        save(profiles)
    }

    static func resetAll() {
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    /// Feed one completed message's timing. Returns the verdict
    /// for THIS sample: while a peer is enrolling, the sample
    /// teaches; once enrolled, the sample is judged first and
    /// then — only if it matched — folded in, so a foreign hand
    /// cannot train the seal to accept it.
    static func record(peer: String, sample: CadenceSample) -> Verdict {
        var profiles = load()
        var profile = profiles[peer]
            ?? Profile(peer: peer, samples: 0, mean: [], m2: [])
        if profile.samples < enrollSamples {
            profile.learn(sample.features)
            profiles[peer] = profile
            save(profiles)
            return .learning(have: profile.samples,
                             need: enrollSamples)
        }
        var sum = 0.0
        for i in sample.features.indices {
            let z = (sample.features[i] - profile.mean[i])
                / (profile.std(i) + 0.05)
            sum += z * z
        }
        let distance = sqrt(sum / Double(sample.features.count))
        if distance < matchThreshold {
            profile.learn(sample.features)
            profiles[peer] = profile
            save(profiles)
            return .match(score: distance)
        }
        return .foreign(score: distance)
    }

    /// The line the chat thread shows for a verdict.
    static func note(for verdict: Verdict) -> String? {
        switch verdict {
        case .unenrolled:
            return nil
        case .learning(let have, let need):
            return "cadence seal: learning these hands "
                + "(\(have)/\(need))"
        case .match:
            return "cadence seal: these hands ✓"
        case .foreign:
            return "cadence seal: FOREIGN HANDS — right key, "
                + "wrong rhythm"
        }
    }
}
