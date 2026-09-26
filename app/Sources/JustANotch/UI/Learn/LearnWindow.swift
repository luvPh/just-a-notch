import SwiftUI
import AppKit
import Charts

/// Cửa sổ học riêng (NSWindow thường, tách khỏi notch).
final class LearnWindowController: NSObject, NSWindowDelegate {
    static let shared = LearnWindowController()
    private var window: NSWindow?

    func show(section: LearnSection = .review) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Just a Notch — Học tiếng Anh"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.backgroundColor = NSColor(LearnTheme.bg)
            w.minSize = NSSize(width: 760, height: 520)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("LearnWindow")
            window = w
        }
        window?.contentView = NSHostingView(rootView: LearnWindowRoot(store: .shared, initial: section))
        // App là agent (LSUIElement) → tạm thành app thường để cửa sổ có Dock/focus.
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

enum LearnSection: String, CaseIterable, Identifiable {
    case review, library, essay, grammar, stats
    var id: String { rawValue }
    var title: String {
        switch self {
        case .review: "Ôn tập"; case .library: "Kho từ"; case .essay: "Essay"
        case .grammar: "Grammar"; case .stats: "Thống kê"
        }
    }
    var icon: String {
        switch self {
        case .review: "rectangle.stack.fill"; case .library: "books.vertical.fill"
        case .essay: "doc.text.fill"; case .grammar: "text.book.closed.fill"; case .stats: "chart.bar.fill"
        }
    }
}

/// Bảng màu Learn — dùng chung cho notch và cửa sổ học: tông trắng-mờ trên nền đen,
/// điểm nhấn tím dịu, xanh/đỏ dịu cho đúng/sai (giống các tab khác của notch).
struct LearnPalette {
    let accent: Color, purple: Color, good: Color, bad: Color, highlight: Color
    let text: Color, secondary: Color, badgeFill: Color, optionFill: Color

    static let notch = LearnPalette(
        accent: .white.opacity(0.9), purple: LearnTheme.purple, good: LearnTheme.good, bad: LearnTheme.bad,
        highlight: LearnTheme.highlight, text: .white.opacity(0.92), secondary: .white.opacity(0.5),
        badgeFill: .white.opacity(0.12), optionFill: .white.opacity(0.08))

    static let window = LearnPalette(
        accent: LearnTheme.accent, purple: LearnTheme.purple, good: LearnTheme.good, bad: LearnTheme.bad,
        highlight: LearnTheme.highlight, text: .white.opacity(0.92), secondary: .white.opacity(0.5),
        badgeFill: .white.opacity(0.12), optionFill: .white.opacity(0.08))
}

private struct LearnOnNotchKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var learnOnNotch: Bool {
        get { self[LearnOnNotchKey.self] }
        set { self[LearnOnNotchKey.self] = newValue }
    }
    var learnPalette: LearnPalette { learnOnNotch ? .notch : .window }
}

enum LearnTheme {
    static let purple = Color(red: 0.66, green: 0.46, blue: 1.0)
    static let accent = purple
    static let good = Color(red: 0.30, green: 0.82, blue: 0.52)
    static let bad = Color(red: 0.96, green: 0.36, blue: 0.33)
    static let highlight = Color.white.opacity(0.78)
    static let sidebar = Color.black
    static let bg = Color(red: 0.05, green: 0.05, blue: 0.055)
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
}

extension View {
    /// Nền thẻ chuẩn của cửa sổ học.
    func learnCard(_ radius: CGFloat = 14) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(LearnTheme.card))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(LearnTheme.cardStroke))
    }
}

struct LearnWindowRoot: View {
    @ObservedObject var store: LearnStore
    @State var section: LearnSection

