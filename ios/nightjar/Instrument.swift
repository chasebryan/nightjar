import Foundation
import HealthKit

/// The Instrument — the Apple Watch, read.
///
/// The watch is never asked to do anything: no watch app,
/// no session, no tap. Worn and paired, it already measures
/// the operator and leaves the readings in this phone's
/// health store. The Instrument reads them — heart, breath,
/// blood, temperature, sleep — and sets the state of the
/// operator beside the state of the house.
///
/// Honest limits, by construction: this is a reading, not a
/// live feed. Samples arrive at the watch's own sync cadence
/// — minutes apart at rest — and every value carries its
/// age. Nothing is written to the health store, nothing is
/// journaled raw, and nothing leaves the device.
///
/// Like the Coin, the Instrument sleeps under a signing
/// that does not carry its entitlement: the code stays,
/// the section reports itself dormant, and nothing breaks.

struct SleepWindow: Equatable {
    let start: Date
    let end: Date
}

struct VitalReading {
    /// Fully formatted: "72 bpm", "98%", "36.4 °C".
    let value: String
    let when: Date
    let source: String?
}

final class InstrumentCenter: ObservableObject {
    static let shared = InstrumentCenter()
    static let sleepUpdated = Notification.Name(
        "instrument.sleep.updated")
    static let baselinesUpdated = Notification.Name(
        "instrument.baselines.updated")

    enum Phase: Equatable {
        case unknown
        case asking
        case reading
        case dormant
        case unavailable
    }

    @Published private(set) var phase: Phase = .unknown
    @Published private(set) var heartRate: VitalReading?
    @Published private(set) var hrv: VitalReading?
    @Published private(set) var restingHeartRate: VitalReading?
    @Published private(set) var oxygen: VitalReading?
    @Published private(set) var respiratory: VitalReading?
    @Published private(set) var wristTemp: VitalReading?
    @Published private(set) var stepsToday: Int?
    @Published private(set) var lastSleep: SleepWindow?
    /// The operator against himself: fortnight means,
    /// learned from the same store. Nil until enough
    /// days of record exist to mean anything.
    @Published private(set) var restingBaseline: Double?
    @Published private(set) var sleepBaselineHours: Double?
    @Published private(set) var restingLatest: Double?
    /// When the latest resting reading was taken —
    /// a latest without a date can be silently
    /// stale, and the Subconscious's comparison
    /// deserves to know which it holds.
    @Published private(set) var restingLatestAt: Date?
    /// Variability and wrist temperature, reckoned
    /// the same way — both were fetched for display
    /// and thought with by nobody; against their
    /// own baselines they are the operator-state
    /// signals with the most to say.
    @Published private(set) var hrvBaseline: Double?
    @Published private(set) var hrvLatest: Double?
    @Published private(set) var tempBaseline: Double?
    @Published private(set) var tempLatest: Double?
    @Published private(set) var watchName: String?
    @Published private(set) var lastReadAt: Date?

    private let store = HKHealthStore()

    init() {
        if !HKHealthStore.isHealthDataAvailable() {
            phase = .unavailable
        }
    }

