# Clipboard History + Timer/Pomodoro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two notch tabs — a clipboard history (text + images, 25 unpinned cap, click-to-recopy) and a Timer/Pomodoro (fully configurable work/break cycles with a chime).

**Architecture:** Each feature follows the existing Model → Store/Service (`ObservableObject`) → Panel (SwiftUI) pattern. Testable core logic (history mutation, Pomodoro phase machine, countdown math) is pulled into pure value types so it can be unit-tested without the pasteboard, real timers, or UI. Side-effecting shells (0.4s pasteboard poll, 1s countdown tick, `NSSound`, PNG files) wrap that core. Two new `RailTab` cases, each gated by an `AppSettings` toggle.

**Tech Stack:** Swift 6 / SwiftUI, AppKit (`NSPasteboard`, `NSSound`, `NSImage`), XCTest via `swift test`. Working dir for build/test is `app/`.

---

## File Structure

**Clipboard**
- Create `app/Sources/JustANotch/Core/ClipboardModels.swift` — `ClipboardItem`, `ClipboardItemKind`, `ClipboardHistory` (pure mutation core).
- Create `app/Sources/JustANotch/Core/ClipboardStore.swift` — `ObservableObject`: pasteboard poll, PNG file I/O, persistence.
- Create `app/Sources/JustANotch/UI/ClipboardPanel.swift` — the tab UI.
- Create `app/Tests/JustANotchTests/ClipboardHistoryTests.swift`.

**Timer**
- Create `app/Sources/JustANotch/Core/PomodoroModels.swift` — `TimerPhase`, `TimerMode`, `PomodoroConfig`, `nextPhase(...)` pure function.
- Create `app/Sources/JustANotch/Core/TimerService.swift` — `ObservableObject`: countdown via `endDate`, start/pause/reset/skip, chime.
- Create `app/Tests/JustANotchTests/PomodoroPhaseTests.swift`.

**Shared wiring (modify)**
- `app/Sources/JustANotch/Core/AppSettings.swift` — `showClipboard`, `showTimer` toggles + `PomodoroConfig`-backed prefs + sound prefs.
- `app/Sources/JustANotch/UI/NotchRootView.swift` — `RailTab` cases `.clipboard`/`.timer`, `visibleTabs`, `selectTab`, panel routing, wing indicator.
- `app/Sources/JustANotch/UI/SettingsPanel.swift` — tab toggles + Timer/Pomodoro settings section.
- `app/Sources/JustANotch/NotchViewModel.swift` — published fields the wing/panels observe.

Build after each task: `cd app && swift build`. Tests: `cd app && swift test`.

---

## Task 1: ClipboardItem model + ClipboardHistory core

**Files:**
- Create: `app/Sources/JustANotch/Core/ClipboardModels.swift`
- Test: `app/Tests/JustANotchTests/ClipboardHistoryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// app/Tests/JustANotchTests/ClipboardHistoryTests.swift
import XCTest
@testable import JustANotch

final class ClipboardHistoryTests: XCTestCase {
    private func text(_ s: String) -> ClipboardItem {
        ClipboardItem(id: UUID(), createdAt: Date(), pinned: false, kind: .text(s))
    }

    func testRecordInsertsAtFront() {
        var h = ClipboardHistory(unpinnedLimit: 25)
        h.record(text("a"))
        h.record(text("b"))
        XCTAssertEqual(h.items.map { $0.plainText }, ["b", "a"])
    }

    func testDuplicateOfFrontIsIgnored() {
        var h = ClipboardHistory(unpinnedLimit: 25)
        h.record(text("a"))
        h.record(text("a"))
        XCTAssertEqual(h.items.count, 1)
    }

    func testUnpinnedCapEvictsOldest() {
        var h = ClipboardHistory(unpinnedLimit: 3)
        ["a", "b", "c", "d"].forEach { h.record(text($0)) }
        XCTAssertEqual(h.items.map { $0.plainText }, ["d", "c", "b"])
    }

    func testPinnedItemsAreExemptFromCap() {
        var h = ClipboardHistory(unpinnedLimit: 2)
        h.record(text("keep"))
        h.togglePin(h.items[0].id)          // "keep" becomes pinned
        ["a", "b", "c"].forEach { h.record(text($0)) }
        XCTAssertTrue(h.items.contains { $0.plainText == "keep" && $0.pinned })
        // 3 unpinned recorded, cap 2 → only 2 unpinned remain + 1 pinned
        XCTAssertEqual(h.items.filter { !$0.pinned }.count, 2)
    }

    func testEvictedReturnsRemovedItemsForCleanup() {
        var h = ClipboardHistory(unpinnedLimit: 1)
        let removedA = h.record(text("a"))   // nothing evicted yet
        XCTAssertTrue(removedA.isEmpty)
        let removedB = h.record(text("b"))   // "a" evicted
        XCTAssertEqual(removedB.map { $0.plainText }, ["a"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && swift test --filter ClipboardHistoryTests`
