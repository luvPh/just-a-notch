// app/Sources/JustANotch/Core/LearnStore.swift
import Foundation
import Combine

/// Lõi thuần: kho từ + trạng thái SRS → chọn lượt học kế tiếp. Không I/O.
struct LearnDeck {
    private(set) var words: [LearnWord] = []
    private(set) var byID: [String: LearnWord] = [:]
    var reviews: [SenseKey: ReviewState] = [:]

    init(words: [LearnWord] = [], reviews: [SenseKey: ReviewState] = [:]) {
        self.reviews = reviews
        add(words)
    }

    /// Thêm từ, bỏ qua trùng id (giữ bản cũ).
    mutating func add(_ ws: [LearnWord]) {
        for w in ws where byID[w.id] == nil && !w.senses.isEmpty {
            words.append(w); byID[w.id] = w
        }
    }

    var allKeys: [SenseKey] {
        words.flatMap { w in w.senses.indices.map { SenseKey(wordID: w.id, index: $0) } }
    }

    func sense(_ k: SenseKey) -> LearnSense? {
        guard let w = byID[k.wordID], w.senses.indices.contains(k.index) else { return nil }
        return w.senses[k.index]
    }

    func dueKeys(now: Date) -> [SenseKey] {
        reviews.filter { $0.value.due <= now && byID[$0.key.wordID] != nil }
            .sorted { $0.value.due < $1.value.due }.map(\.key)
    }

    func newKeys() -> [SenseKey] { allKeys.filter { reviews[$0] == nil } }

    /// Ưu tiên sense đến hạn; hết thì lấy sense mới (ngẫu nhiên). Quiz chỉ cho sense
    /// đã từng học (có state) và với xác suất `quizChance`.
    func nextPrompt<R: RandomNumberGenerator>(now: Date, quizChance: Double = 1.0 / 3,
                                             rng: inout R) -> LearnPrompt? {
        let key: SenseKey
        let isNew: Bool
        if let d = dueKeys(now: now).first { key = d; isNew = false }
        else if let n = newKeys().randomElement(using: &rng) { key = n; isNew = true }
        else { return nil }

        if !isNew, Double.random(in: 0..<1, using: &rng) < quizChance,
           let quiz = makeQuiz(for: key, rng: &rng) {
            return LearnPrompt(key: key, isNew: false, kind: quiz)
        }
        return LearnPrompt(key: key, isNew: isNew, kind: .card)
    }

    /// Quiz 4 đáp án: nghĩa tiếng Việt của sense đúng + 3 nhiễu từ từ khác.
    func makeQuiz<R: RandomNumberGenerator>(for key: SenseKey, rng: inout R) -> LearnPrompt.Kind? {
        guard let right = sense(key)?.defVI else { return nil }
        var pool = Set(words.filter { $0.id != key.wordID }.flatMap { $0.senses.map(\.defVI) })
        pool.remove(right)
        let wrong = Array(pool).shuffled(using: &rng).prefix(3)
        guard wrong.count == 3 else { return nil }
        var opts = Array(wrong) + [right]
        opts.shuffle(using: &rng)
        return .quiz(options: opts, correct: opts.firstIndex(of: right)!)
    }

    mutating func grade(_ key: SenseKey, _ g: ReviewGrade, now: Date) {
        let cur = reviews[key] ?? .new(now: now)
        reviews[key] = cur.graded(g, now: now)
    }
}

/// Store: load seed (bundle) + từ AI + reviews/stats (Application Support), lưu JSON.
final class LearnStore: ObservableObject {
    @Published private(set) var deck: LearnDeck
    @Published private(set) var stats: LearnStats
    @Published private(set) var current: LearnPrompt?

    private let dir: URL
    private var rng = SystemRandomNumberGenerator()

    static var defaultDir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch/Learn", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Seed đóng gói: mọi `seed_*.json` trong bundle Resources/Learn/.
    static func loadSeed(bundle: Bundle = .main) -> [LearnWord] {
        guard let d = bundle.url(forResource: "Learn", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.lastPathComponent.hasPrefix("seed_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { (try? JSONDecoder().decode([LearnWord].self, from: Data(contentsOf: $0))) ?? [] }
    }

    init(dir: URL = LearnStore.defaultDir, seed: [LearnWord] = LearnStore.loadSeed()) {
        self.dir = dir
        let dec = JSONDecoder()
        let ai = (try? dec.decode([LearnWord].self, from: Data(contentsOf: dir.appendingPathComponent("words_ai.json")))) ?? []
        var reviews: [SenseKey: ReviewState] = [:]
        if let data = try? Data(contentsOf: dir.appendingPathComponent("reviews.json")),
           let list = try? dec.decode([ReviewEntry].self, from: data) {
            for e in list { reviews[e.key] = e.state }
        }
        self.deck = LearnDeck(words: seed + ai, reviews: reviews)
        self.stats = (try? dec.decode(LearnStats.self, from: Data(contentsOf: dir.appendingPathComponent("stats.json")))) ?? LearnStats()
    }

    // MARK: Derived
    func word(_ k: SenseKey) -> LearnWord? { deck.byID[k.wordID] }
    func dueCount(now: Date = Date()) -> Int { deck.dueKeys(now: now).count }
    var learnedCount: Int { deck.reviews.count }
    var totalSenses: Int { deck.allKeys.count }
    func streak(now: Date = Date()) -> Int { stats.streak(now: now) }

    // MARK: Session
    /// Lấy lượt học kế tiếp (không đổi nếu đang có lượt dở).
    @discardableResult
    func ensurePrompt(now: Date = Date()) -> LearnPrompt? {
        if current == nil { current = deck.nextPrompt(now: now, rng: &rng) }
        return current
    }

    func answer(_ g: ReviewGrade, now: Date = Date()) {
        guard let p = current else { return }
        deck.grade(p.key, g, now: now)
        stats.record(now: now)
        current = nil
        save()
    }

    /// Bỏ qua lượt hiện tại (không chấm).
    func skip() { current = nil }

    // MARK: Persistence
    private struct ReviewEntry: Codable { let key: SenseKey; let state: ReviewState }

    private func save() {
        let enc = JSONEncoder()
        let entries = deck.reviews.map { ReviewEntry(key: $0.key, state: $0.value) }
        try? enc.encode(entries).write(to: dir.appendingPathComponent("reviews.json"), options: .atomic)
        try? enc.encode(stats).write(to: dir.appendingPathComponent("stats.json"), options: .atomic)
    }
}
