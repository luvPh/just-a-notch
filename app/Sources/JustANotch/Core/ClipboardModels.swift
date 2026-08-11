import Foundation

/// Nội dung một mục clipboard. Ảnh KHÔNG nhét vào JSON — chỉ giữ tên file PNG
/// nằm trong .../Just a Notch/Clipboard/<uuid>.png.
enum ClipboardItemKind: Codable, Equatable {
    case text(String)
    case image(fileName: String)
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var pinned: Bool
    var kind: ClipboardItemKind

    /// Text để so trùng / hiển thị; ảnh trả về "" (so trùng ảnh dùng fileName).
    var plainText: String {
        if case let .text(s) = kind { return s }
        return ""
    }

    /// Khoá so trùng: text theo nội dung, ảnh theo tên file.
    var dedupeKey: String {
        switch kind {
        case let .text(s):            return "t:" + s
        case let .image(fileName):    return "i:" + fileName
        }
    }
}

/// Lõi thuần (không phụ thuộc pasteboard/timer) cho lịch sử clipboard:
/// chèn đầu danh sách, chống trùng mục đầu, cắt giới hạn mục chưa ghim.
struct ClipboardHistory {
    private(set) var items: [ClipboardItem] = []
    let unpinnedLimit: Int

    init(unpinnedLimit: Int, items: [ClipboardItem] = []) {
        self.unpinnedLimit = unpinnedLimit
        self.items = items
    }

    /// Thêm mục mới. Trả về danh sách mục bị đẩy ra (để caller dọn file PNG).
    @discardableResult
    mutating func record(_ item: ClipboardItem) -> [ClipboardItem] {
        if let first = items.first, first.dedupeKey == item.dedupeKey {
            return []                       // trùng mục đầu → bỏ qua
        }
        items.insert(item, at: 0)
        return trim()
    }

    mutating func togglePin(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].pinned.toggle()
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> ClipboardItem? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i)
    }

    /// Xoá tất cả mục CHƯA ghim. Trả về các mục bị xoá (để dọn file).
    @discardableResult
    mutating func clearUnpinned() -> [ClipboardItem] {
        let removed = items.filter { !$0.pinned }
        items.removeAll { !$0.pinned }
        return removed
    }

    /// Giữ tối đa `unpinnedLimit` mục chưa ghim; pinned không tính vào giới hạn.
    private mutating func trim() -> [ClipboardItem] {
        var unpinnedSeen = 0
        var removed: [ClipboardItem] = []
        items = items.filter { item in
            if item.pinned { return true }
            unpinnedSeen += 1
            if unpinnedSeen > unpinnedLimit { removed.append(item); return false }
            return true
        }
        return removed
    }
}