Expected: FAIL — `cannot find 'ClipboardItem' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// app/Sources/JustANotch/Core/ClipboardModels.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && swift test --filter ClipboardHistoryTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/ClipboardModels.swift app/Tests/JustANotchTests/ClipboardHistoryTests.swift
git commit -m "feat(clipboard): history core model with dedup + pinned-exempt cap"
```

---

## Task 2: ClipboardStore — persistence round-trip

**Files:**
- Create: `app/Sources/JustANotch/Core/ClipboardStore.swift`
- Test: `app/Tests/JustANotchTests/ClipboardHistoryTests.swift` (append)

- [ ] **Step 1: Write the failing test** (append to `ClipboardHistoryTests`)

```swift
    func testStoreSaveThenLoadRoundTripsTextItems() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("clip-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = ClipboardStore(fileURL: tmp, imagesDir: nil, autoPoll: false)
        store.recordText("hello")
        store.recordText("world")
        store.togglePin(store.items[0].id)   // pin "world"

        let reloaded = ClipboardStore(fileURL: tmp, imagesDir: nil, autoPoll: false)
        XCTAssertEqual(reloaded.items.map { $0.plainText }, ["world", "hello"])
        XCTAssertTrue(reloaded.items[0].pinned)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && swift test --filter ClipboardHistoryTests`
Expected: FAIL — `cannot find 'ClipboardStore' in scope`.

- [ ] **Step 3: Write minimal implementation** (persistence + text path only; polling/images added in Task 3)

```swift
// app/Sources/JustANotch/Core/ClipboardStore.swift
import Foundation
import Combine
import AppKit

/// Theo dõi NSPasteboard, giữ lịch sử copy (text + ảnh), lưu bền ra JSON.
/// Lõi mutation nằm ở ClipboardHistory; store lo I/O + side-effects.
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private var history: ClipboardHistory
    private let fileURL: URL
    private let imagesDir: URL?

    // Chống loop: changeCount của lần chính store ghi ra pasteboard.
    private var selfChangeCount: Int = -1
    private var lastSeenChangeCount: Int = NSPasteboard.general.changeCount
    private var pollTimer: Timer?

    static let unpinnedLimit = 25

    static var defaultFileURL: URL {
        Self.appSupport().appendingPathComponent("clipboard.json")
    }
    static var defaultImagesDir: URL {
        let d = Self.appSupport().appendingPathComponent("Clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func appSupport() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Just a Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    init(fileURL: URL = ClipboardStore.defaultFileURL,
         imagesDir: URL? = ClipboardStore.defaultImagesDir,
         autoPoll: Bool = true) {
        self.fileURL = fileURL
        self.imagesDir = imagesDir
        self.history = ClipboardHistory(unpinnedLimit: Self.unpinnedLimit)
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            self.history = ClipboardHistory(unpinnedLimit: Self.unpinnedLimit, items: saved)
        }
        self.items = history.items
        if autoPoll { startPolling() }
    }

    // MARK: Public mutations (UI + tests)
    func recordText(_ s: String) {
        let item = ClipboardItem(id: UUID(), createdAt: Date(), pinned: false, kind: .text(s))
        applyRecorded(history.record(item))
    }

    func togglePin(_ id: UUID) { history.togglePin(id); sync() }

    func delete(_ id: UUID) {
        if let removed = history.remove(id) { cleanupFile(for: removed) }
        sync()
    }

    func clearUnpinned() {
        history.clearUnpinned().forEach(cleanupFile(for:))
        sync()
    }

    /// Copy một mục trở lại pasteboard (không auto-paste).
    func copyBack(_ id: UUID) {
        guard let item = history.items.first(where: { $0.id == id }) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case let .text(s):
            pb.setString(s, forType: .string)
        case let .image(fileName):
            if let dir = imagesDir,
               let img = NSImage(contentsOf: dir.appendingPathComponent(fileName)) {
                pb.writeObjects([img])
            }
        }
        selfChangeCount = pb.changeCount        // đừng tự ghi lại mục này
    }

    // MARK: Internals
    private func applyRecorded(_ removed: [ClipboardItem]) {
        removed.forEach(cleanupFile(for:))
        sync()
    }

    private func sync() {
        items = history.items
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(history.items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func cleanupFile(for item: ClipboardItem) {
        guard case let .image(fileName) = item.kind, let dir = imagesDir else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(fileName))
    }

    // startPolling() / pasteboard reading added in Task 3.
    private func startPolling() {}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && swift test --filter ClipboardHistoryTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/ClipboardStore.swift app/Tests/JustANotchTests/ClipboardHistoryTests.swift
git commit -m "feat(clipboard): store with JSON persistence + copy-back"
```

