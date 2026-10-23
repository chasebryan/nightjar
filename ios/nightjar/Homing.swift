import SwiftUI
import CoreLocation
import Combine

/// The Compass — walk to what the ear hears.
///
/// The ear hears Bluetooth advertisements with a strength
/// attached; strength is a distance told roughly, and a
/// phone has no direction-finding antenna — so this
/// compass does the honest thing and the clever thing.
/// The honest thing: it shows how loud the device is, in
/// bands a walker can use, and whether the loudness is
/// climbing or falling as you move. The clever thing: it
/// watches your course while you walk and lays the gains
/// along the headings that earned them, so a bearing
/// condenses out of your own footsteps — a wedge that
/// starts wide and honest and sharpens as the evidence
/// does. Nothing here is invented: no wedge until you have
/// walked, no precision the signal never gave.

// MARK: - Heading & course

final class CompassSource: NSObject, ObservableObject,
                           CLLocationManagerDelegate {
    @Published var heading: Double?
    @Published var course: Double?
    @Published var speed: Double = 0
    @Published var authorized = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.distanceFilter = 3
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        // The platforms name the grant
        // differently (PlaceCenter.isAuthorized
        // carries the same truth): the laptop's
        // SDK has no when-in-use case to spell.
#if os(iOS)
        let granted = manager.authorizationStatus
            == .authorizedWhenInUse
            || manager.authorizationStatus
                == .authorizedAlways
#else
        let granted = manager.authorizationStatus
            == .authorizedAlways
#endif
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            authorized = granted
            if granted { begin() }
        }
    }

    private func begin() {
        manager.startUpdatingHeading()
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager) {
#if os(iOS)
        if manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            authorized = true
            begin()
        }
#else
        if manager.authorizationStatus == .authorizedAlways {
            authorized = true
            begin()
        }
#endif
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0
            ? newHeading.trueHeading : newHeading.magneticHeading
        DispatchQueue.main.async { self.heading = value }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        DispatchQueue.main.async {
            self.speed = max(0, last.speed)
            self.course = last.course >= 0 ? last.course : nil
        }
    }
}

// MARK: - The hunt state

final class HomingEngine: ObservableObject {
    /// Smoothed strength, 0…1.
    @Published var strength: Double = 0
    @Published var dbm: Double?
    @Published var heard = false
    /// -1 falling, 0 steady, +1 climbing.
    @Published var trend = 0
    /// The learned bearing: a center angle to walk and the
    /// width the evidence still allows, in degrees.
    @Published var wedgeCenter: Double?
    @Published var wedgeWidth: Double = 320
    @Published var walkedEnough = false

    private var smooth: Double?
    private var trail: [(Date, Double)] = []
    private var bins = [Double](repeating: 0, count: 36)
    private var lastBinTime = Date.distantPast

    static func band(_ dbm: Double) -> (String, Int) {
        switch dbm {
        case -55...0: return ("ON TOP OF IT", 0)
        case -68 ..< -55: return ("A FEW STEPS", 1)
        case -78 ..< -68: return ("ACROSS THE ROOM", 2)
        case -88 ..< -78: return ("DOWN THE HALL", 3)
        default: return ("A WHISPER", 3)
        }
    }

    /// One sample from the live rows, plus the walker's
    /// course — the whole instrument in one call.
    func sample(rssi: Double?, course: Double?, speed: Double) {
        let now = Date()
        if let rssi {
            heard = true
            let previous = smooth
            smooth = (previous.map { $0 * 0.62 + rssi * 0.38 }
                      ?? rssi)
            dbm = smooth
            if let smooth {
                strength = min(1, max(0, (smooth + 95) / 60))
                trail.append((now, smooth))
                trail = trail.filter {
                    now.timeIntervalSince($0.0) < 6 }
                if let first = trail.first,
                   now.timeIntervalSince(first.0) > 2.5 {
                    let delta = smooth - first.1
                    trend = delta > 1.2 ? 1
                        : delta < -1.2 ? -1 : 0
                }
                // Lay the gains along the heading that
                // earned them.
                if let course, speed > 0.6,
                   let previous,
                   now.timeIntervalSince(lastBinTime) > 1.2 {
                    let gained = smooth - previous
                    if gained > 0.15 {
                        let bin = Int(course / 10) % 36
                        bins[bin] += gained
                        walkedEnough = true
                    }
                    lastBinTime = now
                }
            }
        } else {
            heard = false
        }
        // The wedge: the weighted mean direction of the
        // gains, its concentration setting the width.
        var x = 0.0, y = 0.0, total = 0.0
        for (index, weight) in bins.enumerated()
        where weight > 0 {
            let angle = Double(index) * 10 * .pi / 180
            x += cos(angle) * weight
            y += sin(angle) * weight
            total += weight
        }
        if total > 0.4 {
            let mean = atan2(y, x) * 180 / .pi
            wedgeCenter = (mean + 360)
                .truncatingRemainder(dividingBy: 360)
            let concentration = min(1,
                (x * x + y * y).squareRoot() / total)
            wedgeWidth = 320 - 285 * concentration
        }
        for index in bins.indices { bins[index] *= 0.998 }
    }
}

