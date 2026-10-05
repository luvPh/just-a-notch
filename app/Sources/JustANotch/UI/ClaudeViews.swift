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

// MARK: - Logo Claude biến hình (như spinner của Claude Code, nhưng morph mượt)

/// Hình dạng logo: 12 "cánh" đặt đều 30°, mỗi cánh là một capsule thuôn (gốc dày `b`,
/// đầu dày `t`, dài `l`, đơn vị = bán kính khung) + đĩa giữa bán kính `c`. Mọi hình
/// (chấm, 4 cánh hoa, sao 6 cánh, 12 tia, 6 cánh hoa…) đều là một bộ số như vậy, nên
/// khung chuyển là NỘI SUY hình học — cánh mọc dài/phình/thu dần, không chồng mờ.
struct SparkShape {
    static let rays = 12
    var l: [Double]
    var b: [Double]
    var t: [Double]
    var c: Double

    static func uniform(on slots: (Int) -> Bool, l: Double, b: Double, t: Double, c: Double,
                        jitter: [Double] = []) -> SparkShape {
        var L = [Double](repeating: 0, count: rays), B = L, T = L
        for k in 0..<rays where slots(k) {
            L[k] = l * (jitter.isEmpty ? 1 : jitter[k % jitter.count]); B[k] = b; T[k] = t
        }
        return SparkShape(l: L, b: B, t: T, c: c)
    }

    static let dot     = uniform(on: { _ in false }, l: 0, b: 0, t: 0, c: 0.30)
    static let petals4 = uniform(on: { $0 % 3 == 0 }, l: 0.95, b: 0.07, t: 0.22, c: 0.12)
    static let star6   = uniform(on: { $0 % 2 == 0 }, l: 0.96, b: 0.26, t: 0.03, c: 0.20)
    /// 12 tia dài ngắn so le — gần với logo Claude nhất.
    static let spokes  = uniform(on: { _ in true }, l: 0.96, b: 0.075, t: 0.065, c: 0.10,
                                 jitter: [1, 0.78, 0.92, 0.74, 1, 0.84, 0.9, 0.76, 0.98, 0.8, 0.88, 0.72])
    static let petals6 = uniform(on: { $0 % 2 == 1 }, l: 0.9, b: 0.06, t: 0.24, c: 0.14)

    static func lerp(_ a: SparkShape, _ z: SparkShape, _ f: Double) -> SparkShape {
        func mix(_ x: [Double], _ y: [Double]) -> [Double] { zip(x, y).map { $0 + ($1 - $0) * f } }
        return SparkShape(l: mix(a.l, z.l), b: mix(a.b, z.b), t: mix(a.t, z.t), c: a.c + (z.c - a.c) * f)
    }
}

struct ClaudeSpark: View {
    var size: CGFloat
    var color: Color = Clawd.clay
    let reduceMotion: Bool
    @State private var start = Date()

    /// Chuỗi hình (khép vòng). Mỗi bước chỉ MỌC THÊM hoặc THU BỚT cánh đối xứng (qua
    /// 12 tia — hình logo Claude), không đổi thẳng giữa hai bộ cánh lệch nhau.
    static let keyframes: [SparkShape] = [.dot, .petals4, .spokes, .star6, .spokes, .petals6, .spokes, .petals4]
    /// 8 khung/giây; mỗi lần đổi hình morph qua `framesPerMorph` khung (có ease in/out).
    static let fps = 8.0
    static let framesPerMorph = 4
    static var loopDuration: TimeInterval { Double(keyframes.count * framesPerMorph) / fps }

    /// Hình + góc xoay tại thời điểm t (lượng tử theo 8 khung/giây).
    static func pose(at t: TimeInterval) -> (shape: SparkShape, angle: Double) {
        let n = Int(t * fps)
        let seg = (n / framesPerMorph) % keyframes.count
        let f = Double(n % framesPerMorph) / Double(framesPerMorph)
        let e = f * f * (3 - 2 * f)
        let shape = SparkShape.lerp(keyframes[seg], keyframes[(seg + 1) % keyframes.count], e)
        return (shape, Double(n) * 3.75)   // xoay đều 30°/giây
    }
    static func twinkle(at t: TimeInterval) -> Double { 0.82 + 0.18 * (0.5 + 0.5 * sin(t * 2.6)) }

