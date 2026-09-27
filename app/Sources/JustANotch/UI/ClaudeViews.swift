import SwiftUI

// MARK: - Clawd (mascot Claude Code) dạng pixel

/// Clawd theo đúng hình trong màn chào của Claude Code (thân cam, hai mắt, tay ngang,
/// bốn chân), lưới 18×15 — mỗi hàng logo = 2 hàng lưới như ký tự ¼ khối.
enum Clawd {
    /// work = ngồi gõ phím, thỉnh thoảng liếc lên suy nghĩ; walk = bò ngang;
    /// alert = vẫy tay (chờ duyệt); happy = nhảy mừng (xong).
    enum Mode { case work, walk, alert, happy, still }

    static let clay = Color(red: 0.851, green: 0.467, blue: 0.341)

    /// Khung + bảng màu sinh bởi `app/scripts/gen_sprites.py` (xem `SpriteData.swift`).
    static func timeline(_ m: Mode) -> [[String]] {
        switch m {
        case .work:  return work.map { workFrames[$0] }
        case .walk:  return walk.map { walkFrames[$0] }
        case .alert: return alert.map { alertFrames[$0] }
        case .happy: return happy.map { happyFrames[$0] }
        case .still: return [happyFrames[happy[happy.count - 1]]]   // đứng yên, mắt mở
        }
    }

    /// Thời lượng một vòng hoạt ảnh.
    static func loopDuration(_ m: Mode) -> TimeInterval { Double(timeline(m).count) / fps }
}

struct ClawdSprite: View {
    let mode: Clawd.Mode
    var pixel: CGFloat = 1
    let reduceMotion: Bool
    @State private var start = Date()

    var body: some View {
        let frames = Clawd.timeline(mode)
        Group {
            if reduceMotion || frames.count == 1 {
                PixelCanvas(frame: frames[0], pixel: pixel, palette: Clawd.palette)
            } else {
                TimelineView(.periodic(from: start, by: 1.0 / Clawd.fps)) { ctx in
                    let i = Int(ctx.date.timeIntervalSince(start) * Clawd.fps)
                    PixelCanvas(frame: frames[i % frames.count], pixel: pixel, palette: Clawd.palette)
                }
            }
        }
        .frame(width: CGFloat(Clawd.width) * pixel, height: CGFloat(Clawd.height) * pixel)
    }
}

// MARK: - Logo Claude nhấp nháy đổi hình (như spinner của Claude Code)

/// Ngôi sao cam đổi hình liên tục · ✢ ✳ ✶ ✻ ✽ (tới rồi lui) kèm nhấp nháy nhẹ —
/// đúng kiểu spinner "đang suy nghĩ" của Claude Code.
struct ClaudeSpark: View {
    var size: CGFloat
    var color: Color = Clawd.clay
    let reduceMotion: Bool
    @State private var start = Date()

    static let glyphs = ["·", "✢", "✳", "✶", "✻", "✽"]
    /// Tới rồi lui, không lặp khung ở hai đầu: · ✢ ✳ ✶ ✻ ✽ ✻ ✶ ✳ ✢
    static let cycle: [String] = glyphs + glyphs.dropFirst().dropLast().reversed()
    /// 8 khung/giây, mỗi hình giữ 2 khung: khung đầu là hình trọn vẹn, khung sau là
    /// khung chuyển (hình cũ mờ + co + xoay nhẹ, hình mới hiện dần) — đổi hình mượt, không gấp.
    static let fps = 8.0
    static let framesPerGlyph = 2

    var body: some View {
        Group {
            if reduceMotion {
                ClaudeSparkGlyph(frame: .init(from: "✻", to: "✻", mix: 0), size: size, twinkle: 1, color: color)
            } else {
                TimelineView(.periodic(from: start, by: 1.0 / Self.fps)) { ctx in
                    let t = ctx.date.timeIntervalSince(start)
                    ClaudeSparkGlyph(frame: Self.frame(at: t), size: size, twinkle: Self.twinkle(at: t), color: color)
                }
            }
        }
        .frame(width: size, height: size)
    }

    struct Frame { let from: String; let to: String; let mix: Double }

    /// Khung thứ n: hình `cycle[n / 2]`; khung lẻ trộn 50% sang hình kế tiếp.
    static func frame(at t: TimeInterval) -> Frame {
        let n = Int(t * fps)
        let g = (n / framesPerGlyph) % cycle.count
        let sub = n % framesPerGlyph
        let mix = Double(sub) / Double(framesPerGlyph)
        return Frame(from: cycle[g], to: cycle[(g + 1) % cycle.count], mix: mix)
    }
    /// Thời lượng một vòng đổi hình.
    static var loopDuration: TimeInterval { Double(cycle.count * framesPerGlyph) / fps }
    static func twinkle(at t: TimeInterval) -> Double { 0.78 + 0.22 * (0.5 + 0.5 * sin(t * 2.6)) }
}

