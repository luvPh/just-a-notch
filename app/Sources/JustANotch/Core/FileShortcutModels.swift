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

/// Mục "Truy cập nhanh" (favorite) hiển thị ở tab Files dạng nhỏ.
/// - Là file: giữ bookmark để mở trực tiếp.
/// - Là catalogue: giữ đường dẫn để bấm vào là tự expand + nhảy tới.
struct Favorite: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var isCatalogue: Bool
    var cataloguePath: [UUID]? = nil   // khi là catalogue (folder ảo trong app)
    var bookmark: Data? = nil          // khi là file/folder thật
    var isDirectory: Bool = false      // true = folder thật (cam), false = file (xanh)
}

extension Favorite {
    private enum CodingKeys: String, CodingKey {
        case id, name, isCatalogue, cataloguePath, bookmark, isDirectory
    }
    /// Decode khoan dung: key thiếu (dữ liệu lưu từ bản cũ) dùng giá trị mặc định,
    /// tránh làm hỏng cả file khi thêm field mới. (init(from:) đặt trong extension
    /// để vẫn giữ memberwise init tự sinh.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        isCatalogue = try c.decodeIfPresent(Bool.self, forKey: .isCatalogue) ?? false
        cataloguePath = try c.decodeIfPresent([UUID].self, forKey: .cataloguePath)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        isDirectory = try c.decodeIfPresent(Bool.self, forKey: .isDirectory) ?? false
    }
}

/// Bọc dữ liệu bền của tab Files (root + favorites) để lưu JSON.
struct FileStoreData: Codable {
    var root: Catalogue
    var favorites: [Favorite] = []
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

    mutating func rename(fileId: UUID, atParentPath path: [UUID], to newName: String) {
        update(atPath: path) { parent in
            if let idx = parent.files.firstIndex(where: { $0.id == fileId }) {
                parent.files[idx].name = newName
            }
        }
    }
}
