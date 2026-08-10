# File Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm tab Files vào notch panel: tạo catalogue lồng nhau và gán file để mở nhanh, lưu bền bằng security-scoped bookmark.

**Architecture:** Một cây `Catalogue` (Codable) lưu JSON ở Application Support. `FileShortcutStore` (ObservableObject) giữ cây + CRUD + bookmark. `FilesPanel` (SwiftUI) điều hướng drill-down bằng path stack. `NotchViewModel` giữ store và quản chiều cao panel (150/340). `RailTab.files` đã tồn tại — chỉ route sang `FilesPanel`.

**Tech Stack:** Swift 6 / SPM, SwiftUI, AppKit (`NSOpenPanel`, `NSWorkspace`), XCTest.

---

## File Structure

| File | Trách nhiệm |
|------|-------------|
| `app/Package.swift` | Thêm `testTarget` để chạy unit test. |
| `app/Sources/JustANotch/Core/FileShortcutModels.swift` | struct `Catalogue`, `FileShortcut` + hàm thuần thao tác cây theo path. |
| `app/Sources/JustANotch/Core/FileShortcutStore.swift` | `ObservableObject`: load/save JSON, CRUD, bookmark create/resolve, mở file. |
| `app/Sources/JustANotch/UI/FilesPanel.swift` | View: topbar (Home/Back/title/+/⤢) + list + điều hướng + hover-add. |
| `app/Sources/JustANotch/NotchViewModel.swift` | Giữ `FileShortcutStore`; state `filesExpanded`; mở rộng `surfaceHeight`/`maxSurfaceHeight`. |
| `app/Sources/JustANotch/UI/NotchRootView.swift` | Route `case .files:` sang `FilesPanel`. |
| `app/Tests/JustANotchTests/FileShortcutStoreTests.swift` | Unit test cây + JSON + bookmark. |

**Lệnh build/test dùng xuyên suốt** (chạy trong thư mục `app/`):
- Test: `swift test`
- Build+chạy app: `bash app/scripts/run_app.sh` (từ repo root)

---

## Task 1: Thêm test target + model rỗng + test cây đầu tiên

**Files:**
- Modify: `app/Package.swift`
- Create: `app/Sources/JustANotch/Core/FileShortcutModels.swift`
- Test: `app/Tests/JustANotchTests/FileShortcutStoreTests.swift`

- [ ] **Step 1: Thêm testTarget vào Package.swift**

Thay khối `targets:` thành:

```swift
    targets: [
        .executableTarget(
            name: "JustANotch",
            path: "Sources/JustANotch"
        ),
        .testTarget(
            name: "JustANotchTests",
            dependencies: ["JustANotch"],
            path: "Tests/JustANotchTests"
        )
    ],
```

- [ ] **Step 2: Tạo model tối thiểu**

`app/Sources/JustANotch/Core/FileShortcutModels.swift`:

```swift
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
```

- [ ] **Step 3: Viết test thất bại (tìm node theo path)**

`app/Tests/JustANotchTests/FileShortcutStoreTests.swift`:

```swift
import XCTest
@testable import JustANotch

final class FileShortcutStoreTests: XCTestCase {
    func testFindNodeByPathReturnsNestedCatalogue() {
        let design = Catalogue(name: "Design")
        let work = Catalogue(name: "Work", children: [design])
        let root = Catalogue(name: "", children: [work])

        let found = root.node(atPath: [work.id, design.id])
        XCTAssertEqual(found?.name, "Design")
    }

    func testFindNodeByEmptyPathReturnsSelf() {
        let root = Catalogue(name: "")
        XCTAssertEqual(root.node(atPath: [])?.id, root.id)
    }
}
```

- [ ] **Step 4: Chạy test để xác nhận FAIL**

Run: `cd app && swift test 2>&1 | grep -E "error|node"`
Expected: FAIL — `value of type 'Catalogue' has no member 'node'`.

