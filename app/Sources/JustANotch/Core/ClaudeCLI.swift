// app/Sources/JustANotch/Core/ClaudeCLI.swift
import Foundation

/// Gọi Claude Code CLI (`claude -p`, auth bằng subscription) — cùng cách EngZone.
/// Chạy trong thư mục tạm để CLI không tự đọc CLAUDE.md của repo nào.
enum ClaudeCLI {
    enum CLIError: LocalizedError {
        case notInstalled, failed(String), badJSON(String)
        var errorDescription: String? {
            switch self {
            case .notInstalled: "Không tìm thấy Claude CLI. Cài bằng `brew install claude` rồi chạy `claude login`."
            case let .failed(m): "Claude CLI lỗi: \(m)"
            case let .badJSON(m): "AI trả về dữ liệu không đọc được: \(m.prefix(120))"
            }
        }
    }

    private static let searchDirs: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local",
                "\(home)/.npm-global/bin", "/usr/bin"]
    }()

    static var binary: String? = {
        for d in searchDirs where FileManager.default.isExecutableFile(atPath: "\(d)/claude") {
            return "\(d)/claude"
        }
        return nil
    }()

    static var isAvailable: Bool { binary != nil }

    /// Gửi 1 lượt, trả về text. `system` thay prompt mặc định của Claude Code.
    static func run(system: String, prompt: String, timeout: TimeInterval = 180) async throws -> String {
        guard let bin = binary else { throw CLIError.notInstalled }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: bin)
                p.arguments = ["-p", "--output-format", "text", "--model", "sonnet",
                               "--no-session-persistence", "--system-prompt", system]
                p.currentDirectoryURL = FileManager.default.temporaryDirectory
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = (searchDirs + [env["PATH"] ?? ""]).joined(separator: ":")
                p.environment = env
                let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
                p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
                do { try p.run() } catch { cont.resume(throwing: CLIError.failed(error.localizedDescription)); return }
                // Dấu cách đầu: tránh CLI hiểu nhầm "/..." là slash command của nó.
                inPipe.fileHandleForWriting.write((" " + prompt).data(using: .utf8)!)
                try? inPipe.fileHandleForWriting.close()
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                let err = errPipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                let text = String(decoding: out, as: UTF8.self)
                if p.terminationStatus != 0 {
                    let msg = String(decoding: err, as: UTF8.self)
                    cont.resume(throwing: CLIError.failed(msg.isEmpty ? text : msg))
                } else {
                    cont.resume(returning: text)
                }
            }
        }
    }

    /// Chạy rồi decode JSON (bóc từ `{`/`[` đầu tiên tới `}`/`]` cuối cùng).
    /// JSON hỏng (thỉnh thoảng model quên escape dấu ") → thử lại 1 lần với lời nhắc chặt hơn.
    static func json<T: Decodable>(_ type: T.Type, system: String, prompt: String) async throws -> T {
        var raw = try await run(system: system, prompt: prompt)
        if let v = decode(T.self, raw) { return v }
        raw = try await run(system: system, prompt: prompt + "\n\nLƯU Ý: chỉ in JSON hợp lệ, escape mọi dấu \" bên trong chuỗi.")
        if let v = decode(T.self, raw) { return v }
        throw CLIError.badJSON(raw)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ raw: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(extractJSON(raw).utf8))
    }

    static func extractJSON(_ s: String) -> String {
        var t = s
        if let r = t.range(of: "```json") ?? t.range(of: "```") {
            t = String(t[r.upperBound...])
            if let e = t.range(of: "```") { t = String(t[..<e.lowerBound]) }
        }
        guard let start = t.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return t }
        let close: Character = t[start] == "{" ? "}" : "]"
        guard let end = t.lastIndex(of: close), end > start else { return t }
        return String(t[start...end])
    }
}
