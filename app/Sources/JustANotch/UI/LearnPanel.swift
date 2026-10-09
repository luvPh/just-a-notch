import SwiftUI
import AVFoundation

/// Phát âm bằng TTS hệ thống (UK/US).
enum Pronouncer {
    private static let synth = AVSpeechSynthesizer()
    static func speak(_ text: String, uk: Bool, rate: Float = 0.45) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: uk ? "en-GB" : "en-US")
        u.rate = rate
        synth.speak(u)
    }
    static func stop() { synth.stopSpeaking(at: .immediate) }
}

/// Tab Learn trên notch: header (đến hạn · streak · đã thuộc) + một lượt học
/// (thẻ giới thiệu từ mới, hoặc câu hỏi chấm tự động theo pipeline EngZone).
struct LearnPanel: View {
    @ObservedObject var store: LearnStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let p = store.current, let w = store.word(p.key), w.senses.indices.contains(p.key.index) {
                let s = w.senses[p.key.index]
                Group {
                    switch p {
                    case .intro:
                        IntroCardView(word: w, sense: s, compact: true,
                                      onGotIt: { store.advance() }, onSkip: { store.skip() },
                                      onKnown: { store.markKnown(p.key.wordID); store.ensurePrompt() })
                    case let .question(q):
                        PracticeQuestionView(q: q, word: w, sense: s, stateBefore: store.review(q.key), compact: true,
                                             onAnswer: { store.answer(correct: $0) },
                                             onNext: { store.advance() },
                                             onKnown: store.reviewRemaining > 0 ? nil : { store.markKnown(q.key.wordID); store.ensurePrompt() })
                    }
                }
                .id(p.key.description + "\(p)")
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if store.needsReviewSummary {
                OldReviewSummaryView(store: store, compact: true)
                Spacer(minLength: 0)
            } else if store.dailyComplete {
                DailyCompleteView(store: store, compact: true)
                Spacer(minLength: 0)
            } else {
                NotchEmptyState(symbol: store.totalSenses == 0 ? "books.vertical" : "checkmark",
                                title: store.totalSenses == 0 ? "Chưa có kho từ" : "Hết từ để học rồi",
                                hint: store.totalSenses == 0 ? nil : "Quay lại sau để ôn tiếp nhé")
            }
        }
        .foregroundStyle(LearnPalette.notch.text)
        .padding(.horizontal, 4).padding(.top, 2)
        .environment(\.learnOnNotch, true)
        .onAppear { store.ensurePrompt() }
        .animation(.easeInOut(duration: 0.18), value: store.current)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Hôm nay").font(NotchTheme.toolbarTitle).foregroundStyle(.ink)
            stat("flame.fill", "\(store.streak())", "ngày streak")
                .padding(.horizontal, 8).frame(height: 22)
                .background(Capsule().fill(NotchTheme.card))
            Spacer()
            NotchIconButton(symbol: "macwindow", help: "Mở cửa sổ học") { LearnWindowController.shared.show() }
        }
    }

    private func stat(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(NotchTheme.accent)
            Text(value).font(.system(size: 11, weight: .bold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.ink.opacity(0.5))
        }
    }
}

/// Popup notch tự bung: đúng 1 thẻ từ bộ từ hôm nay, không có rail tab.
/// Trả lời/xem xong → `onDone` (thu notch; lượt sau lấy từ kế tiếp).
struct LearnPopupCard: View {
    @ObservedObject var store: LearnStore
    let onDone: () -> Void
    /// Panel đã được cấp bàn phím (người dùng bấm vào popup ở câu điền từ).
    var keyboardReady = false

