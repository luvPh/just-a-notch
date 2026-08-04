# Notification Mirror

## Goal

Mirror macOS system notifications into the notch. When any app posts a
notification, the notch pops out a short HUD banner for a few seconds, then
retracts. Every mirrored notification is also stored in a history list shown in
the Notifications tab of the expanded panel, grouped by source app. History
entries clear automatically eight hours after they arrive. Clicking a HUD banner
activates the app that sent the notification.

## Constraints

- macOS exposes **no public API** for reading other apps' notifications. The
  only source is the private Notification Center SQLite database.
- Reading that database requires **Full Disk Access** for this app. Without it
  the database cannot be opened, and the feature must degrade gracefully with a
  clear in-app prompt rather than failing silently.
- The database schema is private and may change between macOS releases. The
  reader must tolerate missing columns / undecodable rows without crashing —
  skip a row it cannot parse rather than aborting the whole poll.

## Data source

Database path (per user):
`~/Library/Group Containers/group.com.apple.usernoted/db2/db`

Relevant tables:
- `record` — one row per delivered notification. Columns used: `rec_id`
  (integer rowid, monotonically increasing), `app_id` (FK), `data` (BLOB,
  binary property list), and a delivery timestamp column (`delivered_date` when
  present, else fall back to the date decoded from `data`).
- `app` — maps `app_id` to a bundle identifier. Columns used: `app_id`,
  `identifier` (bundle id string).

Decoding `data`:
- The BLOB is a binary property list. Deserialize with
  `PropertyListSerialization`.
- The notification payload lives under the `req` key as a dictionary with
  `titl` (title), `subt` (subtitle), `body` (body), and `date` (a numeric
  timestamp, Cocoa/`NSDate` reference epoch — 2001-01-01).
- Any of `titl`/`subt`/`body` may be absent; treat missing as empty. A row with
  all three empty is skipped.

New-arrival detection:
- The service tracks the highest `rec_id` it has already emitted (`lastSeenId`).
- On start it reads the current `MAX(rec_id)` and sets `lastSeenId` to it
  **without** emitting anything, so launching the app does not replay old
  notifications as fresh arrivals.
- Each poll runs `SELECT rec_id, app_id, data FROM record WHERE rec_id >
  lastSeenId ORDER BY rec_id ASC`, decodes each row, emits every decoded record
  as an arrival, and advances `lastSeenId` to the max seen.

App metadata:
- Bundle id → display name and icon via `NSWorkspace`:
  `urlForApplication(withBundleIdentifier:)`, then
  `NSWorkspace.shared.icon(forFile:)` and the bundle's display name. Results are
  cached per bundle id (icons are relatively expensive to load).
- If the bundle cannot be resolved, fall back to the bundle id string as the
  name and a generic bell icon.

## Model

```swift
struct NotificationRecord: Identifiable, Equatable {
    let id: Int64          // rec_id — stable, unique, ordered
    let bundleId: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
    // appIcon resolved separately from a cache; not part of Equatable identity.
}
```

`id` is the database `rec_id`, so records are naturally de-duplicated and
ordered.

## NotificationService

New service mirroring the shape and lifecycle of `MediaService`.

Protocol (`NotificationServiceProtocol`):
- `latestArrival: PassthroughSubject<NotificationRecord, Never>` — fires once per
  newly delivered notification. Drives the HUD pop.
- `history: CurrentValueSubject<[NotificationRecord], Never>` — the retained
  list, newest first, already pruned to the last eight hours.
- `permissionState: CurrentValueSubject<PermissionState, Never>` — `.unknown`,
  `.granted`, or `.denied`, derived from whether the database opened.
- `func iconForBundle(_ bundleId: String) -> NSImage` — cached icon lookup.
- `func start()` / `func stop()`.

Behaviour:
- `start()` opens the database read-only. If the open fails (typical when Full
  Disk Access is not granted), set `permissionState = .denied` and retry the
  open on a slow cadence (e.g. every 5 s) so that granting access later recovers
  without a relaunch. On success set `.granted`, seed `lastSeenId`, and begin the
  ~2 s poll timer on a utility `DispatchQueue`.
- Each poll: query new rows, decode, resolve app metadata, append to the
  in-memory history, prune, and publish. Emit each new record on
  `latestArrival`.
- Pruning: drop records with `date` older than eight hours. A prune runs on each
  poll and additionally on a low-frequency timer so history still empties while
  no new notifications arrive.
- All database work stays off the main thread; published values are delivered on
  the main run loop (consumers use `.receive(on: RunLoop.main)`).

## ViewModel additions (`NotchViewModel`)

- `@Published var hudNotification: NotificationRecord?` — the banner currently
  popped, or `nil`.
- `@Published var notifications: [NotificationRecord]` — history for the tab.
- `@Published var notificationsPermissionDenied: Bool` — drives the tab's
  permission prompt.
- Subscribe to the service: `history` updates `notifications`;
  `permissionState` updates the flag; `latestArrival` calls `showHUD(_:)`.
