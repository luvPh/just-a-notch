import SwiftUI

/// Một câu hỏi luyện từ (3 dạng) + phản hồi sau khi trả lời — dùng chung cho
/// notch (`compact`) và cửa sổ học. Chấm tự động, gọi `onAnswer(correct)` đúng 1 lần.
struct PracticeQuestionView: View {
    @Environment(\.learnPalette) private var pal
    let q: PracticeQuestion
    let word: LearnWord
    let sense: LearnSense
    /// Trạng thái TRƯỚC khi trả lời (để hiện "ôn lại sau N ngày").
    let stateBefore: ReviewState?
    var compact = false
    let onAnswer: (Bool) -> Void
    let onNext: () -> Void
    let onSkip: () -> Void
    /// Đánh dấu đã thuộc — không bao giờ hỏi lại từ này. nil = ẩn nút (bài kiểm tra bài cũ).
    var onKnown: (() -> Void)?

    @State private var picked: Int?
    @State private var input = ""
    @State private var result: Bool?
    @FocusState private var focused: Bool

    private var fs: CGFloat { compact ? 1 : 1.6 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 14) {
            HStack {
                Text(q.mode.title.uppercased()).font(.system(size: 9 * fs, weight: .heavy))
                    .foregroundStyle(compact ? pal.secondary : pal.accent)
                LevelBadge(level: sense.level)
                Spacer()
                if let onKnown { KnownButton(size: 10 * fs, action: onKnown) }
                if result == nil {
                    Button("Bỏ qua", action: onSkip).buttonStyle(.plain)
                        .font(.system(size: 10 * fs)).foregroundStyle(.secondary)
                        .help("Tính là sai, gặp lại sau")
                        .learnHover(scale: 1.05, brighten: 0.25)
                }
            }
            prompt
            switch q.mode {
            case .mcqWord, .mcqMeaning: options
            case .fill: fillField
            }
            if let result { feedback(result) }
        }
        .onAppear {
            if q.mode == .mcqWord { Pronouncer.speak(word.headword, uk: false) }
            if q.mode == .fill { focused = true }
        }
        .background {
            // Enter = sang câu tiếp khi đã trả lời.
            if result != nil {
                Button("", action: onNext).keyboardShortcut(.return, modifiers: []).opacity(0)
            }
        }
    }

    @ViewBuilder private var prompt: some View {
        switch q.mode {
        case .mcqWord:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(word.headword).font(.system(size: 20 * fs, weight: .bold))
                Text(word.pos).italic().font(.system(size: 11 * fs)).foregroundStyle(pal.purple)
                Button { Pronouncer.speak(word.headword, uk: false) } label: {
                    Text(word.ipaUS).font(.system(size: 11 * fs)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).learnHover(scale: 1.05, brighten: 0.3)
            }
        case .mcqMeaning, .fill:
            VStack(alignment: .leading, spacing: 2) {
                Text(sense.defVI).font(.system(size: 14 * fs, weight: .semibold))
                Text("\(word.pos) · \(sense.defEN)").font(.system(size: 10.5 * fs)).foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 3)
            }
        }
    }

    private var options: some View {
        VStack(spacing: compact ? 3 : 8) {
            ForEach(q.options.indices, id: \.self) { i in
                Button { choose(i) } label: {
                    Text(q.options[i]).font(.system(size: 11 * fs)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, compact ? 8 : 14).padding(.vertical, compact ? 3 : 10)
                        .background(RoundedRectangle(cornerRadius: compact ? 7 : 10, style: .continuous).fill(optionFill(i)))
                }
                .buttonStyle(.plain)
                .learnHover(scale: 1.01, enabled: result == nil)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
            }
        }
    }

    private var fillField: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 8) {
            Text(q.charHint).font(.system(size: 12 * fs, design: .monospaced)).foregroundStyle(.secondary)
            HStack {
                TextField("Gõ từ tiếng Anh…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13 * fs))
                    .padding(.horizontal, 8).padding(.vertical, compact ? 3 : 8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.1)))
                    .focused($focused)
                    .disabled(result != nil)
                    .onSubmit(submitFill)
                if result == nil {
                    Button("Kiểm tra", action: submitFill).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                        .font(.system(size: 11 * fs))
                }
            }
        }
    }

    private func feedback(_ ok: Bool) -> some View {
        let after = (stateBefore ?? .new(now: Date())).recorded(correct: ok, mode: q.mode, now: Date())
        return VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ok ? pal.good : pal.bad)
                Text(ok ? "Chính xác!" : "Chưa đúng — đáp án: \(word.headword)").fontWeight(.semibold)
                Spacer()
                Button("Tiếp →", action: onNext).font(.system(size: 11 * fs, weight: .semibold))
                    .learnHover(scale: 1.05)
            }
            .font(.system(size: 11.5 * fs))
            if !compact || !ok {
                Text("\(word.headword) — \(sense.defVI)").font(.system(size: 10.5 * fs)).foregroundStyle(compact ? pal.highlight : pal.accent)
                    .lineLimit(compact ? 1 : nil)
            }
            if !compact, let ex = sense.examples.first {
                Text("• " + ex.en).italic().font(.system(size: 10.5 * fs))
            }
            Text(after.mastered
                 ? "🎉 Đã thuộc từ này!"
                 : "Đúng \(min(after.correct, ReviewState.masterAt))/\(ReviewState.masterAt) lần · dạng \(Set(after.modes).count)/3 · \(ReviewState.intervalText(days: after.intervalDays))")
                .font(.system(size: 9.5 * fs)).foregroundStyle(.secondary)
        }
    }

    private func optionFill(_ i: Int) -> Color {
        guard let picked else { return pal.optionFill }
        if i == q.correct { return pal.good.opacity(compact ? 0.35 : 0.6) }
        return i == picked ? pal.bad.opacity(compact ? 0.35 : 0.6) : .white.opacity(0.04)
    }

    private func choose(_ i: Int) {
        guard result == nil else { return }
        picked = i
        finish(i == q.correct)
    }

    private func submitFill() {
        guard result == nil, !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        finish(q.isCorrect(fill: input))
    }

    private func finish(_ ok: Bool) {
        result = ok
        onAnswer(ok)
        if q.mode != .mcqWord { Pronouncer.speak(word.headword, uk: false) }
    }
}