- [ ] **Step 5: Thêm hàm `node(atPath:)` vào FileShortcutModels.swift**

Thêm vào `extension Catalogue`:

```swift
extension Catalogue {
    /// Trả về node ở cuối `path` (danh sách id từ node hiện tại xuống). Path rỗng = self.
    func node(atPath path: [UUID]) -> Catalogue? {
        guard let first = path.first else { return self }
        guard let child = children.first(where: { $0.id == first }) else { return nil }
        return child.node(atPath: Array(path.dropFirst()))
    }
}
```

- [ ] **Step 6: Chạy test để xác nhận PASS**

Run: `cd app && swift test 2>&1 | tail -5`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add app/Package.swift app/Sources/JustANotch/Core/FileShortcutModels.swift app/Tests/JustANotchTests/FileShortcutStoreTests.swift
git commit -m "feat(files): Catalogue/FileShortcut models + test target"
```

---

## Task 2: Thao tác cây bất biến (thêm/xoá/đổi tên) theo path

**Files:**
- Modify: `app/Sources/JustANotch/Core/FileShortcutModels.swift`
- Test: `app/Tests/JustANotchTests/FileShortcutStoreTests.swift`

- [ ] **Step 1: Viết test thất bại**

Thêm vào `FileShortcutStoreTests`:

```swift
    func testInsertChildAtPath() {
        var root = Catalogue(name: "")
        let work = Catalogue(name: "Work")
        root.insert(child: work, atPath: [])
        XCTAssertEqual(root.children.map(\.name), ["Work"])

        let design = Catalogue(name: "Design")
        root.insert(child: design, atPath: [work.id])
        XCTAssertEqual(root.node(atPath: [work.id])?.children.map(\.name), ["Design"])
    }

    func testRemoveCatalogueAtPath() {
        let design = Catalogue(name: "Design")
        var root = Catalogue(name: "", children: [Catalogue(name: "Work", children: [design])])
        let workId = root.children[0].id
        root.removeCatalogue(id: design.id, atParentPath: [workId])
        XCTAssertTrue(root.node(atPath: [workId])!.children.isEmpty)
    }

    func testRenameCatalogueAtPath() {
        var root = Catalogue(name: "", children: [Catalogue(name: "Work")])
        let id = root.children[0].id
        root.rename(catalogueId: id, atParentPath: [], to: "Job")
        XCTAssertEqual(root.children[0].name, "Job")
    }
```

- [ ] **Step 2: Chạy test để xác nhận FAIL**

Run: `cd app && swift test 2>&1 | grep -E "error"`
Expected: FAIL — `insert`, `removeCatalogue`, `rename` chưa tồn tại.

- [ ] **Step 3: Thêm các hàm mutating vào extension Catalogue**

```swift
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
```

- [ ] **Step 4: Chạy test để xác nhận PASS**

Run: `cd app && swift test 2>&1 | tail -5`
Expected: PASS (tất cả test).

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/FileShortcutModels.swift app/Tests/JustANotchTests/FileShortcutStoreTests.swift
git commit -m "feat(files): immutable tree ops (insert/remove/rename) by path"
```

---

## Task 3: FileShortcutStore — persistence JSON

**Files:**
- Create: `app/Sources/JustANotch/Core/FileShortcutStore.swift`
- Test: `app/Tests/JustANotchTests/FileShortcutStoreTests.swift`

- [ ] **Step 1: Viết test thất bại (round-trip qua file tạm)**

Thêm vào test:

```swift
    func testSaveThenLoadRoundTrips() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shortcuts-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = FileShortcutStore(fileURL: tmp)
        store.root.children.append(Catalogue(name: "Work"))
        store.save()

        let reloaded = FileShortcutStore(fileURL: tmp)
        XCTAssertEqual(reloaded.root.children.map(\.name), ["Work"])
    }

    func testLoadMissingFileGivesEmptyRoot() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID()).json")
        let store = FileShortcutStore(fileURL: missing)
        XCTAssertTrue(store.root.children.isEmpty)
        XCTAssertTrue(store.root.files.isEmpty)
    }
```

