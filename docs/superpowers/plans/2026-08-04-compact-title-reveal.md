# Compact Title Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reveal a compact media title with its left wing, pan long titles after the entrance, and retract only after the title has been visible for at least three seconds and its trailing edge for at least one second.

**Architecture:** Extract the timing calculation into a Foundation-only value type so the interaction contract is unit-testable. `NotchViewModel` uses that value type to schedule the wing retraction, while `MarqueeText` receives the same entrance delay before it starts its single pan.

**Tech Stack:** Swift 5, SwiftUI, Swift Package Manager, XCTest.

## Global Constraints

- Preserve the real-title guard: empty and `YouTube` placeholder titles must not open a blank reading wing.
- Keep the existing 0.42-second compact entrance spring and marquee speed of 34 points per second.
- The title is visible for at least 3 seconds from reveal start.
- The trailing edge remains visible for at least 1 second before retraction.
- Do not commit until the user confirms the feature works.

---

### Task 1: Testable reveal timing

**Files:**
- Modify: `app/Package.swift`
- Create: `app/Tests/JustANotchTests/TitleRevealTimingTests.swift`
- Create: `app/Sources/JustANotch/Core/TitleRevealTiming.swift`

**Interfaces:**
- Produces: `struct TitleRevealTiming` with `init(entrance:pan:)`, `let marqueeDelay: TimeInterval`, `let trailingHold: TimeInterval`, and `let retractionDelay: TimeInterval`.
- `retractionDelay` is measured from title reveal start.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import JustANotch

final class TitleRevealTimingTests: XCTestCase {
    func testShortTitleIsVisibleForThreeSeconds() {
        let timing = TitleRevealTiming(entrance: 0.42, pan: 0)
        XCTAssertEqual(timing.marqueeDelay, 0.42, accuracy: 0.0001)
        XCTAssertEqual(timing.trailingHold, 2.58, accuracy: 0.0001)
        XCTAssertEqual(timing.retractionDelay, 3, accuracy: 0.0001)
    }

    func testLongTitleKeepsTrailingEdgeVisibleForOneSecond() {
        let timing = TitleRevealTiming(entrance: 0.42, pan: 4)
        XCTAssertEqual(timing.trailingHold, 1, accuracy: 0.0001)
        XCTAssertEqual(timing.retractionDelay, 5.42, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the tests and verify they fail because the type is missing**

Run: `swift test --package-path app --filter TitleRevealTimingTests`

Expected: compilation fails because `TitleRevealTiming` is not in scope.

- [ ] **Step 3: Add the test target and minimal production type**

Add this target after `executableTarget` in `app/Package.swift`:

```swift
.testTarget(name: "JustANotchTests", dependencies: ["JustANotch"])
```

Create `TitleRevealTiming.swift`:

```swift
import Foundation

struct TitleRevealTiming {
    let marqueeDelay: TimeInterval
    let trailingHold: TimeInterval
    let retractionDelay: TimeInterval

    init(entrance: TimeInterval, pan: TimeInterval) {
        marqueeDelay = entrance
        trailingHold = max(1, 3 - entrance - pan)
        retractionDelay = entrance + pan + trailingHold
    }
}
```

- [ ] **Step 4: Run the timing tests and verify they pass**

Run: `swift test --package-path app --filter TitleRevealTimingTests`

Expected: both tests pass.

### Task 2: Drive the view model and marquee from the timing contract

**Files:**
- Modify: `app/Sources/JustANotch/NotchViewModel.swift:57-68`
- Modify: `app/Sources/JustANotch/UI/NotchRootView.swift:65-66`
- Modify: `app/Sources/JustANotch/UI/Components.swift:48-76`

**Interfaces:**
- Consumes: `TitleRevealTiming(entrance:pan:)` from Task 1.
- Produces: `MarqueeText(text:viewport:entranceDelay:)` which pans after the compact-wing entrance completes.

- [ ] **Step 1: Update the call site to require the new marquee parameter**

Change the compact title call to:

```swift
MarqueeText(text: track.title, viewport: vm.titleViewport,
            entranceDelay: vm.titleEntranceDuration)
```

Run: `swift build --package-path app`

Expected: compilation fails because the new view-model property and marquee initializer do not yet exist.

- [ ] **Step 2: Implement the minimal shared scheduling**

In `NotchViewModel`, define `let titleEntranceDuration: TimeInterval = 0.42`. In `revealTitleTransiently()`, calculate pan duration from the existing estimated text width and viewport, make `TitleRevealTiming`, and schedule the reset at `timing.retractionDelay` rather than adding a fixed pre-slide hold.

In `MarqueeText`, add `let entranceDelay: TimeInterval` and replace the hard-coded `.delay(1.5)` with `.delay(entranceDelay)`. The first rendered title remains at `offset == 0`, so it appears while the wing expands.

- [ ] **Step 3: Verify unit and package tests**

Run: `swift test --package-path app`

Expected: all tests pass.

### Task 3: Build and visually verify the app

**Files:**
- No source changes expected.

- [ ] **Step 1: Build and relaunch the application**

Run: `app/scripts/run_app.sh`

Expected: the debug app builds and launches without errors.

- [ ] **Step 2: Verify the compact choreography manually**

Check a short real title and a long real title:

1. The title becomes visible while the left wing opens.
2. A long title begins panning just after the wing entrance spring finishes.
3. A short title stays visible for at least three seconds.
4. A long title holds its final characters for at least one second before retracting.
5. A `YouTube` placeholder does not create a blank expanded title wing.

## Plan Self-Review

- Spec coverage: Task 1 enforces the three-second and one-second timing contract; Task 2 connects both UI animations to that contract and preserves the placeholder guard; Task 3 validates the user-visible choreography.
- Placeholder scan: no incomplete tasks or unspecified implementation decisions remain.
- Type consistency: Task 1 defines `TitleRevealTiming`; Task 2 consumes it and provides `entranceDelay` to `MarqueeText`.
