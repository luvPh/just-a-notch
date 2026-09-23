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

enum ReviewGrade: Int, CaseIterable { case again = 0, hard, good, easy
    var label: String {
        switch self { case .again: "Quên"; case .hard: "Khó"; case .good: "Nhớ"; case .easy: "Dễ" }
    }
}

/// Trạng thái SRS (SM-2 rút gọn) của một sense.
struct ReviewState: Codable, Equatable {
    var ease: Double = 2.5
    var intervalDays: Double = 0
    var reps: Int = 0
    var lapses: Int = 0
    var due: Date
    var lastReviewed: Date?

    static func new(now: Date) -> ReviewState { ReviewState(due: now) }

    /// Trả về trạng thái sau khi chấm điểm. Thuần, dễ test.
    func graded(_ g: ReviewGrade, now: Date) -> ReviewState {
        var s = self
        s.lastReviewed = now
        switch g {
        case .again:
            s.lapses += 1
            s.reps = 0
            s.ease = max(1.3, s.ease - 0.2)
            s.intervalDays = 0
            s.due = now.addingTimeInterval(10 * 60)      // gặp lại sau 10 phút
            return s
        case .hard:
            s.ease = max(1.3, s.ease - 0.15)
            s.intervalDays = s.reps == 0 ? 0.5 : max(1, s.intervalDays * 1.2)
        case .good:
            s.intervalDays = s.reps == 0 ? 1 : (s.reps == 1 ? 3 : s.intervalDays * s.ease)
        case .easy:
            s.ease += 0.15
            s.intervalDays = s.reps == 0 ? 3 : max(4, s.intervalDays * s.ease * 1.3)
        }
        s.reps += 1
        s.due = now.addingTimeInterval(s.intervalDays * 86_400)
        return s
    }
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

/// Một lượt học: thẻ lật hoặc quiz 4 đáp án.
struct LearnPrompt: Equatable {
    enum Kind: Equatable {
        case card
        case quiz(options: [String], correct: Int)   // options = defVI
    }
    let key: SenseKey
    let isNew: Bool
    let kind: Kind
}
