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
    /// Bundle ID app đang active lúc copy (nil với dữ liệu cũ).
    var sourceApp: String? = nil

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

/// Loại hiển thị của một mục — dùng cho chip lọc và bộ lọc `@` trong ô tìm kiếm.
enum ClipboardCategory: String, CaseIterable {
    case link, color, code, text, image

    var label: String {
        switch self {
        case .link: "Link"; case .color: "Màu"; case .code: "Code"
        case .text: "Text"; case .image: "Ảnh"
        }
    }
    var symbol: String {
        switch self {
        case .link: "link"; case .color: "paintpalette"; case .code: "curlybraces"
        case .text: "text.alignleft"; case .image: "photo"
        }
    }
    /// Các từ khoá `@` được chấp nhận (khớp theo tiền tố).
    var tokens: [String] {
        switch self {
        case .link: ["link", "url"]; case .color: ["color", "mau"]
        case .code: ["code"]; case .text: ["text"]; case .image: ["image", "img", "anh"]
        }
    }

    static func of(_ item: ClipboardItem) -> ClipboardCategory {
        guard case let .text(raw) = item.kind else { return .image }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if ClipboardColor.parse(s) != nil { return .color }
        if !s.contains(" "), !s.contains("\n"),
           let u = URL(string: s), let sc = u.scheme?.lowercased(),
           ["http", "https"].contains(sc), u.host != nil { return .link }
        let codeHints = ["{", "};", "=>", "func ", "const ", "let ", "def ", "import ",
                         "return ", "</", "()", "#include", "class "]
        let hits = codeHints.filter { s.contains($0) }.count
        if hits >= 2 || (s.contains("\n") && hits >= 1) { return .code }
        return .text
    }
}

/// Nhận diện chuỗi màu hex (#RRGGBB / #RGB / #RRGGBBAA). Trả RGB 0...1.
enum ClipboardColor {
    static func parse(_ s: String) -> (r: Double, g: Double, b: Double)? {
        guard s.hasPrefix("#") else { return nil }
        var h = String(s.dropFirst())
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h.prefix(6), radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

/// Lọc danh sách theo chip + truy vấn. Truy vấn có thể chứa `@token`
/// (vd "@link github") — token ép loại, phần còn lại so khớp nội dung.
enum ClipboardFilter {
    enum Chip: Hashable { case all, pinned, category(ClipboardCategory) }

    static func apply(_ items: [ClipboardItem], chip: Chip, query: String) -> [ClipboardItem] {
        var forced: ClipboardCategory?
        var words: [String] = []
        for w in query.lowercased().split(separator: " ") {
            if w.hasPrefix("@") {
                let t = w.dropFirst()
                if !t.isEmpty, let c = ClipboardCategory.allCases.first(where: { $0.tokens.contains { $0.hasPrefix(t) } }) {
                    forced = c
                }
            } else { words.append(String(w)) }
        }
        return items.filter { item in
            switch chip {
            case .all: break
            case .pinned: if !item.pinned { return false }
            case let .category(c): if ClipboardCategory.of(item) != c { return false }
            }
            if let f = forced, ClipboardCategory.of(item) != f { return false }
            let hay = item.plainText.lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }
}
