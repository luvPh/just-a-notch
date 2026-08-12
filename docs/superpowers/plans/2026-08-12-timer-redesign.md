# Timer Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gom mọi kiểu hẹn giờ vào tab Timer dạng carousel 3 trang (Đơn/stopwatch, Pomodoro, Chuỗi tự tạo), mỗi đoạn có âm riêng, thư viện âm mở rộng.

**Architecture:** Tổng quát hoá `TimerService` để chạy một danh sách "đoạn đã trải phẳng" (flattened segments) với endDate-clock sẵn có. Pomodoro/Đơn/Stopwatch/Chuỗi tự tạo đều map thành `[TimerSegment]`. UI SwiftUI kiểm chứng bằng cách chạy app (Stop hook tự build+relaunch); logic Core kiểm bằng XCTest với clock tiêm.

**Tech Stack:** Swift, SwiftUI, Combine, XCTest, `NSSound`.

---

## File Structure

- Create `Core/TimerSequenceModels.swift` — `TimerSegment`, `TimerSequence`, hàm `flatten(_:)` trải phẳng vùng lặp.
- Create `Core/SoundLibrary.swift` — liệt kê âm hệ thống + bundle `Resources/Sounds/`, phát âm theo tên.
- Create `Core/SequenceStore.swift` — lưu/đọc ≤5 chuỗi tự tạo qua UserDefaults (JSON).
- Modify `Core/TimerService.swift` — chạy theo `[TimerSegment]`, chime theo đoạn, nhánh stopwatch (đếm lên).
- Modify `Core/AppSettings.swift` — key cho trang carousel hiện tại + âm mặc định pha.
- Create `UI/TimerCarousel.swift` — container 3 trang + dot indicator + nút ⚙️.
- Create `UI/TimerSequenceBuilder.swift` — trang 3: trình dựng chuỗi (≤4 đoạn, vùng lặp, âm/đoạn, lưu ≤5).
- Create `UI/TimerGeneralSettings.swift` — panel ⚙️ cài đặt tổng (thư viện âm, âm lượng).
- Modify `UI/TimerPanel.swift` — tách trang Đơn + Pomodoro, bỏ settingsView tạm.
- Modify `Resources/` + `Package.swift` — đóng gói thư mục `Sounds/`.

---

## Phase 1 — Core: mô hình chuỗi + trải phẳng vùng lặp

### Task 1: TimerSegment / TimerSequence + flatten()

**Files:**
- Create: `app/Sources/JustANotch/Core/TimerSequenceModels.swift`
- Test: `app/Tests/JustANotchTests/TimerSequenceTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import JustANotch

final class TimerSequenceTests: XCTestCase {
    private func seg(_ name: String, _ min: Int) -> TimerSegment {
        TimerSegment(id: UUID(), name: name, minutes: min, soundName: "Ping", colorHex: "#7F77DD")
    }

    func testFlattenNoLoopIsSequential() {
        let s = TimerSequence(id: UUID(), name: "x",
                              segments: [seg("a", 1), seg("b", 2), seg("c", 3)],
                              loopStart: nil, loopEnd: nil, loopCount: 1)
        XCTAssertEqual(flatten(s).map(\.name), ["a", "b", "c"])
    }

    func testFlattenLoopRegionRepeats() {
        // đoạn 0..1 lặp 2 lần rồi tới đoạn 2 → a,b,a,b,c
        let s = TimerSequence(id: UUID(), name: "x",
                              segments: [seg("a", 1), seg("b", 2), seg("c", 3)],
                              loopStart: 0, loopEnd: 1, loopCount: 2)
        XCTAssertEqual(flatten(s).map(\.name), ["a", "b", "a", "b", "c"])
    }

    func testFlattenLoopTrailingAndLeading() {
        // đoạn 1 lặp 3 lần, có đoạn trước và sau → a,b,b,b,c
        let s = TimerSequence(id: UUID(), name: "x",
                              segments: [seg("a", 1), seg("b", 2), seg("c", 3)],
                              loopStart: 1, loopEnd: 1, loopCount: 3)
        XCTAssertEqual(flatten(s).map(\.name), ["a", "b", "b", "b", "c"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd app && DEVELOPER_DIR=/Applications/Xcode.app swift test --filter TimerSequenceTests 2>&1 | tail -20
```
Expected: FAIL — `cannot find 'TimerSegment' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

struct TimerSegment: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var minutes: Int          // >0 = đếm ngược; 0 = đếm lên (stopwatch, chỉ trang Đơn)
    var soundName: String     // key tra trong SoundLibrary
    var colorHex: String
}

struct TimerSequence: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var segments: [TimerSegment]   // ≤ 4
    var loopStart: Int?
    var loopEnd: Int?
    var loopCount: Int             // số lần chạy vùng lặp (≥1)
}

/// Trải phẳng chuỗi: các đoạn trước vùng (1 lần) → vùng [start…end] lặp loopCount
/// lần → các đoạn sau vùng (1 lần). Không có vùng lặp thì chạy tuần tự 1 lần.
func flatten(_ s: TimerSequence) -> [TimerSegment] {
    guard let start = s.loopStart, let end = s.loopEnd,
          start >= 0, end < s.segments.count, start <= end, s.loopCount > 1 else {
        return s.segments
    }
    var out: [TimerSegment] = []
    out += s.segments[0..<start]
    for _ in 0..<s.loopCount { out += s.segments[start...end] }
    out += s.segments[(end + 1)...]
    return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd app && DEVELOPER_DIR=/Applications/Xcode.app swift test --filter TimerSequenceTests 2>&1 | tail -20
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/TimerSequenceModels.swift app/Tests/JustANotchTests/TimerSequenceTests.swift
git commit -m "feat(timer): mô hình TimerSegment/TimerSequence + flatten vùng lặp"
```

