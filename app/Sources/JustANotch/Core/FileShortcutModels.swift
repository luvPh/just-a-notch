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

extension Catalogue {
    /// Chỉnh sửa node tại `path` (rỗng = self) qua closure.
    mutating func update(atPath path: [UUID], _ body: (inout Catalogue) -> Void) {
        guard let first = path.first else { body(&self); return }
        guard let idx = children.firstIndex(where: { $0.id == first }) else { return }
        children[idx].update(atPath: Array(path.dropFirst()), body)
    }

    mutating func insert(child: Catalogue, atPath path: [UUID]) {
        update(atPath: path) { $0.children.append(child) }
    }

    mutating func insert(file: FileShortcut, atPath path: [UUID]) {
        update(atPath: path) { $0.files.append(file) }
    }

    mutating func removeCatalogue(id: UUID, atParentPath path: [UUID]) {
        update(atPath: path) { $0.children.removeAll { $0.id == id } }
    }

    mutating func removeFile(id: UUID, atParentPath path: [UUID]) {
        update(atPath: path) { $0.files.removeAll { $0.id == id } }
    }

    mutating func rename(catalogueId: UUID, atParentPath path: [UUID], to newName: String) {
        update(atPath: path) { parent in
            if let idx = parent.children.firstIndex(where: { $0.id == catalogueId }) {
                parent.children[idx].name = newName
            }
        }
    }
}
