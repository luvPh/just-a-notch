import SwiftUI

// MARK: - Danh sách + tạo essay

struct EssayHomeView: View {
    @ObservedObject var store: LearnStore
    @State private var selection: UUID?
    @State private var topic = ""
    @State private var level = 3
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tạo essay").font(.headline)
                HStack(spacing: 6) {
                    TextField("Chủ đề — để trống = chọn ngẫu nhiên", text: $topic).textFieldStyle(.roundedBorder)
                    Button { topic = store.nextEssayTopic() } label: { Image(systemName: "dice.fill") }
                        .help("Gợi ý chủ đề ngẫu nhiên (\(store.topics.count) chủ đề)")
                }
                Picker("Độ khó", selection: $level) {
                    ForEach(1...5, id: \.self) { Text("\($0)") }
                }.pickerStyle(.segmented)
                Text("Tối thiểu \(LearnAI.essayMinWords[level] ?? 300) từ").font(.caption).foregroundStyle(.secondary)
                Button { Task { await generate() } } label: {
                    HStack { if busy { ProgressView().controlSize(.small) }; Text(busy ? "Đang viết…" : "Tạo essay") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !ClaudeCLI.isAvailable)
                if !ClaudeCLI.isAvailable {
                    Text(ClaudeCLI.CLIError.notInstalled.localizedDescription).font(.caption).foregroundStyle(LearnTheme.bad)
                }
                if let error { Text(error).font(.caption).foregroundStyle(LearnTheme.bad) }
                Divider()
                Text("Thư viện (\(store.essays.count))").font(.headline)
                List(store.essays, selection: $selection) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title.isEmpty ? e.topic : e.title).lineLimit(2)
                        Text("\(e.topic) · độ khó \(e.level) · \(e.createdAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(e.id)
                    .contentShape(Rectangle())
                    .learnHover(scale: 1.0, brighten: 0.12)
                    .contextMenu { Button("Xoá", role: .destructive) { store.deleteEssay(e.id) } }
                }
                .listStyle(.plain)
            }
            .padding(12)
            .frame(minWidth: 240, idealWidth: 270, maxWidth: 340)

            Group {
                if let id = selection, let e = store.essays.first(where: { $0.id == id }) {
                    EssayDetailView(store: store, essay: e).id(e.id)
                } else {
                    Text("Tạo hoặc chọn một essay").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 460)
        }
    }

    @MainActor private func generate() async {
        busy = true; error = nil
        if topic.trimmingCharacters(in: .whitespaces).isEmpty { topic = store.nextEssayTopic() }
        struct Raw: Decodable {
            var title: String?; var essay: String; var sentences: [LearnExample]?
            var vocab: [EssayVocab]?; var families: [WordFamily]?
        }
        do {
            let r = try await ClaudeCLI.json(Raw.self, system: LearnAI.system, prompt: LearnAI.essay(topic: topic, level: level))
            let e = Essay(topic: topic, level: level, title: r.title ?? topic, essay: r.essay,
                          sentences: r.sentences ?? [], vocab: r.vocab ?? [], families: r.families ?? [])
            store.addEssay(e)
            selection = e.id
            topic = ""
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}

// MARK: - Chi tiết essay

struct EssayDetailView: View {
    @ObservedObject var store: LearnStore
    let essay: Essay
    @State private var tab = Tab.read

    enum Tab: String, CaseIterable { case read = "Bài đọc", vocab = "Từ vựng", family = "Họ từ", practice = "Luyện tập" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) } }
                .pickerStyle(.segmented).labelsHidden().padding(12)
            Divider()
            switch tab {
            case .read:     EssayReader(store: store, essay: essay)
            case .vocab:    EssayVocabList(store: store, essay: essay)
            case .family:   FamilyView(essay: essay)
            case .practice: EssayPracticeView(store: store, essay: essay)
            }
        }
    }
}

// MARK: Bài đọc — bấm từ để tra theo ngữ cảnh

private struct EssayToken: Identifiable {
    let id: Int
    let text: String
    let sentence: String
}

struct EssayReader: View {
    @ObservedObject var store: LearnStore
    let essay: Essay
    @State private var lookupToken: Int?

    private var paragraphs: [[EssayToken]] {
        var id = 0
        return essay.essay.components(separatedBy: "\n\n").map { para in
            splitSentences(para).flatMap { sentence in
                sentence.split(separator: " ").map { w -> EssayToken in
                    defer { id += 1 }
                    return EssayToken(id: id, text: String(w), sentence: sentence)
                }
            }
        }
    }

