import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

/// Một mục đang được "giữ tạm" trên shelf. `url` trỏ tới bản COPY trong thư mục
/// temp của phiên — nên kéo RA là file thật, thả vào đâu cũng được.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
}

/// Kệ giữ tạm file kéo-thả (kiểu Dropover/Yoink).
///
/// - CHỈ trong phiên: mọi file được copy vào một thư mục temp riêng; xoá sạch khi
///   khởi động (dọn rác phiên cũ) và khi thoát app. Không sống sót qua restart.
/// - Kéo RA: mỗi tile cung cấp `NSItemProvider` bọc URL bản copy → file thật.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    /// Thư mục chứa các bản copy của phiên hiện tại.
    private let sessionDir: URL

    init() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("JustANotchShelf", isDirectory: true)
        sessionDir = base
        // Dọn rác phiên trước (nếu app tắt đột ngột) rồi tạo mới sạch.
        try? FileManager.default.removeItem(at: base)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    /// Copy một file/folder vào temp rồi thêm vào shelf. Trả về true nếu thành công.
    @discardableResult
    func add(url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            ?? url.hasDirectoryPath
        // Mỗi mục một thư mục con riêng để tránh trùng tên đè nhau.
        let holder = sessionDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dest = holder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: holder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: holder)
            return false
        }
        items.append(ShelfItem(url: dest, name: url.lastPathComponent, isDirectory: isDir))
        return true
    }

    /// Xoá một mục khỏi shelf (kèm bản copy trong temp).
    func remove(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        // Xoá cả thư mục holder chứa bản copy.
        try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
    }

    /// Xoá sạch shelf.
    func clear() {
        for item in items {
            try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
        }
        items.removeAll()
    }

    /// Dọn toàn bộ thư mục phiên (gọi khi thoát app).
    func cleanup() {
        items.removeAll()
        try? FileManager.default.removeItem(at: sessionDir)
    }

    /// Provider để kéo RA: ưu tiên file-representation (thả vào ô upload/Finder),
    /// fallback về URL thuần.
    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        if let p = NSItemProvider(contentsOf: item.url) { return p }
        return NSItemProvider(object: item.url as NSURL)
    }
}
