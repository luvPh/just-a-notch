import Foundation

/// Lưu/đọc các chuỗi timer tự tạo (tối đa 5) qua UserDefaults (JSON).
final class SequenceStore: ObservableObject {
    @Published private(set) var all: [TimerSequence] = []
    private let d: UserDefaults
    private let key = "cfg.timerSequences"
    static let maxCount = 5

    init(defaults: UserDefaults = .standard) {
        self.d = defaults
        if let data = d.data(forKey: key),
           let arr = try? JSONDecoder().decode([TimerSequence].self, from: data) {
            all = arr
        }
    }

    var isFull: Bool { all.count >= Self.maxCount }

    func save(_ seq: TimerSequence) {
        if let i = all.firstIndex(where: { $0.id == seq.id }) {
            all[i] = seq
        } else if all.count < Self.maxCount {
            all.append(seq)
        }
        persist()
    }

    func delete(_ id: UUID) {
        all.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(all) { d.set(data, forKey: key) }
    }
}
