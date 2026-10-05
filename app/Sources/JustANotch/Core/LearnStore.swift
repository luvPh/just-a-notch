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
    @discardableResult
    mutating func add(_ ws: [LearnWord]) -> [LearnWord] {
        var added: [LearnWord] = []
        for w in ws where byID[w.id] == nil && !w.senses.isEmpty {
            words.append(w); byID[w.id] = w; added.append(w)
        }
        return added
    }

    /// Bỏ từ khỏi kho (và mọi state ôn của nó).
    mutating func remove(_ wordID: String) {
        words.removeAll { $0.id == wordID }
        byID[wordID] = nil
        reviews = reviews.filter { $0.key.wordID != wordID }
    }

    /// Đánh dấu đã biết: coi như đã thuộc (không xuất hiện trong ôn tập nữa).
    mutating func markKnown(_ wordID: String, now: Date) {
        guard let w = byID[wordID] else { return }
        for i in w.senses.indices {
            var st = reviews[SenseKey(wordID: wordID, index: i)] ?? .new(now: now)
            st.correct = max(st.correct, ReviewState.masterAt)
            st.modes = PracticeMode.allCases
            st.lastReviewed = now
            st.due = now.addingTimeInterval(365 * 86_400)
            reviews[SenseKey(wordID: wordID, index: i)] = st
        }
    }

    mutating func unmarkKnown(_ wordID: String, now: Date) {
        guard let w = byID[wordID] else { return }
        for i in w.senses.indices {
            let k = SenseKey(wordID: wordID, index: i)
            guard var st = reviews[k], st.mastered else { continue }
            st.correct = ReviewState.masterAt - 1
            st.due = now
            reviews[k] = st
        }
    }

    var allKeys: [SenseKey] {
        words.flatMap { w in w.senses.indices.map { SenseKey(wordID: w.id, index: $0) } }
    }

    func sense(_ k: SenseKey) -> LearnSense? {
        guard let w = byID[k.wordID], w.senses.indices.contains(k.index) else { return nil }
        return w.senses[k.index]
    }

    /// Sense đang học (đã giới thiệu, chưa thuộc) đã tới hạn — sớm nhất trước.
    func dueKeys(now: Date) -> [SenseKey] {
        reviews.filter { !$0.value.mastered && $0.value.due <= now && byID[$0.key.wordID] != nil }
            .sorted { $0.value.due < $1.value.due }.map(\.key)
    }

    func newKeys() -> [SenseKey] { allKeys.filter { reviews[$0] == nil } }

    var masteredCount: Int { reviews.values.filter(\.mastered).count }

    /// Lô luyện tập (studyBatch của EngZone): sense đến hạn (xáo trộn) trước, rồi tối đa
    /// `newLimit` sense mới, rồi các sense sắp tới hạn nhất để lấp cho đủ `size`.
    func studyBatch<R: RandomNumberGenerator>(size: Int, newLimit: Int, now: Date, rng: inout R) -> [SenseKey] {
        let due = dueKeys(now: now).shuffled(using: &rng)
        let fresh = Array(newKeys().shuffled(using: &rng).prefix(max(0, min(newLimit, size - due.count))))
        let future = reviews.filter { !$0.value.mastered && $0.value.due > now && byID[$0.key.wordID] != nil }
            .sorted { $0.value.due < $1.value.due }.map(\.key)
        return Array((due + fresh + future).prefix(size))
    }

    /// Dựng câu hỏi: chọn ngẫu nhiên 1 trong 3 dạng; thiếu nhiễu → dạng điền.
    func question<R: RandomNumberGenerator>(for key: SenseKey, mode forced: PracticeMode? = nil,
                                            rng: inout R) -> PracticeQuestion? {
        guard let w = byID[key.wordID], let s = sense(key) else { return nil }
        let others = words.filter { $0.id != w.id && $0.headword.caseInsensitiveCompare(w.headword) != .orderedSame }
        // Ưu tiên dạng chưa từng trả lời đúng (điều kiện thuộc cần đủ 3 dạng); đủ rồi thì ngẫu nhiên.
        let done = Set(reviews[key]?.modes ?? [])
        let pending = PracticeMode.allCases.filter { !done.contains($0) }
        let mode = forced ?? (pending.isEmpty ? PracticeMode.allCases : pending).randomElement(using: &rng)!
        func mcq(_ right: String, _ pool: [String]) -> PracticeQuestion? {
            var set = Set(pool); set.remove(right)
            let wrong = Array(set).shuffled(using: &rng).prefix(3)
            guard wrong.count == 3 else { return nil }
            var opts = Array(wrong) + [right]
            opts.shuffle(using: &rng)
            return PracticeQuestion(key: key, mode: mode, options: opts, correct: opts.firstIndex(of: right)!, answer: w.headword)
        }
        switch mode {
        case .mcqWord:
            // Nhiễu cùng loại từ trước cho khó hơn, thiếu thì lấy bất kỳ.
            let same = others.filter { $0.pos == w.pos }.flatMap { $0.senses.map(\.defVI) }
            return mcq(s.defVI, same.count >= 3 ? same : others.flatMap { $0.senses.map(\.defVI) })
                ?? question(for: key, mode: .fill, rng: &rng)
        case .mcqMeaning:
            let same = others.filter { $0.pos == w.pos }.map(\.headword)
            return mcq(w.headword, same.count >= 3 ? same : others.map(\.headword))
                ?? question(for: key, mode: .fill, rng: &rng)
        case .fill:
            return PracticeQuestion(key: key, mode: .fill, options: [], correct: 0, answer: w.headword)
        }
    }

    /// Lượt kế tiếp cho notch: sense đến hạn → câu hỏi; hết → giới thiệu 1 sense mới.
    func nextPrompt<R: RandomNumberGenerator>(now: Date, rng: inout R) -> LearnPrompt? {
        if let d = dueKeys(now: now).first, let q = question(for: d, rng: &rng) { return .question(q) }
        if let n = newKeys().randomElement(using: &rng) { return .intro(n) }
        return nil
    }

    /// Chọn bộ từ trong ngày: ưu tiên sense CHƯA học ở B2–C2, thiếu thì lấy sense đang học
    /// (chưa thuộc) cùng level. Mỗi từ tối đa 1 sense.
    /// `carry` = từ học dở cần giữ lại (bỏ từ đã thuộc/đã xoá); `exclude` = từ không chọn lại.
    func pickDaily<R: RandomNumberGenerator>(day: String, carry: [SenseKey] = [], exclude: Set<String> = [],
                                            rng: inout R) -> DailySet {
        let kept = carry.filter { byID[$0.wordID] != nil && reviews[$0]?.mastered != true }
        let eligible = allKeys.filter { k in
            guard let s = sense(k), DailySet.levels.contains(s.level), !exclude.contains(k.wordID) else { return false }
            return reviews[k]?.mastered != true
        }
        let fresh = eligible.filter { reviews[$0] == nil }.shuffled(using: &rng)
        let learning = eligible.filter { reviews[$0] != nil }.shuffled(using: &rng)
        var picked: [SenseKey] = [], words = Set<String>()
        for k in kept + fresh + learning where !words.contains(k.wordID) {
            picked.append(k); words.insert(k.wordID)
            if picked.count == DailySet.size { break }
        }
        return DailySet(day: day, keys: picked)
    }

    /// Xoá sạch tiến độ một sense (ôn bài cũ trả lời sai → học lại từ đầu).
    mutating func resetProgress(_ key: SenseKey) { reviews[key] = nil }

    /// Lượt kế từ bộ trong ngày: sense ít được hiện nhất (hoà thì ngẫu nhiên).
    /// Chưa học → thẻ giới thiệu; đã học → câu hỏi. Hết (đều đã thuộc) → nil.
    func dailyPrompt<R: RandomNumberGenerator>(_ set: DailySet, rng: inout R) -> LearnPrompt? {
        // Ôn bài cũ bắt buộc làm trước; xong phải xem tổng kết rồi mới học bài mới.
        if let it = set.reviewQueue.first { return question(for: it.key, mode: it.mode, rng: &rng).map { .question($0) } }
        if set.needsReviewSummary { return nil }
        // Vừa sai một từ → hỏi lại ngay từ đó, bằng dạng khác lần sai.
        if let r = set.retry, set.keys.contains(r.key), byID[r.key.wordID] != nil, reviews[r.key]?.mastered != true {
            let other = PracticeMode.allCases.filter { $0 != r.mode }.randomElement(using: &rng)!
            if let q = question(for: r.key, mode: other, rng: &rng) { return .question(q) }
        }
        let open = set.keys.filter { byID[$0.wordID] != nil && (set.again.contains($0) || reviews[$0]?.mastered != true) }
        guard let least = open.map({ set.shown[$0.description] ?? 0 }).min() else { return nil }
        guard let k = open.filter({ (set.shown[$0.description] ?? 0) == least }).randomElement(using: &rng) else { return nil }
        if reviews[k] == nil { return .intro(k) }
        return question(for: k, rng: &rng).map { .question($0) }
    }

    /// Đã xem thẻ giới thiệu → vào lịch ôn, kiểm tra ngay lượt sau.
    mutating func introduce(_ key: SenseKey, now: Date) {
        if reviews[key] == nil { reviews[key] = .new(now: now) }
    }

    mutating func record(_ key: SenseKey, correct: Bool, mode: PracticeMode, now: Date) {
        reviews[key] = (reviews[key] ?? .new(now: now)).recorded(correct: correct, mode: mode, now: now)
    }
}

