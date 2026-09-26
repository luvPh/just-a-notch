import XCTest
@testable import JustANotch

/// Gọi Claude CLI thật — chỉ chạy khi đặt LEARN_AI_LIVE=1 (tốn thời gian + quota).
final class LearnAILiveTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LEARN_AI_LIVE"] == "1")
    }

    func testWordBatchDecodes() async throws {
        let w = try await ClaudeCLI.json([LearnWord].self, system: LearnAI.system,
                                         prompt: LearnAI.wordBatch(topic: "travel", level: "B2", count: 3, exclude: ["trip"]))
        XCTAssertFalse(w.isEmpty); XCTAssertFalse(w[0].senses.isEmpty)
    }

    func testLookupDecodes() async throws {
        let r = try await ClaudeCLI.json(WordLookup.self, system: LearnAI.system,
                                         prompt: LearnAI.lookup(word: "running", sentence: "She is running a small bakery."))
        XCTAssertEqual(r.lemma.lowercased(), "run")
    }

    func testGrammarDecodes() async throws {
        let l = try await ClaudeCLI.json(GrammarLesson.self, system: LearnAI.system, prompt: LearnAI.grammar(point: "since vs for"))
        XCTAssertFalse(l.examples.isEmpty); XCTAssertNotNil(l.quickCheck)
    }

    func testEssayDecodes() async throws {
        struct Raw: Decodable { var essay: String; var sentences: [LearnExample]; var vocab: [EssayVocab]; var families: [WordFamily] }
        let r = try await ClaudeCLI.json(Raw.self, system: LearnAI.system, prompt: LearnAI.essay(topic: "cats", level: 1))
        XCTAssertFalse(r.vocab.isEmpty); XCTAssertGreaterThan(r.sentences.count, 3)
    }

    func testTranslationGradeDecodes() async throws {
        let g = try await ClaudeCLI.json(TranslationGrade.self, system: LearnAI.system,
            prompt: LearnAI.gradeTranslation(vi: "Tôi thích mèo.", reference: "I like cats.", answer: "I likes cat"))
        XCTAssertLessThan(g.score, 10)
    }
}
