import XCTest
@testable import JustANotch

final class TextDiffTests: XCTestCase {
    func testPerfectMatchIgnoresCaseAndPunctuation() {
        XCTAssertEqual(TextDiff.score(reference: "Hello, world!", attempt: "hello world"), 1)
    }

    func testMissingWordMarked() {
        let t = TextDiff.mark(reference: "I really like green tea.", attempt: "I like tea")
        XCTAssertEqual(t.map(\.ok), [true, false, true, false, true])
        XCTAssertEqual(t.map(\.text).joined(separator: " "), "I really like green tea.")
    }

    func testExtraWordsDoNotBreakAlignment() {
        XCTAssertEqual(TextDiff.score(reference: "She don't know", attempt: "she um don't really know"), 1)
    }

    func testExtractJSON() {
        XCTAssertEqual(ClaudeCLI.extractJSON("Sure!\n```json\n{\"a\":1}\n```"), "{\"a\":1}")
        XCTAssertEqual(ClaudeCLI.extractJSON("x [1,2] y"), "[1,2]")
    }
}
