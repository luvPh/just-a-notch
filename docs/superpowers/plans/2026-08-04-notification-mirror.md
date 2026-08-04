# Notification Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mirror macOS system notifications into the notch — pop a HUD banner on arrival and keep an 8-hour history grouped by app in the Notifications tab.

**Architecture:** A `NotificationService` (mirroring `MediaService`'s lifecycle) reads the private Notification Center SQLite database, decodes each new row's binary-plist payload, and publishes arrivals + a pruned history over Combine. Pure decode/detect/prune/group logic lives in a Foundation-only file so it is unit-testable without SQLite or AppKit. `NotchViewModel` gains a HUD state (a third surface state alongside compact/expanded) and history; the UI adds a HUD banner and a real Notifications tab panel.

**Tech Stack:** Swift 6 / SwiftUI / Combine / AppKit, `import SQLite3` (system module, no extra linking), `PropertyListSerialization`. Tests are standalone `swiftc`-compiled check binaries with `fatalError` assertions, matching the existing `TitleRevealTimingCheck` pattern.

---

## Background notes for the implementer

- **No XCTest.** This repo tests pure logic by compiling a source file plus a
  `@main` check file with `swiftc` into a standalone binary that exits 0 on
  success and calls `fatalError` on failure. Example that already works:
  ```bash
  cd app
  swiftc -o /tmp/trtc Sources/JustANotch/Core/TitleRevealTiming.swift Tests/TitleRevealTimingCheck.swift && /tmp/trtc && echo PASSED
  ```
  Follow this exact pattern for the new logic checks. Keep all testable logic in
  `NotificationDecoding.swift`, which must import **only** `Foundation` (no
  AppKit/Combine) so the check compiles fast and standalone.

- **App build/run.** `app/scripts/build_app.sh [debug|release]` builds and
  assembles the `.app`. A Stop hook auto-runs `app/scripts/run_app.sh` (debug
  build + relaunch) after each turn; a build failure re-wakes to fix it. To build
  manually: `cd app && swift build -c debug --product JustANotch`.

- **Full Disk Access.** The database at
  `~/Library/Group Containers/group.com.apple.usernoted/db2/db` is unreadable
  without Full Disk Access (verified: currently not readable). The service must
  degrade gracefully, never crash, and expose a `.denied` permission state.

- **Panel is a fixed canvas.** `NotchWindowController` sizes the panel once to
  `panelWidth × expandedHeight` and animates all states inside SwiftUI,
  top-anchored. The HUD is just a new surface state — no window resize.

- **Cocoa epoch.** Notification `date` values use the `NSDate` reference epoch
  (2001-01-01). Convert with `Date(timeIntervalSinceReferenceDate:)`.

---

## File Structure

**Create:**
- `app/Sources/JustANotch/Core/NotificationModels.swift` — `NotificationRecord`
  struct + `NotificationPermissionState` enum (Foundation only).
- `app/Sources/JustANotch/Core/NotificationDecoding.swift` — pure logic:
  `decodeNotification`, `NewArrivalTracker`, `prune`, `groupByApp` (Foundation
  only, unit-tested).
- `app/Sources/JustANotch/Core/NotificationService.swift` — protocol +
  concrete service (SQLite3, Combine, AppKit icon cache, timers).
- `app/Tests/NotificationDecodingCheck.swift` — standalone `@main` check for the
  pure logic.

**Modify:**
- `app/Sources/JustANotch/NotchViewModel.swift` — inject the service; add HUD +
  history state and HUD geometry.
- `app/Sources/JustANotch/UI/NotchRootView.swift` — HUD banner surface; real
  Notifications tab panel; surface-state precedence.
- `app/Sources/JustANotch/NotchWindowController.swift` — construct/own the
  service; HUD hit-testing + mouse handling.

---

## Task 1: Notification models

**Files:**
- Create: `app/Sources/JustANotch/Core/NotificationModels.swift`

- [ ] **Step 1: Write the models**

```swift
// File: Sources/JustANotch/Core/NotificationModels.swift
import Foundation

/// A single mirrored macOS notification. `id` is the Notification Center
/// database rowid (`rec_id`) — stable, unique, and monotonically increasing,
/// so records de-duplicate and order naturally.
struct NotificationRecord: Identifiable, Equatable {
    let id: Int64
    let bundleId: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date

    /// Best single line of secondary text for compact display.
    var detailLine: String { body.isEmpty ? subtitle : body }
}

/// Whether the app can read the Notification Center database. `.denied` means
/// the open failed — almost always missing Full Disk Access.
enum NotificationPermissionState: Equatable {
    case unknown
    case granted
    case denied
}

/// One app's notifications, for the grouped history list.
struct NotificationGroup: Identifiable, Equatable {
    var id: String { bundleId }
    let bundleId: String
    let appName: String
    let records: [NotificationRecord]   // newest first
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd app && swiftc -parse Sources/JustANotch/Core/NotificationModels.swift`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add app/Sources/JustANotch/Core/NotificationModels.swift
git commit -m "feat(notifications): add NotificationRecord/group/permission models"
```

---

## Task 2: Pure decoding & list logic (TDD)

All logic here is Foundation-only and unit-tested standalone.

**Files:**
- Create: `app/Sources/JustANotch/Core/NotificationDecoding.swift`
- Test: `app/Tests/NotificationDecodingCheck.swift`

- [ ] **Step 1: Write the failing check**

```swift
// File: Tests/NotificationDecodingCheck.swift
import Foundation

private func check(_ cond: Bool, _ message: String,
                   file: StaticString = #filePath, line: UInt = #line) {
    if !cond { fatalError("\(file):\(line): \(message)") }
}

/// Build a Notification Center-style payload plist BLOB for testing decode.
private func payload(titl: String? = nil, subt: String? = nil,
                     body: String? = nil, date: Double? = nil) -> Data {
    var req: [String: Any] = [:]
    if let titl { req["titl"] = titl }
    if let subt { req["subt"] = subt }
    if let body { req["body"] = body }
    if let date { req["date"] = date }
    let root: [String: Any] = ["req": req]
    return try! PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
}

@main
struct NotificationDecodingCheck {
    static func main() {
        // --- decode: full payload ---
        let refDate = 700_000_000.0   // seconds since 2001-01-01
        let full = decodeNotification(id: 42, bundleId: "com.apple.iChat", appName: "Messages",
                                      payload: payload(titl: "Alice", subt: "iMessage",
                                                       body: "Hello there", date: refDate))
        check(full != nil, "full payload should decode")
        check(full!.id == 42, "id maps from rec_id")
        check(full!.title == "Alice", "title maps from titl")
        check(full!.subtitle == "iMessage", "subtitle maps from subt")
        check(full!.body == "Hello there", "body maps from body")
        check(full!.date == Date(timeIntervalSinceReferenceDate: refDate), "date uses Cocoa reference epoch")

        // --- decode: missing subtitle/body tolerated ---
        let titleOnly = decodeNotification(id: 1, bundleId: "x", appName: "X",
                                           payload: payload(titl: "Ping"))
        check(titleOnly != nil, "title-only payload should decode")
        check(titleOnly!.subtitle.isEmpty && titleOnly!.body.isEmpty, "missing subt/body become empty")

        // --- decode: all-empty payload skipped ---
        check(decodeNotification(id: 2, bundleId: "x", appName: "X", payload: payload()) == nil,
              "all-empty payload is skipped")

        // --- decode: missing `req` skipped ---
        let noReq = try! PropertyListSerialization.data(fromPropertyList: ["other": 1], format: .binary, options: 0)
        check(decodeNotification(id: 3, bundleId: "x", appName: "X", payload: noReq) == nil,
              "payload without req is skipped")

        // --- decode: garbage bytes skipped, no crash ---
        check(decodeNotification(id: 4, bundleId: "x", appName: "X", payload: Data([0x00, 0x01, 0x02])) == nil,
              "undecodable bytes are skipped")

        // --- new-arrival tracker ---
        var tracker = NewArrivalTracker()
        check(tracker.lastSeenId == nil, "tracker starts empty")
        tracker.seed(maxId: 100)                       // seeding emits nothing
        check(tracker.lastSeenId == 100, "seed sets lastSeenId")
        check(tracker.isNew(99) == false, "older id is not new")
        check(tracker.isNew(100) == false, "equal id is not new")
        check(tracker.isNew(101) == true, "higher id is new")
        tracker.advance(to: 105)
        check(tracker.lastSeenId == 105, "advance moves lastSeenId forward")
        tracker.advance(to: 103)
        check(tracker.lastSeenId == 105, "advance never moves backward")

        // --- prune: drop older than 8h ---
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        func rec(_ id: Int64, ageHours: Double) -> NotificationRecord {
            NotificationRecord(id: id, bundleId: "b", appName: "B", title: "t",
                               subtitle: "", body: "", date: now.addingTimeInterval(-ageHours * 3600))
        }
        let pruned = prune([rec(1, ageHours: 9), rec(2, ageHours: 7.9), rec(3, ageHours: 0)],
                           now: now, maxAge: 8 * 3600)
        check(pruned.map(\.id) == [2, 3], "prune drops records older than 8h, keeps newer")

        // --- groupByApp: per-app, newest-group first, newest-in-group first ---
        func recA(_ id: Int64, bundle: String, app: String, ageMin: Double) -> NotificationRecord {
            NotificationRecord(id: id, bundleId: bundle, appName: app, title: "t",
                               subtitle: "", body: "", date: now.addingTimeInterval(-ageMin * 60))
        }
        let groups = groupByApp([
            recA(1, bundle: "mail", app: "Mail", ageMin: 30),
            recA(2, bundle: "msg", app: "Messages", ageMin: 10),
            recA(3, bundle: "mail", app: "Mail", ageMin: 5),
        ])
        check(groups.map(\.bundleId) == ["mail", "msg"],
              "groups ordered by most-recent record (mail has id=3 at 5min)")
        check(groups[0].records.map(\.id) == [3, 1], "records newest-first within a group")

        print("NotificationDecodingCheck PASSED")
    }
}
```

- [ ] **Step 2: Run the check to verify it fails to compile (functions undefined)**

Run:
```bash
cd app && swiftc -o /tmp/ndc Sources/JustANotch/Core/NotificationModels.swift Sources/JustANotch/Core/NotificationDecoding.swift Tests/NotificationDecodingCheck.swift
```
Expected: FAIL — `NotificationDecoding.swift` does not exist / `decodeNotification` unresolved.

- [ ] **Step 3: Write the implementation**

```swift
// File: Sources/JustANotch/Core/NotificationDecoding.swift
import Foundation

/// Decode a Notification Center `record.data` binary-plist payload into a
/// `NotificationRecord`. Returns nil when the payload cannot be parsed, has no
/// `req` dictionary, or carries no title/subtitle/body text — so callers can
/// skip unusable rows without special-casing.
func decodeNotification(id: Int64, bundleId: String, appName: String, payload: Data) -> NotificationRecord? {
    guard let root = try? PropertyListSerialization.propertyList(from: payload, options: [], format: nil),
          let dict = root as? [String: Any],
          let req = dict["req"] as? [String: Any] else { return nil }

    let title = (req["titl"] as? String) ?? ""
    let subtitle = (req["subt"] as? String) ?? ""
    let body = (req["body"] as? String) ?? ""
    guard !(title.isEmpty && subtitle.isEmpty && body.isEmpty) else { return nil }

    let date: Date
    if let ts = req["date"] as? Double {
        date = Date(timeIntervalSinceReferenceDate: ts)
    } else {
        date = Date(timeIntervalSinceReferenceDate: 0)
    }

    return NotificationRecord(id: id, bundleId: bundleId, appName: appName,
                              title: title, subtitle: subtitle, body: body, date: date)
}

/// Tracks the highest already-seen `rec_id` so only genuinely new rows emit.
struct NewArrivalTracker {
    private(set) var lastSeenId: Int64?

    /// On start, adopt the current max without emitting existing rows as new.
    mutating func seed(maxId: Int64) { lastSeenId = maxId }

    func isNew(_ id: Int64) -> Bool {
        guard let lastSeenId else { return true }
        return id > lastSeenId
    }

    /// Advance the watermark; never moves backward.
    mutating func advance(to id: Int64) {
        lastSeenId = max(lastSeenId ?? Int64.min, id)
    }
}

/// Drop records whose age exceeds `maxAge`, preserving input order.
func prune(_ records: [NotificationRecord], now: Date, maxAge: TimeInterval) -> [NotificationRecord] {
    records.filter { now.timeIntervalSince($0.date) <= maxAge }
}

/// Group a flat record list by bundle id. Groups are ordered by their most
/// recent record (newest first); records within a group are newest first.
func groupByApp(_ records: [NotificationRecord]) -> [NotificationGroup] {
    var order: [String] = []
    var byBundle: [String: [NotificationRecord]] = [:]
    for r in records {
        if byBundle[r.bundleId] == nil { order.append(r.bundleId) }
        byBundle[r.bundleId, default: []].append(r)
    }
    let groups = order.map { bundle -> NotificationGroup in
        let recs = byBundle[bundle]!.sorted { $0.date > $1.date }
        return NotificationGroup(bundleId: bundle, appName: recs.first?.appName ?? bundle, records: recs)
    }
    return groups.sorted { ($0.records.first?.date ?? .distantPast) > ($1.records.first?.date ?? .distantPast) }
}
```

- [ ] **Step 4: Run the check to verify it passes**

Run:
```bash
cd app && swiftc -o /tmp/ndc Sources/JustANotch/Core/NotificationModels.swift Sources/JustANotch/Core/NotificationDecoding.swift Tests/NotificationDecodingCheck.swift && /tmp/ndc
```
Expected: prints `NotificationDecodingCheck PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/Core/NotificationDecoding.swift app/Tests/NotificationDecodingCheck.swift
git commit -m "feat(notifications): pure decode/arrival/prune/group logic + checks"
```

---

## Task 3: NotificationService (SQLite reader + publishers)

Not unit-tested (touches the live DB / AppKit); correctness is verified by
running the app in Task 7. Keep it thin — the logic it calls is already tested.

**Files:**
- Create: `app/Sources/JustANotch/Core/NotificationService.swift`

- [ ] **Step 1: Write the protocol + service**

```swift
// File: Sources/JustANotch/Core/NotificationService.swift
import Foundation
import Combine
import AppKit
import SQLite3

protocol NotificationServiceProtocol: AnyObject {
    /// Fires once per newly delivered notification (drives the HUD).
    var latestArrival: PassthroughSubject<NotificationRecord, Never> { get }
    /// Retained history, newest first, already pruned to the last 8 hours.
    var history: CurrentValueSubject<[NotificationRecord], Never> { get }
    /// Whether the Notification Center database can be read.
    var permissionState: CurrentValueSubject<NotificationPermissionState, Never> { get }
    /// Cached app icon for a bundle id (generic bell fallback).
    func icon(forBundle bundleId: String) -> NSImage
    func start()
    func stop()
}

final class NotificationService: NotificationServiceProtocol {
    let latestArrival = PassthroughSubject<NotificationRecord, Never>()
    let history = CurrentValueSubject<[NotificationRecord], Never>([])
    let permissionState = CurrentValueSubject<NotificationPermissionState, Never>(.unknown)

    private let maxAge: TimeInterval = 8 * 3600
    private let queue = DispatchQueue(label: "com.notchisland.notifications", qos: .utility)
    private var pollTimer: DispatchSourceTimer?
    private var db: OpaquePointer?
    private var tracker = NewArrivalTracker()

    // Accessed only on `queue`.
    private var records: [NotificationRecord] = []
    private var iconCache: [String: NSImage] = [:]
    private var nameCache: [String: String] = [:]

    private static let dbPath = ("~/Library/Group Containers/group.com.apple.usernoted/db2/db" as NSString)
        .expandingTildeInPath

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 2.0)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        pollTimer = t
    }

    func stop() {
        pollTimer?.cancel(); pollTimer = nil
        if let db { sqlite3_close(db) }
        db = nil
    }

    // MARK: - Poll loop (on `queue`)

    private func tick() {
        guard ensureOpen() else { return }   // sets .denied + leaves db nil on failure
        if tracker.lastSeenId == nil { seedWatermark(); return }
        fetchNewRows()
        pruneAndPublish()
    }

    /// Open the DB read-only if not already open. Publishes permission state.
    private func ensureOpen() -> Bool {
        if db != nil { return true }
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(Self.dbPath, &handle, SQLITE_OPEN_READONLY, nil)
        if rc == SQLITE_OK, let handle {
            db = handle
            publishPermission(.granted)
            return true
        }
        if let handle { sqlite3_close(handle) }
        publishPermission(.denied)
        return false
    }

    private func seedWatermark() {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &stmt, nil) == SQLITE_OK else {
            tracker.seed(maxId: 0); return
        }
        let maxId: Int64 = sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
        tracker.seed(maxId: maxId)
    }

    private func fetchNewRows() {
        guard let lastSeen = tracker.lastSeenId else { return }
        let sql = """
        SELECT r.rec_id, a.identifier, r.data
        FROM record r JOIN app a ON a.app_id = r.app_id
        WHERE r.rec_id > ? ORDER BY r.rec_id ASC
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(stmt, 1, lastSeen)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let recId = sqlite3_column_int64(stmt, 0)
            let bundleId = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            guard let blob = sqlite3_column_blob(stmt, 2) else { tracker.advance(to: recId); continue }
            let len = Int(sqlite3_column_bytes(stmt, 2))
            let data = Data(bytes: blob, count: len)

            tracker.advance(to: recId)
            let appName = displayName(forBundle: bundleId)
            guard let record = decodeNotification(id: recId, bundleId: bundleId,
                                                  appName: appName, payload: data) else { continue }
            records.append(record)
            let arrival = record
            DispatchQueue.main.async { [weak self] in self?.latestArrival.send(arrival) }
        }
    }

    private func pruneAndPublish() {
        records = prune(records, now: Date(), maxAge: maxAge)
        let snapshot = records.sorted { $0.date > $1.date }   // newest first
        DispatchQueue.main.async { [weak self] in self?.history.send(snapshot) }
    }

    private func publishPermission(_ state: NotificationPermissionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.permissionState.value != state else { return }
            self.permissionState.send(state)
        }
    }

    // MARK: - App metadata (on `queue`, cached)

    private func appURL(forBundle bundleId: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    private func displayName(forBundle bundleId: String) -> String {
        if let cached = nameCache[bundleId] { return cached }
        let name = appURL(forBundle: bundleId).flatMap {
            FileManager.default.displayName(atPath: $0.path)
        }?.replacingOccurrences(of: ".app", with: "") ?? bundleId
        nameCache[bundleId] = name
        return name
    }

    func icon(forBundle bundleId: String) -> NSImage {
        // Safe to call from the main thread; cache is only mutated on `queue`,
        // but reads of NSImage here are fine for display. Guard with a sync hop.
        queue.sync {
            if let cached = iconCache[bundleId] { return cached }
            let image: NSImage
            if let url = appURL(forBundle: bundleId) {
                image = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil) ?? NSImage()
            }
            iconCache[bundleId] = image
            return image
        }
    }
}
```

- [ ] **Step 2: Verify the whole target still builds**

Run: `cd app && swift build -c debug --product JustANotch`
Expected: build succeeds (service compiles; not yet wired to UI).

- [ ] **Step 3: Commit**

```bash
git add app/Sources/JustANotch/Core/NotificationService.swift
git commit -m "feat(notifications): NotificationService SQLite reader + publishers"
```

---

## Task 4: ViewModel — inject service, HUD + history state

**Files:**
- Modify: `app/Sources/JustANotch/NotchViewModel.swift`

- [ ] **Step 1: Add published state + init parameter**

In `NotchViewModel`, add these published properties near the existing ones
(after `titleReveal` on line 17):

```swift
    // MARK: Notifications
    /// Banner currently popped over the compact surface, or nil.
    @Published var hudNotification: NotificationRecord?
    /// Retained history (newest first) for the Notifications tab.
    @Published var notifications: [NotificationRecord] = []
    /// True when the Notification Center DB can't be read (needs Full Disk Access).
    @Published var notificationsPermissionDenied = false
    private var hudClearWork: DispatchWorkItem?
    let hudDuration: TimeInterval = 4
```

Add the service dependency. Change the stored property block (after
`private let media: MediaServiceProtocol` on line 27):

```swift
    private let media: MediaServiceProtocol
    private let notifier: NotificationServiceProtocol
    private var bag = Set<AnyCancellable>()
```

Change `init` (lines 30-36) to:

```swift
    init(media: MediaServiceProtocol, notifier: NotificationServiceProtocol) {
        self.media = media
        self.notifier = notifier
        media.currentTrack.receive(on: RunLoop.main).sink { [weak self] track in
            self?.handleTrack(track)
        }.store(in: &bag)
        media.playbackState.receive(on: RunLoop.main).sink { [weak self] in self?.playback = $0 }.store(in: &bag)

        notifier.history.receive(on: RunLoop.main)
            .sink { [weak self] in self?.notifications = $0 }.store(in: &bag)
        notifier.permissionState.receive(on: RunLoop.main)
            .sink { [weak self] in self?.notificationsPermissionDenied = ($0 == .denied) }.store(in: &bag)
        notifier.latestArrival.receive(on: RunLoop.main)
            .sink { [weak self] in self?.showHUD($0) }.store(in: &bag)
    }
```

- [ ] **Step 2: Add HUD actions and start the service**

Add these methods (place after `refreshMedia()` on line 122):

```swift
    /// Icon for a notification's source app (delegates to the service cache).
    func notificationIcon(_ bundleId: String) -> NSImage { notifier.icon(forBundle: bundleId) }

    /// Grouped history for the Notifications tab.
    var notificationGroups: [NotificationGroup] { groupByApp(notifications) }

    /// Pop a HUD banner; latest arrival replaces any current one (no queue).
    /// Suppressed while expanded so it doesn't fight the open player.
    private func showHUD(_ record: NotificationRecord) {
        guard !expanded else { return }
        hudClearWork?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { hudNotification = record }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { self?.hudNotification = nil }
        }
        hudClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hudDuration, execute: work)
    }

    /// Activate the app that sent the current HUD notification, then clear it.
    func openSourceApp() {
        guard let record = hudNotification,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.bundleId) else {
            clearHUD(); return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        clearHUD()
    }

    func clearHUD() {
        hudClearWork?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { hudNotification = nil }
    }
```

Change `start()` (line 141) to also start the notifier:

```swift
    func start() { media.start(); media.refresh(); notifier.start() }
```

Add `import AppKit` at the top of the file (after `import Combine` on line 2) —
`NSWorkspace`/`NSImage` are used now.

- [ ] **Step 3: Add HUD geometry**

The compact surface has three states now. Add a HUD flag and fold it into the
geometry. After `var isPlaying` (line 77) add:

```swift
    /// The HUD takes over the compact surface while a banner is showing and the
    /// panel is not expanded.
    var showingHUD: Bool { hudNotification != nil && !expanded }
    let hudWidth: CGFloat = 412
    let hudHeight: CGFloat = 56
```

Update the surface geometry accessors. Replace `surfaceWidth` / `surfaceHeight`
/ `centerXOffset` / `bottomRadius` (lines 108-115) with:

```swift
    var surfaceWidth: CGFloat {
        if showingHUD { return hudWidth }
        return expanded ? expandedWidth : compactWidth
    }
    var surfaceHeight: CGFloat {
        if showingHUD { return hudHeight }
        return isListOpen ? listExpandedHeight : (expanded ? expandedHeight : compactHeight)
    }
    /// Keep the camera core centred on the notch: shift by half the reveal imbalance.
    /// HUD and expanded are both centred, so no shift.
    var centerXOffset: CGFloat { (expanded || showingHUD) ? 0 : (rightReveal - leftReveal) / 2 }

    var bottomRadius: CGFloat {
        if showingHUD { return 22 }
        return expanded ? 26 : (compactState == .quiet ? 10 : 14)
    }
```

- [ ] **Step 4: Verify it compiles (expect UI/controller call-site errors next task)**

Run: `cd app && swiftc -parse Sources/JustANotch/NotchViewModel.swift Sources/JustANotch/Core/NotificationModels.swift Sources/JustANotch/Core/NotificationDecoding.swift`
Expected: parses (the `init`/`start` call-site breakage lives in other files,
fixed in Tasks 5-6). A full `swift build` will still fail until those are done.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/NotchViewModel.swift
git commit -m "feat(notifications): ViewModel HUD + history state and geometry"
```

---

## Task 5: UI — HUD banner + Notifications tab panel

**Files:**
- Modify: `app/Sources/JustANotch/UI/NotchRootView.swift`

- [ ] **Step 1: Render the HUD in the surface**

In `surface` (lines 42-51), the `ZStack` currently shows `player` when expanded
else `compact` when `hasMedia`. Replace that `if/else if` block so the HUD wins
when showing:

```swift
            if vm.showingHUD {
                hudBanner.transition(.blurFade)
            } else if vm.expanded {
                player.transition(.blurFade)
            } else if vm.hasMedia {
                compact.transition(.blurFade)
            }
```

Add `showingHUD` to the animated values on the outer surface. In `body`
(after line 34, `.animation(openSpring, value: vm.showList)`), add:

```swift
                .animation(revealSpring, value: vm.showingHUD)
```

Update the tap gesture in `surface` (lines 54-56) so a HUD tap opens the source
app instead of expanding:

```swift
        .onTapGesture {
            if vm.showingHUD { vm.openSourceApp(); return }
            if !vm.expanded { vm.refreshMedia(); withAnimation(openSpring) { vm.expanded = true } }
        }
```

- [ ] **Step 2: Add the HUD banner view**

Add this computed view to `NotchRootView` (place after `compact`, before
`player`, around line 86):

```swift
    // MARK: HUD banner (transient notification pop)

    private var hudBanner: some View {
        HStack(spacing: 11) {
            if let n = vm.hudNotification {
                Image(nsImage: vm.notificationIcon(n.bundleId))
                    .resizable().interpolation(.high)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.title.isEmpty ? n.appName : n.title)
                        .font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                    if !n.detailLine.isEmpty {
                        Text(n.detailLine)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, vm.notchHeight + 4)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .frame(width: vm.hudWidth, height: vm.hudHeight, alignment: .leading)
    }
```

- [ ] **Step 3: Route the Notifications tab to a real panel**

In `content` (lines 115-120), add a `.notifications` case:

```swift
    @ViewBuilder private var content: some View {
        switch railTab {
        case .music:         musicPanel
        case .notifications: notificationsPanel
        default:             placeholderPanel(railTab)
        }
    }
```

- [ ] **Step 4: Add the Notifications panel view**

Add after `placeholderPanel` (around line 234):

```swift
    // MARK: Notifications tab

    @ViewBuilder private var notificationsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vm.notificationsPermissionDenied {
                notificationsPermissionPrompt
            } else if vm.notifications.isEmpty {
                Text("Chưa có thông báo")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.notificationGroups) { group in
                            notificationGroupView(group)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func notificationGroupView(_ group: NotificationGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(nsImage: vm.notificationIcon(group.bundleId))
                    .resizable().interpolation(.high).frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(group.appName)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            }
            ForEach(group.records) { rec in notificationRow(rec) }
        }
    }

    private func notificationRow(_ rec: NotificationRecord) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(rec.title.isEmpty ? rec.appName : rec.title)
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                Spacer(minLength: 4)
                Text(Self.relativeTime(rec.date))
                    .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
            }
            if !rec.detailLine.isEmpty {
                Text(rec.detailLine)
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
        }
        .padding(.leading, 23)
    }

    private var notificationsPermissionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cần Full Disk Access")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            Text("Để hiện thông báo hệ thống, cấp quyền Full Disk Access cho Just a Notch trong System Settings.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Mở System Settings")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Compact Vietnamese relative time ("5 phút trước", "2 giờ trước").
    private static func relativeTime(_ date: Date) -> String {
        let s = max(0, Date().timeIntervalSince(date))
        if s < 60 { return "vừa xong" }
        if s < 3600 { return "\(Int(s / 60)) phút trước" }
        return "\(Int(s / 3600)) giờ trước"
    }
```

- [ ] **Step 5: Build (still expect controller init error until Task 6)**

Run: `cd app && swift build -c debug --product JustANotch 2>&1 | tail -5`
Expected: the only remaining error is `NotchWindowController` calling
`NotchViewModel(media:)` without `notifier:` — fixed next task.

- [ ] **Step 6: Commit**

```bash
git add app/Sources/JustANotch/UI/NotchRootView.swift
git commit -m "feat(notifications): HUD banner surface + Notifications tab panel"
```

---

## Task 6: Wire the service into the window controller

**Files:**
- Modify: `app/Sources/JustANotch/NotchWindowController.swift`

- [ ] **Step 1: Construct and own the service**

Add a stored property (after `private let media: MediaService` on line 20):

```swift
    private let notifier: NotificationService
```

In `init` (lines 27-31), construct the service and pass it to the ViewModel:

```swift
    init() {
        media = MediaService()
        notifier = NotificationService()
        vm = NotchViewModel(media: media, notifier: notifier)
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40))
        panel.contentView = ClickableHostingView(rootView: NotchRootView(vm: vm))
        panel.orderFrontRegardless()
```

(`vm.start()` on line 37 already starts the notifier via Task 4's change.)

- [ ] **Step 2: Make the HUD interactive + hit-testable**

The panel currently flips `ignoresMouseEvents` off only when expanded. Extend
that so the HUD banner also receives clicks. Replace the `vm.$expanded`
subscription (lines 40-42) with a combined one:

```swift
        // While expanded OR while a HUD banner is showing, the panel must receive
        // clicks (controls / tap-to-open-source-app).
        vm.$expanded.combineLatest(vm.$hudNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] exp, hud in
                if exp || hud != nil { self?.panel.ignoresMouseEvents = false }
                self?.updateHover()
            }.store(in: &bag)
```

- [ ] **Step 3: Include the HUD in the island rect**

Update `islandScreenRect` (lines 68-74) so hover/click hit-testing covers the
HUD's centred banner:

```swift
    private var islandScreenRect: CGRect {
        let w = vm.surfaceWidth, h = vm.surfaceHeight
        let centred = vm.expanded || vm.showingHUD
        let left: CGFloat = centred
            ? coreCenterX - w / 2
            : coreCenterX - vm.coreWidth / 2 - vm.leftReveal
        return CGRect(x: left, y: screenTopY - h, width: w, height: h)
    }
```

`updateHover` (lines 110-115) already sets `ignoresMouseEvents` from
`vm.expanded`; extend its guard so the HUD stays interactive:

```swift
    private func updateHover() {
        let inside = islandScreenRect.contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = (vm.expanded || vm.showingHUD) ? false : !inside
        let hover = inside && !vm.expanded
        if vm.hovering != hover { vm.hovering = hover }
    }
```

- [ ] **Step 4: Build the full app**

Run: `cd app && swift build -c debug --product JustANotch 2>&1 | tail -5`
Expected: `Build complete!`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add app/Sources/JustANotch/NotchWindowController.swift
git commit -m "feat(notifications): wire service into window controller + HUD hit-testing"
```

---

## Task 7: Assemble, grant access, and verify live

**Files:** none (build/verify + docs).

- [ ] **Step 1: Assemble the app bundle**

Run: `cd app && ./scripts/build_app.sh debug`
Expected: `==> Done: .../build/Just a Notch.app`.

- [ ] **Step 2: Grant Full Disk Access (one-time, manual — user action)**

Launch the app (`open "app/build/Just a Notch.app"`), open the notch, scroll the
rail to **Notifications**. It should show the "Cần Full Disk Access" prompt. Ask
the user to:
1. Click **Mở System Settings** (or open Settings → Privacy & Security → Full
   Disk Access).
2. Add / enable **Just a Notch**.
3. Quit and relaunch the app.

> Full Disk Access requires the user's action in System Settings — Claude cannot
> grant it. Surface this explicitly and wait for confirmation.

- [ ] **Step 3: Verify HUD pop**

With access granted, trigger a notification (e.g. send yourself an iMessage, or
run `osascript -e 'display notification "test body" with title "Test"'` — note:
`osascript`/Script Editor notifications appear under that app's bundle id and
are a quick smoke test). Confirm the notch pops the HUD banner (icon + title +
body), holds ~4s, and retracts.

- [ ] **Step 4: Verify history + grouping + open-source-app**

Open the notch → Notifications tab. Confirm recent notifications appear grouped
by app, newest first, with relative timestamps. Click a HUD banner while it's
showing and confirm the source app activates.

- [ ] **Step 5: Confirm the pure-logic check still passes**

Run:
```bash
cd app && swiftc -o /tmp/ndc Sources/JustANotch/Core/NotificationModels.swift Sources/JustANotch/Core/NotificationDecoding.swift Tests/NotificationDecodingCheck.swift && /tmp/ndc
```
Expected: `NotificationDecodingCheck PASSED`.

- [ ] **Step 6: Note Full Disk Access in the run docs**

Append a short note to `CLAUDE.md` (or a README if the user prefers) that the
Notifications feature needs Full Disk Access granted once in System Settings.

```markdown
## 3. Notifications feature cần Full Disk Access
- Tính năng mirror thông báo đọc DB Notification Center → cần cấp **Full Disk
  Access** cho "Just a Notch" một lần trong System Settings → Privacy & Security.
- Chưa cấp: tab Notifications hiện prompt hướng dẫn; không crash.
```

- [ ] **Step 7: Commit docs**

```bash
git add CLAUDE.md
git commit -m "docs: note Full Disk Access requirement for notifications"
```

---

## Self-Review

**Spec coverage:**
- Data source / DB path / join / decode → Tasks 2 (decode) + 3 (SQLite).
- New-arrival detection (seed + watermark) → Task 2 `NewArrivalTracker`, Task 3
  `seedWatermark`/`fetchNewRows`.
- 8h prune (poll-driven) → Task 2 `prune`, Task 3 `pruneAndPublish`. *(Note: the
  spec also mentioned a separate low-frequency prune timer; the 2s poll already
  prunes on every tick, so a second timer is redundant — omitted per YAGNI.
  History still empties as long as the app polls, which it always does while
  running.)*
- Full Disk Access degrade + prompt → Task 3 `.denied`, Task 5 prompt, Task 7 grant.
- HUD state / geometry / latest-wins → Task 4.
- HUD banner UI + click-to-open → Tasks 4 (`openSourceApp`) + 5 + 6.
- Notifications tab grouped list → Tasks 2 (`groupByApp`) + 5.
- Window controller HUD hit-testing/mouse → Task 6.
- Model → Task 1. Testing (decode/detect/prune/group) → Task 2.
- Out-of-scope items (clear-all, per-row delete, mute, DND, queue) → not built.

**Placeholder scan:** none — every code step is complete.

**Type consistency:** `decodeNotification(id:bundleId:appName:payload:)`,
`NewArrivalTracker.seed/isNew/advance/lastSeenId`, `prune(_:now:maxAge:)`,
`groupByApp(_:)`, `NotificationRecord(id:bundleId:appName:title:subtitle:body:date:)`,
`NotificationGroup(bundleId:appName:records:)`, `showingHUD`, `hudWidth/hudHeight`,
`openSourceApp()`, `notificationIcon(_:)`, `notificationGroups`,
`NotchViewModel(media:notifier:)` — all used consistently across tasks.
