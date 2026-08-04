# Focused Island Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the launcher-like Quick Actions experience and make the island stable, media-focused, and responsive to its settings.

**Architecture:** Keep state transitions in `IslandStateMachine`, make the view model choose only valid user-facing content, and connect focused UI controls to the panel controller through explicit callbacks. Preserve public-API media adapters while tightening availability behavior.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Combine, SwiftPM, XCTest/check runner.

## Global Constraints

- macOS 13+; public Apple APIs only.
- Do not use `MediaRemote` or notification mirroring.
- Follow TDD: every production behavior change starts with a failing test.
- Run `swift run NotchIslandChecks` and `swift build -c release --product NotchIsland` after implementation.

---

### Task 1: Stabilize island content and transient events

**Files:**
- Modify: `Sources/NotchIslandKit/Island/IslandStateMachine.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandViewModel.swift`
- Modify: `Tests/Checks/main.swift`
- Modify: `Tests/NotchIslandTests/IslandStateMachineTests.swift`

**Interfaces:**
- Consumes: `IslandInput`, `IslandPresentationState`, `IslandEvent`.
- Produces: user actions that cancel transient restoration and events that only take over compact/hover state.

- [ ] **Step 1: Write failing regression tests**

```swift
func testHighPriorityEventDoesNotInterruptExpandedContent() {
    var machine = IslandStateMachine()
    machine.handle(.clicked(.systemStatus))
    let event = IslandEvent(type: .systemAlert, priority: .high,
                            payload: IslandEventPayload(title: "Low battery"))
    XCTAssertEqual(machine.handle(.event(event)), .expanded(.systemStatus))
}

func testDismissCancelsTransientRestoration() {
    var machine = IslandStateMachine()
    machine.handle(.clicked(.finderShelf))
    machine.handle(.pin)
    let event = IslandEvent(type: .systemAlert, priority: .high,
                            payload: IslandEventPayload(title: "Low battery"))
    machine.handle(.event(event))
    XCTAssertEqual(machine.handle(.dismiss), .compact)
    XCTAssertEqual(machine.handle(.eventExpired(event.id)), .compact)
}
```

- [ ] **Step 2: Run the check runner and confirm the new assertions fail**

Run: `swift run NotchIslandChecks`

Expected: the two transition assertions fail before the state-machine change.

- [ ] **Step 3: Implement the minimal transition policy**

```swift
case .dismiss:
    activeTransientEventID = nil
    interruptedState = nil
    if case .pinned = state { break }
    if case .editing = state { break }
    state = .compact

private mutating func handleEvent(_ event: IslandEvent) {
    guard event.priority >= .high else { return }
    switch state {
    case .compact, .hoverPreview: break
    default: return
    }
    interruptedState = state
    activeTransientEventID = event.id
    state = .expanded(event.payload.content ?? .notification)
}
```

- [ ] **Step 4: Re-run the focused check runner and XCTest suite where available**

Run: `swift run NotchIslandChecks`

Expected: all checks pass; the XCTest assertions compile/run on a full-Xcode machine.

### Task 2: Remove Quick Actions from the product surface

**Files:**
- Modify: `Sources/NotchIslandKit/Core/Models/IslandState.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandRootView.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandExpandedView.swift`
- Modify: `Sources/NotchIslandKit/App/AppEnvironment.swift`
- Modify: `Sources/NotchIslandKit/App/AppDelegate.swift`
- Modify: `Sources/NotchIslandKit/App/SettingsView.swift`
- Modify: `Sources/NotchIslandKit/App/OnboardingView.swift`
- Modify: `Tests/Checks/main.swift`

**Interfaces:**
- Consumes: island content enum and settings.
- Produces: compact opening behavior that chooses Media or System and no Actions tab/default launcher behavior.

- [ ] **Step 1: Write failing tests for the default content policy**

```swift
expect(IslandDefaultContent.select(mediaAvailable: true) == .media,
       "available media is selected first")
expect(IslandDefaultContent.select(mediaAvailable: false) == .systemStatus,
       "system is selected when media is unavailable")
```

- [ ] **Step 2: Run the check runner and confirm the new helper is unavailable**

Run: `swift run NotchIslandChecks`

Expected: compile failure for the missing selection helper.

- [ ] **Step 3: Implement the focused content policy and delete launcher wiring**

