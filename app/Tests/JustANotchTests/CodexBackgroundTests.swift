import XCTest
@testable import JustANotch

final class CodexBackgroundTests: XCTestCase {
    private func transcript(_ meta: String) throws -> String {
        let p = NSTemporaryDirectory() + UUID().uuidString + ".jsonl"
        try (#"{"type":"session_meta","payload":"# + meta + "}\n{}\n").write(toFile: p, atomically: true, encoding: .utf8)
        return p
    }

    func testGuardianSessionIsBackground() throws {
        let p = try transcript(#"{"source":{"subagent":{"other":"guardian"}},"thread_source":"guardian_review"}"#)
        XCTAssertTrue(ClaudeReducer.isCodexBackgroundSession(UUID().uuidString, transcript: p))
    }

    func testUserAndSpawnedSessionsShown() throws {
        let user = try transcript(#"{"source":"vscode","thread_source":"user"}"#)
        XCTAssertFalse(ClaudeReducer.isCodexBackgroundSession(UUID().uuidString, transcript: user))
        let spawn = try transcript(#"{"source":{"subagent":{"thread_spawn":{"depth":1}}},"thread_source":"subagent"}"#)
        XCTAssertFalse(ClaudeReducer.isCodexBackgroundSession(UUID().uuidString, transcript: spawn))
        XCTAssertFalse(ClaudeReducer.isCodexBackgroundSession(UUID().uuidString, transcript: nil))
    }
}