    private var dailyMastered: Int {
        (store.daily?.keys ?? []).filter { store.review($0)?.mastered == true }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "graduationcap.fill").font(.system(size: 9, weight: .semibold))
                Text(store.reviewRemaining > 0
                     ? "Ôn bài cũ · còn \(store.reviewRemaining) câu"
                     : "Bài hôm nay · \(dailyMastered)/\(store.daily?.keys.count ?? 0) đã thuộc")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Image(systemName: "flame.fill").font(.system(size: 9))
                Text("\(store.streak())").font(.system(size: 10, weight: .bold)).monospacedDigit()
                Menu {
                    Section("Tạm dừng popup") {
                        ForEach(AppSettings.learnPauseOptions(), id: \.0) { opt in
                            Button(opt.0) { AppSettings.shared.learnPausedUntil = opt.1; onDone() }
                        }
                    }
                } label: {
                    Image(systemName: "pause.circle").font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Tạm dừng popup học")
                .learnHover(scale: 1.1, brighten: 0.3)
            }
            .foregroundStyle(.ink.opacity(0.45))
            if let p = store.current, let w = store.word(p.key), w.senses.indices.contains(p.key.index) {
                let s = w.senses[p.key.index]
                switch p {
                case .intro:
                    IntroCardView(word: w, sense: s, compact: true, onGotIt: onDone, onSkip: nil,
                                  onKnown: { store.markKnown(p.key.wordID); onDone() })
                case let .question(q):
                    PracticeQuestionView(q: q, word: w, sense: s, stateBefore: store.review(q.key), compact: true,
                                         keyboardReady: keyboardReady,
                                         onAnswer: { ok in
                                             store.answer(correct: ok)
                                             // Trả lời xong → tự thu: đúng thì nhanh, sai thì đủ lâu để đọc thẻ học lại.
                                             let answered = p
                                             DispatchQueue.main.asyncAfter(deadline: .now() + (ok ? 1.4 : 8)) {
                                                 if store.current == answered { onDone() }
                                             }
                                         },
                                         onNext: onDone,
                                         onKnown: store.reviewRemaining > 0 ? nil : { store.markKnown(q.key.wordID); onDone() })
                }
            } else if store.needsReviewSummary {
                OldReviewSummaryView(store: store, compact: true)
            } else if store.dailyComplete {
                // Chọn xong → popup giữ nguyên và hiện luôn từ kế tiếp.
                DailyCompleteView(store: store, compact: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(LearnPalette.notch.text)
        .environment(\.learnOnNotch, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Dòng đầu mục từ: headword · loại từ · (GUIDEWORD) · level · IPA UK/US có 🔊.
struct WordHeadline: View {
    @Environment(\.learnPalette) private var pal
    let word: LearnWord
    let sense: LearnSense
    var isNew = false
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Từ luôn một dòng riêng (không bẻ giữa chữ); loại từ/guideword/level ở dòng dưới.
            VStack(alignment: .leading, spacing: 1) {
                headword
                HStack(alignment: .firstTextBaseline, spacing: 6) { meta }
            }
            HStack(spacing: 10) {
                ipa("UK", word.ipaUK, uk: true)
                ipa("US", word.ipaUS, uk: false)
            }
        }
    }

    private var headword: some View {
        Text(word.headword).font(.system(size: 20 * scale, weight: .bold))
            .lineLimit(1).minimumScaleFactor(0.6).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var meta: some View {
        Text(word.pos).font(.system(size: 11 * scale, weight: .semibold)).italic()
            .foregroundStyle(pal.purple).fixedSize()
        Text("(\(sense.guideword))").font(.system(size: 10 * scale, weight: .semibold))
            .foregroundStyle(pal.purple.opacity(0.8)).lineLimit(1)
        LevelBadge(level: sense.level).fixedSize()
        if isNew {
            Text("MỚI").font(.system(size: 8 * scale, weight: .heavy))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Capsule().fill(pal.highlight)).foregroundStyle(.black)
        }
    }

    private func ipa(_ tag: String, _ text: String, uk: Bool) -> some View {
        Button { Pronouncer.speak(word.headword, uk: uk) } label: {
            HStack(spacing: 3) {
                Text(tag).font(.system(size: 9 * scale, weight: .heavy))
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 9 * scale))
                Text(text).font(.system(size: 11 * scale)).foregroundStyle(pal.secondary)
            }
        }.buttonStyle(.plain).learnHover(scale: 1.05, brighten: 0.3)
    }
}

struct LevelBadge: View {
    @Environment(\.learnPalette) private var pal
    let level: String
    var body: some View {
        Text(level).font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(pal.badgeFill))
            .foregroundStyle(.ink)
    }
}

/// Định nghĩa EN + VI + ví dụ (EN in nghiêng, VI mờ).
struct SenseDetail: View {
    @Environment(\.learnPalette) private var pal
    let sense: LearnSense
    var scale: CGFloat = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sense.defEN).font(.system(size: 12 * scale, weight: .semibold))
            Text("→ " + sense.defVI).font(.system(size: 11.5 * scale)).foregroundStyle(pal.highlight)
            ForEach(sense.examples.prefix(1).indices, id: \.self) { i in
                let ex = sense.examples[i]
                Text("• " + ex.en).font(.system(size: 11 * scale)).italic().foregroundStyle(pal.text.opacity(0.85))
                Text("  " + ex.vi).font(.system(size: 10.5 * scale)).foregroundStyle(pal.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
