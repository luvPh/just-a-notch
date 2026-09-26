import SwiftUI

/// Grammar logic-first: thư viện chủ đề + hỏi tự do + bài đã lưu + hỏi thêm.
struct GrammarHomeView: View {
    @ObservedObject var store: LearnStore
    @State private var selection: UUID?
    @State private var query = ""
    @State private var busy: String?
    @State private var error: String?

    static let themes: [(String, [String])] = [
        ("Thì", ["present simple vs present continuous", "present perfect vs past simple", "since vs for",
                 "past perfect", "future: will vs be going to", "present perfect continuous"]),
        ("Mạo từ & danh từ", ["a vs an vs the", "zero article", "countable vs uncountable nouns", "much / many / a lot of"]),
        ("Động từ", ["modal verbs of deduction", "gerund vs infinitive", "used to vs be used to", "phrasal verbs basics"]),
        ("Câu", ["conditionals 0–3", "mixed conditionals", "passive voice", "reported speech",
                 "relative clauses (who/which/that)", "inversion for emphasis"]),
        ("Giới từ & liên từ", ["in / on / at (time & place)", "although vs despite", "so vs such", "wish / if only"]),
    ]

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Hỏi điểm ngữ pháp bất kỳ…", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await explain(query) } }
                    Button { Task { await explain(query) } } label: { Image(systemName: "arrow.up.circle.fill") }
                        .buttonStyle(.plain).disabled(query.isEmpty || busy != nil)
                }
                if let busy { HStack { ProgressView().controlSize(.small); Text("Đang giải thích \"\(busy)\"…").font(.caption) } }
                if let error { Text(error).font(.caption).foregroundStyle(LearnTheme.bad) }
                if !ClaudeCLI.isAvailable {
                    Text(ClaudeCLI.CLIError.notInstalled.localizedDescription).font(.caption).foregroundStyle(LearnTheme.bad)
                }
                List(selection: $selection) {
                    if !store.lessons.isEmpty {
                        Section("Đã học") {
                            ForEach(store.lessons) { l in
                                Text(l.title).tag(l.id)
                                    .contextMenu { Button("Xoá", role: .destructive) { store.deleteLesson(l.id) } }
                            }
                        }
                    }
                    ForEach(Self.themes, id: \.0) { theme in
                        Section(theme.0) {
                            ForEach(theme.1, id: \.self) { point in
                                Button { open(point) } label: {
                                    HStack {
                                        Text(point)
                                        Spacer()
                                        if lesson(for: point) != nil { Image(systemName: "checkmark").foregroundStyle(LearnTheme.good) }
                                    }
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).learnHover(scale: 1.0, brighten: 0.2)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .padding(12)
            .frame(minWidth: 250, idealWidth: 290, maxWidth: 360)

            Group {
                if let id = selection, let l = store.lessons.first(where: { $0.id == id }) {
                    GrammarLessonView(store: store, lesson: l).id(l.id)
                } else {
                    Text("Chọn một chủ đề hoặc hỏi bất kỳ điều gì về ngữ pháp").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 460)
        }
    }

    private func lesson(for point: String) -> GrammarLesson? {
        store.lessons.first { $0.point.caseInsensitiveCompare(point) == .orderedSame }
    }

    private func open(_ point: String) {
        if let l = lesson(for: point) { selection = l.id } else { Task { await explain(point) } }
    }

    @MainActor private func explain(_ point: String) async {
        let p = point.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty, busy == nil else { return }
        busy = p; error = nil
        do {
            var l = try await ClaudeCLI.json(GrammarLesson.self, system: LearnAI.system, prompt: LearnAI.grammar(point: p))
            l.point = p
            store.addLesson(l)
            selection = l.id
            query = ""
        } catch { self.error = error.localizedDescription }
        busy = nil
    }
}

struct GrammarLessonView: View {
    @ObservedObject var store: LearnStore
    let lesson: GrammarLesson
    @State private var picked: Int?
    @State private var question = ""
    @State private var asking = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(lesson.title).font(.largeTitle.bold())
                block("🎯", "Trả lời nhanh") { Text(lesson.oneLine).font(.title3.weight(.semibold)) }
                block("🧠", "Tại sao?") { Text(lesson.logic) }
                if !lesson.vietnamese.isEmpty { block("🇻🇳", "So với tiếng Việt") { Text(lesson.vietnamese) } }
                block("✅", "Ví dụ") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(lesson.examples.indices, id: \.self) { i in
                            let e = lesson.examples[i]
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(e.en).italic()
                                    Button { Pronouncer.speak(e.en, uk: false) } label: { Image(systemName: "speaker.wave.1") }
                                        .buttonStyle(.plain).foregroundStyle(.secondary)
                                }
                                Text(e.vi).font(.callout).foregroundStyle(.secondary)
                                if let w = e.wrong, !w.isEmpty, w != "null" {
                                    Label(w, systemImage: "xmark.circle.fill").font(.callout).foregroundStyle(LearnTheme.bad).strikethrough()
                                }
                            }
                        }
                    }
                }
                if !lesson.traps.isEmpty {
                    block("⚠️", "Bẫy thường gặp") {
                        VStack(alignment: .leading, spacing: 4) { ForEach(lesson.traps, id: \.self) { Text("• " + $0) } }
                    }
                }
                if let qc = lesson.quickCheck { quickCheck(qc) }
                followUps
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    private func block<C: View>(_ icon: String, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(icon) \(title)").font(.headline).foregroundStyle(.secondary)
            content()
        }
    }

    private func quickCheck(_ qc: QuickCheck) -> some View {
        block("🔁", "Kiểm tra nhanh") {
            VStack(alignment: .leading, spacing: 6) {
                Text(qc.q).fontWeight(.medium)
                ForEach(qc.options.indices, id: \.self) { i in
                    Button { if picked == nil { picked = i } } label: {
                        Text(qc.options[i]).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(fill(i, qc.correct)))
                    }.buttonStyle(.plain).learnHover(scale: 1.01, enabled: picked == nil)
                }
                if picked != nil { Text(qc.explain).foregroundStyle(LearnTheme.highlight) }
            }
        }
    }

    private func fill(_ i: Int, _ correct: Int) -> Color {
        guard let picked else { return Color.primary.opacity(0.06) }
        if i == correct { return LearnTheme.good.opacity(0.4) }
        return i == picked ? LearnTheme.bad.opacity(0.4) : Color.primary.opacity(0.04)
    }

    private var followUps: some View {
        block("💬", "Hỏi thêm") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lesson.followUps) { qa in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(qa.q).fontWeight(.semibold)
                        Text(qa.a).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("Vd: sao câu này không dùng past simple?", text: $question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await ask() } }
                    if asking { ProgressView().controlSize(.small) }
                }
                if let error { Text(error).font(.caption).foregroundStyle(LearnTheme.bad) }
            }
        }
    }

    @MainActor private func ask() async {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !asking else { return }
        asking = true; error = nil
        struct A: Decodable { let a: String }
        do {
            let r = try await ClaudeCLI.json(A.self, system: LearnAI.system,
                                             prompt: LearnAI.grammarFollowUp(lesson: lesson, question: q))
            var l = lesson
            l.followUps.append(GrammarQA(q: q, a: r.a))
            store.updateLesson(l)
            question = ""
        } catch { self.error = error.localizedDescription }
        asking = false
    }
}