/// Store: load seed (bundle) + từ AI + reviews/stats (Application Support), lưu JSON.
final class LearnStore: ObservableObject {
    static let shared = LearnStore()

    @Published private(set) var deck: LearnDeck
    @Published private(set) var essays: [Essay] = []
    @Published private(set) var lessons: [GrammarLesson] = []
    @Published private(set) var stats: LearnStats
    @Published private(set) var current: LearnPrompt?
    @Published private(set) var daily: DailySet?

    private let dir: URL
    /// id các từ seed người dùng đã xoá (seed nằm trong bundle nên chỉ ẩn đi).
    private var hidden: Set<String>
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
        let hidden = Set((try? dec.decode([String].self, from: Data(contentsOf: dir.appendingPathComponent("hidden.json")))) ?? [])
        self.hidden = hidden
        var reviews: [SenseKey: ReviewState] = [:]
        if let data = try? Data(contentsOf: dir.appendingPathComponent("reviews.json")),
           let list = try? dec.decode([ReviewEntry].self, from: data) {
            for e in list { reviews[e.key] = e.state }
        }
        self.deck = LearnDeck(words: (seed + ai).filter { !hidden.contains($0.id) }, reviews: reviews)
        self.essays = (try? dec.decode([Essay].self, from: Data(contentsOf: dir.appendingPathComponent("essays.json")))) ?? []
        self.lessons = (try? dec.decode([GrammarLesson].self, from: Data(contentsOf: dir.appendingPathComponent("grammar.json")))) ?? []
        self.stats = (try? dec.decode(LearnStats.self, from: Data(contentsOf: dir.appendingPathComponent("stats.json")))) ?? LearnStats()
        self.daily = try? dec.decode(DailySet.self, from: Data(contentsOf: dir.appendingPathComponent("daily.json")))
    }

    // MARK: Derived
    func word(_ k: SenseKey) -> LearnWord? { deck.byID[k.wordID] }
    func dueCount(now: Date = Date()) -> Int { deck.dueKeys(now: now).count }
    var learnedCount: Int { deck.reviews.count }
    var masteredCount: Int { deck.masteredCount }
    var totalSenses: Int { deck.allKeys.count }
    func streak(now: Date = Date()) -> Int { stats.streak(now: now) }

    // MARK: Session
    /// Lấy lượt học kế tiếp (không đổi nếu đang có lượt dở).
    @discardableResult
    func ensurePrompt(now: Date = Date()) -> LearnPrompt? {
        fillPrompt(now: now)
        return current
    }

    private func fillPrompt(now: Date) {
        if current == nil {
            let set = ensureDaily(now: now)
            // Bài hôm nay đã hoàn thành → không ra câu (UI hiện màn "hoàn thành").
            // Kho B2–C2 cạn (bộ rỗng) → quay về lịch ôn chung.
            current = deck.dailyPrompt(set, rng: &rng) ?? (set.keys.isEmpty ? deck.nextPrompt(now: now, rng: &rng) : nil)
            // Đã đem câu hỏi lại ra dùng → xoá cờ (chỉ hỏi lại 1 lần).
            if let r = daily?.retry, current?.key == r.key { daily?.retry = nil }
            if let k = current?.key, set.keys.contains(k) {
                daily?.shown[k.description, default: 0] += 1
                write(daily, "daily.json")
            }
        }
    }

    /// Bài học hôm nay. Sang ngày mới: giữ từ chưa thuộc của bài cũ, lấp bằng từ mới.
    @discardableResult
    func ensureDaily(now: Date = Date()) -> DailySet {
        let today = LearnStats.dayKey(now)
        if let d = daily, d.day == today { return d }
        let old = daily
        // Bài hôm qua đã xong → hôm nay ôn lại (bắt buộc); chưa xong → học nối tiếp.
        let oldDone = old.map { o in !o.keys.isEmpty && o.keys.allSatisfy { deck.reviews[$0]?.mastered == true } } ?? false
        var toReview = (old?.completed ?? []) + (oldDone ? old!.keys : []) + (old?.reviewQueue.map(\.key) ?? [])
        var seen = Set<SenseKey>()
        toReview = toReview.filter { deck.byID[$0.wordID] != nil && deck.reviews[$0] != nil && seen.insert($0).inserted }
        var d = deck.pickDaily(day: today, carry: oldDone ? [] : (old?.keys ?? []),
                               exclude: Set(toReview.map(\.wordID)), rng: &rng)
        // Giữ bộ đếm xoay vòng của các từ học nối tiếp; từ mới bắt đầu ngang từ ít hiện nhất.
        if let old {
            d.shown = old.shown.filter { k, _ in d.keys.contains { $0.description == k } }
            let base = d.shown.values.min() ?? 0
            for k in d.keys where d.shown[k.description] == nil { d.shown[k.description] = base }
        }
        d.reviewQueue = toReview.flatMap { k in PracticeMode.allCases.map { ReviewItem(key: k, mode: $0) } }
            .shuffled(using: &rng)
        setDaily(d)
        return d
    }

    /// Đã thuộc hết bài hôm nay (và chưa chọn ôn lại).
    var dailyComplete: Bool {
        guard let d = daily, !d.keys.isEmpty, !d.reviewAgain, !d.reviewing, !d.needsReviewSummary else { return false }
        return d.keys.allSatisfy { deck.reviews[$0]?.mastered == true }
    }

    /// Popup cần báo "hoàn thành" (chưa báo lần nào).
    var dailyNeedsAnnounce: Bool { dailyComplete && daily?.announced == false }

    func markDailyAnnounced() {
        guard var d = daily else { return }
        d.announced = true
        setDaily(d)
    }

    /// "Học bộ 10 từ khác": bộ mới ngay hôm nay, không chọn lại từ của bộ vừa xong.
    func startNewDailySet(now: Date = Date()) {
        let old = daily
        let done = (old?.completed ?? []) + (old?.keys ?? [])
        var d = deck.pickDaily(day: LearnStats.dayKey(now), exclude: Set(done.map(\.wordID)), rng: &rng)
        d.completed = done                       // hôm sau ôn lại cả các bộ đã xong hôm nay
        d.announced = false
        setDaily(d)
        current = nil
    }

    // MARK: Ôn bài cũ
    var reviewRemaining: Int { daily?.reviewQueue.count ?? 0 }
    var reviewTotal: Int { (daily?.reviewResults.count ?? 0) + reviewRemaining }
    var reviewCorrect: Int { daily?.reviewResults.values.filter { $0 }.count ?? 0 }
    var needsReviewSummary: Bool { daily?.needsReviewSummary ?? false }

    /// Xem xong tổng kết ôn bài cũ → vào bài hôm nay.
    func ackReviewSummary() {
        guard var d = daily else { return }
        d.reviewSummaryAcked = true
        setDaily(d)
        current = nil
    }

    /// Ghi kết quả một câu ôn bài cũ. Sai (bất kỳ dạng nào) → xoá tiến độ từ đó, bỏ các câu
    /// còn lại của nó khỏi phần ôn, thêm thẳng vào bài hôm nay.
    private func handleReviewAnswer(_ key: SenseKey, correct: Bool) {
        guard var d = daily, let i = d.reviewQueue.firstIndex(where: { $0.key == key }) else { return }
        let item = d.reviewQueue.remove(at: i)
        d.reviewResults[item.id] = correct
        if !correct {
            d.reviewQueue.removeAll { $0.key == key }
            deck.resetProgress(key)
            if !d.keys.contains(key) { d.keys.append(key); d.seedShown(key) }
        }
        setDaily(d)
    }

    /// Số từ đã rớt khi ôn bài cũ (đã chuyển vào bài hôm nay).
    var reviewFailedWords: Int {
        Set((daily?.reviewResults ?? [:]).filter { !$0.value }.keys.map { $0.split(separator: "|").first! }).count
    }

    /// "Ôn lại 10 từ này": hỏi lại mỗi từ 1 lần (cả từ đã thuộc, không reset tiến độ);
    /// hỏi hết cả bộ → lại màn hoàn thành.
    func reviewDailyAgain() {
        guard var d = daily else { return }
        d.again = d.keys.filter { deck.byID[$0.wordID] != nil }
        d.evenShown()
        d.announced = false                      // popup báo hoàn thành lại khi xong vòng
        setDaily(d)
        current = nil
    }

    private func setDaily(_ d: DailySet) {
        daily = d
        write(d, "daily.json")
    }

    /// Trả lời câu hỏi đang hiện trên notch.
    func answer(correct: Bool, now: Date = Date()) {
        guard case let .question(q)? = current else { return }
        record(q.key, correct: correct, mode: q.mode, now: now)
    }

    /// Chuyển sang lượt kế (gọi sau khi người học xem xong phản hồi).
    func advance(now: Date = Date()) {
        if case let .intro(k)? = current { deck.introduce(k, now: now); save() }
        current = nil
        ensurePrompt(now: now)
    }

    /// Bỏ qua trong popup: câu hỏi tính sai, KHÔNG lấy lượt mới.
    func skipCurrent(now: Date = Date()) {
        if case let .question(q)? = current { record(q.key, correct: false, mode: q.mode, now: now) }
        current = nil
    }

    /// Kết thúc lượt hiện tại mà KHÔNG lấy lượt mới (popup notch: lượt mới lấy khi bung lần sau).
    func finishCurrent(now: Date = Date()) {
        if case let .intro(k)? = current { deck.introduce(k, now: now); save() }
        current = nil
    }

    /// Bỏ qua: câu hỏi tính là sai (như EngZone); thẻ giới thiệu thì chỉ đổi từ khác.
    func skip(now: Date = Date()) {
        if case let .question(q)? = current { record(q.key, correct: false, mode: q.mode, now: now) }
        current = nil
        ensurePrompt(now: now)
    }

    func question(for key: SenseKey, mode: PracticeMode? = nil) -> PracticeQuestion? {
        deck.question(for: key, mode: mode, rng: &rng)
    }

    /// Câu ôn bài cũ kế tiếp (đúng dạng đã xếp).
    func nextOldReviewQuestion() -> PracticeQuestion? {
        guard let it = daily?.reviewQueue.first else { return nil }
        return question(for: it.key, mode: it.mode)
    }

    func studyBatch(size: Int, newLimit: Int, now: Date = Date()) -> [SenseKey] {
        deck.studyBatch(size: size, newLimit: newLimit, now: now, rng: &rng)
    }

    func introduce(_ key: SenseKey, now: Date = Date()) { deck.introduce(key, now: now); save() }

    /// Ghi kết quả một câu hỏi (phiên ôn trong cửa sổ, bài luyện essay, notch).
    func record(_ key: SenseKey, correct: Bool, mode: PracticeMode, now: Date = Date()) {
        deck.record(key, correct: correct, mode: mode, now: now)
        stats.record(now: now)
        let wasOldReview = daily?.reviewQueue.contains { $0.key == key } == true
        handleReviewAnswer(key, correct: correct)
        // Vòng ôn lại: đã hỏi lại từ này → xong phần của nó (sai thì học tiếp như từ chưa thuộc).
        if var d = daily, d.again.contains(key) {
            d.again.removeAll { $0 == key }
            setDaily(d)
        }
        // Sai trong bài hôm nay (không phải ôn bài cũ) → đánh dấu hỏi lại ở lượt kế.
        if !correct, !wasOldReview, var d = daily, d.keys.contains(key) {
            d.retry = ReviewItem(key: key, mode: mode)
            setDaily(d)
        }
        save()
    }

    // MARK: Kho từ
    /// Thêm từ (AI / tra trong essay). Trả về số từ mới thật sự được thêm.
    @discardableResult
    func addWords(_ ws: [LearnWord]) -> Int {
        let tagged = ws.map { var w = $0; w.source = .ai; return w }
        tagged.forEach { hidden.remove($0.id) }
        let added = deck.add(tagged)
        if !added.isEmpty { saveAIWords(); saveHidden() }
        return added.count
    }

    func contains(headword: String) -> Bool {
        deck.words.contains { $0.headword.caseInsensitiveCompare(headword) == .orderedSame }
    }

    func deleteWord(_ id: String) {
        guard let w = deck.byID[id] else { return }
        deck.remove(id)
        if current?.key.wordID == id { current = nil }
        if w.source == .ai { saveAIWords() } else { hidden.insert(id); saveHidden() }
        save()
    }

    func markKnown(_ id: String, now: Date = Date()) {
        let wasKnown = isKnown(id)
        deck.markKnown(id, now: now)
        if current?.key.wordID == id { current = nil }
        if var d = daily, d.again.contains(where: { $0.wordID == id }) {
            d.again.removeAll { $0.wordID == id }
            setDaily(d)
        }
        // Từ vốn đã thuộc (vd. đang ôn lại) → chỉ bỏ qua, không thay bằng từ mới.
        if !wasKnown { replaceInDaily(wordID: id, now: now) }
        save()
    }

    /// Từ trong bài hôm nay được đánh dấu "đã thuộc" (biết từ trước) → thay bằng từ khác
    /// để bài luôn đủ từ cần học. (Từ thuộc nhờ luyện đúng đủ 10 lần thì KHÔNG thay.)
    private func replaceInDaily(wordID: String, now: Date) {
        // Đang ôn bài cũ mà bấm "đã thuộc" → bỏ hẳn các câu ôn của từ đó.
        if var d = daily, d.reviewQueue.contains(where: { $0.key.wordID == wordID }) {
            d.reviewQueue.removeAll { $0.key.wordID == wordID }
            setDaily(d)
        }
        guard var d = daily, let i = d.keys.firstIndex(where: { $0.wordID == wordID }) else { return }
        let old = d.keys[i]
        let exclude = Set(d.keys.map(\.wordID))
        let pick = deck.pickDaily(day: d.day, exclude: exclude, rng: &rng).keys.first
        d.shown[old.description] = nil
        if let pick { d.keys[i] = pick; d.seedShown(pick) } else { d.keys.remove(at: i) }
        setDaily(d)
    }

    /// Mọi nghĩa của từ đều đã thuộc?
    func isKnown(_ id: String) -> Bool {
        guard let w = deck.byID[id] else { return false }
        return w.senses.indices.allSatisfy { deck.reviews[SenseKey(wordID: id, index: $0)]?.mastered == true }
    }

    /// Bỏ đánh dấu đã thuộc → từ quay lại ôn tập ngay.
    func unmarkKnown(_ id: String, now: Date = Date()) {
        deck.unmarkKnown(id, now: now)
        save()
    }

    /// Trạng thái ôn của sense (nil = chưa học).
    func review(_ k: SenseKey) -> ReviewState? { deck.reviews[k] }


    // MARK: Chủ đề essay (xoay vòng như EngZone: dùng hết chủ đề chưa dùng rồi mới lặp)
    static func loadTopics(bundle: Bundle = .main) -> [String] {
        guard let u = bundle.url(forResource: "Learn/topics", withExtension: "json"),
              let t = try? JSONDecoder().decode([String].self, from: Data(contentsOf: u)) else { return [] }
        return t
    }
    lazy var topics: [String] = Self.loadTopics()

    /// Chủ đề kế tiếp: ngẫu nhiên trong các chủ đề CHƯA dùng ở vòng này; hết → vòng mới.
    func nextEssayTopic() -> String {
        guard !topics.isEmpty else { return "Daily life" }
        let url = dir.appendingPathComponent("topics_used.json")
        var used = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))) ?? [])
            .intersection(topics)
        var remaining = topics.filter { !used.contains($0) }
        if remaining.isEmpty { used = []; remaining = topics }
        let pick = remaining.randomElement(using: &rng)!
        used.insert(pick)
        write(Array(used), "topics_used.json")
        return pick
    }

    // MARK: Essay / Grammar
    func addEssay(_ e: Essay) {
        essays.insert(e, at: 0)
        addWords(e.vocab.map(\.asWord))
        saveEssays()
    }
    func updateEssay(_ e: Essay) {
        guard let i = essays.firstIndex(where: { $0.id == e.id }) else { return }
        essays[i] = e; saveEssays()
    }
    func deleteEssay(_ id: UUID) { essays.removeAll { $0.id == id }; saveEssays() }

    func addLesson(_ l: GrammarLesson) { lessons.insert(l, at: 0); saveLessons() }
    func updateLesson(_ l: GrammarLesson) {
        guard let i = lessons.firstIndex(where: { $0.id == l.id }) else { return }
        lessons[i] = l; saveLessons()
    }
    func deleteLesson(_ id: UUID) { lessons.removeAll { $0.id == id }; saveLessons() }

    // MARK: Persistence
    private func write<T: Encodable>(_ v: T, _ name: String) {
        try? JSONEncoder().encode(v).write(to: dir.appendingPathComponent(name), options: .atomic)
    }
    private func saveAIWords() { write(deck.words.filter { $0.source == .ai }, "words_ai.json") }
    private func saveHidden() { write(Array(hidden), "hidden.json") }
    private func saveEssays() { write(essays, "essays.json") }
    private func saveLessons() { write(lessons, "grammar.json") }

    private struct ReviewEntry: Codable { let key: SenseKey; let state: ReviewState }

    private func save() {
        let enc = JSONEncoder()
        let entries = deck.reviews.map { ReviewEntry(key: $0.key, state: $0.value) }
        try? enc.encode(entries).write(to: dir.appendingPathComponent("reviews.json"), options: .atomic)
        try? enc.encode(stats).write(to: dir.appendingPathComponent("stats.json"), options: .atomic)
    }
}
