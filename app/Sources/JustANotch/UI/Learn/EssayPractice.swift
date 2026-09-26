import SwiftUI
import Speech
import AVFoundation

/// Các bài luyện dựa trên essay (theo EngZone): từ vựng, họ từ, nghe-chép, dịch, đọc to.
struct EssayPracticeView: View {
    @ObservedObject var store: LearnStore
    let essay: Essay
    @State private var mode = Mode.vocab

    enum Mode: String, CaseIterable {
        case vocab = "Từ vựng", family = "Họ từ", dictation = "Nghe-chép", translate = "Dịch", speak = "Đọc to"
        var icon: String {
            switch self {
            case .vocab: "character.book.closed"; case .family: "point.3.connected.trianglepath.dotted"
            case .dictation: "ear"; case .translate: "character.bubble"; case .speak: "mic"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Button { mode = m } label: {
                        Label(m.rawValue, systemImage: m.icon).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(mode == m ? Color.accentColor.opacity(0.3) : .clear))
                    }.buttonStyle(.plain).learnHover(scale: 1.04, brighten: 0.15)
                }
            }
            .padding(10)
            Divider()
            ScrollView {
                Group {
                    switch mode {
                    case .vocab:     VocabDrill(store: store, vocab: essay.vocab)
                    case .family:    FamilyDrill(families: essay.families)
                    case .dictation: DictationDrill(sentences: essay.sentences)
                    case .translate: TranslateDrill(sentences: essay.sentences)
                    case .speak:     SpeakDrill(sentences: essay.sentences)
                    }
                }
                .padding(24)
                .frame(maxWidth: 680)
            }
        }
    }
}

/// Khung chung: tiến độ + Bỏ qua + Tiếp.
private struct DrillFrame<Content: View>: View {
    let index: Int
    let total: Int
    let answered: Bool
    let next: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if total == 0 {
                Text("Essay này chưa có dữ liệu cho bài luyện.").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Câu \(index % total + 1)/\(total)").foregroundStyle(.secondary)
                    Spacer()
                    Button(answered ? "Tiếp →" : "Bỏ qua", action: next)
                        .keyboardShortcut(answered ? .return : .escape, modifiers: answered ? [] : [])
                }
                content
            }
        }
    }
}

// MARK: Từ vựng — chọn nghĩa đúng

private struct VocabDrill: View {
    @ObservedObject var store: LearnStore
    let vocab: [EssayVocab]
    @State private var i = 0
    @State private var picked: Int?
    @State private var order: [EssayVocab] = []

    var body: some View {
        DrillFrame(index: i, total: order.count, answered: picked != nil, next: advance) {
            if !order.isEmpty {
                let v = order[i % order.count]
                let opts = options(for: v)
                Text(v.word).font(.system(size: 30, weight: .bold))
                Text("\(v.pos) · \(v.ipaUS)").foregroundStyle(.secondary)
                ForEach(opts.indices, id: \.self) { k in
                    Button {
                        guard picked == nil else { return }
                        picked = k
                        store.record(SenseKey(wordID: v.asWord.id, index: 0), correct: opts[k] == v.short, mode: .mcqWord)
                    } label: {
                        Text(opts[k]).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(RoundedRectangle(cornerRadius: 8).fill(color(k, opts, v)))
                    }.buttonStyle(.plain).learnHover(scale: 1.01, enabled: picked == nil)
                }
                if picked != nil { Text(v.defVI).foregroundStyle(LearnTheme.highlight) }
            }
        }
        .onAppear { order = vocab.shuffled(); Pronouncer.speak(order.first?.word ?? "", uk: false) }
    }

    private func options(for v: EssayVocab) -> [String] {
        var o = Array(vocab.filter { $0.id != v.id }.map(\.short).prefix(3)) + [v.short]
        var g = SeededRNG(seed: UInt64(abs(v.word.hashValue)))
        o.shuffle(using: &g)
        return o
    }

    private func color(_ k: Int, _ opts: [String], _ v: EssayVocab) -> Color {
        guard let picked else { return Color.primary.opacity(0.06) }
        if opts[k] == v.short { return LearnTheme.good.opacity(0.4) }
        return k == picked ? LearnTheme.bad.opacity(0.4) : Color.primary.opacity(0.04)
    }

