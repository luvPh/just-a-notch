import SwiftUI
import AVFoundation

/// Phát âm bằng TTS hệ thống (UK/US).
enum Pronouncer {
    private static let synth = AVSpeechSynthesizer()
    static func speak(_ text: String, uk: Bool) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: uk ? "en-GB" : "en-US")
        u.rate = 0.45
        synth.speak(u)
    }
}

/// Tab Learn trên notch: header (đến hạn · streak · đã học) + một lượt học (thẻ lật / quiz).
struct LearnPanel: View {
    @ObservedObject var store: LearnStore
    @State private var revealed = false
    @State private var picked: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let p = store.current, let w = store.word(p.key), w.senses.indices.contains(p.key.index) {
                promptView(p, w, w.senses[p.key.index])
                    .id(p.key)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                Text(store.totalSenses == 0 ? "Chưa có kho từ." : "Hết từ để học rồi 🎉")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4).padding(.top, 2)
        .onAppear { store.ensurePrompt() }
        .animation(.easeInOut(duration: 0.2), value: store.current?.key)
    }

    private var header: some View {
        HStack(spacing: 10) {
            stat("clock.arrow.circlepath", "\(store.dueCount())", "đến hạn")
            stat("flame.fill", "\(store.streak())", "ngày")
            stat("checkmark.seal.fill", "\(store.learnedCount)/\(store.totalSenses)", "đã học")
            Spacer()
        }
    }

    private func stat(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(.orange)
            Text(value).font(.system(size: 11, weight: .bold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private func promptView(_ p: LearnPrompt, _ w: LearnWord, _ s: LearnSense) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WordHeadline(word: w, sense: s, isNew: p.isNew)
            switch p.kind {
            case .card: cardBody(s)
            case let .quiz(options, correct): quizBody(options, correct)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Card
    @ViewBuilder private func cardBody(_ s: LearnSense) -> some View {
        if revealed {
            SenseDetail(sense: s)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(ReviewGrade.allCases, id: \.self) { g in
                    Button { finish(g) } label: {
                        Text(g.label).font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(gradeColor(g).opacity(0.85)))
                    }.buttonStyle(.plain)
                }
            }
        } else {
            Spacer(minLength: 0)
            HStack {
                Button { store.skip(); store.ensurePrompt() } label: {
                    Text("Bỏ qua").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }.buttonStyle(.plain)
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.18)) { revealed = true } } label: {
                    Label("Xem nghĩa", systemImage: "eye").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.15)))
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: Quiz
    @ViewBuilder private func quizBody(_ options: [String], _ correct: Int) -> some View {
        Text("Nghĩa nào đúng?").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        VStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    guard picked == nil else { return }
                    picked = i
                    DispatchQueue.main.asyncAfter(deadline: .now() + (i == correct ? 0.8 : 1.6)) {
                        finish(i == correct ? .good : .again)
                    }
                } label: {
                    Text(options[i]).font(.system(size: 11)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7).fill(quizColor(i, correct)))
                }.buttonStyle(.plain)
            }
        }
    }

    private func quizColor(_ i: Int, _ correct: Int) -> Color {
        guard let picked else { return .white.opacity(0.1) }
        if i == correct { return .green.opacity(0.7) }
        if i == picked { return .red.opacity(0.7) }
        return .white.opacity(0.06)
    }

    private func gradeColor(_ g: ReviewGrade) -> Color {
        switch g { case .again: .red; case .hard: .orange; case .good: .green; case .easy: .blue }
    }

    private func finish(_ g: ReviewGrade) {
        store.answer(g)
        revealed = false
        picked = nil
        store.ensurePrompt()
    }
}

/// Dòng đầu mục từ: headword · loại từ · (GUIDEWORD) · level · IPA UK/US có 🔊.
struct WordHeadline: View {
    let word: LearnWord
    let sense: LearnSense
    var isNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(word.headword).font(.system(size: 20, weight: .bold))
                Text(word.pos).font(.system(size: 11, weight: .semibold)).italic()
                    .foregroundStyle(Color(red: 0.7, green: 0.55, blue: 1))
                Text("(\(sense.guideword))").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.7, green: 0.55, blue: 1))
                LevelBadge(level: sense.level)
                if isNew {
                    Text("MỚI").font(.system(size: 8, weight: .heavy))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.yellow)).foregroundStyle(.black)
                }
            }
            HStack(spacing: 10) {
                ipa("UK", word.ipaUK, uk: true)
                ipa("US", word.ipaUS, uk: false)
            }
        }
    }

    private func ipa(_ tag: String, _ text: String, uk: Bool) -> some View {
        Button { Pronouncer.speak(word.headword, uk: uk) } label: {
            HStack(spacing: 3) {
                Text(tag).font(.system(size: 9, weight: .heavy))
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
                Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
            }
        }.buttonStyle(.plain)
    }
}

struct LevelBadge: View {
    let level: String
    var body: some View {
        Text(level).font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color(red: 0.2, green: 0.22, blue: 0.45)))
            .foregroundStyle(.white)
    }
}

/// Định nghĩa EN + VI + ví dụ (EN in nghiêng, VI mờ).
struct SenseDetail: View {
    let sense: LearnSense
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sense.defEN).font(.system(size: 12, weight: .semibold))
            Text("→ " + sense.defVI).font(.system(size: 11.5)).foregroundStyle(.yellow.opacity(0.9))
            ForEach(sense.examples.prefix(1).indices, id: \.self) { i in
                let ex = sense.examples[i]
                Text("• " + ex.en).font(.system(size: 11)).italic().foregroundStyle(.white.opacity(0.85))
                Text("  " + ex.vi).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
