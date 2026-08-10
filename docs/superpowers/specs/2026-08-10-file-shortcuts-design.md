# File Shortcuts — Thiết kế

**Ngày:** 2026-08-10
**Branch:** feat/calendar-lunar
**Trạng thái:** Đã duyệt thiết kế, chờ lập implementation plan.

## 1. Mục tiêu

Thêm tab **Files** (📁) vào rail của notch panel, cho phép người dùng:

- Tạo **catalogue lồng nhau** (thư mục ảo, lồng vô hạn cấp).
- Gán **file** vào từng catalogue để mở nhanh bằng app mặc định của macOS.
- Điều hướng **drill-down**: bấm catalogue → sang trang con; có nút Home và Back.

Đây là các shortcut ảo do người dùng tự tổ chức — **không** phản chiếu cây thư mục thật trên đĩa. Một file có thể nằm ở bất kỳ catalogue nào.

## 2. Phạm vi

**Trong phạm vi:**
- Tab Files với điều hướng drill-down (Home / Back).
- Tạo/xoá/đổi tên catalogue con.
- Thêm file (qua `NSOpenPanel`) / xoá file / mở file.
- File thả trực tiếp ở gốc (root) cũng được.
- Panel mặc định nhỏ (150pt), nút expand phóng to (340pt), ghi nhớ trạng thái.
- Nút `+` hover ra 2 nút riêng: 📂 Catalogue và 📄 File.
- Lưu bền vững bằng **security-scoped bookmark**.

**Ngoài phạm vi (YAGNI):**
- Kéo-thả file từ Finder (có thể thêm sau).
- Sắp xếp lại thứ tự (drag reorder).
- Di chuyển file/catalogue giữa các catalogue.
- Icon thật của từng loại file (giai đoạn đầu dùng SF Symbol chung; có thể nâng cấp sau bằng `NSWorkspace.icon(forFile:)`).
- Đồng bộ đa máy.

## 3. Mô hình dữ liệu

```swift
struct Catalogue: Codable, Identifiable {
    var id: UUID
    var name: String
    var children: [Catalogue]     // catalogue con — lồng vô hạn
    var files: [FileShortcut]
}

struct FileShortcut: Codable, Identifiable {
    var id: UUID
    var name: String              // tên hiển thị, mặc định = tên file trên đĩa
    var bookmark: Data            // security-scoped bookmark
}
```

- **Root** là một `Catalogue` (name rỗng, không hiển thị tiêu đề "gốc" — dùng tiêu đề "Shortcuts") chứa các catalogue gốc + file thả trực tiếp ở gốc.
- Toàn bộ cây serialize thành **JSON**, lưu tại:
  `~/Library/Application Support/Just a Notch/shortcuts.json`
  (chọn file JSON thay vì UserDefaults vì bookmark là `Data` có thể lớn).

## 4. Điều hướng

- State điều hướng là một **path stack**: `[UUID]` — danh sách id catalogue từ root đến catalogue đang mở (rỗng = đang ở Home).
- Bấm một catalogue → `push(id)` sang trang con (cross-fade/slide nhẹ theo motion sẵn có).
- Nút **‹ Back** → `pop()` lùi 1 tầng. Mờ (disabled) khi ở Home.
- Nút **⌂ Home** → clear stack về rỗng. Mờ khi đã ở Home.
- Tiêu đề topbar = tên catalogue hiện tại (ở Home hiển thị "Shortcuts").

## 5. Thêm / mở / xoá

- Nút **+** ở topbar: mặc định là 1 nút. Khi **hover**, morph tách thành 2 nút:
  - **📂 Catalogue** → hiện ô nhập tên (inline hoặc alert), tạo catalogue con trong catalogue hiện tại.
  - **📄 File** → mở `NSOpenPanel` (cho chọn nhiều file); mỗi file tạo `FileShortcut` với bookmark, thêm vào catalogue hiện tại.
  - Rê chuột ra ngoài → gộp lại thành `+`.
- Bấm vào **hàng file** → resolve bookmark → `NSWorkspace.shared.open(url)`.
- Bấm vào **hàng catalogue** → drill vào (không mở gì).
- **Xoá** (catalogue hoặc file): cử chỉ phụ — context menu (right-click) hoặc nút xoá khi hover hàng. Xoá catalogue xoá cả nhánh con (có xác nhận).

## 6. Panel size / expand

