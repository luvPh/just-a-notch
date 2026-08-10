import Foundation
import Combine
import AppKit

/// Giữ cây shortcut và lưu bền ra JSON. UI quan sát `root`.
final class FileShortcutStore: ObservableObject {
    @Published var root: Catalogue
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
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Catalogue.self, from: data) {
            self.root = decoded
        } else {
            self.root = Catalogue(name: "")
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(root) else { return }
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