    // MARK: - the reading types

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for id in [HKQuantityTypeIdentifier.heartRate,
                   .heartRateVariabilitySDNN,
                   .restingHeartRate,
                   .oxygenSaturation,
                   .respiratoryRate,
                   .appleSleepingWristTemperature,
                   .stepCount] {
            if let t = HKObjectType.quantityType(forIdentifier: id) {
                types.insert(t)
            }
        }
        if let sleep = HKObjectType.categoryType(
            forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    // MARK: - asking

    /// The one conversation the Instrument ever has with the
    /// operator. Apple's sheet decides what is shared; read
    /// permission can never be confirmed back (by design),
    /// so success here means "asked" — the readings, or
    /// their absence, say the rest.
    func requestAccess() {
        guard phase != .unavailable else { return }
        phase = .asking
        store.requestAuthorization(toShare: [], read: readTypes) {
            [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error,
                   error.localizedDescription
                       .lowercased().contains("entitlement") {
                    self.phase = .dormant
                    return
                }
                self.phase = .reading
                if success { self.fetchAll() }
            }
        }
    }

    // MARK: - reading

    func fetchAll() {
        guard phase == .reading || phase == .unknown else { return }
        if phase == .unknown { phase = .reading }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        latest(.heartRate, unit: bpm,
               assign: { self.heartRate = $0 }) {
            VitalReading(value: "\(Int($0.rounded())) bpm",
                         when: $1, source: $2)
        }
        latest(.heartRateVariabilitySDNN,
               unit: .secondUnit(with: .milli),
               assign: { self.hrv = $0 }) {
            VitalReading(value: "\(Int($0.rounded())) ms",
                         when: $1, source: $2)
        }
        latest(.restingHeartRate, unit: bpm,
               assign: { self.restingHeartRate = $0 }) {
            VitalReading(value: "\(Int($0.rounded())) bpm",
                         when: $1, source: $2)
        }
        latest(.oxygenSaturation, unit: .percent(),
               assign: { self.oxygen = $0 }) {
            VitalReading(value: "\(Int(($0 * 100).rounded()))%",
                         when: $1, source: $2)
        }
        latest(.respiratoryRate, unit: bpm,
               assign: { self.respiratory = $0 }) {
            VitalReading(value: String(format: "%.1f /min", $0),
                         when: $1, source: $2)
        }
        latest(.appleSleepingWristTemperature,
               unit: .degreeCelsius(),
               assign: { self.wristTemp = $0 }) {
            VitalReading(value: String(format: "%.1f °C", $0),
                         when: $1, source: $2)
        }
        fetchSteps()
        fetchSleep()
        fetchBaselines()
        DispatchQueue.main.async { [weak self] in
            self?.lastReadAt = Date()
        }
    }

    private func latest(
        _ id: HKQuantityTypeIdentifier, unit: HKUnit,
        assign: @escaping (VitalReading?) -> Void,
        format: @escaping (Double, Date, String?) -> VitalReading
    ) {
        guard let type = HKObjectType.quantityType(
            forIdentifier: id) else { return }
        let sort = [NSSortDescriptor(
            key: HKSampleSortIdentifierEndDate, ascending: false)]
        let query = HKSampleQuery(
            sampleType: type, predicate: nil,
            limit: 1, sortDescriptors: sort) {
            [weak self] _, samples, error in
            if let error = error,
               error.localizedDescription
                   .lowercased().contains("entitlement") {
                DispatchQueue.main.async { self?.phase = .dormant }
                return
            }
            let sample = samples?.first as? HKQuantitySample
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let sample = sample {
                    if id == .restingHeartRate {
                        self.restingLatest = sample.quantity
                            .doubleValue(for: unit)
                        self.restingLatestAt = sample.endDate
                    }
                    let reading = format(
                        sample.quantity.doubleValue(for: unit),
                        sample.endDate,
                        sample.sourceRevision.source.name)
                    assign(reading)
                    if let source = reading.source,
                       source.contains("Watch"),
                       self.watchName == nil {
                        self.watchName = source
                    }
                } else {
                    assign(nil)
                }
            }
        }
        store.execute(query)
    }

