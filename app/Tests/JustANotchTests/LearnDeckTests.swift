import XCTest
@testable import JustANotch

final class LearnDeckTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func word(_ h: String, _ vi: String) -> LearnWord {
        LearnWord(headword: h, pos: "noun", ipaUK: "", ipaUS: "",
                  senses: [LearnSense(guideword: "X", level: "B1", defEN: h, defVI: vi, examples: [])])
    }

    private struct Seeded: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    func testEngZoneIntervals() {
        var s = ReviewState.new(now: t0)
        s = s.recorded(correct: true, mode: .fill, now: t0); XCTAssertEqual(s.intervalDays, 1)
        s = s.recorded(correct: true, mode: .fill, now: t0); XCTAssertEqual(s.intervalDays, 3)
        s = s.recorded(correct: true, mode: .fill, now: t0); XCTAssertEqual(s.intervalDays, 8) // 3 × 2.7→2.6 cap
        s = s.recorded(correct: false, mode: .fill, now: t0)
        XCTAssertEqual(s.reps, 0); XCTAssertEqual(s.lapses, 1); XCTAssertEqual(s.due, t0)
        XCTAssertEqual(s.correct, 1)                          // sai → trừ tiến độ thuộc
    }

    func testWrongAnswerDropsMastery() {
        var s = ReviewState.new(now: t0)
        s = s.recorded(correct: false, mode: .fill, now: t0)
        XCTAssertEqual(s.correct, 0)                          // không âm
        for m in PracticeMode.allCases { for _ in 0..<4 { s = s.recorded(correct: true, mode: m, now: t0) } }
        XCTAssertTrue(s.mastered); XCTAssertEqual(s.correct, 12)
        s = s.recorded(correct: false, mode: .fill, now: t0)
        XCTAssertEqual(s.correct, ReviewState.masterAt - ReviewState.wrongPenalty)
        XCTAssertFalse(s.mastered)
    }

    func testMasteryNeedsTenCorrectAcrossAllModes() {
        var s = ReviewState.new(now: t0)
        for _ in 0..<12 { s = s.recorded(correct: true, mode: .mcqWord, now: t0) }
        XCTAssertFalse(s.mastered)
        s = s.recorded(correct: true, mode: .mcqMeaning, now: t0)
        XCTAssertFalse(s.mastered)
        s = s.recorded(correct: true, mode: .fill, now: t0)
        XCTAssertTrue(s.mastered)
    }

    func testOldReviewJSONStillDecodes() throws {
        let json = #"{"ease":2.5,"intervalDays":1,"reps":1,"lapses":0,"due":0}"#
        let s = try JSONDecoder().decode(ReviewState.self, from: Data(json.utf8))
        XCTAssertEqual(s.correct, 0); XCTAssertEqual(s.modes, [])
    }

    func testNotchDueQuestionBeforeNewIntro() {
        var deck = LearnDeck(words: ["a", "b", "c", "d", "e"].map { word($0, "nghĩa \($0)") })
        let k = SenseKey(wordID: deck.words[0].id, index: 0)
        deck.introduce(k, now: t0)
        var r = Seeded(s: 1)
        guard case let .question(q)? = deck.nextPrompt(now: t0, rng: &r) else { return XCTFail() }
        XCTAssertEqual(q.key, k)
        deck.record(k, correct: true, mode: q.mode, now: t0)
        guard case .intro? = deck.nextPrompt(now: t0, rng: &r) else { return XCTFail() }
    }

    func testQuestionModes() {
        let deck = LearnDeck(words: ["a", "b", "c", "d", "e"].map { word($0, "nghĩa \($0)") })
        let k = SenseKey(wordID: deck.words[2].id, index: 0)
        var r = Seeded(s: 7)
        let q1 = deck.question(for: k, mode: .mcqWord, rng: &r)!
        XCTAssertEqual(Set(q1.options).count, 4); XCTAssertEqual(q1.options[q1.correct], "nghĩa c")
        let q2 = deck.question(for: k, mode: .mcqMeaning, rng: &r)!
        XCTAssertEqual(q2.options[q2.correct], "c")
        let q3 = deck.question(for: k, mode: .fill, rng: &r)!
        XCTAssertTrue(q3.isCorrect(fill: "  C "))
        XCTAssertEqual(q3.charHint, "‧")
    }

    func testMcqFallsBackToFillWithoutDistractors() {
        let deck = LearnDeck(words: [word("a", "1"), word("b", "2")])
        var r = Seeded(s: 3)
        XCTAssertEqual(deck.question(for: SenseKey(wordID: deck.words[0].id, index: 0), mode: .mcqWord, rng: &r)?.mode, .fill)
    }

    func testStudyBatchOrderAndNewLimit() {
        var deck = LearnDeck(words: (0..<20).map { word("w\($0)", "n\($0)") })
        let due = SenseKey(wordID: deck.words[0].id, index: 0)
        let future = SenseKey(wordID: deck.words[1].id, index: 0)
        deck.introduce(due, now: t0)
        deck.record(future, correct: true, mode: .fill, now: t0)
        deck.markKnown(deck.words[2].id, now: t0)
        var r = Seeded(s: 5)
        let b = deck.studyBatch(size: 5, newLimit: 3, now: t0.addingTimeInterval(60), rng: &r)
        XCTAssertEqual(b.first, due)
        XCTAssertEqual(b.last, future)
        XCTAssertEqual(b.count, 5)
        XCTAssertFalse(b.contains(SenseKey(wordID: deck.words[2].id, index: 0)))
    }

    func testDuplicateWordsIgnored() {
        let deck = LearnDeck(words: [word("a", "1"), word("A", "2")])
        XCTAssertEqual(deck.words.count, 1)
    }

    func testStreak() {
        var st = LearnStats()
        let cal = Calendar.current
        st.record(now: cal.date(byAdding: .day, value: -1, to: t0)!)
        st.record(now: cal.date(byAdding: .day, value: -2, to: t0)!)
        XCTAssertEqual(st.streak(now: t0), 2)
        st.record(now: t0)
        XCTAssertEqual(st.streak(now: t0), 3)
    }

    func testStorePersistsReviews() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seed = [word("a", "1"), word("b", "2")]
        let s1 = LearnStore(dir: dir, seed: seed)
        let k = SenseKey(wordID: seed[0].id, index: 0)
        s1.record(k, correct: true, mode: .fill, now: t0)
        let s2 = LearnStore(dir: dir, seed: seed)
        XCTAssertEqual(s2.review(k)?.correct, 1)
        XCTAssertEqual(s2.stats.today(now: t0), 1)
    }
}