// MARK: - The face

struct HomingCompassView: View {
    @EnvironmentObject var post: ListeningPost
    let targetID: String
    let label: String
    var kind: String = ""

    @StateObject private var compass = CompassSource()
    @StateObject private var engine = HomingEngine()
    @Environment(\.dismiss) private var dismiss
    private let timer = Timer.publish(
        every: 0.3, on: .main, in: .common).autoconnect()

    private var theme: AppTheme { ThemeCenter.shared.current }
    private var row: DeviceRow? {
        post.rows.first { $0.id == targetID }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MatrixDots(color: theme.accent.opacity(0.14))
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.headline)
                            .foregroundStyle(theme.glow)
                        if !kind.isEmpty {
                            Text(kind)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(L("Done")) { dismiss() }
                        .foregroundStyle(theme.accent)
                }
                Spacer()
                face
                Spacer()
                readout
            }
            .padding(20)
        }
        .onAppear { compass.start() }
        .onReceive(timer) { _ in
            engine.sample(
                rssi: row?.rssiSmooth
                    ?? row?.rssiLast.map(Double.init),
                course: compass.course,
                speed: compass.speed)
        }
    }

    private var face: some View {
        ZStack {
            // The learned wedge turns with the world; the
            // whole rose turns with the phone.
            ZStack {
                if let center = engine.wedgeCenter,
                   engine.walkedEnough {
                    WedgeShape(width: engine.wedgeWidth)
                        .fill(theme.accent.opacity(0.22))
                        .rotationEffect(.degrees(center))
                }
                Circle()
                    .stroke(theme.accent.opacity(0.25),
                            lineWidth: 1)
                ForEach(0 ..< 4, id: \.self) { quarter in
                    Text(["N", "E", "S", "W"][quarter])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(theme.accent)
                        .offset(y: -118)
                        .rotationEffect(
                            .degrees(Double(quarter) * 90))
                }
            }
            .rotationEffect(
                .degrees(-(compass.heading ?? 0)))
            Circle()
                .stroke(theme.accent.opacity(0.15),
                        lineWidth: 14)
                .frame(width: 190, height: 190)
            Circle()
                .trim(from: 0, to: engine.strength)
                .stroke(theme.accent,
                        style: StrokeStyle(lineWidth: 14,
                                           lineCap: .round))
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                Text(engine.heard
                     ? HomingEngine.band(engine.dbm ?? -99).0
                     : "NOT HEARD")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.glow)
                    .multilineTextAlignment(.center)
                Text(engine.dbm.map {
                    "\(Int($0.rounded())) dBm"
                } ?? "—")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    let band = HomingEngine.band(
                        engine.dbm ?? -99)
                    ForEach(0 ..< 3, id: \.self) { step in
                        Image(systemName: "pawprint.fill")
                            .font(.caption2)
                            .foregroundStyle(
                                step < 3 - band.1
                                    && engine.heard
                                    ? theme.accent
                                    : theme.accent.opacity(0.2))
                    }
                }
            }
            .frame(width: 170)
        }
        .frame(width: 260, height: 260)
    }

    private var readout: some View {
        VStack(spacing: 6) {
            Text(trendText)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.glow)
            Text(hintText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !compass.authorized {
                Text(L("Compass is off — this is signal only. Allow location while in use and the rose and the bearing wake up; the signal never needed them."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var trendText: String {
        guard engine.heard else {
            return "The ear cannot hear it right now."
        }
        switch engine.trend {
        case 1: return "Climbing — this way is warmer."
        case -1: return "Falling — that way was warmer."
        default: return "Steady. Keep walking."
        }
    }

    private var hintText: String {
        if engine.walkedEnough, engine.wedgeCenter != nil {
            return engine.wedgeWidth < 70
                ? "The bearing has condensed. Walk the wedge."
                : "A bearing is condensing from your steps — "
                    + "it sharpens as you walk."
        }
        return "Walk slow — the ring fills as you close in, "
            + "and your steps teach it which way."
    }
}

/// A wedge sector centered on up (0°), `width` degrees wide.
struct WedgeShape: Shape {
    var width: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(-90 - width / 2),
                    endAngle: .degrees(-90 + width / 2),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The matrix's dot field, shared by the compass and the Map.
struct MatrixDots: View {
    var color: Color = .white
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 26
            var x: CGFloat = step / 2
            while x < size.width {
                var y: CGFloat = step / 2
                while y < size.height {
                    let dot = CGRect(x: x - 1, y: y - 1,
                                     width: 2, height: 2)
                    context.fill(Path(ellipseIn: dot),
                                 with: .color(color))
                    y += step
                }
                x += step
            }
        }
    }
}


/// The matrix's slow radar sweep — a wedge turning over
/// the dot field, for the Map's canvas.
struct MatrixSweep: View {
    var color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) {
            timeline in
            WedgeShape(width: 55)
                .fill(color.opacity(0.09))
                .rotationEffect(.degrees(
                    timeline.date
                        .timeIntervalSinceReferenceDate * 24
                        .truncatingRemainder(dividingBy: 360)))
        }
    }
}
