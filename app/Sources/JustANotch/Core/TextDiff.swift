// app/Sources/JustANotch/Core/TextDiff.swift
import Foundation

/// So khớp từng từ (LCS) giữa câu mẫu và câu người học — dùng cho nghe-chép & đọc to.
enum TextDiff {
    struct Token: Equatable { let text: String; let ok: Bool }

    static func words(_ s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
    }

    /// Đánh dấu từng từ của câu MẪU: ok = người học có từ đó (đúng thứ tự).
    static func mark(reference: String, attempt: String) -> [Token] {
        let refDisplay = reference.split(separator: " ").map(String.init)
        let ref = refDisplay.map { words($0).joined() }
        let att = words(attempt)
        let n = ref.count, m = att.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = ref[i] == att[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var out: [Token] = []
        var i = 0, j = 0
        while i < n {
            if j < m, ref[i] == att[j] { out.append(Token(text: refDisplay[i], ok: true)); i += 1; j += 1 }
            else if j < m, dp[i][j + 1] >= dp[i + 1][j] { j += 1 }
            else { out.append(Token(text: refDisplay[i], ok: ref[i].isEmpty)); i += 1 }
        }
        return out
    }

    /// Tỉ lệ từ đúng (0…1).
    static func score(reference: String, attempt: String) -> Double {
        let t = mark(reference: reference, attempt: attempt)
        return t.isEmpty ? 0 : Double(t.filter(\.ok).count) / Double(t.count)
    }
}