### Task 2: TimerService chạy theo [TimerSegment] + chime theo đoạn

**Files:**
- Modify: `app/Sources/JustANotch/Core/TimerService.swift`
- Modify: `app/Sources/JustANotch/NotchViewModel.swift:28-38` (chime closure nhận tên âm)
- Modify: `app/Tests/JustANotchTests/PomodoroPhaseTests.swift` (cập nhật chữ ký chime)
- Test: `app/Tests/JustANotchTests/TimerSequenceRunTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import JustANotch

final class TimerSequenceRunTests: XCTestCase {
    private func seg(_ name: String, _ min: Int, _ sound: String) -> TimerSegment {
        TimerSegment(id: UUID(), name: name, minutes: min, soundName: sound, colorHex: "#fff")
    }

    @MainActor
    func testRunSequenceAdvancesThroughSegmentsAndChimesPerSegment() {
        var now = Date(timeIntervalSince1970: 0)
        var chimed: [String] = []
        let svc = TimerService(config: { PomodoroConfig(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, roundsBeforeLongBreak: 4) },
                               now: { now }, autoStartNext: { true },
                               chime: { chimed.append($0) })
        svc.startSequence([seg("a", 1, "Glass"), seg("b", 1, "Ping")], label: "test")
        XCTAssertEqual(svc.currentSegmentName, "a")
        XCTAssertEqual(svc.remaining, 60, accuracy: 0.5)

        now = Date(timeIntervalSince1970: 61)
        svc.tickForTest()
        XCTAssertEqual(chimed, ["Glass"])           // âm của đoạn a
        XCTAssertEqual(svc.currentSegmentName, "b")  // sang đoạn b

        now = Date(timeIntervalSince1970: 122)
        svc.tickForTest()
        XCTAssertEqual(chimed, ["Glass", "Ping"])    // âm của đoạn b
        XCTAssertTrue(svc.justFinished)              // hết chuỗi
    }

    @MainActor
    func testStopwatchCountsUp() {
        var now = Date(timeIntervalSince1970: 0)
        let svc = TimerService(config: { PomodoroConfig(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, roundsBeforeLongBreak: 4) },
                               now: { now }, autoStartNext: { true }, chime: { _ in })
        svc.startStopwatch()
        XCTAssertEqual(svc.elapsed, 0, accuracy: 0.5)
        now = Date(timeIntervalSince1970: 45)
        svc.tickForTest()
        XCTAssertEqual(svc.elapsed, 45, accuracy: 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd app && DEVELOPER_DIR=/Applications/Xcode.app swift test --filter TimerSequenceRunTests 2>&1 | tail -20
```
Expected: FAIL — `value of type 'TimerService' has no member 'startSequence'`.

