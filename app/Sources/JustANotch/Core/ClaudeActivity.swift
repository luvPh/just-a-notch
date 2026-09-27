import Foundation
import AppKit
import Combine

// MARK: - Model

/// Trạng thái một phiên Claude Code, dựng lại từ các sự kiện hook.
struct ClaudeSession: Identifiable, Equatable {
    enum State: String { case idle, working, waiting, done }

    let id: String                 // session_id
    var cwd: String
    var state: State
    var tool: String?              // tool đang chạy (PreToolUse)
    var detail: String?            // tóm tắt: file đang sửa, lệnh bash, prompt…
    var message: String?           // nội dung Notification (xin quyền…)
    var bundleID: String?          // app chứa phiên (Terminal, Claude desktop, VS Code…)
    var turnStartedAt: Date?
    var updatedAt: Date

    /// Tên dự án = thư mục cuối của cwd.
    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "Claude" : name
    }
    var isActive: Bool { state == .working || state == .waiting }
}

/// Một sự kiện hook đã giải mã.
struct ClaudeHookEvent: Equatable {
    var session: String
    var cwd: String
    var name: String               // hook_event_name
    var tool: String?
    var detail: String?
    var message: String?
    var bundleID: String?
    var at: Date
}

enum ClaudeTransition: Equatable {
    case waiting(ClaudeSession)
    case done(ClaudeSession, duration: TimeInterval)
}

// MARK: - Reducer (thuần, có test)

enum ClaudeReducer {
    /// Phiên không có sự kiện nào quá lâu → bỏ khỏi danh sách.
    static let dropAfter: TimeInterval = 3 * 3600
    /// Đang "working" mà im quá lâu (phiên bị kill giữa chừng) → coi như idle.
    static let staleWorking: TimeInterval = 20 * 60

    static func apply(_ e: ClaudeHookEvent, to sessions: inout [String: ClaudeSession]) -> ClaudeTransition? {
        if e.name == "SessionEnd" { sessions[e.session] = nil; return nil }

        var s = sessions[e.session] ?? ClaudeSession(id: e.session, cwd: e.cwd, state: .idle, updatedAt: e.at)
        if !e.cwd.isEmpty { s.cwd = e.cwd }
        if let b = e.bundleID, !b.isEmpty { s.bundleID = b }
        s.updatedAt = e.at
        var transition: ClaudeTransition?

        switch e.name {
        case "SessionStart":
            if s.state != .working { s.state = .idle }
        case "UserPromptSubmit":
            s.state = .working
            s.turnStartedAt = e.at
            s.tool = nil; s.message = nil
            s.detail = e.detail
        case "PreToolUse", "PostToolUse":
            s.state = .working
            if s.turnStartedAt == nil { s.turnStartedAt = e.at }
            s.message = nil
            if let t = e.tool { s.tool = t; s.detail = e.detail }
        case "Notification":
            let m = (e.message ?? "").lowercased()
            if m.contains("permission") || m.contains("approve") || m.contains("needs your") {
                s.state = .waiting
                s.message = e.message
                transition = .waiting(s)
            }
            // "Claude is waiting for your input" (nhắc sau 60s rảnh) → không phải việc mới.
        case "Stop":
            let was = s.state
            s.state = .done
            s.tool = nil; s.message = nil
            if was == .working || was == .waiting {
                transition = .done(s, duration: e.at.timeIntervalSince(s.turnStartedAt ?? e.at))
            }
            s.turnStartedAt = nil
        default:
            break
        }
        sessions[e.session] = s
        return transition
    }

    /// Dọn phiên cũ / working bị treo.
    static func prune(_ sessions: inout [String: ClaudeSession], now: Date) {
        for (id, s) in sessions {
            let idle = now.timeIntervalSince(s.updatedAt)
            if idle > dropAfter { sessions[id] = nil }
            else if s.state == .working && idle > staleWorking { sessions[id]?.state = .idle }
        }
    }

    // MARK: Parse file sự kiện