---

## Task 3: ClipboardStore — pasteboard polling + image capture

**Files:**
- Modify: `app/Sources/JustANotch/Core/ClipboardStore.swift`

No unit test — this reads the live `NSPasteboard` and uses a real `Timer`; verified manually in the running app (Task 5). Keep the logic thin so the untested surface stays small.

- [ ] **Step 1: Implement polling + capture** — replace the empty `startPolling()` and add capture helpers:

```swift
    private func startPolling() {
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        let cc = pb.changeCount
        guard cc != lastSeenChangeCount else { return }
        lastSeenChangeCount = cc
        guard cc != selfChangeCount else { return }   // do chính ta copy-back

        if let s = pb.string(forType: .string), !s.isEmpty {
            recordText(s)
        } else if let img = captureImage(from: pb) {
            recordImage(img)
        }
    }

    private func captureImage(from pb: NSPasteboard) -> NSImage? {
        guard let items = pb.readObjects(forClasses: [NSImage.self], options: nil),
              let img = items.first as? NSImage else { return nil }
        return img
    }

    private func recordImage(_ img: NSImage) {
        guard let dir = imagesDir,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let fileName = "\(UUID().uuidString).png"
        try? png.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        let item = ClipboardItem(id: UUID(), createdAt: Date(), pinned: false,
                                 kind: .image(fileName: fileName))
        applyRecorded(history.record(item))
    }

    /// Ảnh thumbnail cho UI (nil nếu không đọc được file).
    func image(for item: ClipboardItem) -> NSImage? {
        guard case let .image(fileName) = item.kind, let dir = imagesDir else { return nil }
        return NSImage(contentsOf: dir.appendingPathComponent(fileName))
    }

    deinit { pollTimer?.invalidate() }
```

- [ ] **Step 2: Build**

Run: `cd app && swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add app/Sources/JustANotch/Core/ClipboardStore.swift
git commit -m "feat(clipboard): poll NSPasteboard + capture images to PNG"
```

---

## Task 4: AppSettings — clipboard + timer tab toggles

**Files:**
- Modify: `app/Sources/JustANotch/Core/AppSettings.swift`

- [ ] **Step 1: Add published toggles** — after the `showCalendar` line, add:

```swift
    @Published var showClipboard: Bool { didSet { d.set(showClipboard, forKey: "cfg.showClipboard") } }
    @Published var showTimer: Bool { didSet { d.set(showTimer, forKey: "cfg.showTimer") } }
```

- [ ] **Step 2: Register defaults + load** — in `d.register(defaults: [...])` add:

```swift
            "cfg.showClipboard": true,
            "cfg.showTimer": true,
```

and after the `showCalendar = ...` load line add:

```swift
        showClipboard = d.bool(forKey: "cfg.showClipboard")
        showTimer = d.bool(forKey: "cfg.showTimer")
```

- [ ] **Step 3: Build**

Run: `cd app && swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add app/Sources/JustANotch/Core/AppSettings.swift
git commit -m "feat(settings): add clipboard + timer tab toggles"
```

---

## Task 5: Clipboard tab wiring + ClipboardPanel UI

**Files:**
- Modify: `app/Sources/JustANotch/UI/NotchRootView.swift` (RailTab, visibleTabs, selectTab, panel routing)
- Create: `app/Sources/JustANotch/UI/ClipboardPanel.swift`
- Modify: `app/Sources/JustANotch/NotchViewModel.swift` (hold the shared `ClipboardStore`)

No unit test — SwiftUI view + live pasteboard; verified visually via `run_app.sh`.

- [ ] **Step 1: Add RailTab case** — in `enum RailTab` (`NotchRootView.swift:739`) add `clipboard` to the case list, and add to `icon` / `title`:

```swift
    case music, files, notifications, calendar, clipboard, timer, settings
```
```swift
        case .clipboard:     return "doc.on.clipboard"
```
```swift
        case .clipboard:     return "Clipboard"
```
(Also add the `.timer` arms here now to avoid a second edit: `case .timer: return "timer"` in `icon`, `case .timer: return "Timer"` in `title`.)