/// Thẻ giới thiệu từ mới (trước khi được kiểm tra).
struct IntroCardView: View {
    @Environment(\.learnPalette) private var pal
    let word: LearnWord
    let sense: LearnSense
    var compact = false
    let onGotIt: () -> Void
    var onSkip: (() -> Void)?
    let onKnown: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 12) {
            HStack {
                Text("TỪ MỚI").font(.system(size: compact ? 9 : 12, weight: .heavy)).foregroundStyle(compact ? pal.purple : LearnTheme.accent)
                Spacer()
                KnownButton(size: compact ? 10 : 13, action: onKnown)
                if let onSkip {
                    Button("Đổi từ khác", action: onSkip).buttonStyle(.plain).learnHover(scale: 1.05, brighten: 0.25)
                        .font(.system(size: compact ? 10 : 13)).foregroundStyle(.secondary)
                }
            }
            WordHeadline(word: word, sense: sense, scale: compact ? 1 : 1.6)
            SenseDetail(sense: sense, scale: compact ? 1 : 1.4)
            HStack {
                Spacer()
                Button(action: onGotIt) {
                    Label("Đã hiểu, kiểm tra sau", systemImage: "checkmark")
                        .font(.system(size: compact ? 11 : 14, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, compact ? 4 : 8)
                        .background(Capsule().fill(compact ? Color.white.opacity(0.14) : LearnTheme.accent.opacity(0.85)))
                        .foregroundStyle(compact ? Color.white : Color.black)
                }
                .buttonStyle(.plain)
                .learnHover(scale: 1.04)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .onAppear { Pronouncer.speak(word.headword, uk: false) }
    }
}

/// Nút "Đã thuộc": bỏ từ khỏi ôn tập vĩnh viễn (bỏ đánh dấu được trong Kho từ).
struct KnownButton: View {
    @Environment(\.learnPalette) private var pal
    let size: CGFloat
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Đã thuộc", systemImage: "checkmark.seal").font(.system(size: size, weight: .semibold))
        }
        .buttonStyle(.plain).foregroundStyle(pal.good.opacity(0.85))
        .learnHover(scale: 1.06, brighten: 0.2)
        .help("Đánh dấu đã thuộc — không hỏi lại từ này khi ôn tập")
    }
}