    init(store: LearnStore, initial: LearnSection) {
        self.store = store
        _section = State(initialValue: initial)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Group {
                switch section {
                case .review:  ReviewSessionView(store: store)
                case .library: LibraryView(store: store)
                case .essay:   EssayHomeView(store: store)
                case .grammar: GrammarHomeView(store: store)
                case .stats:   StatsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LearnTheme.bg)
        }
        .tint(LearnTheme.accent)
        .preferredColorScheme(.dark)
        .scrollIndicators(.never)
        .scrollContentBackground(.hidden)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill").foregroundStyle(LearnTheme.accent)
                Text("Learn").font(.system(size: 17, weight: .bold))
            }
            .padding(.horizontal, 12).padding(.top, 44).padding(.bottom, 14)
            ForEach(LearnSection.allCases) { s in
                SidebarItem(section: s, selected: section == s,
                            badge: s == .review ? store.dueCount() : 0) { section = s }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(LearnTheme.highlight)
                Text("Streak \(store.streak()) ngày").font(.caption.weight(.semibold))
                Spacer()
            }
            .padding(12).learnCard(10)
        }
        .padding(10)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(LearnTheme.sidebar)
    }
}

private struct SidebarItem: View {
    let section: LearnSection
    let selected: Bool
    let badge: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon).frame(width: 20)
                    .foregroundStyle(selected ? LearnTheme.accent : .white.opacity(0.6))
                Text(section.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.caption2.bold()).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(LearnTheme.accent)).foregroundStyle(.black)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.white.opacity(0.1) : (hover ? Color.white.opacity(0.05) : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Mục từ đầy đủ (kiểu từ điển)

struct WordEntryView: View {
    let word: LearnWord
    @ObservedObject var store: LearnStore
    var showActions = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.headword).font(.system(size: 34, weight: .bold))
                Text(word.pos).font(.system(size: 14, weight: .semibold)).italic()
                HStack(spacing: 16) {
                    ipa("UK", word.ipaUK, uk: true)
                    ipa("US", word.ipaUS, uk: false)
                }
            }
            ForEach(word.senses.indices, id: \.self) { i in
                senseBlock(i, word.senses[i])
            }
            if showActions {
                HStack {
                    if store.isKnown(word.id) {
                        Button { store.unmarkKnown(word.id) } label: { Label("Bỏ đánh dấu đã thuộc", systemImage: "arrow.uturn.backward") }
                    } else {
                        Button { store.markKnown(word.id) } label: { Label("Đã thuộc", systemImage: "checkmark.seal") }
                    }
                    Button(role: .destructive) { store.deleteWord(word.id) } label: { Label("Xoá khỏi kho", systemImage: "trash") }
                    Spacer()
                    if word.source == .ai { Text("AI").font(.caption2.bold()).foregroundStyle(.secondary) }
                }
                .buttonStyle(.borderless).padding(.top, 6)
            }
        }
        .textSelection(.enabled)
    }

    private func ipa(_ tag: String, _ t: String, uk: Bool) -> some View {
        Button { Pronouncer.speak(word.headword, uk: uk) } label: {
            HStack(spacing: 4) {
                Text(tag).font(.system(size: 12, weight: .heavy))
                Image(systemName: "speaker.wave.2.fill")
                Text(t).font(.system(size: 14))
            }
        }.buttonStyle(.plain).learnHover(scale: 1.04, brighten: 0.2)
    }

    private func senseBlock(_ i: Int, _ s: LearnSense) -> some View {
        let key = SenseKey(wordID: word.id, index: i)
        let accent = LearnTheme.purple
        return VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(accent).frame(height: 2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(word.headword).font(.system(size: 15, weight: .bold)).foregroundStyle(accent)
                Text(word.pos).font(.system(size: 13, weight: .semibold)).italic().foregroundStyle(accent)
                Text("(\(s.guideword))").font(.system(size: 13, weight: .semibold)).foregroundStyle(accent)
                Spacer()
                if let r = store.review(key) {
                    Text(r.mastered ? "✓ đã thuộc"
                         : "đúng \(r.correct)/\(ReviewState.masterAt) lần · dạng \(Set(r.modes).count)/3 · "
                           + (r.due > Date() ? "ôn lại \(r.due.formatted(.relative(presentation: .named)))" : "đến hạn"))
                        .font(.caption).foregroundStyle(r.mastered ? LearnTheme.good : .secondary)
                } else {
                    Text("chưa học").font(.caption).foregroundStyle(.secondary)
                }
            }
            Rectangle().fill(LearnTheme.accent.opacity(0.8)).frame(height: 1)
            LevelBadge(level: s.level)
            Text(s.defEN + ":").font(.system(size: 16, weight: .semibold))
            Text(s.defVI).font(.system(size: 15)).foregroundStyle(LearnTheme.accent)
            ForEach(s.examples.indices, id: \.self) { j in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(s.examples[j].en).italic()
                        Button { Pronouncer.speak(s.examples[j].en, uk: false) } label: {
                            Image(systemName: "speaker.wave.1").font(.caption)
                        }.buttonStyle(.plain).foregroundStyle(.secondary).learnHover(scale: 1.15, brighten: 0.3)
                    }
                    Text(s.examples[j].vi).font(.system(size: 13)).foregroundStyle(.secondary).padding(.leading, 14)
                }.font(.system(size: 14))
            }
        }
    }
}