/// Một khung của logo (tách riêng để dựng video soát hoạt ảnh): hình cũ `from` và hình
/// mới `to` chồng lên nhau theo `mix` (0 = chỉ hình cũ).
struct ClaudeSparkGlyph: View {
    let frame: ClaudeSpark.Frame
    let size: CGFloat
    let twinkle: Double
    var color: Color = Clawd.clay

    var body: some View {
        let m = frame.mix
        ZStack {
            glyph(frame.from)
                .opacity(1 - m)
                .scaleEffect(1 - 0.18 * m)
                .rotationEffect(.degrees(22 * m))
            if m > 0 {
                glyph(frame.to)
                    .opacity(m)
                    .scaleEffect(0.82 + 0.18 * m)
                    .rotationEffect(.degrees(-22 * (1 - m)))
            }
        }
        .opacity(twinkle)
        .shadow(color: color.opacity(0.55 * twinkle), radius: size * 0.18)
        .frame(width: size, height: size)
    }

    private func glyph(_ g: String) -> some View {
        Text(g)
            .font(.system(size: size * (g == "·" ? 1.25 : 0.92), weight: .bold))
            .foregroundStyle(color)
    }
}

// MARK: - Dấu hiệu "đang làm" — mỗi phiên một kiểu: gõ phím / đi bộ / logo

struct ClaudeWorkingMark: View {
    enum Variant: CaseIterable { case typing, walk, logo }

    /// Kiểu cố định cho một phiên, "ngẫu nhiên" theo session_id (FNV-1a — ổn định
    /// qua các lần mở app, khác `hashValue` vốn đổi mỗi tiến trình).
    static func variant(for sessionID: String) -> Variant {
        var h: UInt64 = 0xcbf29ce484222325
        for b in sessionID.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Variant.allCases[Int(h % UInt64(Variant.allCases.count))]
    }

    let variant: Variant
    var pixel: CGFloat = 1.4
    let reduceMotion: Bool

    private var size: CGSize { CGSize(width: CGFloat(Clawd.width) * pixel, height: CGFloat(Clawd.height) * pixel) }

    var body: some View {
        ZStack {
            switch variant {
            case .typing: ClawdSprite(mode: .work, pixel: pixel, reduceMotion: reduceMotion)
            case .walk:   ClawdSprite(mode: .walk, pixel: pixel, reduceMotion: reduceMotion)
            case .logo:   ClaudeSpark(size: size.height * 0.95, reduceMotion: reduceMotion)
            }
        }
        .id(variant)
        .transition(.opacity)
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Chỉ báo ở wing khi có phiên đang chạy

struct ClaudeWingIndicator: View {
    let waiting: Bool
    /// Phiên đang hiển thị (quyết định kiểu gõ phím / đi bộ / logo).
    let sessionID: String
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        Group {
            if waiting {
                ClawdSprite(mode: .alert, pixel: 1.4, reduceMotion: reduceMotion)
            } else {
                ClaudeWorkingMark(variant: ClaudeWorkingMark.variant(for: sessionID),
                                  pixel: 1.4, reduceMotion: reduceMotion)
            }
        }
            .overlay(alignment: .topTrailing) {
                if waiting {
                    Circle().fill(Color(red: 1.0, green: 0.78, blue: 0.3))
                        .frame(width: 5, height: 5)
                        .scaleEffect(pulse ? 1.25 : 0.8)
                        .opacity(pulse ? 1 : 0.6)
                        .offset(x: 2, y: 0)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
                        }
                }
            }
            .help(waiting ? "Claude đang chờ bạn duyệt" : "Claude đang làm việc")
    }
}

// MARK: - Thông báo ngắn ở hai wing (xong / chờ duyệt)

struct ClaudeAlertView: View {
    @ObservedObject var vm: NotchViewModel
    let alert: ClaudeTransition
    let reduceMotion: Bool

    private var session: ClaudeSession {
        switch alert { case .waiting(let s): return s; case .done(let s, _): return s }
    }
    private var isWaiting: Bool { if case .waiting = alert { return true }; return false }

