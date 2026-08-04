# Notch Island

A macOS menu-bar utility that turns the MacBook notch (or a simulated notch on
any Mac) into an interactive Dynamic-Island-style overlay.

> **Status: MVP complete (Phases 1–8, trimmed scope).** The app builds, bundles,
> launches, and shows an interactive compact/expanded island anchored to the
> top-centre of the screen — with Finder Shelf, live System
> status, Media control (Music / Spotify / YouTube-in-browser), app
> notifications, a full tabbed Settings window, custom global-shortcut recording,
> Launch-at-Login, a permissions panel, and a 3-step first-run onboarding wizard.
> Scope was trimmed per the QC notes in *Known Limitations*. The
> Command-Line-Tools check runner currently contains 172 assertions; an XCTest
> suite is also available when full Xcode is installed.

## Screenshots

_TODO: add screenshots of compact and expanded states._

## Requirements

- macOS 13 Ventura or later (deployment target `.macOS(.v13)`).
- Apple Silicon or Intel.
- **To build:** Swift 5.9 toolchain. Full **Xcode** is recommended (also required
  to run the XCTest suite). The app *target* additionally builds with **Command
  Line Tools** alone via SwiftPM.

## Build & Run

This is a SwiftPM package — open `Package.swift` directly in Xcode, **or** build
from the terminal:

```bash
# Compile the app target
swift build -c release

# Assemble and launch a runnable .app bundle (works with CLT-only)
./scripts/build_app.sh release
open "build/Notch Island.app"
```

### Testing — two ways

The pure logic can be verified with or without Xcode:

```bash
# 1. No Xcode needed — plain executable check runner (Command Line Tools only)
swift run NotchIslandChecks

# 2. Full XCTest suite (requires Xcode — XCTest is not in Command Line Tools)
swift test
```

`swift run NotchIslandChecks` runs 172 assertions over the state machine,
settings migration, media parsing, system formatting, compact geometry, shell
motion, and tab-transition behavior, exiting non-zero on any failure.

## Permissions

Notch Island requests permissions **lazily**, only when you enable the feature
that needs them:

| Permission     | Needed for                                   | When requested            |
|----------------|----------------------------------------------|---------------------------|
| Automation     | Controlling Music / Spotify (Phase 5)        | On enabling media control |
| Notifications  | App-owned notifications (Phase 6)            | On enabling notifications |
| Files & Folders| Finder Shelf bookmarks (Phase 3)            | On pinning via open panel |
| Accessibility  | Experimental notification mirroring (opt-in) | Experimental only         |

Denied permissions never crash the app; the affected feature shows an
unavailable state with a link to System Settings.

## Feature Matrix

| Feature                         | Status         | Notes                                       |
|---------------------------------|----------------|---------------------------------------------|
| Menu-bar utility (no Dock icon) | ✅ Working     | `LSUIElement`, `NSStatusItem` menu          |
| Floating notch panel            | ✅ Working     | Borderless non-activating `NSPanel`         |
| Top-centre anchoring            | ✅ Working     | Repositions on screen/space/wake changes    |
| Notch detection                 | ✅ Working     | `safeAreaInsets` + auxiliary top areas      |
| Simulated notch                 | ✅ Working     | For Macs without a physical notch           |
| Compact / expanded states       | ✅ Working     | Deterministic state machine + animation     |
| Hover / click / dismiss / pin   | ✅ Working     | Hover delay + auto-collapse timers          |
| Internal event surfacing        | ✅ Working     | Priority-based transient takeover           |
| Settings persistence            | ✅ Working     | `UserDefaults` + schema migration           |
| Finder Shelf                    | ✅ Working     | Pin/open/reveal, bookmarks, drag-in, search |
| Global shortcut (⌥⌘Space)       | ✅ Working     | `NSEvent` monitor; needs Accessibility      |
| System status                   | ✅ Working     | Battery, CPU, memory, disk (live polling)   |
| Media — Music / Spotify         | ✅ Working     | AppleScript; needs Automation permission    |
| Media — YouTube in browser      | 🟡 Best-effort | Reads tab title; control needs JS-from-AE   |
| App notifications               | ✅ Working     | `UNUserNotificationCenter`, lazy auth       |
| Full Settings (tabbed)          | ✅ Working     | General/Appearance/Features/Shortcuts/…     |
| Custom shortcut recording       | ✅ Working     | Records + persists; re-registers live       |
| Launch at Login                 | ✅ Working     | `SMAppService` (macOS 13+)                   |
| Permissions panel               | ✅ Working     | Status + deep link to System Settings       |
| Onboarding wizard (3-step)      | ✅ Working     | First-run; lazy permission requests         |
| Media system-wide / mirroring   | ❌ Cut         | Private/scraping API — removed from scope   |

## Architecture

MVVM + service layer. UI never performs system integration directly; each
integration is a protocol-backed service that can be mocked.

```
Sources/NotchIsland/
├── App/            NotchIslandApp, AppDelegate, AppEnvironment (DI)
├── Core/
│   ├── Models/     IslandState (state, content, events)
│   └── Utilities/  Log (OSLog categories)
├── Window/         NotchPanel, NotchPanelController, NotchGeometryProvider
├── Island/         IslandStateMachine, IslandViewModel, Root/Compact/Expanded views
│   └── Components/  NotchShape
└── Persistence/    SettingsStore
Tests/NotchIslandTests/
```

- `IslandStateMachine` is a **pure value type** — fully unit-tested, no AppKit.
- `IslandViewModel` owns hover-delay / auto-collapse / event-expiry timers.
- `NotchPanelController` keeps the panel anchored across geometry changes.

## Known Limitations

- **XCTest requires full Xcode.** With Command Line Tools only, the app builds
  but `swift test` cannot run (XCTest.framework is absent).
- **Notch geometry** on physical-notch Macs uses public `safeAreaInsets` /
  `auxiliaryTop*Area`; verify on real hardware and use the alignment offset /
  simulated mode as a fallback.
- **YouTube media** is best-effort: the video title is read from the active
  Safari/Chrome tab (needs Automation permission). Play/pause/next inject
  JavaScript. In Chrome, enable **View › Developer › Allow JavaScript from
  Apple Events**; otherwise controls no-op. No artwork/progress.
- System-wide media (`MediaRemote`) and full Notification Center mirroring are
  **not** public API and are gated behind experimental compile flags (off by
  default) — the default Release build links only public API.

## Privacy

No telemetry. Notification content is never logged or persisted by default.
Security-scoped bookmarks (Phase 3) stay local.

## Development

Phased plan (see prompt): 1) Foundation ✅ · 2) Interaction ✅ · 3) Finder Shelf ·
4) System status · 5) Media · 6) Notifications · 7) Settings +
onboarding · 8) Tests + release prep.

## Release build & experimental flags

```bash
swift build -c release
# Experimental (NOT App Store safe, off by default):
swift build -c release -Xswiftc -DEXPERIMENTAL_MEDIA_REMOTE
swift build -c release -Xswiftc -DEXPERIMENTAL_NOTIFICATION_MIRRORING
```

The default Release build uses only public Apple API — no private frameworks,
no SIP changes, no root, no process injection.