- `showHUD(_ record:)` sets `hudNotification`, and schedules a
  `DispatchWorkItem` to clear it after the display duration
  (`hudDuration = 4 s`). A new arrival cancels the pending clear and replaces the
  banner (latest wins; no queue in v1).
- `openSourceApp(for record:)` activates the sending app via
  `NSWorkspace.shared.openApplication(at:configuration:)` resolved from the
  bundle id, then clears the HUD.

Surface state:
- `compactState` gains precedence handling: while `hudNotification != nil` and
  the panel is **not** expanded, the surface renders the HUD instead of the
  music compact. Music resumes when the HUD clears.
- New geometry for the HUD surface: `hudWidth` (≈ `expandedWidth`, 412) and
  `hudHeight` (≈ 56). These already fit inside the fixed panel canvas
  (`panelWidth` × `expandedHeight`), so no window resize is needed.
- `surfaceWidth` / `surfaceHeight` / `bottomRadius` account for the HUD state
  (rounded like a small expanded surface). The HUD is centred on the notch
  (symmetric), so `centerXOffset` is 0 in this state.
- Tapping the surface while a HUD is showing (and not expanded) calls
  `openSourceApp`. Tapping to expand still works when there is no HUD.

## UI

### HUD banner (new component)
A compact horizontal banner rendered in the surface when in the HUD state:
- Leading: source app icon (~28pt).
- Centre: title (bold, one line, truncated) over body/subtitle (secondary,
  one line, truncated). Body falls back to subtitle when body is empty.
- Enters and exits with the existing `blurFade` transition and the panel's
  spring animation. Clears itself when the ViewModel clears `hudNotification`.
- The whole banner is the tap target → `openSourceApp`.

### Notifications tab (replaces the current placeholder)
When `railTab == .notifications`, render `notificationsPanel` instead of
`placeholderPanel`:
- **Permission denied:** a short message explaining Full Disk Access is
  required, plus a button that opens
  `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`.
  Copy in Vietnamese, consistent with existing tab copy.
- **Empty (granted, no records):** "Chưa có thông báo".
- **Populated:** a vertical `ScrollView` (hidden indicators, matching the queue
  list) of app groups. Each group: a header row with the app icon + app name,
  then its notification rows (newest first) showing title, body/subtitle, and a
  relative timestamp ("5 phút trước"). Groups ordered by their most recent
  notification.

Grouping is derived in the view (or a computed property on the ViewModel) from
`notifications` keyed by `bundleId`; no separate grouped model is stored.

## Window controller

- The HUD is an interactive lightweight state. Extend `islandScreenRect` and
  `updateHover` to use the HUD dimensions when `hudNotification != nil` and not
  expanded, so hover/click hit-testing covers the banner.
- Ensure the panel receives clicks while a HUD is showing (same treatment as
  `expanded`): when `hudNotification` becomes non-nil, set
  `panel.ignoresMouseEvents = false`; restore pass-through logic when it clears.
- Wire the new service into `NotchWindowController` alongside `MediaService`,
  start it in `init`, and pass it into the ViewModel.

## Integration & lifecycle

- `NotchViewModel.init` takes both a `MediaServiceProtocol` and a
  `NotificationServiceProtocol`.
- `NotchWindowController` constructs and owns the `NotificationService`, starts
  it after geometry setup.
- Full Disk Access must be added to the app's requirements. Document in the run
  script / README that the built `.app` needs Full Disk Access granted once in
  System Settings; the in-app prompt guides the user there.

## Error handling

- Database open failure → `.denied` permission state + retry loop; never crash.
- Undecodable row (bad plist, missing `req`, all-empty payload) → skip that row,
  continue the poll.
- Unresolvable bundle id → fall back to bundle id text + generic bell icon.
- `openApplication` failure → clear the HUD; no user-facing error in v1.

## Testing

- **Plist decoding:** a pure function `decodeRecord(appId:bundleId:data:) ->
  NotificationRecord?` unit-tested against sample `req` payloads: full payload,
  missing subtitle, missing body, all-empty (skipped), missing `req` (skipped),
  and the Cocoa-epoch date conversion.
- **New-arrival detection:** `lastSeenId` logic tested with a fake row source —
  seeding on start emits nothing; subsequent higher `rec_id`s emit in order;
  equal/lower ids emit nothing.
- **Pruning:** history prune drops records older than eight hours and keeps
  newer ones, given an injected reference date.
- **Grouping:** grouping of a flat record list into per-app groups, ordered by
  most recent, newest-first within a group.
- SQLite access itself and `NSWorkspace` lookups are isolated behind small
  seams so the logic above is testable without the live database.

## Out of scope (v1)

- Manual "Clear all" and per-row dismissal.
- Per-app mute / filtering.
- Respecting Focus / Do Not Disturb.
- HUD queueing (latest arrival replaces the current banner).
- Notification actions / reply.