    private func splitSentences(_ p: String) -> [String] {
        var out: [String] = []
        p.enumerateSubstrings(in: p.startIndex..., options: .bySentences) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { out.append(s) }
        }
        return out.isEmpty ? [p] : out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(essay.title).font(.title2.bold())
                    Spacer()
                    Button { Pronouncer.speak(essay.essay.replacingOccurrences(of: "\n\n", with: " "), uk: false) } label: {
                        Label("Nghe cả bài", systemImage: "speaker.wave.2")
                    }
                    Button { Pronouncer.stop() } label: { Image(systemName: "stop.fill") }
                }
                Text("\(TextDiff.words(essay.essay).count) từ · bấm vào từ bất kỳ để tra nghĩa theo ngữ cảnh")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, tokens in
                    FlowLayout(spacing: 4, lineSpacing: 6) {
                        ForEach(tokens) { t in
                            Text(t.text)
                                .font(.system(size: 16))
                                .padding(.horizontal, 1)
                                .background(RoundedRectangle(cornerRadius: 3)
                                    .fill(isVocab(t.text) ? LearnTheme.accent.opacity(0.25) : .clear))
                                .learnHover(scale: 1.0, brighten: 0.25)
                                .onTapGesture { lookupToken = t.id }
                                .popover(isPresented: Binding(get: { lookupToken == t.id },
                                                              set: { if !$0 { lookupToken = nil } })) {
                                    LookupPopover(store: store, word: clean(t.text), sentence: t.sentence)
                                }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func clean(_ w: String) -> String {
        w.trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).inverted)
    }
    private func isVocab(_ w: String) -> Bool {
        let c = clean(w).lowercased()
        return essay.vocab.contains { c.hasPrefix($0.word.lowercased()) }
    }
}

struct LookupPopover: View {
    @ObservedObject var store: LearnStore
    let word: String
    let sentence: String
    @State private var result: WordLookup?
    @State private var error: String?
    @State private var added = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let r = result {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(r.lemma).font(.title3.bold())
                    Text(r.pos).italic().foregroundStyle(LearnTheme.purple)
                    Text("(\(r.guideword))").font(.caption).foregroundStyle(LearnTheme.purple)
                    LevelBadge(level: r.level)
                }
                HStack(spacing: 12) {
                    Button { Pronouncer.speak(r.lemma, uk: true) } label: { Text("UK \(r.ipaUK)") }
                    Button { Pronouncer.speak(r.lemma, uk: false) } label: { Text("US \(r.ipaUS)") }
                }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                Text(r.defEN).fontWeight(.semibold)
                Text(r.defVI).foregroundStyle(LearnTheme.highlight)
                Text("• " + r.example.en).italic().font(.callout)
                Text(r.example.vi).font(.caption).foregroundStyle(.secondary)
                Button {
                    added = store.addWords([r.asWord]) > 0 || store.contains(headword: r.lemma)
                } label: {
                    Label(added ? "Đã có trong kho" : "Thêm vào kho ôn", systemImage: added ? "checkmark" : "plus")
                }
                .disabled(added)
            } else if let error {
                Text(error).foregroundStyle(LearnTheme.bad).font(.caption)
            } else {
                HStack { ProgressView().controlSize(.small); Text("Đang tra \"\(word)\"…") }
            }
        }
        .padding(14)
        .frame(width: 320)
        .task {
            added = store.contains(headword: word)
            do {
                result = try await ClaudeCLI.json(WordLookup.self, system: LearnAI.system,
                                                  prompt: LearnAI.lookup(word: word, sentence: sentence))
                if let r = result { added = store.contains(headword: r.lemma) }
            } catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: Từ vựng

struct EssayVocabList: View {
    @ObservedObject var store: LearnStore
    let essay: Essay

    var body: some View {
        List {
            ForEach(essay.vocab) { v in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(v.word).font(.headline)
                        Text(v.pos).italic().foregroundStyle(LearnTheme.purple)
                        Button { Pronouncer.speak(v.word, uk: false) } label: { Text(v.ipaUS) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                        LevelBadge(level: v.level)
                        Text("— \(v.short)").foregroundStyle(LearnTheme.highlight)
                        Spacer()
                        Button {
                            var e = essay; e.vocab.removeAll { $0.id == v.id }
                            store.updateEssay(e)
                            store.markKnown(v.asWord.id)
                        } label: { Image(systemName: "checkmark.circle") }
                        .buttonStyle(.borderless).help("Đã biết — bỏ khỏi danh sách và kho ôn")
                        .learnHover(scale: 1.15, brighten: 0.25)
                    }
                    Text(v.defVI)
                    Text("• " + v.example.en).italic().font(.callout)
                    Text(v.example.vi).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .overlay { if essay.vocab.isEmpty { Text("Không còn từ nào").foregroundStyle(.secondary) } }
    }
}

// MARK: Họ từ

struct FamilyView: View {
    let essay: Essay
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(essay.families.indices, id: \.self) { i in
                    let f = essay.families[i]
                    VStack(alignment: .leading, spacing: 10) {
                        Text(f.root).font(.title3.bold())
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(LearnTheme.purple.opacity(0.3)))
                        FlowLayout(spacing: 10, lineSpacing: 10) {
                            ForEach(f.members.indices, id: \.self) { j in
                                let m = f.members[j]
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(m.word).fontWeight(.semibold)
                                        Button { Pronouncer.speak(m.word, uk: false) } label: {
                                            Image(systemName: "speaker.wave.1").font(.caption)
                                        }.buttonStyle(.plain)
                                    }
                                    Text(m.pos).font(.caption).italic().foregroundStyle(LearnTheme.purple)
                                    Text(m.meaning).font(.caption).foregroundStyle(LearnTheme.highlight)
                                }
                                .padding(10)
                                .learnCard(10)
                                .learnHover(scale: 1.03)
                            }
                        }
                        .padding(.leading, 24)
                    }
                }
                if essay.families.isEmpty { Text("Essay này chưa có họ từ.").foregroundStyle(.secondary) }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in rows.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var pts: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + lineSpacing; rowH = 0 }
            pts.append(CGPoint(x: x, y: y))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            maxW = max(maxW, x - spacing)
        }
        return (pts, maxW, y + rowH)
    }
}