- [ ] **Step 2: Chạy test để xác nhận FAIL**

Run: `cd app && swift test 2>&1 | grep -E "error"`
Expected: FAIL — `FileShortcutStore` chưa tồn tại.

- [ ] **Step 3: Tạo FileShortcutStore với load/save**

`app/Sources/JustANotch/Core/FileShortcutStore.swift`:

```swift
import Foundation
import Combine

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
```

- [ ] **Step 4: Chạy test để xác nhận PASS**

Run: `cd app && swift test 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/FileShortcutStore.swift app/Tests/JustANotchTests/FileShortcutStoreTests.swift
git commit -m "feat(files): FileShortcutStore JSON persistence"
```

---

## Task 4: Store — CRUD catalogue/file có auto-save

**Files:**
- Modify: `app/Sources/JustANotch/Core/FileShortcutStore.swift`
- Test: `app/Tests/JustANotchTests/FileShortcutStoreTests.swift`

- [ ] **Step 1: Viết test thất bại**

```swift
    func testAddCatalogueAutoSaves() {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sc-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = FileShortcutStore(fileURL: tmp)
        store.addCatalogue(named: "Work", atPath: [])

        let reloaded = FileShortcutStore(fileURL: tmp)
        XCTAssertEqual(reloaded.root.children.map(\.name), ["Work"])
    }

    func testDeleteCatalogue() {
        let store = FileShortcutStore(fileURL: URL(fileURLWithPath: "/nonexistent-\(UUID()).json"))
        store.addCatalogue(named: "Work", atPath: [])
        let id = store.root.children[0].id
        store.deleteCatalogue(id: id, atParentPath: [])
        XCTAssertTrue(store.root.children.isEmpty)
    }
```

- [ ] **Step 2: Chạy test để xác nhận FAIL**

Run: `cd app && swift test 2>&1 | grep -E "error"`
Expected: FAIL — `addCatalogue`/`deleteCatalogue` chưa có.

- [ ] **Step 3: Thêm CRUD vào FileShortcutStore**

```swift
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
```

- [ ] **Step 4: Chạy test để xác nhận PASS**

Run: `cd app && swift test 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/FileShortcutStore.swift app/Tests/JustANotchTests/FileShortcutStoreTests.swift
git commit -m "feat(files): catalogue/file CRUD with auto-save"
```

---

## Task 5: Store — thêm file (bookmark) + resolve + mở + stale

**Files:**
- Modify: `app/Sources/JustANotch/Core/FileShortcutStore.swift`
- Test: `app/Tests/JustANotchTests/FileShortcutStoreTests.swift`

- [ ] **Step 1: Viết test thất bại (bookmark round-trip trên file thật)**

```swift
    func testAddFileFromURLStoresResolvableBookmark() throws {
        let tmpFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("target-\(UUID()).txt")
        try "hi".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let store = FileShortcutStore(fileURL: URL(fileURLWithPath: "/nonexistent-\(UUID()).json"))
        store.addFile(url: tmpFile, atPath: [])

        let file = store.root.files[0]
        XCTAssertEqual(file.name, tmpFile.lastPathComponent)

        let resolved = store.resolveURL(for: file)
        XCTAssertEqual(resolved?.resolved?.lastPathComponent, tmpFile.lastPathComponent)
        XCTAssertFalse(resolved?.isMissing ?? true)
    }

    func testResolveBrokenBookmarkReportsMissing() {
        let store = FileShortcutStore(fileURL: URL(fileURLWithPath: "/nonexistent-\(UUID()).json"))
        let bogus = FileShortcut(name: "gone.txt", bookmark: Data([0x00, 0x01, 0x02]))
        let resolved = store.resolveURL(for: bogus)
        XCTAssertTrue(resolved?.isMissing ?? false)
    }
```

- [ ] **Step 2: Chạy test để xác nhận FAIL**