final class LearnKnownTests: XCTestCase {
    func testMarkAndUnmarkKnown() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let w = LearnWord(headword: "a", pos: "noun", ipaUK: "", ipaUS: "",
                          senses: [LearnSense(guideword: "X", level: "B1", defEN: "", defVI: "1", examples: [])])
        var deck = LearnDeck(words: [w])
        let k = SenseKey(wordID: w.id, index: 0)
        deck.markKnown(w.id, now: t0)
        XCTAssertTrue(deck.reviews[k]!.mastered)
        XCTAssertTrue(deck.dueKeys(now: t0.addingTimeInterval(400 * 86_400)).isEmpty)
        deck.unmarkKnown(w.id, now: t0)
        XCTAssertEqual(deck.dueKeys(now: t0), [k])
    }
}

final class LearnModePriorityTests: XCTestCase {
    func testPrefersModesNotYetCorrect() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let words = ["a", "b", "c", "d", "e"].map {
            LearnWord(headword: $0, pos: "noun", ipaUK: "", ipaUS: "",
                      senses: [LearnSense(guideword: "X", level: "B1", defEN: "", defVI: "n\($0)", examples: [])])
        }
        var deck = LearnDeck(words: words)
        let k = SenseKey(wordID: words[0].id, index: 0)
        deck.record(k, correct: true, mode: .mcqWord, now: t0)
        deck.record(k, correct: true, mode: .fill, now: t0)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<30 { XCTAssertEqual(deck.question(for: k, rng: &rng)?.mode, .mcqMeaning) }
    }
}

final class DailySetTests: XCTestCase {
    private func w(_ h: String, _ level: String) -> LearnWord {
        LearnWord(headword: h, pos: "noun", ipaUK: "", ipaUS: "",
                  senses: [LearnSense(guideword: "X", level: level, defEN: "", defVI: "n\(h)", examples: [])])
    }