    private func advance() {
        i += 1; picked = nil
        if !order.isEmpty { Pronouncer.speak(order[i % order.count].word, uk: false) }
    }
}

struct SeededRNG: RandomNumberGenerator {
    var s: UInt64
    init(seed: UInt64) { s = seed | 1 }
    mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
}

// MARK: Họ từ — chọn dạng từ đúng theo nghĩa + loại từ

private struct FamilyDrill: View {
    let families: [WordFamily]
    @State private var i = 0
    @State private var picked: String?

    private var items: [(FamilyMember, WordFamily)] {
        families.flatMap { f in f.members.map { ($0, f) } }
    }

    var body: some View {
        let list = items
        DrillFrame(index: i, total: list.count, answered: picked != nil, next: { i += 1; picked = nil }) {
            if !list.isEmpty {
                let (m, f) = list[i % list.count]
                Text("Họ từ: \(f.root)").foregroundStyle(.secondary)
                Text("\(m.pos) — \"\(m.meaning)\"").font(.title3.bold())
                FlowLayout(spacing: 10, lineSpacing: 10) {
                    ForEach(f.members.map(\.word), id: \.self) { w in
                        Button { if picked == nil { picked = w; Pronouncer.speak(m.word, uk: false) } } label: {
                            Text(w).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(fill(w, m.word)))
                        }.buttonStyle(.plain).learnHover(scale: 1.05, enabled: picked == nil)
                    }
                }
            }
        }
    }

    private func fill(_ w: String, _ right: String) -> Color {
        guard let picked else { return Color.primary.opacity(0.08) }
        if w == right { return LearnTheme.good.opacity(0.45) }
        return w == picked ? LearnTheme.bad.opacity(0.45) : Color.primary.opacity(0.05)
    }
}

// MARK: Nghe-chép

private struct DictationDrill: View {
    let sentences: [LearnExample]
    @State private var i = 0
    @State private var text = ""
    @State private var result: [TextDiff.Token]?