// MARK: - Ôn tập
//
// Một lượt N từ (đến hạn → mới → sắp tới hạn), 2 giai đoạn tách biệt:
//  1. Xem lại: lật qua toàn bộ N từ (không chấm).
//  2. Kiểm tra: 1 vòng, mỗi từ 1 câu với dạng ngẫu nhiên (chọn nghĩa / chọn từ / điền).
//     Bỏ qua = sai + hỏi lại cuối vòng (1 lần). Đúng đủ 10 lần → thuộc.

struct ReviewSessionView: View {
    @ObservedObject var store: LearnStore

    private enum Phase { case start, preview, test, oldReview, done }

    @State private var phase = Phase.start
    @State private var words: [SenseKey] = []
    @State private var previewIndex = 0
    @State private var testQueue: [SenseKey] = []
    @State private var pos = 0
    @State private var requeued: Set<SenseKey> = []
    @State private var question: PracticeQuestion?
    @State private var stateBefore: ReviewState?
    @State private var results: [(SenseKey, Bool)] = []
    @AppStorage("learn.batchSize") private var batchSize = 10
    @AppStorage("learn.newPerBatch") private var newPerBatch = 5

    var body: some View {
        VStack(spacing: 16) {
            switch phase {
            case .start: startScreen
            case .preview: previewScreen
            case .test: testScreen
            case .oldReview: oldReviewScreen
            case .done: doneScreen
            }
        }
        .padding(28)
    }

