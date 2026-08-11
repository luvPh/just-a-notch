import Foundation
import Combine
import AppKit

/// Giữ cây shortcut và lưu bền ra JSON. UI quan sát `root`.
final class FileShortcutStore: ObservableObject {
    @Published var root: Catalogue
    /// Mục Truy cập nhanh (favorites) hiển thị ở tab Files dạng nhỏ.
    @Published var favorites: [Favorite] = []
    /// Vị trí catalogue đang duyệt (id từ root xuống). Giữ ở đây để không bị
    /// reset về Home mỗi khi panel Files được dựng lại (đóng/mở notch, đổi tab).
    @Published var browsePath: [UUID] = []
    private let fileURL: URL

    /// Đường dẫn mặc định: ~/Library/Application Support/Just a Notch/shortcuts.json
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("shortcuts.json")
    }

    init(fileURL: URL = FileShortcutStore.defaultURL) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        if let data, let bundle = try? JSONDecoder().decode(FileStoreData.self, from: data) {
            self.root = bundle.root
            self.favorites = bundle.favorites
        } else if let data, let legacy = try? JSONDecoder().decode(Catalogue.self, from: data) {
            // Định dạng cũ chỉ có root — nạp và giữ favorites rỗng.
            self.root = legacy
        } else {
            self.root = Catalogue(name: "")
        }
    }

    func save() {
        let bundle = FileStoreData(root: root, favorites: favorites)
        guard let data = try? JSONEncoder().encode(bundle) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension FileShortcutStore {
    func addCatalogue(named name: String, atPath path: [UUID]) {
        root.insert(child: Catalogue(name: name), atPath: path)
        save()
    }

    func deleteCatalogue(id: UUID, atParentPath path: [UUID]) {
        root.removeCatalogue(id: id, atParentPath: path)
        save()
    }

    func renameCatalogue(id: UUID, atParentPath path: [UUID], to newName: String) {
        root.rename(catalogueId: id, atParentPath: path, to: newName)
        save()
    }

    func deleteFile(id: UUID, atParentPath path: [UUID]) {
        root.removeFile(id: id, atParentPath: path)
        save()
    }
}

extension FileShortcutStore {
    /// Tra cứu file / catalogue theo id + đường dẫn cha.
    func file(id: UUID, atParentPath path: [UUID]) -> FileShortcut? {
        root.node(atPath: path)?.files.first { $0.id == id }
    }
    func catalogue(id: UUID, atParentPath path: [UUID]) -> Catalogue? {
        root.node(atPath: path)?.children.first { $0.id == id }
    }

    /// Di chuyển file sang catalogue khác (không tự save — gọi save() sau khi xong lô).
    func moveFile(id: UUID, from src: [UUID], to dest: [UUID]) {
        guard src != dest, let f = file(id: id, atParentPath: src) else { return }
        root.removeFile(id: id, atParentPath: src)
        root.insert(file: f, atPath: dest)
    }

    /// Di chuyển catalogue (kèm toàn bộ nội dung). Bỏ qua nếu chuyển vào chính nó
    /// hoặc vào một hậu duệ của nó (sẽ tạo vòng lặp).
    func moveCatalogue(id: UUID, from src: [UUID], to dest: [UUID]) {
        guard src != dest else { return }
        let selfPath = src + [id]
        if dest.count >= selfPath.count && Array(dest.prefix(selfPath.count)) == selfPath { return }
        guard let c = catalogue(id: id, atParentPath: src) else { return }
        root.removeCatalogue(id: id, atParentPath: src)
        root.insert(child: c, atPath: dest)
    }
}

extension FileShortcutStore {
    func addFavoriteCatalogue(path: [UUID], name: String) {
        guard !favorites.contains(where: { $0.isCatalogue && $0.cataloguePath == path }) else { return }
        favorites.append(Favorite(name: name, isCatalogue: true, cataloguePath: path))
        save()
    }

    func addFavoriteFile(_ file: FileShortcut) {
        guard !favorites.contains(where: { !$0.isCatalogue && $0.bookmark == file.bookmark }) else { return }
        let isDir = resolveURL(for: file).resolved?.hasDirectoryPath ?? false
        favorites.append(Favorite(name: file.name, isCatalogue: false, bookmark: file.bookmark, isDirectory: isDir))
        save()
    }

    func removeFavorite(id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    /// Ghim thẳng một URL (file/folder thả từ Finder) vào Truy cập nhanh.
    func addFavoriteURL(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
        ) else { return }
        guard !favorites.contains(where: { !$0.isCatalogue && $0.bookmark == bookmark }) else { return }
        favorites.append(Favorite(name: url.lastPathComponent, isCatalogue: false,
                                  bookmark: bookmark, isDirectory: url.hasDirectoryPath))
        save()
    }

    /// Mở favorite dạng file (giải bookmark rồi mở app mặc định).
    @discardableResult
    func openFavoriteFile(_ fav: Favorite) -> Bool {
        guard let bookmark = fav.bookmark else { return false }
        return open(FileShortcut(name: fav.name, bookmark: bookmark))
    }
}

extension FileShortcutStore {
    /// Kết quả resolve một bookmark.
    struct Resolved {
        var resolved: URL?      // nil nếu không tạo được URL
        var isMissing: Bool     // true nếu file không còn tồn tại / bookmark hỏng
    }

    func addFile(url: URL, atPath path: [UUID]) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
        ) else { return }
        root.insert(file: FileShortcut(name: url.lastPathComponent, bookmark: bookmark), atPath: path)
        save()
    }

    /// Resolve bookmark → URL; đánh dấu missing nếu hỏng hoặc file không tồn tại.
    func resolveURL(for file: FileShortcut) -> Resolved {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: file.bookmark,
            options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale
        ) else {
            return Resolved(resolved: nil, isMissing: true)
        }
        let exists = FileManager.default.fileExists(atPath: url.path)
        return Resolved(resolved: url, isMissing: !exists)
    }

    /// Mở file bằng app mặc định. Trả về false nếu file không mở được.
    @discardableResult
    func open(_ file: FileShortcut) -> Bool {
        let r = resolveURL(for: file)
        guard let url = r.resolved, !r.isMissing else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return NSWorkspace.shared.open(url)
    }
}