- [ ] **Step 3: Implement in TimerService.swift**

Đổi `chime` thành `(String) -> Void` và thêm chế độ chạy chuỗi. Thêm vào `TimerService`:

```swift
// Thêm published:
@Published private(set) var currentSegmentName: String = ""
@Published private(set) var elapsed: TimeInterval = 0     // cho stopwatch

// Thay thuộc tính chime:
private let chime: (String) -> Void
// init: chime: @escaping (String) -> Void

// Trạng thái chuỗi:
private var runSegments: [TimerSegment] = []
private var segIndex = 0
private var countingUp = false

func startSequence(_ segments: [TimerSegment], label: String = "") {
    mode = .plain
    self.label = label
    justFinished = false
    countingUp = false
    runSegments = segments
    segIndex = 0
    guard let first = segments.first else { return }
    currentSegmentName = first.name
    phaseLength = TimeInterval(max(1, first.minutes) * 60)
    arm(phaseLength)
}

func startStopwatch() {
    mode = .plain
    justFinished = false
    countingUp = true
    runSegments = []
    elapsed = 0
    endDate = now()          // dùng endDate làm mốc bắt đầu
    isRunning = true
    startTicker()
}
```

Trong `tick()`, thêm nhánh đếm lên:

```swift
private func tick() {
    guard isRunning, let end = endDate else { return }
    if countingUp {
        elapsed = max(0, now().timeIntervalSince(end))
        return
    }
    remaining = max(0, end.timeIntervalSince(now()))
    if remaining <= 0 { advancePhase() }
}
```

Trong `advancePhase()`, khi đang chạy chuỗi (runSegments không rỗng) thì chime theo đoạn hiện tại và sang đoạn kế:

```swift
private func advancePhase() {
    if !runSegments.isEmpty {
        chime(runSegments[segIndex].soundName)
        segIndex += 1
        if segIndex >= runSegments.count {
            isRunning = false; endDate = nil; stopTicker()
            remaining = 0; justFinished = true
            return
        }
        let next = runSegments[segIndex]
        currentSegmentName = next.name
        phaseLength = TimeInterval(max(1, next.minutes) * 60)
        arm(phaseLength)
        return
    }
    // ... nhánh Pomodoro/plain cũ, đổi chime() → chime(defaultSoundName)
}
```

Với Pomodoro/plain cũ, `chime()` giờ cần tên âm — dùng âm timer mặc định: `chime(TimerSoundDefault.name)` hoặc truyền qua provider. Đơn giản: thêm `private let defaultSound: () -> String` vào init, gọi `chime(defaultSound())`.

- [ ] **Step 4: Cập nhật NotchViewModel chime closure**

Tại `app/Sources/JustANotch/NotchViewModel.swift` (khối `lazy var timer`):

```swift
return TimerService(config: { s.pomodoroConfig },
                    autoStartNext: { s.pomoAutoStart },
                    defaultSound: { s.timerSoundName },
                    chime: { name in
                        guard s.timerSoundEnabled else { return }
                        SoundLibrary.shared.play(name, volume: Float(s.timerVolume))
                    })
```

(SoundLibrary tạo ở Phase 2; tạm thời có thể dùng `NSSound(named: name)?.play()` rồi thay ở Phase 2.)

- [ ] **Step 5: Sửa test cũ cho chữ ký chime mới**

Tại `PomodoroPhaseTests.swift` đổi mọi `chime: { chimes += 1 }` → `chime: { _ in chimes += 1 }` và `chime: {}` → `chime: { _ in }`, thêm `defaultSound: { "Glass" }` vào init.

- [ ] **Step 6: Run tests**

Run:
```bash
cd app && DEVELOPER_DIR=/Applications/Xcode.app swift test --filter "Timer\|Pomodoro" 2>&1 | tail -25
```
Expected: PASS toàn bộ TimerSequenceRunTests + PomodoroPhaseTests.

- [ ] **Step 7: Commit**

