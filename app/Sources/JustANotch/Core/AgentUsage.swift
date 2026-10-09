import Foundation
import Combine

// MARK: - Model

/// Một cửa sổ hạn mức (5 giờ / tuần) của Codex, đọc từ `rate_limits` trong log phiên.
struct UsageWindow: Equatable {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date?
}

struct CodexUsage: Equatable {
    var primary: UsageWindow?      // thường là 5 giờ
    var secondary: UsageWindow?    // thường là 1 tuần
    var updatedAt: Date
}

/// Claude Code không ghi % hạn mức ra đĩa → chỉ cộng token từ log phiên.
struct ClaudeUsage: Equatable {
    var todayTokens: Int           // input + output + cache_creation (bỏ cache_read cho khỏi phình)
    var todayOutput: Int
    var blockTokens: Int           // 5 giờ gần nhất
    var messages: Int
}

// MARK: - Parsers (thuần, có test)

enum AgentUsageParser {
    /// Lấy `rate_limits` cuối cùng trong một file rollout của Codex.
    static func codex(fromJSONL text: String) -> (UsageWindow?, UsageWindow?)? {
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let rl = findRateLimits(obj) else { continue }
            return (window(rl["primary"]), window(rl["secondary"]))
        }
        return nil
    }

    private static func findRateLimits(_ any: Any) -> [String: Any]? {
        if let d = any as? [String: Any] {
            if let rl = d["rate_limits"] as? [String: Any] { return rl }
            for v in d.values { if let r = findRateLimits(v) { return r } }
        }
        return nil
    }

    private static func window(_ any: Any?) -> UsageWindow? {
        guard let d = any as? [String: Any], let p = (d["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let reset = (d["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        return UsageWindow(usedPercent: p, windowMinutes: (d["window_minutes"] as? NSNumber)?.intValue ?? 0, resetsAt: reset)
    }

    /// Một dòng assistant của Claude Code → (khoá chống trùng, thời điểm, token tính, output).
    static func claudeLine(_ line: Substring) -> (key: String, at: Date, tokens: Int, output: Int)? {
        guard line.contains("\"usage\""),
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let msg = obj["message"] as? [String: Any],
              let u = msg["usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String, let at = iso.date(from: ts) ?? isoPlain.date(from: ts)
        else { return nil }
        func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        let out = n("output_tokens")
        let key = "\(msg["id"] as? String ?? "")|\(obj["requestId"] as? String ?? ts)"
        return (key, at, n("input_tokens") + out + n("cache_creation_input_tokens"), out)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
}

// MARK: - Store

/// Đọc usage của Codex / Claude Code từ log trên máy, mỗi 60 giây (không gọi mạng).
final class AgentUsageStore: ObservableObject {
    static let shared = AgentUsageStore()

    @Published private(set) var codex: CodexUsage?
    @Published private(set) var claude: ClaudeUsage?

    private let queue = DispatchQueue(label: "agent-usage", qos: .utility)
    private var timer: Timer?
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let c = self.readCodex(), k = self.readClaude()
            DispatchQueue.main.async {
                if c != self.codex { self.codex = c }
                if k != self.claude { self.claude = k }
            }
        }
    }

    private func recentFiles(in root: URL, ext: String, since: Date) -> [(URL, Date)] {
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        var out: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == ext {
            if let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d >= since {
                out.append((url, d))
            }
        }
        return out.sorted { $0.1 > $1.1 }
    }

    private func readCodex() -> CodexUsage? {
        let root = home.appendingPathComponent(".codex/sessions")
        // File mới nhất có rate_limits (phiên vừa mở có thể chưa có).
        for (url, date) in recentFiles(in: root, ext: "jsonl", since: Date().addingTimeInterval(-8 * 86400)).prefix(5) {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let (p, s) = AgentUsageParser.codex(fromJSONL: text) else { continue }
            return CodexUsage(primary: p, secondary: s, updatedAt: date)
        }
        return nil
    }

    private func readClaude() -> ClaudeUsage? {
        let now = Date()
        let dayStart = Calendar.current.startOfDay(for: now)
        let blockStart = now.addingTimeInterval(-5 * 3600)
        let since = min(dayStart, blockStart)
        let files = recentFiles(in: home.appendingPathComponent(".claude/projects"), ext: "jsonl", since: since)
        guard !files.isEmpty else { return nil }
        var seen = Set<String>()
        var u = ClaudeUsage(todayTokens: 0, todayOutput: 0, blockTokens: 0, messages: 0)
        for (url, _) in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let r = AgentUsageParser.claudeLine(line), r.at >= since, seen.insert(r.key).inserted else { continue }
                if r.at >= dayStart { u.todayTokens += r.tokens; u.todayOutput += r.output; u.messages += 1 }
                if r.at >= blockStart { u.blockTokens += r.tokens }
            }
        }
        return u
    }
}

enum UsageFormat {
    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.0fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }

    /// "2g 15p" / "3 ngày" — thời gian tới lúc reset.
    static func until(_ d: Date?, now: Date = Date()) -> String? {
        guard let d else { return nil }
        let s = max(0, d.timeIntervalSince(now))
        if s >= 86400 { return "\(Int(s / 86400)) ngày" }
        let h = Int(s / 3600), m = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "\(h)g \(m)p" : "\(m)p"
    }
}
