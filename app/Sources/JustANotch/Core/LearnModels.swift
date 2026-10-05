// app/Sources/JustANotch/Core/LearnModels.swift
import Foundation

/// Mục từ kiểu từ điển (headword + nhiều nghĩa), kèm tiếng Việt.
struct LearnWord: Codable, Identifiable, Equatable {
    var id: String { headword.lowercased() + "|" + pos }
    var headword: String
    var pos: String
    var ipaUK: String
    var ipaUS: String
    var senses: [LearnSense]
    var source: Source? = .seed

    enum Source: String, Codable { case seed, ai }
}

struct LearnSense: Codable, Equatable {
    var guideword: String
    var level: String          // A2…C2
    var defEN: String
    var defVI: String
    var examples: [LearnExample]
}

struct LearnExample: Codable, Equatable {
    var en: String
    var vi: String
}

/// Đơn vị ôn tập: một nghĩa của một từ.
struct SenseKey: Hashable, Codable, CustomStringConvertible {
    let wordID: String
    let index: Int
    var description: String { "\(wordID)#\(index)" }
}

/// 3 dạng câu hỏi luyện từ (theo EngZone).
enum PracticeMode: String, Codable, CaseIterable {
    case mcqWord      // cho từ → chọn nghĩa
    case mcqMeaning   // cho nghĩa → chọn từ
    case fill         // cho nghĩa + gợi ý số ký tự → gõ từ

    var title: String {
        switch self { case .mcqWord: "Chọn nghĩa"; case .mcqMeaning: "Chọn từ"; case .fill: "Điền từ" }
    }
}

/// Trạng thái SRS của một sense — chấm đúng/sai tự động, thuộc khi đúng đủ 10 lần
/// VÀ đã đúng ở đủ cả 3 dạng câu hỏi.
struct ReviewState: Codable, Equatable {
    static let masterAt = 10
    /// Trả lời sai → trừ bấy nhiêu lần đúng (tính từ mức trần `masterAt`, không âm).
    static let wrongPenalty = 2

    var ease: Double = 2.5
    var intervalDays: Double = 0
    var reps: Int = 0
    var lapses: Int = 0
    var due: Date
    var lastReviewed: Date?
    var correct: Int = 0
    var modes: [PracticeMode] = []

    var mastered: Bool { correct >= Self.masterAt && Set(modes).count == PracticeMode.allCases.count }

    init(due: Date) { self.due = due }
    static func new(now: Date) -> ReviewState { ReviewState(due: now) }

    /// Khoảng ôn kế tiếp (ngày) nếu trả lời đúng/sai bây giờ.
    func nextIntervalDays(correct ok: Bool) -> Double {
        guard ok else { return 0 }
        let r = reps + 1
        return r == 1 ? 1 : r == 2 ? 3 : (intervalDays * ease).rounded()
    }

    /// Ghi một lượt trả lời. Đúng → giãn lịch; sai → reset chuỗi, trừ tiến độ thuộc, ôn lại ngay.
    func recorded(correct ok: Bool, mode: PracticeMode, now: Date) -> ReviewState {
        var s = self
        s.lastReviewed = now
        if ok {
            s.intervalDays = nextIntervalDays(correct: true)
            s.correct += 1
            if !s.modes.contains(mode) { s.modes.append(mode) }
            s.reps += 1
            s.ease = min(2.6, s.ease + 0.1)
        } else {
            s.reps = 0
            s.correct = max(0, min(s.correct, Self.masterAt) - Self.wrongPenalty)
            s.intervalDays = 0
            s.lapses += 1
            s.ease = max(1.3, s.ease - 0.2)
        }
        s.due = now.addingTimeInterval(s.intervalDays * 86_400)
        return s
    }

    private enum CodingKeys: String, CodingKey { case ease, intervalDays, reps, lapses, due, lastReviewed, correct, modes }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        ease = try c.decodeIfPresent(Double.self, forKey: .ease) ?? 2.5
        intervalDays = try c.decodeIfPresent(Double.self, forKey: .intervalDays) ?? 0
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
        lapses = try c.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        due = try c.decode(Date.self, forKey: .due)
        lastReviewed = try c.decodeIfPresent(Date.self, forKey: .lastReviewed)
        correct = try c.decodeIfPresent(Int.self, forKey: .correct) ?? 0
        modes = try c.decodeIfPresent([PracticeMode].self, forKey: .modes) ?? []
    }

    static func intervalText(days: Double) -> String {
        if days <= 0 { return "ôn lại ngay" }
        if days < 30 { return "ôn lại sau \(Int(days)) ngày" }
        if days < 365 { return "ôn lại sau \(Int((days / 30).rounded())) tháng" }
        return "ôn lại sau \(Int((days / 365).rounded())) năm"
    }
}

/// Một câu ôn bài cũ: sense × dạng câu hỏi (mỗi từ ôn đủ cả 3 dạng).
struct ReviewItem: Codable, Hashable {
    let key: SenseKey
    let mode: PracticeMode
    var id: String { "\(key)|\(mode.rawValue)" }
}

/// Bài học trong ngày: 10 sense B2–C2. Chưa thuộc hết → hôm sau học nối tiếp (giữ từ
/// chưa thuộc, lấp chỗ trống bằng từ mới). Thuộc hết → "hoàn thành", người học chọn
/// học bộ khác hoặc ôn lại bộ này (không giới hạn, không reset tiến độ).
struct DailySet: Codable, Equatable {
    static let size = 10
    static let levels: Set<String> = ["B2", "C1", "C2"]

