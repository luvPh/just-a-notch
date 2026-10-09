import Foundation
import SwiftUI

// MARK: - Model

/// Nhóm thời tiết rút gọn từ mã WMO của Open-Meteo.
enum WeatherKind: String, Codable {
    case clear, partly, cloudy, fog, drizzle, rain, thunder, snow

    /// Mã WMO → nhóm (https://open-meteo.com/en/docs, "Weather variable documentation").
    static func from(wmo c: Int) -> WeatherKind {
        switch c {
        case 0: return .clear
        case 1, 2: return .partly
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51...57: return .drizzle
        case 61...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .thunder
        default: return .cloudy
        }
    }

    var label: String {
        switch self {
        case .clear: return "Trời quang"
        case .partly: return "Có mây"
        case .cloudy: return "Nhiều mây"
        case .fog: return "Sương mù"
        case .drizzle: return "Mưa phùn"
        case .rain: return "Mưa"
        case .thunder: return "Dông"
        case .snow: return "Tuyết"
        }
    }

    func symbol(day: Bool) -> String {
        switch self {
        case .clear: return day ? "sun.max.fill" : "moon.stars.fill"
        case .partly: return day ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        case .snow: return "cloud.snow.fill"
        }
    }
}

struct WeatherNow: Codable, Equatable {
    var city: String
    var temp: Double
    var feels: Double
    var kind: WeatherKind
    var isDay: Bool
    var hi: Double
    var lo: Double
    var rainChance: Int?
    var hourly: [Hour]
    var at: Date

    struct Hour: Codable, Equatable, Identifiable {
        var time: Date
        var temp: Double
        var kind: WeatherKind
        var isDay: Bool
        var id: Date { time }
    }
}

// MARK: - Parse (thuần, có test)

enum WeatherParser {
    static func forecast(_ data: Data, city: String, now: Date = Date()) -> WeatherNow? {
        struct Root: Decodable {
            let current: Cur
            let hourly: H
            let daily: D
        }
        struct Cur: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
        }
        struct H: Decodable {
            let time: [Double]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
        }
        struct D: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]?
        }
        guard let r = try? JSONDecoder().decode(Root.self, from: data) else { return nil }
        var hours: [WeatherNow.Hour] = []
        for i in r.hourly.time.indices where i < r.hourly.temperature_2m.count {
            let t = Date(timeIntervalSince1970: r.hourly.time[i])
            guard t > now.addingTimeInterval(-1800) else { continue }
            hours.append(.init(time: t, temp: r.hourly.temperature_2m[i],
                               kind: .from(wmo: r.hourly.weather_code[i]), isDay: r.hourly.is_day[i] == 1))
            if hours.count == 6 { break }
        }
        return WeatherNow(city: city, temp: r.current.temperature_2m, feels: r.current.apparent_temperature,
                          kind: .from(wmo: r.current.weather_code), isDay: r.current.is_day == 1,
                          hi: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
                          lo: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
                          rainChance: r.daily.precipitation_probability_max?.first ?? nil,
                          hourly: hours, at: now)
    }

    static func geocode(_ data: Data) -> (name: String, lat: Double, lon: Double)? {
        struct Root: Decodable { let results: [R]? }
        struct R: Decodable { let name: String; let latitude: Double; let longitude: Double }
        guard let r = (try? JSONDecoder().decode(Root.self, from: data))?.results?.first else { return nil }
        return (r.name, r.latitude, r.longitude)
    }
}

// MARK: - Store

/// Thời tiết theo thành phố người dùng đặt (Open-Meteo, không cần key, không xin quyền vị trí).
@MainActor
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    @Published private(set) var now: WeatherNow?
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published var city: String {
        didSet {
            guard city != oldValue else { return }
            UserDefaults.standard.set(city, forKey: "weather.city")
            refresh(force: true)
        }
    }

    private var timer: Timer?
    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JustANotch/weather.json")
    }

    private init() {
        city = UserDefaults.standard.string(forKey: "weather.city") ?? "Hà Nội"
        if let d = try? Data(contentsOf: Self.cacheURL), let w = try? JSONDecoder().decode(WeatherNow.self, from: d) {
            now = w
        }
    }

    /// Bắt đầu cập nhật định kỳ (30′). Gọi nhiều lần không sao.
    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            Task { @MainActor in WeatherStore.shared.refresh(force: true) }
        }
    }

    func refresh(force: Bool = false) {
        if !force, let n = now, n.city == city, Date().timeIntervalSince(n.at) < 900 { return }
        guard !loading else { return }
        loading = true
        let city = city
        Task {
            let w = await Self.fetch(city: city)
            loading = false
            failed = w == nil
            guard let w, w.city == self.city || city == self.city else { return }
            now = w
            try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(w) { try? d.write(to: Self.cacheURL, options: .atomic) }
        }
    }

    private nonisolated static func get(_ url: URL) async -> Data? {
        var req = URLRequest(url: url); req.timeoutInterval = 10
        guard let (d, r) = try? await URLSession.shared.data(for: req),
              (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return d
    }

    nonisolated static func fetch(city: String) async -> WeatherNow? {
        var g = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        g.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "vi")]
        guard let gd = await get(g.url!), let place = WeatherParser.geocode(gd) else { return nil }
        var f = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        f.queryItems = [
            .init(name: "latitude", value: String(place.lat)), .init(name: "longitude", value: String(place.lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"), .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "2"),
        ]
        guard let fd = await get(f.url!) else { return nil }
        return WeatherParser.forecast(fd, city: place.name)
    }
}

// MARK: - Palette

extension WeatherKind {
    /// (màu chính, màu phụ) cho ánh nền notch khi bật "Notch theo thời tiết".
    func ambient(day: Bool) -> (Color, Color) {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch self {
        case .clear:   return day ? (c(1.0, 0.72, 0.30), c(1.0, 0.88, 0.50)) : (c(0.35, 0.40, 0.85), c(0.62, 0.55, 0.95))
        case .partly:  return day ? (c(0.98, 0.78, 0.45), c(0.55, 0.75, 0.98)) : (c(0.38, 0.42, 0.75), c(0.55, 0.60, 0.80))
        case .cloudy:  return (c(0.55, 0.62, 0.72), c(0.70, 0.75, 0.82))
        case .fog:     return (c(0.62, 0.66, 0.70), c(0.80, 0.82, 0.85))
        case .drizzle: return (c(0.40, 0.62, 0.90), c(0.55, 0.78, 0.95))
        case .rain:    return (c(0.25, 0.48, 0.95), c(0.40, 0.70, 1.00))
        case .thunder: return (c(0.48, 0.35, 0.95), c(0.95, 0.85, 0.45))
        case .snow:    return (c(0.70, 0.82, 1.00), c(0.92, 0.96, 1.00))
        }
    }
}