Run: `cd app && swift test 2>&1 | grep -E "error"`
Expected: FAIL — `addFile`/`resolveURL` chưa có.

- [ ] **Step 3: Thêm bookmark + open vào FileShortcutStore**

```swift
import AppKit

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
    /// Nếu bookmark stale nhưng URL còn hợp lệ, tự tạo lại bookmark (không lưu ở đây).
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
```

- [ ] **Step 4: Chạy test để xác nhận PASS**

Run: `cd app && swift test 2>&1 | tail -5`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/FileShortcutStore.swift app/Tests/JustANotchTests/FileShortcutStoreTests.swift
git commit -m "feat(files): security-scoped bookmarks — add/resolve/open"
```

---

## Task 6: NotchViewModel — giữ store + state expand + chiều cao

**Files:**
- Modify: `app/Sources/JustANotch/NotchViewModel.swift`

- [ ] **Step 1: Thêm store + state Files**

Trong `NotchViewModel`, sau các `@Published` hiện có (gần dòng 22):

```swift
    /// Cây shortcut cho tab Files.
    let fileStore = FileShortcutStore()
    /// True khi người dùng bấm ⤢ để phóng to panel Files. Ghi nhớ qua UserDefaults.
    @Published var filesExpanded: Bool = UserDefaults.standard.bool(forKey: "filesExpanded") {
        didSet { UserDefaults.standard.set(filesExpanded, forKey: "filesExpanded") }
    }
    /// Panel Files đang mở? (do NotchRootView set khi railTab == .files)
    @Published var filesTabActive = false
```

- [ ] **Step 2: Thêm hằng chiều cao Files**

Cạnh `calendarExpandedHeight` (dòng ~142):

```swift
    /// Chiều cao panel Files khi bấm ⤢ (đủ chỗ cho nhiều hàng).
    let filesExpandedHeight: CGFloat = 340
```

- [ ] **Step 3: Đưa Files vào maxSurfaceHeight**

Sửa `maxSurfaceHeight`:

```swift
    var maxSurfaceHeight: CGFloat {
        max(expandedHeight, listExpandedHeight, calendarExpandedHeight, filesExpandedHeight)
    }
```

- [ ] **Step 4: Đưa Files vào surfaceHeight**

Trong `surfaceHeight`, trước `if panelWantsTall`:

```swift
        if filesTabActive { return filesExpanded ? filesExpandedHeight : expandedHeight }
```

- [ ] **Step 5: Build để xác nhận biên dịch**

Run: `cd app && swift build 2>&1 | grep -E "error:" | head; echo done`
Expected: `done` không có dòng error.

- [ ] **Step 6: Commit**

```bash
git add app/Sources/JustANotch/NotchViewModel.swift
git commit -m "feat(files): view-model wiring — store, expand state, panel height"
```

---

## Task 7: FilesPanel — topbar + điều hướng + list (đọc)

**Files:**
- Create: `app/Sources/JustANotch/UI/FilesPanel.swift`

- [ ] **Step 1: Tạo FilesPanel với path stack + list**

`app/Sources/JustANotch/UI/FilesPanel.swift`:

```swift
import SwiftUI

/// Tab Files: duyệt catalogue lồng nhau + mở file. Điều hướng drill-down.
struct FilesPanel: View {
    @ObservedObject var store: FileShortcutStore
    @Binding var expanded: Bool

    /// Đường dẫn id từ root xuống catalogue đang mở (rỗng = Home).
    @State private var path: [UUID] = []
    @State private var hoveringAdd = false