    var day: String
    var keys: [SenseKey]
    /// Số lần mỗi sense đã hiện (key = SenseKey.description) — để xoay vòng đều.
    var shown: [String: Int] = [:]
    /// Vòng "Ôn lại 10 từ này": các từ còn phải hỏi lại 1 lần (kể cả đã thuộc). Hỏi hết → hoàn thành lại.
    var again: [SenseKey] = []
    /// Popup đã báo "hoàn thành" (chỉ báo 1 lần).
    var announced = false
    /// Các bộ đã hoàn thành trong ngày (trước khi chọn "Học 10 từ khác") — hôm sau ôn lại.
    var completed: [SenseKey] = []
    /// Ôn bài cũ (bắt buộc, đầu ngày): các câu (từ × 3 dạng) còn phải hỏi.
    var reviewQueue: [ReviewItem] = []
    /// Kết quả từng câu ôn bài cũ (key = ReviewItem.id).
    var reviewResults: [String: Bool] = [:]
    /// Đã xem màn tổng kết ôn bài cũ.
    var reviewSummaryAcked = false
    /// Câu vừa trả lời sai (trong bài hôm nay) → lượt popup kế tiếp hỏi lại bằng dạng khác.
    var retry: ReviewItem?

    init(day: String, keys: [SenseKey], shown: [String: Int] = [:]) {
        self.day = day; self.keys = keys; self.shown = shown
    }

    private enum CodingKeys: String, CodingKey {
        case day, keys, shown, again, announced, completed, reviewQueue, reviewResults, reviewSummaryAcked, retry
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        keys = try c.decode([SenseKey].self, forKey: .keys)
        shown = try c.decodeIfPresent([String: Int].self, forKey: .shown) ?? [:]
        again = try c.decodeIfPresent([SenseKey].self, forKey: .again) ?? []
        // Bản cũ: cờ `reviewAgain` bật mãi → chuyển thành 1 vòng ôn lại cả bộ.
        if try d.container(keyedBy: LegacyKeys.self).decodeIfPresent(Bool.self, forKey: .reviewAgain) == true,
           !c.contains(.again) { again = keys; evenShown() }
        announced = try c.decodeIfPresent(Bool.self, forKey: .announced) ?? false
        completed = try c.decodeIfPresent([SenseKey].self, forKey: .completed) ?? []
        reviewQueue = (try? c.decodeIfPresent([ReviewItem].self, forKey: .reviewQueue)) ?? []
        reviewResults = try c.decodeIfPresent([String: Bool].self, forKey: .reviewResults) ?? [:]
        reviewSummaryAcked = try c.decodeIfPresent(Bool.self, forKey: .reviewSummaryAcked) ?? false
        retry = try? c.decodeIfPresent(ReviewItem.self, forKey: .retry)
    }
    private enum LegacyKeys: String, CodingKey { case reviewAgain }

    /// Đang trong vòng "Ôn lại 10 từ này".
    var reviewAgain: Bool { !again.isEmpty }

    /// Cân bộ đếm cả bộ về cùng mức (đầu vòng ôn lại) → mọi từ xoay vòng ngẫu nhiên, đều nhau.
    mutating func evenShown() {
        let top = shown.values.max() ?? 0
        shown = Dictionary(uniqueKeysWithValues: keys.map { ($0.description, top) })
    }

    /// Từ mới vào bài giữa chừng: cho số lần hiện bằng từ ít hiện nhất để xoay vòng chung,
    /// không bị hỏi dồn liên tục cho tới khi "đuổi kịp" các từ khác.
    mutating func seedShown(_ k: SenseKey) {
        let others = keys.filter { $0 != k }.compactMap { shown[$0.description] }
        shown[k.description] = others.min() ?? 0
    }

    /// Đang trong phần ôn bài cũ (còn câu phải hỏi).
    var reviewing: Bool { !reviewQueue.isEmpty }
    /// Ôn xong nhưng chưa xem tổng kết.
    var needsReviewSummary: Bool { reviewQueue.isEmpty && !reviewResults.isEmpty && !reviewSummaryAcked }
}

/// Streak + số lượt ôn theo ngày (key yyyy-MM-dd).
struct LearnStats: Codable, Equatable {
    var reviewsByDay: [String: Int] = [:]

    static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    mutating func record(now: Date) { reviewsByDay[Self.dayKey(now), default: 0] += 1 }

    func today(now: Date) -> Int { reviewsByDay[Self.dayKey(now)] ?? 0 }

    /// Số ngày liên tiếp có ôn, tính tới hôm nay (hôm nay chưa ôn vẫn giữ streak tới hôm qua).
    func streak(now: Date, calendar: Calendar = .current) -> Int {
        var day = now
        if reviewsByDay[Self.dayKey(day, calendar: calendar)] == nil {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var n = 0
        while reviewsByDay[Self.dayKey(day, calendar: calendar)] != nil {
            n += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return n
    }
}

/// Một câu hỏi luyện từ. mcq: `options` + `correct`; fill: `answer` (headword).
struct PracticeQuestion: Equatable {
    let key: SenseKey
    let mode: PracticeMode
    let options: [String]
    let correct: Int
    let answer: String

    /// Gợi ý số ký tự: "resilient" → "‧ ‧ ‧ ‧ ‧ ‧ ‧ ‧ ‧" (không lộ chữ nào).
    var charHint: String { answer.map { $0 == " " ? " " : "‧" }.joined(separator: " ") }

    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    func isCorrect(fill input: String) -> Bool { Self.normalize(input) == Self.normalize(answer) }
}

/// Một lượt học trên notch: giới thiệu từ mới, hoặc một câu hỏi.
enum LearnPrompt: Equatable {
    case intro(SenseKey)
    case question(PracticeQuestion)

    var key: SenseKey {
        switch self { case let .intro(k): k; case let .question(q): q.key }
    }
}