```bash
git add app/Sources/JustANotch/Core/TimerService.swift app/Sources/JustANotch/NotchViewModel.swift app/Tests/JustANotchTests/
git commit -m "feat(timer): TimerService chạy chuỗi đoạn + stopwatch + chime theo đoạn"
```

---

## Phase 2 — Thư viện âm

### Task 3: SoundLibrary (âm hệ thống + bundle Sounds/)

**Files:**
- Create: `app/Sources/JustANotch/Core/SoundLibrary.swift`
- Create: `app/Sources/JustANotch/Resources/Sounds/README.txt` (chỗ bỏ file âm)
- Modify: `app/Package.swift` (thêm resources copy) và `scripts/build_app.sh` nếu cần copy Resources.
- Test: `app/Tests/JustANotchTests/SoundLibraryTests.swift`

- [ ] **Step 1: Write failing test**

```swift
import XCTest
@testable import JustANotch

final class SoundLibraryTests: XCTestCase {
    func testSystemSoundsListed() {
        let names = SoundLibrary.shared.available.map(\.name)
        XCTAssertTrue(names.contains("Glass"))
        XCTAssertTrue(names.contains("Ping"))
        XCTAssertTrue(names.count >= 10)   // toàn bộ âm hệ thống
    }
}
```

- [ ] **Step 2: Run → FAIL** (`cannot find 'SoundLibrary'`).

Run: `cd app && DEVELOPER_DIR=/Applications/Xcode.app swift test --filter SoundLibraryTests 2>&1 | tail`

- [ ] **Step 3: Implement**

```swift
import AppKit

struct SoundOption: Identifiable, Equatable {
    var id: String { name }
    let name: String        // key hiển thị + lưu
    let url: URL?           // nil = âm hệ thống (dùng NSSound(named:))
}

final class SoundLibrary {
    static let shared = SoundLibrary()
    private(set) var available: [SoundOption] = []

    private init() { reload() }

    func reload() {
        var opts: [SoundOption] = []
        // Âm hệ thống trong /System/Library/Sounds
        let sysDir = URL(fileURLWithPath: "/System/Library/Sounds")
        if let files = try? FileManager.default.contentsOfDirectory(at: sysDir, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "aiff" {
                opts.append(SoundOption(name: f.deletingPathExtension().lastPathComponent, url: nil))
            }
        }
        // Âm đóng gói trong bundle Resources/Sounds/
        if let bundleDir = Bundle.main.url(forResource: "Sounds", withExtension: nil),
           let files = try? FileManager.default.contentsOfDirectory(at: bundleDir, includingPropertiesForKeys: nil) {
            for f in files where ["caf","m4a","aiff","wav","mp3"].contains(f.pathExtension.lowercased()) {
                opts.append(SoundOption(name: f.deletingPathExtension().lastPathComponent, url: f))
            }
        }
        available = opts.sorted { $0.name < $1.name }
    }

    func play(_ name: String, volume: Float = 0.8) {
        if let opt = available.first(where: { $0.name == name }), let url = opt.url {
            let snd = NSSound(contentsOf: url, byReference: true)
            snd?.volume = volume; snd?.play()
        } else {
            let snd = NSSound(named: name); snd?.volume = volume; snd?.play()
        }
    }
}
```

- [ ] **Step 4: Run → PASS**. Nếu build phàn nàn thiếu Resources dir, tạo `Resources/Sounds/README.txt` với nội dung hướng dẫn bỏ file.

- [ ] **Step 5: Đóng gói Resources** — kiểm `Package.swift` target `JustANotch` có `resources: [.copy("Resources/Sounds")]`. Kiểm `scripts/build_app.sh` copy bundle resources vào `.app`. Chạy `bash scripts/run_app.sh` xác nhận app mở được.

- [ ] **Step 6: Commit**

```bash
git add app/Sources/JustANotch/Core/SoundLibrary.swift app/Sources/JustANotch/Resources/Sounds app/Package.swift
git commit -m "feat(timer): SoundLibrary — âm hệ thống + bundle Resources/Sounds"
```

### Task 4: StyledSoundPicker dùng nguồn động + play qua SoundLibrary

**Files:**
- Modify: `app/Sources/JustANotch/UI/SettingsPanel.swift` (StyledSoundPicker)