```swift
enum IslandDefaultContent {
    static func select(mediaAvailable: Bool) -> IslandContent {
        mediaAvailable ? .media : .systemStatus
    }
}
```

Remove `.quickActions` from `IslandContent`, tab construction, Settings, onboarding, environment wiring, and launch/toggle handlers. Remove `postWelcomeEvent()` and any call to it. Keep persisted legacy keys harmlessly ignored so existing preferences do not crash migration.

- [ ] **Step 4: Run checks and release compile**

Run: `swift run NotchIslandChecks && swift build -c release --product NotchIsland`

Expected: all checks pass and there are no references to `quickActions` outside retired service files.

### Task 3: Make Finder search focusable and menu-bar icon reactive

**Files:**
- Modify: `Sources/NotchIslandKit/Island/Components/FeaturePanels.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandExpandedView.swift`
- Modify: `Sources/NotchIslandKit/Window/NotchPanelController.swift`
- Modify: `Sources/NotchIslandKit/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `FinderShelfPanel`, `NotchPanelController.setAcceptsKeyboard(_:)`, `SettingsStore.$showMenuBarIcon`.
- Produces: focus callback that allows text entry only while Finder search is focused and immediate menu-item installation/removal.

- [ ] **Step 1: Add a focused UI contract test or compile-time test fixture**

Add a testable controller-free callback contract: Finder panel receives `onSearchFocusChanged: (Bool) -> Void` and invokes it from focus state changes.

- [ ] **Step 2: Verify the project does not yet satisfy the new contract**

Run: `swift build -c debug --product NotchIsland`

Expected: compilation fails until the callback is threaded through the expanded view and controller.

- [ ] **Step 3: Implement explicit focus and status-item lifecycle methods**

```swift
@FocusState private var searchFocused: Bool
.onChange(of: searchFocused) { onSearchFocusChanged($0) }

private func updateStatusItem(visible: Bool) {
    if visible { setupStatusItem() } else { statusItem = nil }
}
```

Pass `panelController?.setAcceptsKeyboard` as the focus callback and subscribe to `$showMenuBarIcon.dropFirst()` in `AppDelegate`.

- [ ] **Step 4: Build release**

Run: `swift build -c release --product NotchIsland`

Expected: successful build; manual verification can focus/blur Finder search and toggle the status item without restart.

### Task 4: Make media availability honest and polish the empty state

**Files:**
- Modify: `Sources/NotchIslandKit/Services/MediaService.swift`
- Modify: `Sources/NotchIslandKit/Island/Components/FeaturePanels.swift`
- Modify: `Tests/Checks/main.swift`
- Modify: `Tests/NotchIslandTests/ServiceLogicTests.swift`

**Interfaces:**
- Consumes: `MediaAdapter.fetch() -> (track: MediaTrack?, state: PlaybackState)`.
- Produces: an empty-media presentation based on real service state, never an implicit playing state.

- [ ] **Step 1: Write failing media-source selection tests**

```swift
let adapter = StubMediaAdapter(running: true, track: nil, state: .stopped)
let service = MediaService(adapters: [adapter])
service.pollSynchronouslyForTesting()
expect(service.currentTrack.value == nil, "stopped source has no track")
expect(service.playbackState.value == .stopped, "stopped source stays stopped")
```

Define the test-only `StubMediaAdapter` in the check runner and add the
internal `pollSynchronouslyForTesting()` seam to `MediaService`.

- [ ] **Step 2: Run the focused checks and observe the intended failure**

Run: `swift run NotchIslandChecks`

Expected: the stopped/empty-source assertion fails before the service seam or selection change.

- [ ] **Step 3: Implement the smallest media-state correction and UI copy**

Keep `.unsupported` only when no source is running. For a running source that cannot return a track, preserve its reported playback state and show “Open Music, Spotify, or a YouTube video. Grant Automation when macOS asks.” Controls stay hidden unless a track is available.

- [ ] **Step 4: Run full available verification**

Run: `swift run NotchIslandChecks && swift build -c release --product NotchIsland`

Expected: all checks pass and release build succeeds.

### Task 5: Align project documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the feature matrix and testing count**

Remove Quick Actions from the feature matrix/architecture narrative and state that the check runner currently executes 37 assertions.

- [ ] **Step 2: Verify documentation claims against the check output**

Run: `swift run NotchIslandChecks`

Expected: the reported check count matches the README.
