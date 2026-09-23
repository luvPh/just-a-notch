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

    func testSM2Progression() {
        var s = ReviewState.new(now: t0)
        s = s.graded(.good, now: t0); XCTAssertEqual(s.intervalDays, 1)
        s = s.graded(.good, now: t0); XCTAssertEqual(s.intervalDays, 3)
        s = s.graded(.good, now: t0); XCTAssertEqual(s.intervalDays, 7.5, accuracy: 0.001)
        s = s.graded(.again, now: t0)
        XCTAssertEqual(s.reps, 0); XCTAssertEqual(s.lapses, 1)
        XCTAssertEqual(s.ease, 2.3, accuracy: 0.001)
        XCTAssertEqual(s.due, t0.addingTimeInterval(600))
    }

    func testDueBeforeNew() {
        var deck = LearnDeck(words: [word("a", "1"), word("b", "2")])
        let k = SenseKey(wordID: deck.words[0].id, index: 0)
        deck.grade(k, .again, now: t0)
        var r = Seeded(s: 1)
        let p = deck.nextPrompt(now: t0.addingTimeInterval(700), quizChance: 0, rng: &r)
        XCTAssertEqual(p?.key, k); XCTAssertEqual(p?.isNew, false)
        let p2 = deck.nextPrompt(now: t0.addingTimeInterval(60), quizChance: 0, rng: &r)
        XCTAssertEqual(p2?.isNew, true)
        XCTAssertEqual(p2?.key.wordID, deck.words[1].id)
    }

    func testQuizHasFourDistinctOptions() {
        var deck = LearnDeck(words: ["a", "b", "c", "d", "e"].map { word($0, "nghĩa \($0)") })
        let k = SenseKey(wordID: deck.words[2].id, index: 0)
        deck.grade(k, .again, now: t0)
        var r = Seeded(s: 7)
        guard case let .quiz(opts, correct)? = deck.nextPrompt(now: t0.addingTimeInterval(700), quizChance: 1, rng: &r)?.kind
        else { return XCTFail("expected quiz") }
        XCTAssertEqual(Set(opts).count, 4)
        XCTAssertEqual(opts[correct], "nghĩa c")
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
        XCTAssertNotNil(s1.ensurePrompt(now: t0))
        s1.answer(.good, now: t0)
        let s2 = LearnStore(dir: dir, seed: seed)
        XCTAssertEqual(s2.learnedCount, 1)
        XCTAssertEqual(s2.stats.today(now: t0), 1)
    }
}