- [ ] **Step 1:** Đổi `options` mặc định của `StyledSoundPicker` thành `SoundLibrary.shared.available.map(\.name)`; nút chọn gọi `SoundLibrary.shared.play(name)` thay `NSSound(named:)`.
- [ ] **Step 2:** Build + chạy app, mở tab Settings → dropdown liệt kê nhiều âm, nghe thử chạy.
- [ ] **Step 3: Commit** `git commit -am "feat(timer): dropdown âm dùng SoundLibrary động"`

---

## Phase 3 — Carousel 3 trang

### Task 5: TimerCarousel container + dot indicator + nút ⚙️

**Files:**
- Create: `app/Sources/JustANotch/UI/TimerCarousel.swift`
- Modify: `app/Sources/JustANotch/UI/NotchRootView.swift:389` (case .timer dùng TimerCarousel)
- Modify: `app/Sources/JustANotch/Core/AppSettings.swift` (key `cfg.timerPage`)

- [ ] **Step 1:** Thêm `AppSettings`: `@Published var timerPage: Int { didSet {...} }` key `cfg.timerPage`, default 0.
- [ ] **Step 2:** Tạo `TimerCarousel`:

```swift
import SwiftUI

struct TimerCarousel: View {
    @ObservedObject var timer: TimerService
    @ObservedObject var settings: AppSettings
    @State private var showingGeneral = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showingGeneral {
                TimerGeneralSettings(settings: settings, onBack: { showingGeneral = false })
            } else {
                VStack(spacing: 6) {
                    TabView(selection: $settings.timerPage) {
                        TimerPanel(timer: timer, settings: settings).tag(0)
                        PomodoroPage(timer: timer, settings: settings).tag(1)
                        TimerSequenceBuilder(timer: timer, settings: settings).tag(2)
                    }
                    .tabViewStyle(.automatic)
                    dots
                }
                Button { showingGeneral = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.white.opacity(settings.timerPage == i ? 0.9 : 0.25))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
```

Ghi chú: macOS `TabView` không vuốt ngang mặc định; nếu cần cử chỉ scroll ngang, dùng `ScrollViewReader`/`ScrollView(.horizontal)` với paging thủ công. Chốt: dùng `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)` (macOS 14+) hoặc fallback nút mũi tên. Kiểm bản macOS mục tiêu trước khi chọn.

- [ ] **Step 3:** Tạm stub `PomodoroPage` và `TimerSequenceBuilder` bằng `Text("...")` để build; hoàn thiện ở Task 6-7.
- [ ] **Step 4:** Build + chạy, xác nhận chuyển trang + dot + nút ⚙️ hiện.
- [ ] **Step 5: Commit.**

### Task 6: Trang Đơn (stopwatch toggle) + Trang Pomodoro

**Files:**
- Modify: `app/Sources/JustANotch/UI/TimerPanel.swift` (trang Đơn: thêm toggle đếm ngược/đếm lên, gọi `timer.startStopwatch()`; bỏ `settingsView`/`gearshape` tạm cũ)
- Create: `PomodoroPage` trong `TimerCarousel.swift` hoặc file riêng — hiển thị đồng hồ pha + chỉnh `pomo*` (dùng stepper compact) + nút chạy `timer.startPomodoro()`.

- [ ] **Step 1:** Trang Đơn: thêm `@State stopwatchMode`; khi bật, UI hiện `elapsed` đếm lên + nút chạy/dừng/reset; khi tắt giữ nút 5/10/25/⋯.
- [ ] **Step 2:** PomodoroPage: đồng hồ + "Vòng x/N" + steppers phút Làm/Nghỉ/Số vòng + toggle tự chạy.
- [ ] **Step 3:** Build + chạy, kiểm cả hai trang.
- [ ] **Step 4: Commit.**

---

## Phase 4 — Trang 3: trình dựng chuỗi + lưu ≤5

### Task 7: SequenceStore (persist ≤5 chuỗi)

**Files:**
- Create: `app/Sources/JustANotch/Core/SequenceStore.swift`
- Test: `app/Tests/JustANotchTests/SequenceStoreTests.swift`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import JustANotch