    func testPicksTenB2ToC2PreferringNew() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var words = (0..<15).map { w("b1_\($0)", "B1") }
        words += (0..<8).map { w("new\($0)", "C1") }
        words += (0..<5).map { w("old\($0)", "B2") }
        var deck = LearnDeck(words: words)
        for i in 0..<5 { deck.introduce(SenseKey(wordID: deck.byID["old\(i)|noun"]!.id, index: 0), now: t0) }
        var r = SystemRandomNumberGenerator()
        let set = deck.pickDaily(day: "d", rng: &r)
        XCTAssertEqual(set.keys.count, 10)
        XCTAssertEqual(set.keys.filter { $0.wordID.hasPrefix("new") }.count, 8)
        XCTAssertFalse(set.keys.contains { $0.wordID.hasPrefix("b1") })
    }

    func testDailyPromptRotatesLeastShown() {
        let deck = LearnDeck(words: ["a", "b", "c", "d", "e"].map { w($0, "C2") })
        var set = DailySet(day: "d", keys: deck.allKeys)
        for k in deck.allKeys.dropLast() { set.shown[k.description] = 2 }
        var r = SystemRandomNumberGenerator()
        XCTAssertEqual(deck.dailyPrompt(set, rng: &r), .intro(deck.allKeys.last!))
    }
}

final class DailyLessonFlowTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func words(_ n: Int) -> [LearnWord] {
        (0..<n).map { i in LearnWord(headword: "w\(i)", pos: "noun", ipaUK: "", ipaUS: "",
            senses: [LearnSense(guideword: "X", level: "C1", defEN: "", defVI: "n\(i)", examples: [])]) }
    }
    private func master(_ s: LearnStore, _ k: SenseKey) {
        for m in PracticeMode.allCases { for _ in 0..<4 { s.record(k, correct: true, mode: m, now: t0) } }
    }
    private func store() throws -> LearnStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return LearnStore(dir: dir, seed: words(40))
    }

    func testUnfinishedLessonCarriesOverNextDay() throws {
        let s = try store()
        let day1 = s.ensureDaily(now: t0).keys
        for k in day1.prefix(4) { master(s, k) }
        let day2 = s.ensureDaily(now: t0.addingTimeInterval(86_400)).keys
        XCTAssertEqual(day2.count, 10)
        XCTAssertEqual(Set(day2).intersection(day1), Set(day1.dropFirst(4)))
    }

    func testCompletionThenNewSetOrReviewAgain() throws {
        let s = try store()
        let set = s.ensureDaily(now: t0).keys
        set.forEach { master(s, $0) }
        XCTAssertTrue(s.dailyComplete)
        XCTAssertNil(s.ensurePrompt(now: t0))
        s.reviewDailyAgain()
        XCTAssertFalse(s.dailyComplete)
        XCTAssertNotNil(s.ensurePrompt(now: t0))
        XCTAssertTrue(set.contains(s.current!.key))
        XCTAssertEqual(s.review(set[0])?.correct, 12)          // tiến độ không bị reset
        s.startNewDailySet(now: t0)
        XCTAssertFalse(s.daily!.reviewAgain)
        XCTAssertTrue(Set(s.daily!.keys).isDisjoint(with: set))
        XCTAssertEqual(s.daily!.keys.count, 10)
    }
}

