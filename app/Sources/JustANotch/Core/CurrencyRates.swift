import Foundation

/// Bảng tỷ giá cho máy tính nhanh. Nguồn: open.er-api.com (miễn phí, không key,
/// base USD, cập nhật ~1 lần/ngày). Cache ra đĩa để mất mạng vẫn đổi được.
@MainActor
final class CurrencyRates: ObservableObject {
    static let shared = CurrencyRates()

    /// `rates["VND"]` = số VND cho 1 USD.
    @Published private(set) var rates: [String: Double]?
    /// Thời điểm nguồn cập nhật bảng (không phải lúc ta tải về).
    @Published private(set) var updatedAt: Date?
    @Published private(set) var loading = false

    private let maxAge: TimeInterval = 6 * 3600
    private var fetchedAt: Date?
    private static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!

    private struct Cache: Codable {
        var rates: [String: Double]
        var updatedAt: Date
        var fetchedAt: Date
    }

    private static var cacheURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("rates.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let c = try? JSONDecoder().decode(Cache.self, from: data) {
            rates = c.rates; updatedAt = c.updatedAt; fetchedAt = c.fetchedAt
        }
    }

    /// Tải lại nếu cache cũ hơn 6h (hoặc chưa có). Gọi mỗi khi mở máy tính.
    func refreshIfStale() {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge, rates != nil { return }
        guard !loading else { return }
        loading = true
        var req = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let parsed = data.flatMap(Self.parse)
            Task { @MainActor in
                self.loading = false
                guard let parsed else { return }
                self.rates = parsed.rates
                self.updatedAt = parsed.updatedAt
                self.fetchedAt = Date()
                let cache = Cache(rates: parsed.rates, updatedAt: parsed.updatedAt, fetchedAt: Date())
                if let out = try? JSONEncoder().encode(cache) { try? out.write(to: Self.cacheURL, options: .atomic) }
            }
        }.resume()
    }

    private struct Payload: Decodable {
        let result: String
        let time_last_update_unix: TimeInterval?
        let rates: [String: Double]
    }

    nonisolated private static func parse(_ data: Data) -> (rates: [String: Double], updatedAt: Date)? {
        guard let p = try? JSONDecoder().decode(Payload.self, from: data), p.result == "success",
              p.rates["VND"] != nil else { return nil }
        return (p.rates, Date(timeIntervalSince1970: p.time_last_update_unix ?? Date().timeIntervalSince1970))
    }
}