    /// Một file sự kiện = JSON stdin của hook Claude Code. Có thể có thêm một dòng
    /// đầu (không phải JSON) dạng "<bundle id app chứa phiên>\t<TERM_PROGRAM>".
    static func parseEventFile(_ data: Data, at: Date) -> ClaudeHookEvent? {
        var body = data
        var bundle: String?
        if data.first != UInt8(ascii: "{"), let nl = data.firstIndex(of: UInt8(ascii: "\n")) {
            let header = String(decoding: data[..<nl], as: UTF8.self)
            bundle = header.split(separator: "\t", omittingEmptySubsequences: false).first.map(String.init)
            body = Data(data[data.index(after: nl)...])
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let session = json["session_id"] as? String,
              let name = json["hook_event_name"] as? String else { return nil }
        let tool = json["tool_name"] as? String
        var detail: String?
        if let input = json["tool_input"] as? [String: Any] { detail = summarize(tool: tool ?? "", input: input) }
        if name == "UserPromptSubmit", let p = json["prompt"] as? String { detail = oneLine(p, max: 60) }
        return ClaudeHookEvent(session: session, cwd: json["cwd"] as? String ?? "", name: name,
                               tool: tool, detail: detail, message: json["message"] as? String,
                               bundleID: (bundle?.isEmpty ?? true) ? nil : bundle, at: at)
    }

    static func summarize(tool: String, input: [String: Any]) -> String? {
        func str(_ k: String) -> String? { (input[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        switch tool {
        case "Bash":
            return str("description") ?? str("command").map { oneLine($0, max: 50) }
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit":
            return (str("file_path") ?? str("notebook_path")).map { ($0 as NSString).lastPathComponent }
        case "Grep", "Glob":
            return str("pattern").map { oneLine($0, max: 40) }
        case "WebFetch":
            return str("url").flatMap { URL(string: $0)?.host }
        case "WebSearch":
            return str("query").map { oneLine($0, max: 40) }
        default:
            return (str("description") ?? str("prompt")).map { oneLine($0, max: 50) }
        }
    }

    static func oneLine(_ s: String, max: Int) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > max ? String(flat.prefix(max - 1)) + "…" : flat
    }
}

// MARK: - Store (theo dõi thư mục sự kiện)

/// Đọc các file sự kiện hook trong `eventsDir` (mỗi sự kiện một file `.json`, ghi
/// bởi một hook command do người dùng tự đăng ký), cập nhật trạng thái phiên rồi xoá file.
@MainActor
final class ClaudeActivityStore: ObservableObject {
    static let shared = ClaudeActivityStore()

    @Published private(set) var sessions: [ClaudeSession] = []
    /// Đã từng nhận sự kiện nào chưa (để Settings/launcher gợi ý cách thiết lập).
    @Published private(set) var receivedAny = UserDefaults.standard.bool(forKey: "claude.receivedAny")
    /// Phát khi một phiên chuyển sang chờ duyệt / làm xong một lượt.
    let transitions = PassthroughSubject<ClaudeTransition, Never>()

    private var map: [String: ClaudeSession] = [:]
    private var timer: Timer?
    private var pruneCounter = 0

    static var eventsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch/claude-events", isDirectory: true)
    }

    var activeSessions: [ClaudeSession] { sessions.filter(\.isActive) }
    var anyWaiting: Bool { sessions.contains { $0.state == .waiting } }

    func start() {
        try? FileManager.default.createDirectory(at: Self.eventsDir, withIntermediateDirectories: true)
        // Bỏ qua thông báo của các sự kiện tồn đọng khi app không chạy (tránh bung "xong" muộn).
        drain(silent: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drain(silent: false) }
        }
    }

    private func drain(silent: Bool) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: Self.eventsDir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return }
        let ready = files.filter { $0.pathExtension == "json" }
        pruneCounter += 1
        if ready.isEmpty {
            if pruneCounter % 60 == 0 { prune() }   // ~30s một lần
            return
        }
        let dated = ready.map { url -> (URL, Date) in
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            return (url, d)
        }.sorted { $0.1 < $1.1 }
        var out: [ClaudeTransition] = []
        for (url, date) in dated {
            defer { try? fm.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let e = ClaudeReducer.parseEventFile(data, at: date) else { continue }
            if let t = ClaudeReducer.apply(e, to: &map) { out.append(t) }
        }
        if !receivedAny { receivedAny = true; UserDefaults.standard.set(true, forKey: "claude.receivedAny") }
        ClaudeReducer.prune(&map, now: Date())
        publish()
        if !silent { out.forEach(transitions.send) }
    }

    private func prune() {
        let before = map
        ClaudeReducer.prune(&map, now: Date())
        if before != map { publish() }
    }

    private func publish() {
        // Đang chờ duyệt lên đầu, rồi đang chạy, rồi mới nhất.
        let rank: [ClaudeSession.State: Int] = [.waiting: 0, .working: 1, .done: 2, .idle: 3]
        sessions = map.values.sorted {
            (rank[$0.state]!, $1.updatedAt) < (rank[$1.state]!, $0.updatedAt)
        }
    }

    /// Đưa app chứa phiên ra trước (Terminal / Claude desktop / VS Code…).
    static func focus(_ s: ClaudeSession) {
        guard let b = s.bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: b).first else { return }
        app.unhide()
        app.activate(options: [.activateAllWindows])
    }
}

// MARK: - Lọc thông báo Claude khỏi tab/HUD Notifications

/// Khi notch đã tự theo dõi Claude (Clawd + báo xong/chờ duyệt), thông báo hệ thống
/// của Claude chỉ gây báo trùng → bỏ khỏi HUD và lịch sử Notifications.
enum ClaudeNotificationFilter {
    static let claudeBundles: Set<String> = ["com.anthropic.claudefordesktop", "com.claudeai.bridge"]

    static func isClaude(_ r: NotificationRecord) -> Bool {
        if claudeBundles.contains(r.bundleId) || r.bundleId.hasPrefix("com.anthropic.") { return true }
        // terminal-notifier / terminal gửi hộ hook Notification của Claude Code.
        return r.title.localizedCaseInsensitiveContains("Claude Code")
    }
}