final class DailyReviewAgainTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func store() throws -> LearnStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seed = (0..<30).map { i in LearnWord(headword: "w\(i)", pos: "noun", ipaUK: "", ipaUS: "",
            senses: [LearnSense(guideword: "X", level: "C1", defEN: "", defVI: "n\(i)", examples: [])]) }
        return LearnStore(dir: dir, seed: seed)
    }
    private func master(_ s: LearnStore, _ k: SenseKey) {
        for m in PracticeMode.allCases { for _ in 0..<4 { s.record(k, correct: true, mode: m, now: t0) } }
    }

    /// Ôn lại = đúng 1 vòng: mỗi từ hỏi 1 lần rồi quay về màn hoàn thành.
    func testReviewAgainIsOneRound() throws {
        let s = try store()
        let set = s.ensureDaily(now: t0).keys
        set.forEach { master(s, $0) }
        s.reviewDailyAgain()
        var asked: [SenseKey] = []
        while let p = s.ensurePrompt(now: t0) {
            asked.append(p.key)
            s.answer(correct: true, now: t0)
            s.finishCurrent(now: t0)
            if asked.count > 20 { return XCTFail("vòng ôn lại không dừng") }
        }
        XCTAssertEqual(Set(asked), Set(set)); XCTAssertEqual(asked.count, set.count)
        XCTAssertTrue(s.dailyComplete)
        XCTAssertEqual(s.daily!.keys, set)
    }

    /// Bấm "đã thuộc" khi ôn lại → bỏ qua từ đó, không thay bằng từ mới.
    func testMarkKnownDuringReviewAgainKeepsSet() throws {
        let s = try store()
        let set = s.ensureDaily(now: t0).keys
        set.forEach { master(s, $0) }
        s.reviewDailyAgain()
        s.markKnown(set[2].wordID, now: t0)
        XCTAssertEqual(s.daily!.keys, set)
        XCTAssertFalse(s.daily!.again.contains(set[2]))
    }

    /// Sai khi ôn lại → rớt thuộc, phải học tiếp tới khi thuộc lại mới hoàn thành.
    func testWrongDuringReviewAgainMustRelearn() throws {
        let s = try store()
        let set = s.ensureDaily(now: t0).keys
        set.forEach { master(s, $0) }
        s.reviewDailyAgain()
        s.record(set[0], correct: false, mode: .fill, now: t0)
        set.dropFirst().forEach { s.record($0, correct: true, mode: .fill, now: t0) }
        XCTAssertFalse(s.daily!.reviewAgain)
        XCTAssertFalse(s.dailyComplete)
        XCTAssertEqual(s.ensurePrompt(now: t0)?.key, set[0])
    }

    func testLegacyReviewAgainFlagBecomesOneRound() throws {
        let json = #"{"day":"d","keys":[{"wordID":"a|noun","index":0},{"wordID":"b|noun","index":0}],"#
            + #""shown":{"a|noun#0":20,"b|noun#0":6},"reviewAgain":true}"#
        let d = try JSONDecoder().decode(DailySet.self, from: Data(json.utf8))
        XCTAssertEqual(d.again, d.keys)
        XCTAssertEqual(Set(d.shown.values), [20])
    }
}

final class DailyReplaceKnownTests: XCTestCase {
    /// Từ thay vào giữa chừng xoay vòng chung với cả bộ, không bị hỏi dồn liên tục.
    func testReplacementWordJoinsRotation() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seed = (0..<30).map { i in LearnWord(headword: "w\(i)", pos: "noun", ipaUK: "", ipaUS: "",
            senses: [LearnSense(guideword: "X", level: "B2", defEN: "", defVI: "n\(i)", examples: [])]) }
        let s = LearnStore(dir: dir, seed: seed)
        let before = s.ensureDaily(now: t0).keys
        for _ in 0..<30 {                                    // mỗi từ đã hiện ~3 lần
            guard s.ensurePrompt(now: t0) != nil else { break }
            s.answer(correct: true, now: t0); s.finishCurrent(now: t0)
        }
        s.markKnown(before[3].wordID, now: t0)
        let fresh = s.daily!.keys.first { !before.contains($0) }!
        var hits = 0
        for _ in 0..<5 {
            guard let p = s.ensurePrompt(now: t0) else { break }
            if p.key == fresh { hits += 1 }
            s.answer(correct: true, now: t0); s.finishCurrent(now: t0)
        }
        XCTAssertLessThanOrEqual(hits, 1)
    }

    func testMarkKnownReplacesWordInDailySet() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seed = (0..<30).map { i in LearnWord(headword: "w\(i)", pos: "noun", ipaUK: "", ipaUS: "",
            senses: [LearnSense(guideword: "X", level: "B2", defEN: "", defVI: "n\(i)", examples: [])]) }
        let s = LearnStore(dir: dir, seed: seed)
        let before = s.ensureDaily(now: t0).keys
        s.markKnown(before[3].wordID, now: t0)
        let after = s.daily!.keys
        XCTAssertEqual(after.count, 10)
        XCTAssertFalse(after.contains(before[3]))
        XCTAssertEqual(Set(after).intersection(before).count, 9)
        XCTAssertFalse(s.dailyComplete)
    }
}