    var body: some View {
        DrillFrame(index: i, total: sentences.count, answered: result != nil, next: next) {
            if !sentences.isEmpty {
                let s = sentences[i % sentences.count]
                HStack(spacing: 10) {
                    Button { Pronouncer.speak(s.en, uk: false) } label: { Label("Nghe", systemImage: "play.fill") }
                    Button { Pronouncer.speak(s.en, uk: false, rate: 0.32) } label: { Label("Chậm", systemImage: "tortoise.fill") }
                }.controlSize(.large)
                TextField("Gõ lại câu bạn nghe được…", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder).font(.title3)
                    .onSubmit(check)
                Button("Kiểm tra", action: check).buttonStyle(.borderedProminent).disabled(text.isEmpty || result != nil)
                if let result {
                    DiffText(tokens: result)
                    Text(s.vi).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { if let s = sentences.first { Pronouncer.speak(s.en, uk: false) } }
    }

    private func check() {
        guard !sentences.isEmpty else { return }
        result = TextDiff.mark(reference: sentences[i % sentences.count].en, attempt: text)
    }
    private func next() {
        i += 1; text = ""; result = nil
        if !sentences.isEmpty { Pronouncer.speak(sentences[i % sentences.count].en, uk: false) }
    }
}

struct DiffText: View {
    let tokens: [TextDiff.Token]
    var body: some View {
        let pct = tokens.isEmpty ? 0 : tokens.filter(\.ok).count * 100 / tokens.count
        VStack(alignment: .leading, spacing: 6) {
            Text("Đúng \(pct)%").font(.headline).foregroundStyle(pct >= 80 ? LearnTheme.good : LearnTheme.highlight)
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(tokens.indices, id: \.self) { k in
                    Text(tokens[k].text).font(.title3)
                        .foregroundStyle(tokens[k].ok ? LearnTheme.good : LearnTheme.bad)
                        .underline(!tokens[k].ok)
                }
            }
        }
    }
}

// MARK: Dịch câu (VI → EN), AI chấm

private struct TranslateDrill: View {
    let sentences: [LearnExample]
    @State private var i = 0
    @State private var text = ""
    @State private var grade: TranslationGrade?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        DrillFrame(index: i, total: sentences.count, answered: grade != nil, next: { i += 1; text = ""; grade = nil; error = nil }) {
            if !sentences.isEmpty {
                let s = sentences[i % sentences.count]
                Text(s.vi).font(.title3.bold())
                TextField("Dịch sang tiếng Anh…", text: $text, axis: .vertical).textFieldStyle(.roundedBorder).font(.title3)
                HStack {
                    Button { Task { await check(s) } } label: {
                        HStack { if busy { ProgressView().controlSize(.small) }; Text("Chấm bằng AI") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty || busy || grade != nil || !ClaudeCLI.isAvailable)
                    Button("Xem đáp án") { grade = TranslationGrade(score: -1, corrected: s.en, feedback: "") }
                }
                if let error { Text(error).font(.caption).foregroundStyle(LearnTheme.bad) }
                if let g = grade {
                    if g.score >= 0 {
                        Text("\(g.score)/10").font(.title.bold()).foregroundStyle(g.score >= 7 ? LearnTheme.good : LearnTheme.highlight)
                        Text(g.feedback)
                        Label(g.corrected, systemImage: "pencil").foregroundStyle(LearnTheme.good)
                    }
                    Text("Bản gốc: \(s.en)").italic().foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor private func check(_ s: LearnExample) async {
        busy = true; error = nil
        do {
            grade = try await ClaudeCLI.json(TranslationGrade.self, system: LearnAI.system,
                                             prompt: LearnAI.gradeTranslation(vi: s.vi, reference: s.en, answer: text))
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}

// MARK: Đọc to — nhận dạng giọng nói

private struct SpeakDrill: View {
    let sentences: [LearnExample]
    @StateObject private var rec = SpeechRecorder()
    @State private var i = 0
    @State private var result: [TextDiff.Token]?

    var body: some View {
        DrillFrame(index: i, total: sentences.count, answered: result != nil, next: { i += 1; result = nil; rec.transcript = "" }) {
            if !sentences.isEmpty {
                let s = sentences[i % sentences.count]
                Text(s.en).font(.title2.weight(.semibold))
                Text(s.vi).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { Pronouncer.speak(s.en, uk: false) } label: { Label("Nghe mẫu", systemImage: "speaker.wave.2") }
                    Button {
                        if rec.recording {
                            rec.stop()
                            result = TextDiff.mark(reference: s.en, attempt: rec.transcript)
                        } else {
                            result = nil; rec.start()
                        }
                    } label: {
                        Label(rec.recording ? "Dừng & chấm" : "Bắt đầu đọc", systemImage: rec.recording ? "stop.circle.fill" : "mic.fill")
                    }
                    .buttonStyle(.borderedProminent).tint(rec.recording ? LearnTheme.bad : .accentColor)
                }.controlSize(.large)
                if !rec.transcript.isEmpty { Text("Nghe được: \(rec.transcript)").foregroundStyle(.secondary) }
                if let e = rec.error { Text(e).font(.caption).foregroundStyle(LearnTheme.bad) }
                if let result { DiffText(tokens: result) }
            }
        }
        .onDisappear { rec.stop() }
    }
}

final class SpeechRecorder: ObservableObject {
    @Published var recording = false
    @Published var transcript = ""
    @Published var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        error = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.error = "Chưa cấp quyền Nhận dạng giọng nói (System Settings → Privacy & Security)."
                    return
                }
                self.begin()
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else { error = "Nhận dạng giọng nói không khả dụng."; return }
        transcript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in
            req.append(buf)
        }
        do { engine.prepare(); try engine.start() } catch { self.error = "Không mở được micro: \(error.localizedDescription)"; return }
        recording = true
        task = recognizer.recognitionTask(with: req) { [weak self] res, _ in
            guard let self, let res else { return }
            DispatchQueue.main.async { self.transcript = res.bestTranscription.formattedString }
        }
    }

    func stop() {
        guard recording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        recording = false
    }
}
