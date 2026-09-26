import SwiftUI

/// Kho từ: tìm kiếm, lọc level, xem mục từ, tạo thêm từ bằng AI.
struct LibraryView: View {
    @ObservedObject var store: LearnStore
    @State private var query = ""
    @State private var level = "Tất cả"
    @State private var filter = Filter.all
    @State private var selection: String?
    @State private var showGen = false

    enum Filter: String, CaseIterable { case all = "Tất cả", new = "Chưa học", learning = "Đang học", known = "Đã thuộc", ai = "Từ AI" }
    private let levels = ["Tất cả", "A2", "B1", "B2", "C1", "C2"]

    private var filtered: [LearnWord] {
        store.deck.words.filter { w in
            (query.isEmpty || w.headword.localizedCaseInsensitiveContains(query)
                || w.senses.contains { $0.defVI.localizedCaseInsensitiveContains(query) })
            && (level == "Tất cả" || w.senses.contains { $0.level == level })
            && {
                let learned = w.senses.indices.contains { store.review(SenseKey(wordID: w.id, index: $0)) != nil }
                switch filter {
                case .all: return true
                case .new: return !learned
                case .learning: return learned && !store.isKnown(w.id)
                case .known: return store.isKnown(w.id)
                case .ai: return w.source == .ai
                }
            }()
        }
        .sorted { $0.headword.localizedCaseInsensitiveCompare($1.headword) == .orderedAscending }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 8) {
                HStack {
                    TextField("Tìm từ hoặc nghĩa…", text: $query).textFieldStyle(.roundedBorder)
                    Button { showGen = true } label: { Image(systemName: "sparkles") }
                        .help("Tạo thêm từ bằng AI")
                }
                HStack {
                    Picker("", selection: $level) { ForEach(levels, id: \.self) { Text($0) } }.labelsHidden()
                    Picker("", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) } }.labelsHidden()
                }
                let list = filtered
                Text("\(list.count) từ").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                List(list, id: \.id, selection: $selection) { w in
                    HStack {
                        Text(w.headword).fontWeight(.medium)
                        Text(w.pos).font(.caption).italic().foregroundStyle(.secondary)
                        Spacer()
                        Text(w.senses.map(\.level).joined(separator: "·")).font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(w.id)
                    .contentShape(Rectangle())
                    .learnHover(scale: 1.0, brighten: 0.12)
                }
                .listStyle(.plain)
            }
            .padding(12)
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            ScrollView {
                if let id = selection, let w = store.deck.byID[id] {
                    WordEntryView(word: w, store: store).padding(28)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Chọn một từ để xem chi tiết").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 120)
                }
            }
            .frame(minWidth: 380)
        }
        .sheet(isPresented: $showGen) { GenerateWordsSheet(store: store) }
    }
}

struct GenerateWordsSheet: View {
    @ObservedObject var store: LearnStore
    @Environment(\.dismiss) private var dismiss
    @State private var topic = ""
    @State private var level = "B2"
    @State private var count = 15
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tạo thêm từ bằng AI").font(.title3.bold())
            TextField("Chủ đề (vd: business, emotions, travel…) — để trống = tổng hợp", text: $topic)
                .textFieldStyle(.roundedBorder)
            Picker("Trình độ", selection: $level) { ForEach(["B1", "B2", "C1", "C2"], id: \.self) { Text($0) } }
                .pickerStyle(.segmented)
            Stepper("Số từ: \(count)", value: $count, in: 5...40, step: 5)
            if !ClaudeCLI.isAvailable {
                Text(ClaudeCLI.CLIError.notInstalled.localizedDescription).font(.caption).foregroundStyle(LearnTheme.bad)
            }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Đóng") { dismiss() }
                Button {
                    Task { await generate() }
                } label: {
                    if busy { ProgressView().controlSize(.small) } else { Text("Tạo") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !ClaudeCLI.isAvailable)
            }
        }
        .padding(22).frame(width: 440)
    }

    @MainActor private func generate() async {
        busy = true; message = "Đang tạo… (có thể mất 30–90 giây)"
        do {
            let words = try await ClaudeCLI.json([LearnWord].self, system: LearnAI.system,
                prompt: LearnAI.wordBatch(topic: topic, level: level, count: count,
                                          exclude: store.deck.words.map(\.headword).shuffled()))
            let n = store.addWords(words)
            message = "Đã thêm \(n) từ mới vào kho (\(words.count - n) từ trùng bị bỏ qua)."
        } catch {
            message = error.localizedDescription
        }
        busy = false
    }
}