    var body: some View {
        HStack(spacing: 0) {
            // Clawd + chữ đều ở wing trái (Clawd thường trực cũng ở bên trái).
            HStack(spacing: 10) {
                ClawdSprite(mode: isWaiting ? .alert : .happy, pixel: 1.9, reduceMotion: reduceMotion)
                VStack(alignment: .leading, spacing: 1) {
                Text(isWaiting ? "Claude cần bạn duyệt" : "Claude xong rồi")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(isWaiting ? Color(red: 1.0, green: 0.8, blue: 0.4) : .white)
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
            }
            .padding(.leading, 12).padding(.trailing, 10)
            .frame(width: vm.leftReveal, alignment: .leading)
            .clipped()

            Color.clear.frame(width: vm.coreWidth)
            Color.clear.frame(width: vm.rightReveal)
        }
        .frame(width: vm.compactWidth, height: vm.compactHeight)
    }

    private var subtitle: String {
        switch alert {
        case .waiting(let s):
            let tool = s.message.flatMap(Self.toolName) ?? s.tool
            return tool.map { "\(s.project) · \($0)" } ?? s.project
        case .done(let s, let d):
            return "\(s.project) · \(ClaudeFormat.duration(d))"
        }
    }

    /// "Claude needs your permission to use Bash" → "Bash".
    private static func toolName(_ m: String) -> String? {
        guard let r = m.range(of: "to use ") else { return nil }
        let t = m[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return t.isEmpty ? nil : t
    }
}

enum ClaudeFormat {
    static func duration(_ d: TimeInterval) -> String {
        let s = max(0, Int(d))
        if s < 60 { return "\(s)″" }
        if s < 3600 { return "\(s / 60)′\(String(format: "%02d", s % 60))″" }
        return "\(s / 3600)h\(String(format: "%02d", (s % 3600) / 60))′"
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "vừa xong" }
        if s < 3600 { return "\(s / 60) phút trước" }
        return "\(s / 3600) giờ trước"
    }
}

// MARK: - Danh sách phiên (tính năng trong launcher)

struct ClaudeSessionsView: View {
    @ObservedObject var vm: NotchViewModel
    let onBack: () -> Void
    let reduceMotion: Bool
    @ObservedObject private var store = ClaudeActivityStore.shared
    private var sessions: [ClaudeSession] { vm.claudeSessions }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LauncherBackButton(action: onBack)
                Text("CLAUDE CODE")
                    .font(.system(size: 9, weight: .bold)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer(minLength: 0)
                let active = sessions.filter(\.isActive).count
                if active > 0 {
                    Text("\(active) đang chạy")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Clawd.clay)
                }
            }
            if sessions.isEmpty {
                empty
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(sessions) { s in
                            ClaudeSessionRow(session: s, reduceMotion: reduceMotion)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand(perform: onBack)
    }

    private var empty: some View {
        HStack(spacing: 10) {
            ClawdSprite(mode: .still, pixel: 1.6, reduceMotion: true).opacity(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text("Chưa có phiên nào đang chạy")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                Text(store.receivedAny ? "Mở Claude Code và giao việc — tiến trình hiện ở đây."
                                       : "Chưa nhận được sự kiện hook — xem Settings → Claude Code.")
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
    }
}

private struct ClaudeSessionRow: View {
    let session: ClaudeSession
    let reduceMotion: Bool
    @State private var hovering = false

    var body: some View {
        Button { ClaudeActivityStore.focus(session) } label: {
            HStack(spacing: 9) {
                Group {
                    if session.state == .working {
                        ClaudeWorkingMark(variant: ClaudeWorkingMark.variant(for: session.id),
                                          pixel: 1.1, reduceMotion: reduceMotion)
                    } else {
                        ClawdSprite(mode: mode, pixel: 1.1, reduceMotion: reduceMotion || !session.isActive)
                    }
                }
                    .opacity(session.isActive ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project)
                        .font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white.opacity(0.92))
                    Text(status)
                        .font(.system(size: 9.5)).foregroundStyle(statusColor)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if session.state == .working, let start = session.turnStartedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(ClaudeFormat.duration(ctx.date.timeIntervalSince(start)))
                            .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(hovering ? 0.1 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(session.cwd)
    }

    private var mode: Clawd.Mode {
        switch session.state {
        case .working: return .work
        case .waiting: return .alert
        default: return .still
        }
    }

    private var status: String {
        switch session.state {
        case .working:
            let t = [session.tool, session.detail].compactMap { $0 }.joined(separator: " · ")
            return t.isEmpty ? "Đang suy nghĩ…" : t
        case .waiting: return session.message ?? "Đang chờ bạn duyệt"
        case .done: return "Xong · \(ClaudeFormat.ago(session.updatedAt))"
        case .idle: return "Rảnh · \(ClaudeFormat.ago(session.updatedAt))"
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .waiting: return Color(red: 1.0, green: 0.8, blue: 0.4)
        case .working: return Clawd.clay.opacity(0.95)
        default: return .white.opacity(0.4)
        }
    }
}
