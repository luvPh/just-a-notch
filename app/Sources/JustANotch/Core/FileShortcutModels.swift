import Foundation

struct FileShortcut: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bookmark: Data
}

struct Catalogue: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var children: [Catalogue] = []
    var files: [FileShortcut] = []
}

extension Catalogue {
    /// Trả về node ở cuối `path` (danh sách id từ node hiện tại xuống). Path rỗng = self.
    func node(atPath path: [UUID]) -> Catalogue? {
        guard let first = path.first else { return self }
        guard let child = children.first(where: { $0.id == first }) else { return nil }
        return child.node(atPath: Array(path.dropFirst()))
    }
}
