import SwiftUI
import CoreLocation
import Combine

/// Her sense of place: she knows what part of
/// the world she is in, precisely, and reads
/// the sky over it. The fix comes from the
/// phone's own location services; the weather
/// from Open-Meteo, a keyless service, fetched
/// only when she is asked — coordinates leave
/// the phone at that moment and no other, and
/// nothing about place is ever stored. Her
/// switch is `place.enabled` in her Options;
/// while it is off she is honestly placeless.

// MARK: - Snapshots

struct PlaceSnapshot: Equatable {
    var city: String?
    var region: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var timeZone: TimeZone
    var at: Date

    var nameLine: String {
        [city, region, country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct WeatherSnapshot {
    var placeName: String
    var temperature: Double
    var feelsLike: Double
    var humidity: Int
    var code: Int
    var windSpeed: Double
    var windCompass: String
    var pressure: Double
    var high: Double
    var low: Double
    var sunrise: String
    var sunset: String
    var tomorrowHigh: Double
    var tomorrowLow: Double
    var tomorrowCode: Int
    var tomorrowPrecipChance: Int?
    var rainChanceNext12h: Int?
    var at: Date
    var fahrenheit: Bool
}

// MARK: - The center

final class PlaceCenter: NSObject, ObservableObject,
                         CLLocationManagerDelegate {
    static let shared = PlaceCenter()

    @Published private(set) var snapshot: PlaceSnapshot?
    @Published private(set) var weather: WeatherSnapshot?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var weatherSpot: (lat: Double, lon: Double)?
    private var fixWaiters:
        [CheckedContinuation<PlaceSnapshot?, Never>] = []
    private var wantsFix = false

    /// Her switch, defaulting on: the sense is
    /// hers unless the operator closes it.
    var enabled: Bool {
        UserDefaults.standard.object(forKey: "place.enabled")
            as? Bool ?? true
    }

    var authorization: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy =
            kCLLocationAccuracyNearestTenMeters
    }

    // MARK: the fix

    /// One fix, cached for ten minutes: where
    /// the house stands, named by the system's
    /// own geocoder. Nil when the sense is off,
    /// barred, or the satellites stay silent.
    func fix() async -> PlaceSnapshot? {
        guard enabled else { return nil }
        if let snap = snapshot,
           Date().timeIntervalSince(snap.at) < 600 {
            return snap
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return await withCheckedContinuation {
                waiter in
                fixWaiters.append(waiter)
                if fixWaiters.count == 1 {
                    manager.requestLocation()
                }
            }
        case .notDetermined:
            wantsFix = true
            manager.requestWhenInUseAuthorization()
            return nil
        default:
            return nil
        }
    }

    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager) {
        if (manager.authorizationStatus
                == .authorizedWhenInUse
                || manager.authorizationStatus
                    == .authorizedAlways), wantsFix {
            wantsFix = false
            Task { _ = await fix() }
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations:
                            [CLLocation]) {
        guard let fix = locations.last else { return }
        geocoder.reverseGeocodeLocation(fix) {
            [weak self] marks, _ in
            guard let self else { return }
            let mark = marks?.first
            let snap = PlaceSnapshot(
                city: mark?.locality,
                region: mark?.administrativeArea,
                country: mark?.country,
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                timeZone: mark?.timeZone
                    ?? TimeZone.current,
                at: Date())
            DispatchQueue.main.async {
                self.snapshot = snap
                let waiters = self.fixWaiters
                self.fixWaiters = []
                waiters.forEach { $0.resume(returning: snap) }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0.resume(returning: nil) }
    }

    // MARK: the weather

    private struct Meteo: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double
            let relative_humidity_2m: Int
            let apparent_temperature: Double
            let weather_code: Int
            let wind_speed_10m: Double
            let wind_direction_10m: Double
            let pressure_msl: Double
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let sunrise: [String]
            let sunset: [String]
            let weather_code: [Int]
            let precipitation_probability_max: [Int?]
        }
        struct Hourly: Decodable {
            let time: [String]
            let precipitation_probability: [Int?]
        }
        let current: Current
        let daily: Daily
        let hourly: Hourly
    }

    private struct GeoResult: Decodable {
        struct Hit: Decodable {
            let name: String
            let admin1: String?
            let country: String?
            let latitude: Double
            let longitude: Double
            let timezone: String
        }
        let results: [Hit]?
    }

    private var useFahrenheit: Bool {
        Locale.current.measurementSystem == .us
    }

    /// Resolve a named place anywhere on Earth
    /// to coordinates and its own timezone.
    func geocode(_ query: String) async
        -> (name: String, lat: Double, lon: Double,
            tz: TimeZone)? {
        var comps = URLComponents(
            string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared
                .data(from: url),
              let decoded = try? JSONDecoder().decode(
                GeoResult.self, from: data),
              let hit = decoded.results?.first
        else { return nil }
        let name = [hit.name, hit.admin1, hit.country]
            .compactMap { $0 }
            .joined(separator: ", ")
        return (name, hit.latitude, hit.longitude,
                TimeZone(identifier: hit.timezone)
                    ?? TimeZone.current)
    }

    func fetchWeather(lat: Double, lon: Double,
                      name: String, tz: TimeZone) async
        -> WeatherSnapshot? {
        let fahr = useFahrenheit
        var comps = URLComponents(
            string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude",
                         value: String(lat)),
            URLQueryItem(name: "longitude",
                         value: String(lon)),
            URLQueryItem(name: "current",
                         value: "temperature_2m,"
                            + "relative_humidity_2m,"
                            + "apparent_temperature,"
                            + "weather_code,"
                            + "wind_speed_10m,"
                            + "wind_direction_10m,"
                            + "pressure_msl"),
            URLQueryItem(name: "hourly",
                         value: "precipitation_probability"),
            URLQueryItem(name: "daily",
                         value: "temperature_2m_max,"
                            + "temperature_2m_min,sunrise,"
                            + "sunset,weather_code,"
                            + "precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days",
                         value: "3"),
            URLQueryItem(name: "temperature_unit",
                         value: fahr ? "fahrenheit"
                                     : "celsius"),
            URLQueryItem(name: "wind_speed_unit",
                         value: fahr ? "mph" : "kmh"),
        ]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared
                .data(from: url),
              let m = try? JSONDecoder().decode(
                Meteo.self, from: data),
              m.daily.temperature_2m_max.count > 1
        else { return nil }

        // Rain over the next twelve hours: the
        // wettest hour's odds from the hour the
        // service itself calls now, forward.
        var rain: Int? = nil
        let hourPrefix = String(m.current.time.prefix(13))
        if let start = m.hourly.time.firstIndex(
            where: { $0.hasPrefix(hourPrefix) }) {
            rain = m.hourly.precipitation_probability[
                start..<min(start + 12,
                            m.hourly.time.count)]
                .compactMap { $0 }.max()
        }

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        dayFmt.timeZone = tz
        let clockFmt = DateFormatter()
        clockFmt.dateStyle = .none
        clockFmt.timeStyle = .short
        clockFmt.timeZone = tz
        func clock(_ raw: String) -> String {
            dayFmt.date(from: raw).map {
                clockFmt.string(from: $0)
            } ?? raw
        }
        let compassPoints = ["N", "NNE", "NE", "ENE",
                             "E", "ESE", "SE", "SSE",
                             "S", "SSW", "SW", "WSW",
                             "W", "WNW", "NW", "NNW"]
        let compass = compassPoints[
            Int((m.current.wind_direction_10m + 11.25)
                / 22.5) % 16]
        return WeatherSnapshot(
            placeName: name,
            temperature: m.current.temperature_2m,
            feelsLike: m.current.apparent_temperature,
            humidity: m.current.relative_humidity_2m,
            code: m.current.weather_code,
            windSpeed: m.current.wind_speed_10m,
            windCompass: compass,
            pressure: m.current.pressure_msl,
            high: m.daily.temperature_2m_max[0],
            low: m.daily.temperature_2m_min[0],
            sunrise: clock(m.daily.sunrise[0]),
            sunset: clock(m.daily.sunset[0]),
            tomorrowHigh: m.daily.temperature_2m_max[1],
            tomorrowLow: m.daily.temperature_2m_min[1],
            tomorrowCode: m.daily.weather_code[1],
            tomorrowPrecipChance:
                m.daily.precipitation_probability_max[1],
            rainChanceNext12h: rain,
            at: Date(),
            fahrenheit: fahr)
    }

    /// The weather where she stands, cached for
    /// fifteen minutes against the spot it was
    /// read at.
    func weatherHere() async -> WeatherSnapshot? {
        guard let snap = await fix() else { return nil }
        if let w = weather, let spot = weatherSpot,
           Date().timeIntervalSince(w.at) < 900,
           abs(spot.lat - snap.latitude) < 0.01,
           abs(spot.lon - snap.longitude) < 0.01 {
            return w
        }
        let fresh = await fetchWeather(
            lat: snap.latitude, lon: snap.longitude,
            name: snap.nameLine, tz: snap.timeZone)
        if let fresh {
            weather = fresh
            weatherSpot = (snap.latitude, snap.longitude)
        }
        return fresh
    }

    /// The weather over a named place, anywhere.
    func weatherElsewhere(_ query: String) async
        -> WeatherSnapshot? {
        guard let hit = await geocode(query)
        else { return nil }
        return await fetchWeather(lat: hit.lat,
                                  lon: hit.lon,
                                  name: hit.name,
                                  tz: hit.tz)
    }

    // MARK: her words for it

    /// What the WMO sky-codes mean, in words.
    static func conditionWord(_ code: Int) -> String {
        switch code {
        case 0: return L("clear sky")
        case 1: return L("mainly clear")
        case 2: return L("partly cloudy")
        case 3: return L("overcast")
        case 45, 48: return L("fog")
        case 51, 53, 55: return L("drizzle")
        case 56, 57: return L("freezing drizzle")
        case 61, 63, 65: return L("rain")
        case 66, 67: return L("freezing rain")
        case 71, 73, 75, 77: return L("snowfall")
        case 80, 81, 82: return L("rain showers")
        case 85, 86: return L("snow showers")
        case 95: return L("thunderstorm")
        case 96, 99: return L("thunderstorm with hail")
        default: return L("unreadable skies")
        }
    }

    static func tempText(_ value: Double,
                         _ fahrenheit: Bool) -> String {
        "\(Int(value.rounded()))°"
            + (fahrenheit ? "F" : "C")
    }

    /// The full current reading over a place.
    static func weatherReport(_ w: WeatherSnapshot,
                              tomorrow: Bool) -> String {
        var lines: [String] = []
        lines.append(
            w.placeName + " — "
            + conditionWord(w.code) + ", "
            + tempText(w.temperature, w.fahrenheit)
            + L(", feels like ")
            + tempText(w.feelsLike, w.fahrenheit) + ".")
        lines.append(
            L("Wind ") + "\(Int(w.windSpeed.rounded())) "
            + (w.fahrenheit ? "mph" : "km/h") + " "
            + w.windCompass + L(", humidity ")
            + "\(w.humidity)" + L("%, pressure ")
            + "\(Int(w.pressure.rounded())) hPa.")
        lines.append(
            L("Today: high ")
            + tempText(w.high, w.fahrenheit)
            + L(", low ")
            + tempText(w.low, w.fahrenheit)
            + L(". Sunrise ") + w.sunrise
            + L(", sunset ") + w.sunset + ".")
        if let rain = w.rainChanceNext12h {
            lines.append(
                L("Rain chance over the next twelve hours: ")
                + "\(rain)" + L("%."))
        }
        if tomorrow {
            var line = L("Tomorrow: ")
                + conditionWord(w.tomorrowCode)
                + L(", high ")
                + tempText(w.tomorrowHigh, w.fahrenheit)
                + L(", low ")
                + tempText(w.tomorrowLow, w.fahrenheit)
            if let chance = w.tomorrowPrecipChance {
                line += L(", rain chance ") + "\(chance)"
                    + L("%")
            }
            lines.append(line + ".")
        }
        return lines.joined(separator: "\n")
    }

    /// The one-fact line her bench is grounded
    /// with, when she has a fresh fix and sky.
    var sitrepFact: String? {
        guard enabled, let snap = snapshot
        else { return nil }
        var line = "she is in " + snap.nameLine
        if let w = weather,
           Date().timeIntervalSince(w.at) < 1800 {
            line += "; the weather there: "
                + Self.conditionWord(w.code) + ", "
                + Self.tempText(w.temperature,
                                w.fahrenheit)
        }
        return line
    }
}