/// Hiệu ứng hover chung của mục Learn: sáng lên + phóng nhẹ + con trỏ bàn tay.
struct LearnHover: ViewModifier {
    var scale: CGFloat = 1.02
    var brighten: Double = 0.08
    var enabled = true
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .brightness(hovering && enabled ? brighten : 0)
            .scaleEffect(hovering && enabled ? scale : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { h in
                guard enabled else { return }
                hovering = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
    }
}

extension View {
    func learnHover(scale: CGFloat = 1.02, brighten: Double = 0.08, enabled: Bool = true) -> some View {
        modifier(LearnHover(scale: scale, brighten: brighten, enabled: enabled))
    }
}

/// Màn "hoàn thành bài học hôm nay" + 2 lựa chọn (không giới hạn số lần).
struct DailyCompleteView: View {
    @Environment(\.learnPalette) private var pal
    @ObservedObject var store: LearnStore
    var compact = false
    /// Gọi sau khi chọn (popup: hiện luôn từ kế tiếp).
    var onChoose: () -> Void = {}

    var body: some View {
        VStack(alignment: compact ? .leading : .center, spacing: compact ? 6 : 14) {
            HStack(spacing: 6) {
                Text("🎉").font(.system(size: compact ? 18 : 40))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hoàn thành bài học hôm nay!").font(.system(size: compact ? 14 : 22, weight: .bold))
                    Text("Đã thuộc cả \(store.daily?.keys.count ?? 0) từ · streak \(store.streak()) ngày")
                        .font(.system(size: compact ? 10.5 : 13)).foregroundStyle(pal.secondary)
                }
            }
            HStack(spacing: compact ? 6 : 12) {
                choice("Học 10 từ khác", "sparkles", primary: true) { store.startNewDailySet() }
                choice("Ôn lại 10 từ này", "arrow.clockwise", primary: false) { store.reviewDailyAgain() }
            }
        }
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
    }

    private func choice(_ title: String, _ icon: String, primary: Bool, _ act: @escaping () -> Void) -> some View {
        Button { act(); store.ensurePrompt(); onChoose() } label: {
            Label(title, systemImage: icon)
                .font(.system(size: compact ? 11 : 14, weight: .semibold))
                .frame(maxWidth: compact ? .infinity : 200)
                .padding(.vertical, compact ? 6 : 10)
                .background(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .fill(primary ? pal.purple.opacity(compact ? 0.45 : 0.7) : Color.white.opacity(0.1)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .learnHover(scale: 1.03)
    }
}

/// Tổng kết ôn bài cũ (bắt buộc xem rồi mới vào bài hôm nay).
struct OldReviewSummaryView: View {
    @Environment(\.learnPalette) private var pal
    @ObservedObject var store: LearnStore
    var compact = false

    var body: some View {
        let failed = store.reviewFailedWords
        VStack(alignment: compact ? .leading : .center, spacing: compact ? 6 : 14) {
            HStack(spacing: 8) {
                Text(failed == 0 ? "✅" : "📝").font(.system(size: compact ? 18 : 40))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ôn bài cũ xong · đúng \(store.reviewCorrect)/\(store.reviewTotal) câu")
                        .font(.system(size: compact ? 14 : 22, weight: .bold))
                    Text(failed == 0 ? "Nhớ hết bài hôm qua, giỏi quá!"
                                     : "\(failed) từ bị quên → đã xoá tiến độ và thêm vào bài hôm nay")
                        .font(.system(size: compact ? 10.5 : 13)).foregroundStyle(pal.secondary)
                }
            }
            Button { store.ackReviewSummary(); store.ensurePrompt() } label: {
                Label("Học bài hôm nay", systemImage: "arrow.right")
                    .font(.system(size: compact ? 11 : 14, weight: .semibold))
                    .frame(maxWidth: compact ? .infinity : 240).padding(.vertical, compact ? 6 : 10)
                    .background(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                        .fill(pal.purple.opacity(compact ? 0.45 : 0.7)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain).learnHover(scale: 1.03)
        }
        .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
    }
}