    private var current: Catalogue { store.root.node(atPath: path) ?? store.root }
    private var atHome: Bool { path.isEmpty }
    private var title: String { atHome ? "Shortcuts" : current.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topBar
            list
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var topBar: some View {
        HStack(spacing: 7) {
            navButton("house", enabled: !atHome) { path.removeAll() }
            navButton("chevron.left", enabled: !atHome) { if !path.isEmpty { path.removeLast() } }
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            addControls
            iconButton(expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                expanded.toggle()
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(current.children) { cat in
                    row(icon: "folder.fill", name: cat.name, trailingCount: cat.children.count + cat.files.count, isFolder: true)
                        .onTapGesture { path.append(cat.id) }
                        .contextMenu {
                            Button("Xoá", role: .destructive) { store.deleteCatalogue(id: cat.id, atParentPath: path) }
                        }
                }
                ForEach(current.files) { file in
                    fileRow(file)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func row(icon: String, name: String, trailingCount: Int?, isFolder: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 13)).frame(width: 18)
                .foregroundStyle(isFolder ? .white : .white.opacity(0.85))
            Text(name).font(.system(size: 12.5, weight: isFolder ? .semibold : .regular))
                .foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if let c = trailingCount { Text("\(c)").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4)) }
            if isFolder { Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.white.opacity(0.35)) }
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func fileRow(_ file: FileShortcut) -> some View {
        let missing = store.resolveURL(for: file).isMissing
        HStack(spacing: 9) {
            Image(systemName: missing ? "exclamationmark.triangle.fill" : "doc")
                .font(.system(size: 13)).frame(width: 18)
                .foregroundStyle(missing ? .yellow.opacity(0.8) : .white.opacity(0.85))
            Text(file.name).font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(missing ? 0.45 : 1)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 7).padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture { store.open(file) }
        .contextMenu {
            Button("Xoá", role: .destructive) { store.deleteFile(id: file.id, atParentPath: path) }
        }
    }

    // Placeholder — hoàn thiện ở Task 8.
    private var addControls: some View {
        iconButton("plus") { }
    }

    private func navButton(_ symbol: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        iconButton(symbol, action: action).opacity(enabled ? 1 : 0.3).disabled(!enabled)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build để xác nhận biên dịch**

Run: `cd app && swift build 2>&1 | grep -E "error:" | head; echo done`
Expected: `done`, không error. (Chưa dùng ở đâu — chỉ compile.)

- [ ] **Step 3: Commit**

```bash
git add app/Sources/JustANotch/UI/FilesPanel.swift
git commit -m "feat(files): FilesPanel — nav + list rows (read + open + delete)"
```

---

## Task 8: FilesPanel — nút + hover tách 2, tạo catalogue, thêm file

**Files:**
- Modify: `app/Sources/JustANotch/UI/FilesPanel.swift`

- [ ] **Step 1: Thêm state nhập tên catalogue**

Cạnh `@State private var hoveringAdd`:

```swift
    @State private var creatingCatalogue = false
    @State private var newName = ""
```

- [ ] **Step 2: Thay `addControls` bằng bản hover-tách-2**

```swift
    private var addControls: some View {
        HStack(spacing: 7) {
            if hoveringAdd {
                pillButton("folder.badge.plus", tint: Color(red: 0.56, green: 0.71, blue: 1.0)) {
                    creatingCatalogue = true
                }
                pillButton("doc.badge.plus", tint: Color(red: 0.60, green: 0.83, blue: 0.56)) {
                    pickFiles()
                }
            } else {
                iconButton("plus") { }
                    .foregroundStyle(Color(red: 0.56, green: 0.71, blue: 1.0))
            }
        }
        .onHover { hoveringAdd = $0 }
        .popover(isPresented: $creatingCatalogue, arrowEdge: .bottom) {
            catalogueNameField
        }
    }

    private var catalogueNameField: some View {
        HStack(spacing: 6) {
            TextField("Tên catalogue", text: $newName)
                .textFieldStyle(.roundedBorder).frame(width: 160)
                .onSubmit(commitCatalogue)
            Button("Tạo", action: commitCatalogue)
        }
        .padding(10)
    }

    private func commitCatalogue() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.addCatalogue(named: name, atPath: path)
        newName = ""
        creatingCatalogue = false
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls { store.addFile(url: url, atPath: path) }
        }
    }

    private func pillButton(_ symbol: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 26, height: 24).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
```

- [ ] **Step 3: Thêm import AppKit ở đầu file**

Đảm bảo đầu `FilesPanel.swift` có (SwiftUI đã đủ `NSOpenPanel` qua AppKit — thêm cho chắc):

```swift
import SwiftUI
import AppKit
```

- [ ] **Step 4: Build để xác nhận biên dịch**

Run: `cd app && swift build 2>&1 | grep -E "error:" | head; echo done`
Expected: `done`, không error.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/UI/FilesPanel.swift
git commit -m "feat(files): hover-split add button — new catalogue + NSOpenPanel"
```

---

## Task 9: Route .files trong NotchRootView + kiểm tra bằng mắt

**Files:**
- Modify: `app/Sources/JustANotch/UI/NotchRootView.swift`

- [ ] **Step 1: Set `filesTabActive` khi đổi tab**

Trong `.onChange(of: railTab)` (khoảng dòng 163-164), sau dòng `vm.panelWantsTall = ...`:

```swift
                    vm.filesTabActive = (newTab == .files)
```

- [ ] **Step 2: Route case .files trong `content`**

Sửa switch (dòng ~188):

```swift
        switch railTab {
        case .music:         musicPanel
        case .notifications: notificationsPanel
        case .calendar:      calendarPanel
        case .files:         filesPanel
        default:             placeholderPanel(railTab)
        }
```

- [ ] **Step 3: Thêm computed `filesPanel`**

Gần các panel khác trong NotchRootView (ví dụ sau `calendarPanel`):

```swift
    private var filesPanel: some View {
        FilesPanel(store: vm.fileStore,
                   expanded: Binding(get: { vm.filesExpanded },
                                     set: { vm.filesExpanded = $0 }))
            .padding(.top, vm.notchHeight + 8)
    }
```

- [ ] **Step 4: Build + chạy app**

Run: `bash app/scripts/run_app.sh 2>&1 | tail -6`
Expected: `Relaunched ...`, không có dòng `error:`.

- [ ] **Step 5: Kiểm tra bằng mắt (thủ công)**

Mở panel → rail cuộn tới tab 📁 Files. Xác nhận:
- Home hiện "Shortcuts", nút ⌂/‹ mờ.
- Hover + → tách 📂/📄. Tạo catalogue "Test" → hàng mới xuất hiện.
- Bấm 📄 → chọn 1 file → hàng file hiện ra; bấm hàng file → file mở bằng app mặc định.
- Bấm vào catalogue → drill vào, tiêu đề đổi, ⌂/‹ sáng; bấm ‹ về lại.
- Bấm ⤢ → panel cao lên; đóng/mở lại app vẫn nhớ trạng thái.

- [ ] **Step 6: Commit**

```bash
git add app/Sources/JustANotch/UI/NotchRootView.swift
git commit -m "feat(files): route Files tab to FilesPanel + wire active state"
```

---

## Self-Review Notes

- **Spec coverage:** mô hình dữ liệu (T1-2), JSON persistence (T3), CRUD (T4), bookmark/open/stale (T5), panel size/expand (T6), UI nav + list + Home/Back (T7), hover-add + NSOpenPanel + tạo catalogue (T8), route tab + kiểm tra bằng mắt (T9). Xoá qua context menu (T7). ✔
- **Bỏ khỏi phạm vi (đúng spec YAGNI):** drag-drop, reorder, di chuyển node, icon theo loại file, đồng bộ.
- **Type consistency:** `node(atPath:)`, `insert(child:atPath:)`, `insert(file:atPath:)`, `addCatalogue(named:atPath:)`, `addFile(url:atPath:)`, `resolveURL(for:) -> Resolved{resolved,isMissing}`, `open(_:)` dùng nhất quán giữa store, test và UI.
- **Ghi chú:** `RailTab.files` đã có sẵn (icon/title) — không cần thêm case enum.