- [ ] **Step 2: Add store to NotchViewModel** — in `NotchViewModel.swift` add a stored property:

```swift
    let clipboard = ClipboardStore()
```

- [ ] **Step 3: Show tab when enabled** — in `visibleTabs` (NotchRootView.swift ~line 15) mirror the existing Files pattern:

```swift
        if settings.showClipboard { t.append(.clipboard) }
```
(Insert in the same order block where `.files`, `.notifications`, `.calendar` are appended, before `.settings`.)

- [ ] **Step 4: Route the panel** — in the `switch railTab` body that builds panel content (NotchRootView.swift ~line 129), add:

```swift
        case .clipboard:
            ClipboardPanel(store: vm.clipboard)
```

- [ ] **Step 5: Create the panel**

```swift
// app/Sources/JustANotch/UI/ClipboardPanel.swift
import SwiftUI

struct ClipboardPanel: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Clipboard").font(.headline)
                Spacer()
                Button {
                    store.clearUnpinned()
                } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("Xoá tất cả (giữ mục ghim)")
            }
            if store.items.isEmpty {
                Text("Chưa có gì được sao chép.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.items) { item in
                            ClipboardRow(item: item, store: store)
                        }
                    }
                }
            }
        }
        .padding(10)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    @ObservedObject var store: ClipboardStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            preview
            Spacer(minLength: 4)
            if hovering || item.pinned {
                Button { store.togglePin(item.id) } label: {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                }.buttonStyle(.plain).help("Ghim")
            }
            if hovering {
                Button { store.delete(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                }.buttonStyle(.plain).help("Xoá")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hovering ? 0.10 : 0.05)))
        .contentShape(Rectangle())
        .onTapGesture { store.copyBack(item.id) }
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case let .text(s):
            Text(s).lineLimit(2).font(.system(.callout, design: .monospaced))
        case .image:
            if let img = store.image(for: item) {
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: 44, height: 32).clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 6: Build + run + verify**

Run: `cd app && swift build`
Expected: Build succeeds. Then run `app/scripts/run_app.sh`. Copy some text and a screenshot; open the Clipboard tab; confirm items appear, clicking recopies, pin/delete/clear work.

- [ ] **Step 7: Commit**

```bash
git add app/Sources/JustANotch/UI/ClipboardPanel.swift app/Sources/JustANotch/UI/NotchRootView.swift app/Sources/JustANotch/NotchViewModel.swift
git commit -m "feat(clipboard): rail tab + panel UI"
```

---

## Task 6: Pomodoro phase machine + config (pure core)

**Files:**
- Create: `app/Sources/JustANotch/Core/PomodoroModels.swift`
- Test: `app/Tests/JustANotchTests/PomodoroPhaseTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// app/Tests/JustANotchTests/PomodoroPhaseTests.swift
import XCTest
@testable import JustANotch

final class PomodoroPhaseTests: XCTestCase {
    let cfg = PomodoroConfig(workMinutes: 25, shortBreakMinutes: 5,
                             longBreakMinutes: 15, roundsBeforeLongBreak: 4)

    func testWorkGoesToShortBreakWhenRoundsNotReached() {
        let (phase, rounds) = nextPhase(after: .work, completedWorkRounds: 0, cfg: cfg)
        XCTAssertEqual(phase, .shortBreak)
        XCTAssertEqual(rounds, 1)
    }

    func testFourthWorkGoesToLongBreakAndResetsRounds() {
        let (phase, rounds) = nextPhase(after: .work, completedWorkRounds: 3, cfg: cfg)
        XCTAssertEqual(phase, .longBreak)
        XCTAssertEqual(rounds, 0)
    }

    func testShortBreakGoesBackToWork() {
        let (phase, rounds) = nextPhase(after: .shortBreak, completedWorkRounds: 1, cfg: cfg)
        XCTAssertEqual(phase, .work)
        XCTAssertEqual(rounds, 1)
    }

    func testLongBreakGoesBackToWork() {
        let (phase, _) = nextPhase(after: .longBreak, completedWorkRounds: 0, cfg: cfg)
        XCTAssertEqual(phase, .work)
    }

