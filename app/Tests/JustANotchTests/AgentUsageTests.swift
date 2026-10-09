import XCTest
@testable import JustANotch

final class AgentUsageTests: XCTestCase {
    func testCodexTakesLastRateLimits() {
        let text = """
        {"payload":{"rate_limits":{"primary":{"used_percent":1.0,"window_minutes":300,"resets_at":100}}}}
        {"type":"other"}
        {"payload":{"info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":5.0,"window_minutes":300,"resets_at":1791286829},"secondary":{"used_percent":7.0,"window_minutes":10080,"resets_at":1791609612}}}}
        """
        let r = AgentUsageParser.codex(fromJSONL: text)
        XCTAssertEqual(r?.0?.usedPercent, 5)
        XCTAssertEqual(r?.1?.usedPercent, 7)
        XCTAssertEqual(r?.1?.windowMinutes, 10080)
    }

    func testClaudeLineSumsTokens() {
        let line: Substring = #"{"timestamp":"2026-10-06T08:00:00.123Z","requestId":"r1","message":{"id":"m1","usage":{"input_tokens":2,"cache_creation_input_tokens":400,"cache_read_input_tokens":78770,"output_tokens":286}}}"#
        let r = AgentUsageParser.claudeLine(line)
        XCTAssertEqual(r?.tokens, 688)
        XCTAssertEqual(r?.output, 286)
        XCTAssertEqual(r?.key, "m1|r1")
    }

    func testTokenFormat() {
        XCTAssertEqual(UsageFormat.tokens(1_500_000), "1.5M")
        XCTAssertEqual(UsageFormat.tokens(42_000), "42K")
    }
}