- Mặc định tab Files: **380 × 150pt** (giống `expandedHeight`).
- Nút **⤢** → phóng to **380 × 340pt** (dùng `listExpandedHeight` sẵn có, hoặc hằng riêng `filesExpandedHeight`). Nút đổi thành **⤡** để thu lại.
- Trạng thái expand ghi nhớ giữa các lần mở (lưu vào UserDefaults).
- List cuộn **ẩn scrollbar** (giống ThemeCarousel — không dùng scrollbar hệ thống), **không** dòng gợi ý "cuộn để xem thêm".
- Tên dài cắt bằng truncation `…`, không xuống dòng.

## 7. Kiến trúc code

Theo đúng pattern Calendar/Notification hiện có.

| File | Trách nhiệm |
|------|-------------|
| `Core/FileShortcutModels.swift` | struct `Catalogue`, `FileShortcut` (Codable) + helper tìm/thêm/xoá node theo path. |
| `Core/FileShortcutStore.swift` | `ObservableObject`: load/save JSON; CRUD catalogue & file; tạo/resolve/refresh bookmark; mở file qua `NSWorkspace`. |
| `UI/FilesPanel.swift` | View chính: topbar (Home/Back/title/+/⤢) + list hàng; giữ state path stack, hover-add, expand. |
| `NotchViewModel.swift` | Giữ instance `FileShortcutStore`; thêm state chiều cao Files (mặc định 150 / expand 340) — mở rộng logic `surfaceHeight`. |
| `NotchRootView.swift` | Route `case .files:` sang `FilesPanel` (thay `placeholderPanel`). |

**Ghi chú theo code thật:**
- `RailTab.files` đã tồn tại (icon `folder.fill`, title "Files"); hiện rơi vào `placeholderPanel`. Chỉ cần thêm `case .files: filesPanel` trong `content` switch (NotchRootView.swift:188).
- Chiều cao panel do `NotchViewModel.surfaceHeight` quyết định. Hiện chỉ calendar dùng `panelWantsTall`. Files cần cơ chế cao riêng — thêm biến (ví dụ `filesExpanded: Bool`) và mở rộng `surfaceHeight` + `maxSurfaceHeight` để bao gồm 340pt cho Files.
- Motion/spring dùng lại `openSpring` sẵn có để đồng nhất.

Mỗi unit một trách nhiệm: `FileShortcutStore` test được độc lập với UI.

## 8. Xử lý lỗi & edge case

- **Bookmark stale** (file bị di chuyển/xoá): hàng file hiển thị mờ + icon ⚠️; bấm vào báo "File không còn ở vị trí cũ" và cho phép xoá shortcut. Khi resolve, nếu `isStale == true` nhưng URL vẫn hợp lệ thì tự tạo lại bookmark và lưu.
- **Trùng tên catalogue:** cho phép (phân biệt bằng `id`).
- **JSON hỏng / không đọc được:** khởi tạo cây rỗng, không crash; log cảnh báo.
- **Ghi file thất bại:** giữ state trong bộ nhớ, thử lại lần lưu sau; không crash.
- **Panel hẹp:** tên dài truncation, không wrap.

## 9. Bảo mật / bookmark

- Khi thêm file từ `NSOpenPanel`: tạo bookmark bằng `url.bookmarkData(options: .withSecurityScope, ...)`.
- Khi mở: `URL(resolvingBookmarkData:options:.withSecurityScope,...)`, gọi `startAccessingSecurityScopedResource()` trước khi `NSWorkspace.open`, và `stopAccessing...` sau đó.
- App hiện chạy có ký (dev cert) — bookmark security-scope hoạt động ổn định kể cả khi bật sandbox sau này.

## 10. Test

- **Unit — `FileShortcutStore`:**
  - Thêm/xoá/đổi tên catalogue lồng nhau (theo path).
  - Thêm/xoá file trong catalogue.
  - Serialize ↔ deserialize JSON round-trip giữ nguyên cây.
  - Xử lý JSON hỏng → cây rỗng.
  - Bookmark stale (mock) → đánh dấu lỗi thay vì crash.
- **Logic điều hướng:** push/pop path stack, về Home, disabled state của Home/Back.
- **Kiểm tra bằng mắt:** build + chạy app (theo quy tắc dự án), mở tab Files, tạo catalogue, thêm file, mở file, expand/thu, kiểm tra hàng file hỏng.