    // MARK: Header chung
    private func header(_ title: String, _ i: Int, _ total: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.headline).foregroundStyle(LearnTheme.accent)
                Text("\(min(i + 1, total))/\(total)").foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Kết thúc") { phase = results.isEmpty ? .start : .done }
            }
            ProgressView(value: Double(i), total: Double(max(total, 1))).tint(LearnTheme.accent)
        }
        .frame(maxWidth: 680)
    }

    // MARK: 1. Xem lại
    @ViewBuilder private var previewScreen: some View {
        header("Xem lại", previewIndex, words.count)
        if previewIndex < words.count, let w = store.word(words[previewIndex]),
           w.senses.indices.contains(words[previewIndex].index) {
            let k = words[previewIndex]
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(store.review(k) == nil ? "TỪ MỚI" : "ĐANG ÔN")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(store.review(k) == nil ? LearnTheme.accent : LearnTheme.accent)
                        Spacer()
                        KnownButton(size: 13) { markKnown(k) }
                    }
                    WordHeadline(word: w, sense: w.senses[k.index], scale: 1.6)
                    SenseDetail(sense: w.senses[k.index], scale: 1.4)
                }
                .padding(28).frame(maxWidth: 680, alignment: .leading).learnCard(18)
                .frame(maxWidth: .infinity)
                .id(k)
                .onAppear { Pronouncer.speak(w.headword, uk: false) }
            }
            HStack {
                Button { previewIndex -= 1 } label: { Label("Trước", systemImage: "chevron.left") }
                    .disabled(previewIndex == 0)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Spacer()
                if previewIndex < words.count - 1 {
                    Button { previewIndex += 1 } label: { Label("Tiếp", systemImage: "chevron.right") }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    Button("Bỏ qua, kiểm tra luôn") { startTest() }.learnHover()
                } else {
                    Button { startTest() } label: {
                        Label("Bắt đầu kiểm tra", systemImage: "checkmark.circle.fill").padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                }
            }
            .controlSize(.large).frame(maxWidth: 680)
        }
    }

    // MARK: 2. Kiểm tra
    @ViewBuilder private var testScreen: some View {
        header("Kiểm tra", pos, testQueue.count)
        if pos < testQueue.count, let q = question, q.key == testQueue[pos],
           let w = store.word(q.key), w.senses.indices.contains(q.key.index) {
            let k = q.key
            ScrollView {
                PracticeQuestionView(q: q, word: w, sense: w.senses[k.index], stateBefore: stateBefore,
                                     onAnswer: { ok in
                                         results.append((k, ok))
                                         store.record(k, correct: ok, mode: q.mode)
                                     },
                                     onNext: nextQuestion,
                                     onSkip: { skip(q) },
                                     onKnown: { markKnown(k) })
                .id("q\(pos)")
                .padding(28).frame(maxWidth: 680).learnCard(18)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Ôn bài cũ (bắt buộc): mỗi từ × 3 dạng, câu lấy từ hàng đợi của store
    @ViewBuilder private var oldReviewScreen: some View {
        header("Ôn bài cũ", store.reviewTotal - store.reviewRemaining, store.reviewTotal)
        if let q = question, let w = store.word(q.key), w.senses.indices.contains(q.key.index) {
            let k = q.key
            ScrollView {
                PracticeQuestionView(q: q, word: w, sense: w.senses[k.index], stateBefore: stateBefore,
                                     onAnswer: { ok in store.record(k, correct: ok, mode: q.mode) },
                                     onNext: nextOldReview,
                                     onSkip: { store.record(k, correct: false, mode: q.mode); nextOldReview() },
                                     onKnown: nil)   // bài kiểm tra: không cho "đã thuộc"
                .id("old\(store.reviewRemaining)-\(k)")
                .padding(28).frame(maxWidth: 680).learnCard(18)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func startOldReview() {
        phase = .oldReview
        prepareOldReview()
    }

    private func prepareOldReview() {
        question = store.nextOldReviewQuestion()
        stateBefore = question.flatMap { store.review($0.key) }
        if question == nil { phase = .start }        // xong → thẻ bài hôm nay hiện tổng kết
    }

    private func nextOldReview() { prepareOldReview() }

    // MARK: Bắt đầu / tổng kết
    private var startScreen: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.fill").font(.system(size: 46)).foregroundStyle(LearnTheme.accent)
            Text("Luyện từ").font(.title2.bold())
            stats
            dailyCard
            VStack(alignment: .leading, spacing: 8) {
                Stepper("Số từ mỗi lượt: \(batchSize)", value: $batchSize, in: 5...50, step: 5)
                Stepper("Từ mới tối đa mỗi lượt: \(newPerBatch)", value: $newPerBatch, in: 0...20)
            }
            .frame(width: 300).padding(14).learnCard(12)
            startButton("Bắt đầu")
                .onAppear { store.ensureDaily() }
            Text("① Xem lại toàn bộ từ của lượt → ② kiểm tra mỗi từ 1 câu (chọn nghĩa · chọn từ · điền từ, ngẫu nhiên). Đúng đủ 10 lần, đủ cả 3 dạng → đã thuộc.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var doneScreen: some View {
        let right = results.filter(\.1).count
        let wrong = Array(Set(results.filter { !$0.1 }.map(\.0)))
        return ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 46)).foregroundStyle(LearnTheme.good)
                Text("Xong lượt! Đúng \(right)/\(results.count) câu").font(.title2.bold())
                if !wrong.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Từ cần xem lại").font(.headline)
                        ForEach(wrong, id: \.self) { k in
                            if let w = store.word(k), let s = store.deck.sense(k) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(w.headword).fontWeight(.semibold)
                                    Text(w.pos).italic().foregroundStyle(LearnTheme.purple).font(.caption)
                                    Text("— " + s.defVI).foregroundStyle(LearnTheme.accent)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(16).frame(maxWidth: 520).learnCard(12)
                }
                stats
                startButton("Luyện lượt tiếp")
            }
            .frame(maxWidth: .infinity).padding(.top, 30)
        }
    }

    /// Bộ 10 từ B2–C2 của hôm nay (notch popup xoay vòng bộ này).
    private var dailyCard: some View {
        let keys = store.daily?.keys ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.daily?.reviewAgain == true ? "Bài hôm nay · đang ôn lại" : "Bài hôm nay",
                      systemImage: "sun.max.fill").font(.headline)
                Spacer()
                Text("\(keys.filter { store.review($0)?.mastered == true }.count)/\(keys.count) đã thuộc")
                    .font(.caption).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(keys, id: \.self) { k in
                    if let w = store.word(k) {
                        Text(w.headword).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(store.review(k)?.mastered == true
                                                       ? LearnTheme.good.opacity(0.3) : Color.white.opacity(0.08)))
                    }
                }
            }
            if store.reviewRemaining > 0 {
                Text("Hôm qua bạn đã học xong bài — ôn lại đủ 3 dạng cho mỗi từ (còn \(store.reviewRemaining) câu) rồi mới học bài mới.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { startOldReview() } label: {
                    Label("Ôn bài cũ", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).learnHover()
            } else if store.needsReviewSummary {
                OldReviewSummaryView(store: store).padding(.top, 4)
            } else if store.dailyComplete {
                DailyCompleteView(store: store).padding(.top, 4)
            } else {
                HStack {
                    Button { start(keys: keys) } label: {
                        Label(store.daily?.reviewAgain == true ? "Ôn lại bộ này" : "Học bài hôm nay",
                              systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).learnHover()
                    .disabled(keys.isEmpty)
                    if store.daily?.reviewAgain == true {
                        Button { store.startNewDailySet() } label: {
                            Label("Học 10 từ khác", systemImage: "sparkles").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).learnHover()
                    }
                }
            }
        }
        .padding(16).frame(width: 440).learnCard(12)
    }

    private var stats: some View {
        HStack(spacing: 14) {
            statPill("Đến hạn", store.dueCount(), LearnTheme.bad)
            statPill("Đang học", store.learnedCount - store.masteredCount, LearnTheme.accent)
            statPill("Đã thuộc", store.masteredCount, LearnTheme.good)
            statPill("Chưa học", store.totalSenses - store.learnedCount, .secondary)
        }
    }

    private func startButton(_ title: String) -> some View {
        Button { start() } label: {
            Label(title, systemImage: "play.fill").font(.headline).padding(.horizontal, 18).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .keyboardShortcut(.return, modifiers: [])
    }

    private func statPill(_ t: String, _ n: Int, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.title3.bold()).monospacedDigit().foregroundStyle(c)
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 84).padding(.vertical, 10).learnCard(10)
    }

    // MARK: Điều khiển
    private func start(keys: [SenseKey]? = nil) {
        words = keys?.filter { store.daily?.reviewAgain == true || store.review($0)?.mastered != true }
            ?? store.studyBatch(size: batchSize, newLimit: newPerBatch)
        previewIndex = 0; results = []
        phase = words.isEmpty ? .start : .preview
    }

    private func startTest() {
        words.forEach { store.introduce($0) }      // từ mới vào lịch ôn
        testQueue = words.shuffled()
        pos = 0; requeued = []
        if testQueue.isEmpty { phase = .done } else { phase = .test; prepare() }
    }

    private func prepare() {
        guard pos < testQueue.count else { return }
        stateBefore = store.review(testQueue[pos])
        question = store.question(for: testQueue[pos])
    }

    private func nextQuestion() {
        pos += 1
        if pos >= testQueue.count { phase = .done } else { prepare() }
    }

    private func skip(_ q: PracticeQuestion) {
        results.append((q.key, false))
        store.record(q.key, correct: false, mode: q.mode)
        if !requeued.contains(q.key) { requeued.insert(q.key); testQueue.append(q.key) }
        nextQuestion()
    }

    /// Đã thuộc: bỏ từ khỏi lượt (cả phần xem lại lẫn kiểm tra).
    private func markKnown(_ k: SenseKey) {
        store.markKnown(k.wordID)
        switch phase {
        case .preview:
            words.remove(at: previewIndex)
            if words.isEmpty { phase = .start } else { previewIndex = min(previewIndex, words.count - 1) }
        case .test:
            words.removeAll { $0.wordID == k.wordID }
            testQueue = Array(testQueue[...pos]) + testQueue[(pos + 1)...].filter { $0.wordID != k.wordID }
            nextQuestion()
        default: break
        }
    }
}