    func testPhaseDurationsFromConfig() {
        XCTAssertEqual(cfg.duration(for: .work), 25 * 60)
        XCTAssertEqual(cfg.duration(for: .shortBreak), 5 * 60)
        XCTAssertEqual(cfg.duration(for: .longBreak), 15 * 60)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && swift test --filter PomodoroPhaseTests`
Expected: FAIL — `cannot find 'PomodoroConfig' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// app/Sources/JustANotch/Core/PomodoroModels.swift
import Foundation

enum TimerPhase: String, Codable { case work, shortBreak, longBreak }
enum TimerMode { case pomodoro, plain }

struct PomodoroConfig: Equatable {
    var workMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var roundsBeforeLongBreak: Int

    func duration(for phase: TimerPhase) -> TimeInterval {
        switch phase {
        case .work:       return TimeInterval(workMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak:  return TimeInterval(longBreakMinutes * 60)
        }
    }
}

/// Luật chuyển pha Pomodoro. Trả về (pha kế tiếp, số vòng làm đã hoàn tất mới).
/// - Sau .work: tăng vòng; nếu đủ roundsBeforeLongBreak → .longBreak + reset vòng,
///   ngược lại → .shortBreak.
/// - Sau break → .work.
func nextPhase(after phase: TimerPhase,
               completedWorkRounds: Int,
               cfg: PomodoroConfig) -> (TimerPhase, Int) {
    switch phase {
    case .work:
        let done = completedWorkRounds + 1
        if done >= cfg.roundsBeforeLongBreak { return (.longBreak, 0) }
        return (.shortBreak, done)
    case .shortBreak, .longBreak:
        return (.work, completedWorkRounds)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && swift test --filter PomodoroPhaseTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/PomodoroModels.swift app/Tests/JustANotchTests/PomodoroPhaseTests.swift
git commit -m "feat(timer): pomodoro phase machine + config core"
```

---

## Task 7: PomodoroConfig + sound prefs in AppSettings

**Files:**
- Modify: `app/Sources/JustANotch/Core/AppSettings.swift`

- [ ] **Step 1: Add published prefs** — after the `showTimer` toggle add:

```swift
    // MARK: Pomodoro — tuỳ biến chu kỳ + chuông.
    @Published var pomoWorkMinutes: Int { didSet { d.set(pomoWorkMinutes, forKey: "cfg.pomoWork") } }
    @Published var pomoShortMinutes: Int { didSet { d.set(pomoShortMinutes, forKey: "cfg.pomoShort") } }
    @Published var pomoLongMinutes: Int { didSet { d.set(pomoLongMinutes, forKey: "cfg.pomoLong") } }
    @Published var pomoRounds: Int { didSet { d.set(pomoRounds, forKey: "cfg.pomoRounds") } }
    @Published var pomoAutoStart: Bool { didSet { d.set(pomoAutoStart, forKey: "cfg.pomoAutoStart") } }
    @Published var timerSoundEnabled: Bool { didSet { d.set(timerSoundEnabled, forKey: "cfg.timerSoundOn") } }
    @Published var timerSoundName: String { didSet { d.set(timerSoundName, forKey: "cfg.timerSound") } }
    @Published var timerVolume: Double { didSet { d.set(timerVolume, forKey: "cfg.timerVolume") } }

    var pomodoroConfig: PomodoroConfig {
        PomodoroConfig(workMinutes: pomoWorkMinutes, shortBreakMinutes: pomoShortMinutes,
                       longBreakMinutes: pomoLongMinutes, roundsBeforeLongBreak: pomoRounds)
    }
```

- [ ] **Step 2: Register defaults + load** — add to `d.register(defaults: [...])`:

```swift
            "cfg.pomoWork": 25, "cfg.pomoShort": 5, "cfg.pomoLong": 15,
            "cfg.pomoRounds": 4, "cfg.pomoAutoStart": true,
            "cfg.timerSoundOn": true, "cfg.timerSound": "Glass", "cfg.timerVolume": 0.8,
```

and in `init` after the existing loads:

```swift
        pomoWorkMinutes = d.integer(forKey: "cfg.pomoWork")
        pomoShortMinutes = d.integer(forKey: "cfg.pomoShort")
        pomoLongMinutes = d.integer(forKey: "cfg.pomoLong")
        pomoRounds = d.integer(forKey: "cfg.pomoRounds")
        pomoAutoStart = d.bool(forKey: "cfg.pomoAutoStart")
        timerSoundEnabled = d.bool(forKey: "cfg.timerSoundOn")
        timerSoundName = d.string(forKey: "cfg.timerSound") ?? "Glass"
        timerVolume = d.double(forKey: "cfg.timerVolume")
```

- [ ] **Step 3: Build**

Run: `cd app && swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add app/Sources/JustANotch/Core/AppSettings.swift
git commit -m "feat(settings): pomodoro config + chime prefs"
```

---

## Task 8: TimerService — countdown, phases, chime

**Files:**
- Create: `app/Sources/JustANotch/Core/TimerService.swift`
- Test: `app/Tests/JustANotchTests/PomodoroPhaseTests.swift` (append)

The countdown is tested with an injectable clock so no real waiting is needed.

- [ ] **Step 1: Write the failing test** (append)

```swift
    @MainActor
    func testCountdownUsesInjectedClockAndAdvancesPhaseWhenElapsed() {
        var now = Date(timeIntervalSince1970: 0)
        let cfg = PomodoroConfig(workMinutes: 1, shortBreakMinutes: 1,
                                 longBreakMinutes: 1, roundsBeforeLongBreak: 4)
        var chimes = 0
        let svc = TimerService(config: { cfg }, now: { now },
                               autoStartNext: { true }, chime: { chimes += 1 })
        svc.startPomodoro()
        XCTAssertEqual(svc.phase, .work)
        XCTAssertEqual(svc.remaining, 60, accuracy: 0.5)

        now = Date(timeIntervalSince1970: 30)   // 30s later
        svc.tickForTest()
        XCTAssertEqual(svc.remaining, 30, accuracy: 0.5)

        now = Date(timeIntervalSince1970: 61)   // past end
        svc.tickForTest()
        XCTAssertEqual(svc.phase, .shortBreak)  // auto-advanced
        XCTAssertEqual(chimes, 1)
    }

    @MainActor
    func testPauseWaitsForUserWhenAutoStartOff() {
        var now = Date(timeIntervalSince1970: 0)
        let cfg = PomodoroConfig(workMinutes: 1, shortBreakMinutes: 1,
                                 longBreakMinutes: 1, roundsBeforeLongBreak: 4)
        let svc = TimerService(config: { cfg }, now: { now },
                               autoStartNext: { false }, chime: {})
        svc.startPomodoro()
        now = Date(timeIntervalSince1970: 61)
        svc.tickForTest()
        XCTAssertEqual(svc.phase, .shortBreak)
        XCTAssertFalse(svc.isRunning)           // chờ user bấm
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && swift test --filter PomodoroPhaseTests`
Expected: FAIL — `cannot find 'TimerService' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// app/Sources/JustANotch/Core/TimerService.swift
import Foundation
import Combine
import AppKit

@MainActor
final class TimerService: ObservableObject {
    @Published private(set) var phase: TimerPhase = .work
    @Published private(set) var mode: TimerMode = .pomodoro
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var completedWorkRounds = 0
    @Published private(set) var phaseLength: TimeInterval = 0   // để UI vẽ vòng %

    private var endDate: Date?
    private var ticker: Timer?

    // Injectable cho test; production dùng AppSettings + Date().
    private let configProvider: () -> PomodoroConfig
    private let now: () -> Date
    private let autoStartNextProvider: () -> Bool
    private let chime: () -> Void

    init(config: @escaping () -> PomodoroConfig,
         now: @escaping () -> Date = { Date() },
         autoStartNext: @escaping () -> Bool,
         chime: @escaping () -> Void) {
        self.configProvider = config
        self.now = now
        self.autoStartNextProvider = autoStartNext
        self.chime = chime
    }

    // MARK: Controls
    func startPomodoro() {
        mode = .pomodoro
        beginPhase(.work, resetRounds: true)
    }

    func startPlain(minutes: Int) {
        mode = .plain
        phase = .work
        phaseLength = TimeInterval(minutes * 60)
        arm(phaseLength)
    }

    func pause() {
        guard isRunning, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSince(now()))
        isRunning = false
        endDate = nil
        stopTicker()
    }

    func resume() {
        guard !isRunning, remaining > 0 else { return }
        arm(remaining)
    }

    func reset() {
        isRunning = false; endDate = nil; stopTicker()
        remaining = 0; phaseLength = 0; completedWorkRounds = 0
    }

    func skip() { advancePhase() }

    // MARK: Phase lifecycle
    private func beginPhase(_ p: TimerPhase, resetRounds: Bool) {
        if resetRounds { completedWorkRounds = 0 }
        phase = p
        phaseLength = configProvider().duration(for: p)
        arm(phaseLength)
    }

    private func arm(_ seconds: TimeInterval) {
        remaining = seconds
        endDate = now().addingTimeInterval(seconds)
        isRunning = true
        startTicker()
    }

    private func advancePhase() {
        chime()
        if mode == .plain {
            reset()
            return
        }
        let (next, rounds) = nextPhase(after: phase,
                                       completedWorkRounds: completedWorkRounds,
                                       cfg: configProvider())
        completedWorkRounds = rounds
        phase = next
        phaseLength = configProvider().duration(for: next)
        if autoStartNextProvider() {
            arm(phaseLength)
        } else {
            remaining = phaseLength
            isRunning = false
            endDate = nil
            stopTicker()
        }
    }

    // MARK: Ticking
    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    /// Test seam — chạy đúng logic của tick mà không cần chờ Timer thật.
    func tickForTest() { tick() }

    private func tick() {
        guard isRunning, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSince(now()))
        if remaining <= 0 { advancePhase() }
    }

    deinit { ticker?.invalidate() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && swift test --filter PomodoroPhaseTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/TimerService.swift app/Tests/JustANotchTests/PomodoroPhaseTests.swift
git commit -m "feat(timer): countdown service with endDate clock + phase advance"
```

---

## Task 9: Timer tab wiring + TimerPanel UI + wing indicator

**Files:**
- Modify: `app/Sources/JustANotch/NotchViewModel.swift` (own the `TimerService`, expose wing fields)
- Modify: `app/Sources/JustANotch/UI/NotchRootView.swift` (visibleTabs, panel routing, wing)
- Create: `app/Sources/JustANotch/UI/TimerPanel.swift`

`.timer` RailTab icon/title were already added in Task 5 Step 1.

- [ ] **Step 1: Own the service in NotchViewModel** — add:

```swift
    lazy var timer: TimerService = {
        let s = AppSettings.shared
        return TimerService(config: { s.pomodoroConfig },
                            autoStartNext: { s.pomoAutoStart },
                            chime: { [weak s] in
                                guard let s, s.timerSoundEnabled,
                                      let snd = NSSound(named: s.timerSoundName) else { return }
                                snd.volume = Float(s.timerVolume)
                                snd.play()
                            })
    }()
```
(Add `import AppKit` at the top of NotchViewModel.swift if not present.)

- [ ] **Step 2: Show tab when enabled** — in `visibleTabs` add alongside the others:

```swift
        if settings.showTimer { t.append(.timer) }
```

- [ ] **Step 3: Route the panel** — in the `switch railTab` panel builder add:

```swift
        case .timer:
            TimerPanel(timer: vm.timer, settings: AppSettings.shared)
```

- [ ] **Step 4: Create the panel**

```swift
// app/Sources/JustANotch/UI/TimerPanel.swift
import SwiftUI

struct TimerPanel: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings

    private var progress: Double {
        guard timer.phaseLength > 0 else { return 0 }
        return 1 - (timer.remaining / timer.phaseLength)
    }
    private var phaseColor: Color {
        switch timer.phase {
        case .work:                   return .red
        case .shortBreak, .longBreak: return .green
        }
    }
    private var mmss: String {
        let s = Int(timer.remaining.rounded())
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
    private var phaseLabel: String {
        switch timer.phase {
        case .work:       return "Làm việc"
        case .shortBreak: return "Nghỉ ngắn"
        case .longBreak:  return "Nghỉ dài"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 8)
                Circle().trim(from: 0, to: progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack {
                    Text(mmss).font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text(phaseLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            if timer.mode == .pomodoro {
                Text("Vòng \(timer.completedWorkRounds + 1)/\(settings.pomoRounds)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if timer.isRunning {
                    Button("Tạm dừng") { timer.pause() }
                } else {
                    Button("Bắt đầu") {
                        if timer.remaining > 0 { timer.resume() } else { timer.startPomodoro() }
                    }
                }
                Button("Đặt lại") { timer.reset() }
                Button("Bỏ qua") { timer.skip() }
            }
            .buttonStyle(.bordered).font(.caption)

            HStack(spacing: 6) {
                ForEach([5, 10, 25], id: \.self) { m in
                    Button("\(m)m") { timer.startPlain(minutes: m) }
                        .buttonStyle(.borderless).font(.caption2)
                }
            }
        }
        .padding(12)
    }
}
```

- [ ] **Step 5: Wing indicator** — in NotchRootView, find the wing overlay block that shows `filesSelCount` (~line 187–189) and add, in the matching wing (right), a compact countdown shown when the timer runs. Insert near the other wing overlays:

```swift
            if vm.expanded == false, vm.timer.isRunning {
                ZStack {
                    Circle().trim(from: 0, to: max(0.001, 1 - (vm.timer.remaining / max(1, vm.timer.phaseLength))))
                        .stroke(vm.timer.phase == .work ? Color.red : Color.green,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 14, height: 14)
                    Text("\(Int(vm.timer.remaining / 60))")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                }
            }
```
(Match the exact wing container/conditions used by the existing `filesSelCount` overlay; place it so it only shows while collapsed and running. Adjust the guard to the app's real "collapsed" flag if `vm.expanded == false` isn't the right one — check the neighbouring overlay's condition.)

- [ ] **Step 6: Build + run + verify**

Run: `cd app && swift build`
Expected: Build succeeds. Then `app/scripts/run_app.sh`. Open Timer tab, start a plain 5m timer and a Pomodoro; confirm ring animates, mm:ss counts down, phase color/label correct, wing shows countdown when panel collapsed, chime plays at phase end (set work to 1 min in Settings after Task 10 to test quickly, or temporarily use a 5m plain timer).

- [ ] **Step 7: Commit**

```bash
git add app/Sources/JustANotch/UI/TimerPanel.swift app/Sources/JustANotch/UI/NotchRootView.swift app/Sources/JustANotch/NotchViewModel.swift
git commit -m "feat(timer): rail tab + panel UI + wing countdown"
```

---

## Task 10: Settings UI — tab toggles + Pomodoro section

**Files:**
- Modify: `app/Sources/JustANotch/UI/SettingsPanel.swift`

No unit test — SwiftUI settings form; verified visually.

- [ ] **Step 1: Add tab toggles** — where the existing `showFiles` / `showNotifications` / `showCalendar` toggles live, add two more bound to the new settings:

```swift
            Toggle("Clipboard", isOn: $settings.showClipboard)
            Toggle("Timer", isOn: $settings.showTimer)
```
(Match the exact binding style used by the neighbouring toggles — e.g. `$settings.showFiles`.)

- [ ] **Step 2: Add Pomodoro section** — add a new section following the file's existing section layout:

```swift
            Divider()
            Text("Timer / Pomodoro").font(.headline)
            Stepper("Làm: \(settings.pomoWorkMinutes)m", value: $settings.pomoWorkMinutes, in: 1...120)
            Stepper("Nghỉ ngắn: \(settings.pomoShortMinutes)m", value: $settings.pomoShortMinutes, in: 1...60)
            Stepper("Nghỉ dài: \(settings.pomoLongMinutes)m", value: $settings.pomoLongMinutes, in: 1...60)
            Stepper("Số vòng trước nghỉ dài: \(settings.pomoRounds)", value: $settings.pomoRounds, in: 1...12)
            Toggle("Tự chạy pha kế tiếp", isOn: $settings.pomoAutoStart)
            Toggle("Chuông báo", isOn: $settings.timerSoundEnabled)
            Picker("Âm chuông", selection: $settings.timerSoundName) {
                ForEach(["Glass", "Ping", "Submarine", "Funk", "Blow"], id: \.self) { Text($0).tag($0) }
            }
            HStack {
                Text("Âm lượng")
                Slider(value: $settings.timerVolume, in: 0...1)
                Button("Nghe thử") {
                    if let snd = NSSound(named: settings.timerSoundName) {
                        snd.volume = Float(settings.timerVolume); snd.play()
                    }
                }
            }
```
(Add `import AppKit` to SettingsPanel.swift if `NSSound` isn't already resolvable.)

- [ ] **Step 3: Build + run + verify**

Run: `cd app && swift build`
Expected: Build succeeds. Then `app/scripts/run_app.sh`. Open Settings: toggle Clipboard/Timer tabs on/off (rail updates), change Pomodoro numbers, press "Nghe thử" (sound plays), adjust volume.

- [ ] **Step 4: Commit**

```bash
git add app/Sources/JustANotch/UI/SettingsPanel.swift
git commit -m "feat(settings): timer/pomodoro controls + tab toggles UI"
```

---

## Final verification

- [ ] `cd app && swift test` — all tests pass (ClipboardHistory + PomodoroPhase suites).
- [ ] `cd app && swift build` — clean build.
- [ ] `app/scripts/run_app.sh` — manual pass: clipboard captures text+image, recopy/pin/delete/clear work; timer runs Pomodoro through a work→break transition with chime, plain presets work, wing countdown shows while collapsed, settings changes take effect.

## Notes for the implementer
- The app has no existing DI container; services are owned by `NotchViewModel` and read `AppSettings.shared`. Follow that.
- `RailTab` is used in several `switch` statements (icon, title, panel routing, and possibly others). After adding cases, `swift build` will point out any non-exhaustive switch — handle each the same way neighbouring cases are handled.
- Keep the untested surface (pasteboard poll, real Timers, `NSSound`, SwiftUI views) thin; all branching logic lives in the tested cores (`ClipboardHistory`, `nextPhase`, `TimerService.tick`).
