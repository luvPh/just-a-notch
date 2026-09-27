import Foundation

/// Giá vàng nhanh cho launcher: XAU/USD thế giới + bảng giá Bảo Tín Mạnh Hải.
///
/// Nguồn (đã kiểm tra 09/2026):
/// - XAU/USD: api.gold-api.com (không key, gần realtime); % thay đổi lấy từ
///   `previousClose` của hợp đồng vàng COMEX (Yahoo `GC=F`) — cũng là dự phòng giá.
/// - BTMH: GraphQL chính chủ `baotinmanhhai.vn/api/graphql` (`goldRates`), VND/chỉ.
///   `sell_price` ≤ 1 nghĩa là không bán ra.
@MainActor
final class GoldPrices: ObservableObject {
    static let shared = GoldPrices()

    struct World: Codable, Equatable {
        var price: Double          // USD/oz
        var changePct: Double?     // so với phiên trước
        var at: Date
    }

    struct Local: Codable, Equatable, Identifiable {
        var code: String
        var name: String
        var buy: Double
        var sell: Double?
        var trend: Double?         // chênh lệch VND so với lần cập nhật trước (có dấu)
        var at: Date?
        var id: String { code }
    }

    /// Mã BTMH hiển thị, theo thứ tự: nhẫn Kim Gia Bảo (nhẫn tròn trơn) + vàng miếng SJC.
    nonisolated static let localCodes: [(code: String, label: String)] = [("KGB", "Nhẫn Kim Gia Bảo"), ("SJC9999", "Vàng miếng SJC")]

    @Published private(set) var world: World?
    @Published private(set) var local: [Local] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    private var fetchedAt: Date?

    private struct Cache: Codable { var world: World?; var local: [Local]; var fetchedAt: Date }

    private static var cacheURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("gold.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let c = try? JSONDecoder().decode(Cache.self, from: data) {
            world = c.world; local = c.local; fetchedAt = c.fetchedAt
        }
    }

    /// Làm mới nếu dữ liệu cũ hơn `maxAge` giây (mặc định 60s — gọi khi mở + mỗi phút).
    func refresh(maxAge: TimeInterval = 60) {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < maxAge, world != nil || !local.isEmpty { return }
        guard !loading else { return }
        loading = true
        Task {
            async let w = Self.fetchWorld()
            async let l = Self.fetchLocal()
            let (world, local) = await (w, l)
            self.loading = false
            self.failed = world == nil && local == nil
            if let world { self.world = world }
            if let local, !local.isEmpty { self.local = local }
            guard world != nil || local != nil else { return }
            self.fetchedAt = Date()
            let cache = Cache(world: self.world, local: self.local, fetchedAt: Date())
            if let out = try? JSONEncoder().encode(cache) { try? out.write(to: Self.cacheURL, options: .atomic) }
        }
    }

    // MARK: Fetch

    private static func get(_ url: URL, body: Data? = nil) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("Mozilla/5.0 (Macintosh) JustANotch", forHTTPHeaderField: "User-Agent")
        if let body {
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    nonisolated static func fetchWorld() async -> World? {
        async let spot = get(URL(string: "https://api.gold-api.com/price/XAU")!)
        async let fut = get(URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/GC=F?range=1d&interval=1d")!)
        let (s, f) = await (spot, fut)
        let spotPrice = s.flatMap(parseGoldAPI)
        let futures = f.flatMap(parseYahoo)
        guard let price = spotPrice ?? futures?.price else { return nil }
        var pct: Double?
        if let prev = futures?.prevClose, prev > 0 {
            // % theo giá hợp đồng tương lai của chính nó (spot và futures lệch nhau vài đô).
            pct = ((futures?.price ?? price) - prev) / prev * 100
        }
        return World(price: price, changePct: pct, at: Date())
    }

    nonisolated static func fetchLocal() async -> [Local]? {
        let q = #"{"query":"{ goldRates { items { code name buy_price sell_price trend_value last_updated } } }"}"#
        guard let data = await get(URL(string: "https://baotinmanhhai.vn/api/graphql")!, body: Data(q.utf8)) else { return nil }
        return parseBTMH(data)
    }

    // MARK: Parse (tách riêng để test)

    nonisolated static func parseGoldAPI(_ data: Data) -> Double? {
        struct P: Decodable { let price: Double }
        return (try? JSONDecoder().decode(P.self, from: data))?.price
    }

    nonisolated static func parseYahoo(_ data: Data) -> (price: Double, prevClose: Double?)? {
        struct Root: Decodable { let chart: Chart }
        struct Chart: Decodable { let result: [R]? }
        struct R: Decodable { let meta: Meta }
        struct Meta: Decodable {
            let regularMarketPrice: Double?
            let chartPreviousClose: Double?
            let previousClose: Double?
        }
        guard let m = (try? JSONDecoder().decode(Root.self, from: data))?.chart.result?.first?.meta,
              let p = m.regularMarketPrice else { return nil }
        return (p, m.chartPreviousClose ?? m.previousClose)
    }

    nonisolated static func parseBTMH(_ data: Data) -> [Local]? {
        struct Root: Decodable { let data: D? }
        struct D: Decodable { let goldRates: G? }
        struct G: Decodable { let items: [Item] }
        struct Item: Decodable {
            let code: String
            let name: String?
            let buy_price: Double?
            let sell_price: Double?
            let trend_value: String?
            let last_updated: String?
        }
        guard let items = (try? JSONDecoder().decode(Root.self, from: data))?.data?.goldRates?.items else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.S"
        return localCodes.compactMap { want in
            guard let it = items.first(where: { $0.code == want.code }), let buy = it.buy_price, buy > 1 else { return nil }
            // "-10.000" = giảm 10.000đ (kiểu Việt: dấu chấm phân cách nghìn).
            let trend = it.trend_value.flatMap { Double($0.replacingOccurrences(of: ".", with: "")) }
            return Local(code: want.code, name: want.label, buy: buy,
                         sell: (it.sell_price ?? 0) > 1 ? it.sell_price : nil,
                         trend: trend == 0 ? nil : trend,
                         at: it.last_updated.flatMap { f.date(from: $0) })
        }
    }
}