    private func fetchSteps() {
        guard let type = HKObjectType.quantityType(
            forIdentifier: .stepCount) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: nil, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: type, quantitySamplePredicate: predicate,
            options: .cumulativeSum) { [weak self] _, stats, _ in
            let steps = stats?.sumQuantity()?.doubleValue(
                for: .count())
            DispatchQueue.main.async {
                self?.stepsToday = steps.map(Int.init)
            }
        }
        store.execute(query)
    }

    /// One vital's fortnight reckoning: daily means
    /// over complete days only — the enumeration
    /// stops at this morning, so no partial day
    /// blunts the mean — with the newest complete
    /// day standing outside the baseline as the
    /// latest, so every latest/baseline pair the
    /// Subconscious compares is consistent by
    /// construction. Needs five days of record.
    private func dailyBaseline(
        _ id: HKQuantityTypeIdentifier, unit: HKUnit,
        apply: @escaping (Double, Double, Date) -> Void) {
        guard let type = HKObjectType.quantityType(
            forIdentifier: id) else { return }
        let anchor = Calendar.current.startOfDay(
            for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: anchor.addingTimeInterval(
                -14 * 24 * 3600),
            end: nil, options: .strictStartDate)
        let query = HKStatisticsCollectionQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: .discreteAverage,
            anchorDate: anchor,
            intervalComponents: DateComponents(day: 1))
        query.initialResultsHandler = { _, results, _ in
            var daily: [Double] = []
            results?.enumerateStatistics(
                from: anchor.addingTimeInterval(
                    -14 * 24 * 3600),
                to: anchor) { stats, _ in
                if let avg = stats.averageQuantity() {
                    daily.append(avg.doubleValue(for: unit))
                }
            }
            guard daily.count >= 5,
                  let latest = daily.last else { return }
            let baseDays = daily.count >= 6
                ? Array(daily.dropLast()) : daily
            let mean = baseDays.reduce(0, +)
                / Double(baseDays.count)
            DispatchQueue.main.async {
                apply(mean, latest, anchor)
            }
        }
        store.execute(query)
    }

    /// The operator's fortnight baselines: mean daily
    /// resting heart rate and mean night's sleep, each
    /// only once at least five days of record stand
    /// behind them. The Subconscious reads the operator
    /// against these.
    func fetchBaselines() {
        guard phase == .reading || phase == .unknown else {
            return
        }
        // Resting heart, daily means over the fortnight.
        let bpm = HKUnit.count().unitDivided(by: .minute())
        dailyBaseline(.restingHeartRate, unit: bpm) {
            [weak self] mean, latestDay, anchor in
            guard let self = self else { return }
            let changed = self.restingBaseline != mean
            self.restingBaseline = mean
            if self.restingLatestAt == nil
                || self.restingLatestAt! < anchor {
                self.restingLatest = latestDay
                self.restingLatestAt = anchor
            }
            if changed {
                NotificationCenter.default.post(
                    name: Self.baselinesUpdated, object: nil)
            }
        }
        // Variability and wrist temperature: the
        // same reckoning, against themselves.
        dailyBaseline(.heartRateVariabilitySDNN,
                      unit: .secondUnit(with: .milli)) {
            [weak self] mean, latest, _ in
            guard let self = self else { return }
            let changed = self.hrvBaseline != mean
            self.hrvBaseline = mean
            self.hrvLatest = latest
            if changed {
                NotificationCenter.default.post(
                    name: Self.baselinesUpdated, object: nil)
            }
        }
        dailyBaseline(.appleSleepingWristTemperature,
                      unit: .degreeCelsius()) {
            [weak self] mean, latest, _ in
            guard let self = self else { return }
            let changed = self.tempBaseline != mean
            self.tempBaseline = mean
            self.tempLatest = latest
            if changed {
                NotificationCenter.default.post(
                    name: Self.baselinesUpdated, object: nil)
            }
        }
        // Sleep: cluster the fortnight's asleep samples
        // into nights, average the real ones.
        if let type = HKObjectType.categoryType(
            forIdentifier: .sleepAnalysis) {
            let predicate = HKQuery.predicateForSamples(
                withStart: Date().addingTimeInterval(
                    -14 * 24 * 3600),
                end: nil, options: .strictStartDate)
            let sort = [NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: true)]
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort) { [weak self] _, samples, _ in
                let asleep = (samples as? [HKCategorySample]
                    ?? []).filter {
                    [.asleepUnspecified, .asleepCore,
                     .asleepDeep, .asleepREM].contains(
                        HKCategoryValueSleepAnalysis(
                            rawValue: $0.value) ?? .inBed)
                }.sorted { $0.startDate < $1.startDate }
                var nights: [TimeInterval] = []
                var start: Date?, end: Date?
                for sample in asleep {
                    if let e = end,
                       sample.startDate.timeIntervalSince(e)
                           > 90 * 60 {
                        if let st = start {
                            nights.append(
                                e.timeIntervalSince(st))
                        }
                        start = sample.startDate
                        end = sample.endDate
                    } else {
                        if start == nil {
                            start = sample.startDate
                        }
                        end = max(end ?? sample.endDate,
                                  sample.endDate)
                    }
                }
                if let st = start, let e = end {
                    nights.append(e.timeIntervalSince(st))
                }
                let real = nights.filter { $0 >= 3 * 3600 }
                guard real.count >= 5 else { return }
                let meanHours = real.reduce(0, +)
                    / Double(real.count) / 3600
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    let changed = self
                        .sleepBaselineHours != meanHours
                    self.sleepBaselineHours = meanHours
                    if changed {
                        NotificationCenter.default.post(
                            name: Self.baselinesUpdated,
                            object: nil)
                    }
                }
            }
            store.execute(query)
        }
    }

    /// The most recent night's sleep, as a window: walk back
    /// from the newest asleep sample while the gaps stay
    /// under ninety minutes. Other organs ask for this —
    /// the Subconscious reads the night against it.
    func fetchSleep(completion: ((SleepWindow?) -> Void)? = nil) {
        guard let type = HKObjectType.categoryType(
            forIdentifier: .sleepAnalysis) else {
            completion?(nil)
            return
        }
        let from = Date().addingTimeInterval(-40 * 3600)
        let predicate = HKQuery.predicateForSamples(
            withStart: from, end: nil, options: .strictStartDate)
        let sort = [NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate, ascending: true)]
        let query = HKSampleQuery(
            sampleType: type, predicate: predicate,
            limit: HKObjectQueryNoLimit, sortDescriptors: sort) {
            [weak self] _, samples, _ in
            let asleep = (samples as? [HKCategorySample] ?? [])
                .filter {
                    [.asleepUnspecified, .asleepCore, .asleepDeep,
                     .asleepREM].contains(
                        HKCategoryValueSleepAnalysis(
                            rawValue: $0.value) ?? .inBed)
                }
                .sorted { $0.startDate < $1.startDate }
            var window: SleepWindow?
            if let newest = asleep.last {
                var start = newest.startDate
                var end = newest.endDate
                var i = asleep.count - 2
                while i >= 0 {
                    let s = asleep[i]
                    if start.timeIntervalSince(s.endDate) > 90 * 60 {
                        break
                    }
                    start = min(start, s.startDate)
                    end = max(end, s.endDate)
                    i -= 1
                }
                window = SleepWindow(start: start, end: end)
            }
            DispatchQueue.main.async {
                guard let self = self else {
                    completion?(window)
                    return
                }
                let changed = window != self.lastSleep
                self.lastSleep = window
                completion?(window)
                if changed, window != nil {
                    NotificationCenter.default.post(
                        name: Self.sleepUpdated, object: nil)
                }
            }
        }
        store.execute(query)
    }

    // MARK: - presentation helpers

    /// "just now", "4 min ago", "2 h ago", "Tue 21:14".
    static func ageLine(_ when: Date) -> String {
        let seconds = Date().timeIntervalSince(when)
        if seconds < 90 { return L("just now") }
        if seconds < 3600 { return String(format: L("%lld min ago"), Int(seconds / 60)) }
        if seconds < 24 * 3600 { return String(format: L("%lld h ago"), Int(seconds / 3600)) }
        return when.formatted(date: .abbreviated, time: .shortened)
    }

    static func durationLine(_ window: SleepWindow) -> String {
        let total = Int(window.end.timeIntervalSince(window.start))
        return "\(total / 3600) h \((total % 3600) / 60) min"
    }
}