    var body: some View {
        Group {
            if reduceMotion {
                ClaudeSparkCanvas(shape: .spokes, angle: 0, size: size, twinkle: 1, color: color)
            } else {
                TimelineView(.periodic(from: start, by: 1.0 / Self.fps)) { ctx in
                    let t = ctx.date.timeIntervalSince(start)
                    let p = Self.pose(at: t)
                    ClaudeSparkCanvas(shape: p.shape, angle: p.angle, size: size,
                                      twinkle: Self.twinkle(at: t), color: color)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Vẽ một hình `SparkShape` (tách riêng để dựng video soát hoạt ảnh).
struct ClaudeSparkCanvas: View {
    let shape: SparkShape
    let angle: Double
    let size: CGFloat
    let twinkle: Double
    var color: Color = Clawd.clay

    var body: some View {
        Canvas { ctx, sz in
            let r = min(sz.width, sz.height) / 2
            let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
            var path = Path()
            for k in 0..<SparkShape.rays {
                let l = shape.l[k]
                guard l > 0.02 else { continue }
                // Cánh ngắn thì cũng mảnh lại — không để lại "cục" ở tâm khi co về 0.
                let grow = min(1, l / 0.3)
                let b = shape.b[k] * grow * r, t = shape.t[k] * grow * r, L = l * r
                let a = (Double(k) * 30 + angle) * .pi / 180
                path.addPath(Self.ray(length: L, base: b, tip: t),
                             transform: CGAffineTransform(rotationAngle: a)
                                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
            }
            let c = shape.c * r
            path.addEllipse(in: CGRect(x: center.x - c, y: center.y - c, width: 2 * c, height: 2 * c))
            ctx.fill(path, with: .color(color))
        }
        .opacity(twinkle)
        .shadow(color: color.opacity(0.5 * twinkle), radius: size * 0.16)
        .frame(width: size, height: size)
    }

    /// Capsule thuôn hướng +x: gốc bán kính `base` ở tâm, đầu bán kính `tip` cách tâm `length`.
    static func ray(length L: CGFloat, base b: CGFloat, tip t: CGFloat) -> Path {
        var p = Path()
        let tipC = max(L - t, 0)
        p.move(to: CGPoint(x: 0, y: -b))
        p.addLine(to: CGPoint(x: tipC, y: -t))
        p.addArc(center: CGPoint(x: tipC, y: 0), radius: t, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: b))
        p.addArc(center: .zero, radius: b, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Dấu hiệu "đang làm" — mỗi phiên một kiểu: gõ phím / đi bộ / logo

struct ClaudeWorkingMark: View {
    /// Claude: gõ phím / đi bộ / logo ✻ · Codex: terminal >_ / logo OpenAI.
    enum Variant: CaseIterable { case typing, walk, logo, terminal, openai }

    static func pool(_ agent: AgentKind) -> [Variant] {
        agent == .claude ? [.typing, .walk, .logo] : [.terminal, .openai]
    }

    /// Kiểu cố định cho một phiên, "ngẫu nhiên" theo session_id (FNV-1a — ổn định
    /// qua các lần mở app, khác `hashValue` vốn đổi mỗi tiến trình).
    static func variant(for sessionID: String, agent: AgentKind = .claude) -> Variant {
        var h: UInt64 = 0xcbf29ce484222325
        for b in sessionID.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        let p = pool(agent)
        return p[Int(h % UInt64(p.count))]
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
            case .terminal: CodexTermSprite(mode: .work, pixel: pixel, reduceMotion: reduceMotion)
            case .openai: OpenAIKnot(size: size.height * 0.95, reduceMotion: reduceMotion)
            }
        }
        .id(variant)
        .transition(.opacity)
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Hình theo agent cho các trạng thái chờ duyệt / xong / rảnh

enum ClaudeAgentMark {
    @ViewBuilder static func waiting(_ a: AgentKind, pixel: CGFloat, reduceMotion: Bool) -> some View {
        if a == .claude { ClawdSprite(mode: .alert, pixel: pixel, reduceMotion: reduceMotion) }
        else { CodexTermSprite(mode: .alert, pixel: pixel, reduceMotion: reduceMotion) }
    }
    @ViewBuilder static func done(_ a: AgentKind, pixel: CGFloat, reduceMotion: Bool) -> some View {
        if a == .claude { ClawdSprite(mode: .happy, pixel: pixel, reduceMotion: reduceMotion) }
        else { CodexTermSprite(mode: .happy, pixel: pixel, reduceMotion: reduceMotion) }
    }
    @ViewBuilder static func still(_ a: AgentKind, pixel: CGFloat) -> some View {
        if a == .claude { ClawdSprite(mode: .still, pixel: pixel, reduceMotion: true) }
        else { CodexTermSprite(mode: .happy, pixel: pixel, reduceMotion: true) }
    }
}

// MARK: - Chỉ báo ở wing khi có phiên đang chạy

struct ClaudeWingIndicator: View {
    let waiting: Bool
    /// Phiên đang hiển thị (quyết định kiểu gõ phím / đi bộ / logo…).
    let sessionID: String
    var agent: AgentKind = .claude
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        Group {
            if waiting {
                ClaudeAgentMark.waiting(agent, pixel: 1.4, reduceMotion: reduceMotion)
            } else {
                ClaudeWorkingMark(variant: ClaudeWorkingMark.variant(for: sessionID, agent: agent),
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
            .help(waiting ? "\(agent.displayName) đang chờ bạn duyệt" : "\(agent.displayName) đang làm việc")
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
        if vm.pillMode {
            // Pill không có camera → Clawd + chữ canh giữa cả bề ngang.
            content
                .padding(.horizontal, 12)
                .frame(width: vm.compactWidth, height: vm.compactHeight)
        } else {
            notchBody
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            if isWaiting { ClaudeAgentMark.waiting(session.agent, pixel: 1.9, reduceMotion: reduceMotion) }
            else { ClaudeAgentMark.done(session.agent, pixel: 1.9, reduceMotion: reduceMotion) }
            VStack(alignment: .leading, spacing: 1) {
                Text(isWaiting ? "\(session.agent.displayName) cần bạn duyệt" : "\(session.agent.displayName) xong rồi")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(isWaiting ? Color(red: 1.0, green: 0.8, blue: 0.4) : .white)
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
        }
    }

    private var notchBody: some View {
        HStack(spacing: 0) {
            // Clawd + chữ đều ở wing trái (Clawd thường trực cũng ở bên trái).
            HStack(spacing: 10) {
                if isWaiting { ClaudeAgentMark.waiting(session.agent, pixel: 1.9, reduceMotion: reduceMotion) }
                else { ClaudeAgentMark.done(session.agent, pixel: 1.9, reduceMotion: reduceMotion) }
                VStack(alignment: .leading, spacing: 1) {
                Text(isWaiting ? "\(session.agent.displayName) cần bạn duyệt" : "\(session.agent.displayName) xong rồi")
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
                Text("CLAUDE & CODEX")
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
                Text("Chưa có phiên Claude / Codex nào")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                Text(store.receivedAny ? "Mở Claude Code hoặc Codex và giao việc — tiến trình hiện ở đây."
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
                        ClaudeWorkingMark(variant: ClaudeWorkingMark.variant(for: session.id, agent: session.agent),
                                          pixel: 1.1, reduceMotion: reduceMotion)
                    } else if session.state == .waiting {
                        ClaudeAgentMark.waiting(session.agent, pixel: 1.1, reduceMotion: reduceMotion)
                    } else {
                        ClaudeAgentMark.still(session.agent, pixel: 1.1)
                    }
                }
                    .opacity(session.isActive ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(session.project)
                            .font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white.opacity(0.92))
                        Text(session.agent.displayName.uppercased())
                            .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.1)))
                            .foregroundStyle(.white.opacity(0.55))
                    }
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