final class OldLessonReviewTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func master(_ s: LearnStore, _ k: SenseKey) {
        for m in PracticeMode.allCases { for _ in 0..<4 { s.record(k, correct: true, mode: m, now: t0) } }
    }
    private func store() throws -> LearnStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seed = (0..<50).map { i in LearnWord(headword: "w\(i)", pos: "noun", ipaUK: "", ipaUS: "",
            senses: [LearnSense(guideword: "X", level: "C1", defEN: "", defVI: "n\(i)", examples: [])]) }
        return LearnStore(dir: dir, seed: seed)
    }

    func testCompletedYesterdayMustBeReviewedFirst() throws {
        let s = try store()
        let day1 = s.ensureDaily(now: t0).keys
        day1.forEach { master(s, $0) }
        let day2 = t0.addingTimeInterval(86_400)
        let set2 = s.ensureDaily(now: day2)
        XCTAssertEqual(set2.reviewQueue.count, 30)                       // 10 từ × 3 dạng
        XCTAssertEqual(Set(set2.reviewQueue.map(\.key)), Set(day1))
        XCTAssertTrue(Set(set2.keys).isDisjoint(with: day1))
        var failed: SenseKey?
        var asked = 0
        while case let .question(q)? = s.ensurePrompt(now: day2) {
            XCTAssertTrue(day1.contains(q.key))
            let ok = failed != nil || q.key != day1[0]                  // rớt từ đầu tiên
            if !ok { failed = q.key }
            s.answer(correct: ok, now: day2)
            s.finishCurrent(now: day2)
            asked += 1
            if asked > 40 { return XCTFail("loop") }
        }
        XCTAssertTrue(s.needsReviewSummary)
        XCTAssertEqual(s.reviewFailedWords, 1)
        XCTAssertLessThanOrEqual(asked, 30)
        XCTAssertGreaterThanOrEqual(asked, 28)                          // 27 câu của 9 từ + 1–3 câu của từ rớt
        XCTAssertNil(s.review(day1[0]))
        XCTAssertTrue(s.daily!.keys.contains(day1[0]))
        XCTAssertEqual(s.daily!.keys.count, 11)
        s.ackReviewSummary()
        XCTAssertNotNil(s.ensurePrompt(now: day2))
    }

    func testUnfinishedYesterdayHasNoReview() throws {
        let s = try store()
        let day1 = s.ensureDaily(now: t0).keys
        master(s, day1[0])
        let set2 = s.ensureDaily(now: t0.addingTimeInterval(86_400))
        XCTAssertTrue(set2.reviewQueue.isEmpty)
        XCTAssertTrue(set2.keys.contains(day1[1]))
    }
}

final class RelearnRetryTests: XCTestCase {
    func testWrongAnswerIsAskedAgainNextWithDifferentMode() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let seed = (0..<30).map { i in LearnWord(headword: "w\(i)", pos: "noun", ipaUK: "", ipaUS: "",
            senses: [LearnSense(guideword: "X", level: "C1", defEN: "", defVI: "n\(i)", examples: [])]) }
        let s = LearnStore(dir: dir, seed: seed)
        let keys = s.ensureDaily(now: t0).keys
        keys.forEach { s.introduce($0, now: t0) }
        guard case let .question(q1)? = s.ensurePrompt(now: t0) else { return XCTFail() }
        s.answer(correct: false, now: t0)
        s.finishCurrent(now: t0)
        guard case let .question(q2)? = s.ensurePrompt(now: t0) else { return XCTFail() }
        XCTAssertEqual(q2.key, q1.key)
        XCTAssertNotEqual(q2.mode, q1.mode)
        s.answer(correct: true, now: t0)
        s.finishCurrent(now: t0)
        XCTAssertEqual(s.review(q1.key)?.correct, 1)          // lần hỏi lại có tính điểm
        XCTAssertNil(s.daily?.retry)
    }
}