final class SequenceStoreTests: XCTestCase {
    func testSaveLoadRoundTripAndCap() {
        let d = UserDefaults(suiteName: "test.seqstore")!
        d.removePersistentDomain(forName: "test.seqstore")
        let store = SequenceStore(defaults: d)
        for i in 0..<7 {
            store.save(TimerSequence(id: UUID(), name: "s\(i)", segments: [], loopStart: nil, loopEnd: nil, loopCount: 1))
        }
        XCTAssertEqual(store.all.count, 5)   // giới hạn 5
    }
}
```

- [ ] **Step 2: Run → FAIL.**
- [ ] **Step 3: Implement**

```swift
import Foundation

final class SequenceStore: ObservableObject {
    @Published private(set) var all: [TimerSequence] = []
    private let d: UserDefaults
    private let key = "cfg.timerSequences"
    static let maxCount = 5

    init(defaults: UserDefaults = .standard) {
        self.d = defaults
        if let data = d.data(forKey: key),
           let arr = try? JSONDecoder().decode([TimerSequence].self, from: data) {
            all = arr
        }
    }

    func save(_ seq: TimerSequence) {
        if let i = all.firstIndex(where: { $0.id == seq.id }) { all[i] = seq }
        else { all.append(seq) }
        if all.count > Self.maxCount { all = Array(all.prefix(Self.maxCount)) }
        persist()
    }
    func delete(_ id: UUID) { all.removeAll { $0.id == id }; persist() }
    private func persist() {
        if let data = try? JSONEncoder().encode(all) { d.set(data, forKey: key) }
    }
}
```

- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Commit.**

### Task 8: TimerSequenceBuilder UI

**Files:**
- Create: `app/Sources/JustANotch/UI/TimerSequenceBuilder.swift`

- [ ] **Step 1:** UI: danh sách chuỗi đã lưu (chọn để chạy `timer.startSequence(flatten(seq), label:)`); nút "＋ Chuỗi mới".
- [ ] **Step 2:** Editor 1 chuỗi: ≤4 đoạn (mỗi đoạn: tên, phút, `StyledSoundPicker`); đặt vùng lặp (2 stepper index start/end + stepper số lần); nút Lưu (gọi `store.save`), Xoá.
- [ ] **Step 3:** Chặn thêm quá 4 đoạn / lưu quá 5 chuỗi (disable nút + ghi chú).
- [ ] **Step 4:** Build + chạy: tạo chuỗi a(1')+b(1'), vùng lặp 0..0 ×2 → chạy thấy a,a,b; mỗi đoạn kêu âm đã chọn.
- [ ] **Step 5: Commit.**

---

## Phase 5 — Panel cài đặt tổng (⚙️)

### Task 9: TimerGeneralSettings

**Files:**
- Create: `app/Sources/JustANotch/UI/TimerGeneralSettings.swift`

- [ ] **Step 1:** Panel (nút ◀ quay lại — `onBack`): bật/tắt chuông (`timerSoundEnabled`), âm mặc định pha Làm/Nghỉ (dùng `StyledSoundPicker`), âm lượng (`timerVolume`), nút "Nạp lại thư viện âm" gọi `SoundLibrary.shared.reload()`.
- [ ] **Step 2:** Build + chạy: nút ⚙️ luôn hiện trong tab Timer, mở panel này.
- [ ] **Step 3: Commit.**

### Task 10: Dọn dẹp + xác nhận

- [ ] **Step 1:** Xoá `settingsView`/`stepRow`/`switchRow` tạm trong TimerPanel nếu đã chuyển hết sang carousel/general settings.
- [ ] **Step 2:** Chạy toàn bộ test: `cd app && DEVELOPER_DIR=/Applications/Xcode.app swift test 2>&1 | tail -15` → PASS.
- [ ] **Step 3:** `bash scripts/run_app.sh` → app chạy, thử cả 3 trang + ⚙️.
- [ ] **Step 4: Commit** dọn dẹp.

---

## Ghi chú kiểm thử

- Core (Phase 1, 2 Task 3, 4 Task 7) kiểm bằng XCTest với `DEVELOPER_DIR` trỏ Xcode.app (theo memory `swift-test-developer-dir`).
- UI kiểm bằng chạy app thật (Stop hook tự build+relaunch). Không tuyên bố xong khi chưa chạy app.
