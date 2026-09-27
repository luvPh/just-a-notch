import XCTest
@testable import JustANotch

final class ClaudeReducerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func ev(_ name: String, _ dt: TimeInterval, tool: String? = nil, detail: String? = nil,
                    message: String? = nil) -> ClaudeHookEvent {
        ClaudeHookEvent(session: "s1", cwd: "/Users/x/repo/just-a-notch", name: name, tool: tool,
                        detail: detail, message: message, bundleID: "com.apple.Terminal", at: t0 + dt)
    }

    func testTurnLifecycleEmitsDoneWithDuration() {
        var m: [String: ClaudeSession] = [:]
        XCTAssertNil(ClaudeReducer.apply(ev("SessionStart", 0), to: &m))
        XCTAssertEqual(m["s1"]?.state, .idle)
        XCTAssertNil(ClaudeReducer.apply(ev("UserPromptSubmit", 1, detail: "fix bug"), to: &m))
        XCTAssertEqual(m["s1"]?.state, .working)
        XCTAssertNil(ClaudeReducer.apply(ev("PreToolUse", 5, tool: "Edit", detail: "Foo.swift"), to: &m))
        XCTAssertEqual(m["s1"]?.tool, "Edit")
        XCTAssertEqual(m["s1"]?.detail, "Foo.swift")
        XCTAssertEqual(m["s1"]?.project, "just-a-notch")
        guard case .done(let s, let d)? = ClaudeReducer.apply(ev("Stop", 31), to: &m) else { return XCTFail() }
        XCTAssertEqual(d, 30)
        XCTAssertEqual(s.state, .done)
        XCTAssertNil(m["s1"]?.tool)
    }

    func testPermissionNotificationWaitsThenResumes() {
        var m: [String: ClaudeSession] = [:]
        _ = ClaudeReducer.apply(ev("UserPromptSubmit", 0), to: &m)
        guard case .waiting? = ClaudeReducer.apply(ev("Notification", 2, message: "Claude needs your permission to use Bash"), to: &m)
        else { return XCTFail() }
        XCTAssertEqual(m["s1"]?.state, .waiting)
        _ = ClaudeReducer.apply(ev("PreToolUse", 4, tool: "Bash"), to: &m)
        XCTAssertEqual(m["s1"]?.state, .working)
        XCTAssertNil(m["s1"]?.message)
    }

    func testIdleInputReminderIsIgnored() {
        var m: [String: ClaudeSession] = [:]
        _ = ClaudeReducer.apply(ev("Stop", 0), to: &m)
        XCTAssertNil(ClaudeReducer.apply(ev("Notification", 60, message: "Claude is waiting for your input"), to: &m))
        XCTAssertEqual(m["s1"]?.state, .done)
    }

    func testStopWithoutWorkDoesNotEmit() {
        var m: [String: ClaudeSession] = [:]
        XCTAssertNil(ClaudeReducer.apply(ev("Stop", 0), to: &m))
    }

    func testSessionEndRemoves() {
        var m: [String: ClaudeSession] = [:]
        _ = ClaudeReducer.apply(ev("UserPromptSubmit", 0), to: &m)
        _ = ClaudeReducer.apply(ev("SessionEnd", 1), to: &m)
        XCTAssertNil(m["s1"])
    }

    func testPrune() {
        var m: [String: ClaudeSession] = [:]
        _ = ClaudeReducer.apply(ev("UserPromptSubmit", 0), to: &m)
        ClaudeReducer.prune(&m, now: t0 + 21 * 60)
        XCTAssertEqual(m["s1"]?.state, .idle)
        ClaudeReducer.prune(&m, now: t0 + 4 * 3600)
        XCTAssertNil(m["s1"])
    }

    func testParseEventFileWithHeader() {
        let body = #"{"session_id":"abc","cwd":"/tmp/proj","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"swift build","description":"Build the app"}}"#
        let data = Data(("com.apple.Terminal\tApple_Terminal\n" + body).utf8)
        let e = ClaudeReducer.parseEventFile(data, at: t0)!
        XCTAssertEqual(e.session, "abc")
        XCTAssertEqual(e.bundleID, "com.apple.Terminal")
        XCTAssertEqual(e.tool, "Bash")
        XCTAssertEqual(e.detail, "Build the app")
    }

    func testParseEventFilePlainJSON() {
        let body = #"{"session_id":"abc","cwd":"/tmp/proj","hook_event_name":"UserPromptSubmit","prompt":"hello\nworld"}"#
        let e = ClaudeReducer.parseEventFile(Data(body.utf8), at: t0)!
        XCTAssertNil(e.bundleID)
        XCTAssertEqual(e.detail, "hello world")
    }
}

final class ClaudeNotificationFilterTests: XCTestCase {
    private func rec(_ bundle: String, _ title: String) -> NotificationRecord {
        NotificationRecord(id: 1, bundleId: bundle, appName: "", title: title, subtitle: "", body: "", date: Date())
    }

    func testFiltersClaudeSources() {
        XCTAssertTrue(ClaudeNotificationFilter.isClaude(rec("com.anthropic.claudefordesktop", "Task done")))
        XCTAssertTrue(ClaudeNotificationFilter.isClaude(rec("fr.julienxx.oss.terminal-notifier", "Claude Code")))
        XCTAssertFalse(ClaudeNotificationFilter.isClaude(rec("com.tinyspeck.slackmacgap", "Tin nhắn mới")))
    }
}

@MainActor
final class ClaudeWorkingVariantTests: XCTestCase {
    func testVariantIsStablePerSessionAndCoversAll() {
        let id = "3f2b9c1e-aaaa-bbbb-cccc-1234567890ab"
        XCTAssertEqual(ClaudeWorkingMark.variant(for: id), ClaudeWorkingMark.variant(for: id))
        let seen = Set((0..<60).map { ClaudeWorkingMark.variant(for: "session-\($0)") })
        XCTAssertEqual(seen.count, ClaudeWorkingMark.Variant.allCases.count)
    }
}