// MARK: - Thống kê

struct StatsView: View {
    @ObservedObject var store: LearnStore

    private struct DayCount: Identifiable { let id: String; let date: Date; let n: Int }
    private struct LevelCount: Identifiable { let id: String; let total: Int; let learned: Int }

    private var days: [DayCount] {
        let cal = Calendar.current
        return (0..<21).reversed().map { off in
            let d = cal.date(byAdding: .day, value: -off, to: Date())!
            let k = LearnStats.dayKey(d)
            return DayCount(id: k, date: d, n: store.stats.reviewsByDay[k] ?? 0)
        }
    }

    private var levels: [LevelCount] {
        let order = ["A1", "A2", "B1", "B2", "C1", "C2"]
        var total: [String: Int] = [:], learned: [String: Int] = [:]
        for k in store.deck.allKeys {
            guard let s = store.deck.sense(k) else { continue }
            total[s.level, default: 0] += 1
            if store.review(k) != nil { learned[s.level, default: 0] += 1 }
        }
        return order.filter { total[$0] != nil }.map { LevelCount(id: $0, total: total[$0]!, learned: learned[$0] ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    tile("Streak", "\(store.streak()) ngày", "flame.fill", LearnTheme.highlight)
                    tile("Hôm nay", "\(store.stats.today(now: Date())) lượt", "bolt.fill", LearnTheme.accent)
                    tile("Đến hạn", "\(store.dueCount())", "clock.fill", LearnTheme.bad)
                    tile("Đã thuộc", "\(store.masteredCount)/\(store.totalSenses)", "checkmark.seal.fill", LearnTheme.good)
                }
                Text("Lượt ôn 3 tuần gần đây").font(.headline)
                Chart(days) { d in
                    BarMark(x: .value("Ngày", d.date, unit: .day), y: .value("Lượt", d.n))
                        .foregroundStyle(LearnTheme.highlight.gradient).cornerRadius(3)
                }
                .frame(height: 180)
                Text("Tiến độ theo trình độ").font(.headline)
                ForEach(levels) { l in
                    HStack {
                        LevelBadge(level: l.id).frame(width: 34)
                        ProgressView(value: Double(l.learned), total: Double(max(l.total, 1)))
                        Text("\(l.learned)/\(l.total)").monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                    }
                }
                Text("Essay đã tạo: \(store.essays.count) · Bài grammar: \(store.lessons.count)")
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
    }

    private func tile(_ title: String, _ value: String, _ icon: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(c)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .learnCard(12)
    }
}
