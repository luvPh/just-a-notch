# Hybrid Orbital Notch Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make compact media visible outside the physical camera notch and implement the approved Hybrid B+C shell choreography, anticipation collapse, and interruptible Orbital Portal tab transitions.

**Architecture:** Add pure geometry and transition reducers first, then expose them through two focused observable coordinators. `NotchPanelController` remains responsible for screen/window geometry, while SwiftUI renders the shell, wing content, and composited tab layers from coordinator state. Media polling can update content but cannot select tabs.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Combine, QuartzCore, macOS 13+, existing XCTest-free `NotchIslandChecks` runner.

## Global Constraints

- Keep the deployment target at macOS 13.0.
- Add no third-party dependency and use no private framework.
- Use SF Symbols only; add no emoji or raster control icons.
- Active compact width is `physicalNotchWidth + 166 pt`, with an 83 pt visible wing on each side.
- Fallback core width is 200 pt; fallback active width is 366 pt.
- Quiet width is `coreWidth + 24 pt` and may not be narrower than the core.
- Expansion is 260 ms total with at most 18 pt entry overshoot.
- Collapse is 80 ms anticipation followed by a monotonic 240 ms return with no endpoint rebound.
- The one-shot progress trace lasts 650 ms.
- Orbital Portal timings are: indicator 220 ms, outgoing panel 140 ms, portal icon 280 ms, incoming panel 240 ms, and 60 ms panel overlap.
- Reduced Motion removes spatial motion, anticipation, overshoot, blur, glow, trace, and waveform; retain a 160 ms opacity crossfade.
- App termination from X remains immediate.
- This workspace has no `.git` directory. Record task checkpoints in the plan instead of running `git add` or `git commit`.

---

## File map

- Create `Sources/NotchIslandKit/Island/IslandMotion.swift`: constants, compact geometry, shell reducer, and observable shell coordinator.
- Create `Sources/NotchIslandKit/Island/TabTransitionCoordinator.swift`: tab ordering, direction, transition reducer, and observable tab coordinator.
- Create `Sources/NotchIslandKit/Island/Components/CompactMediaMotionView.swift`: visible media wings, waveform, sweep, trace, and orbital content modifiers.
- Modify `Sources/NotchIslandKit/Island/IslandCompactView.swift`: consume explicit core/wing geometry and delegate active media rendering.
- Modify `Sources/NotchIslandKit/Island/IslandRootView.swift`: own shell coordinator input, use coordinator width, and thread Reduced Motion.
- Modify `Sources/NotchIslandKit/Island/IslandExpandedView.swift`: render outgoing/incoming panel layers, moving indicator, and portal icon.
- Modify `Sources/NotchIslandKit/Window/NotchPanelController.swift`: publish detected core width, coordinate frame timing, and collapse instead of ordering out on outside click.
- Modify `Sources/NotchIslandKit/Services/MediaService.swift`: preserve the last stable media result across one failed poll.
- Modify `Tests/Checks/main.swift`: add regression checks for every pure geometry/state/timing rule.
- Modify `Tests/NotchIslandTests/ServiceLogicTests.swift`: mirror media debounce behavior when XCTest is available.

---

### Task 1: Compact geometry and shared motion constants

**Files:**
- Create: `Sources/NotchIslandKit/Island/IslandMotion.swift`
- Modify: `Tests/Checks/main.swift`

**Interfaces:**
- Produces: `IslandMotion`, `CompactContentState`, `CompactGeometry`, and `CompactGeometryModel.layout(coreWidth:state:)`.
- Consumed by: Tasks 3, 4, and 7.

- [ ] **Step 1: Add failing geometry and timing checks**

Add this group to `Tests/Checks/main.swift`:

```swift
group("Hybrid compact geometry") {
    let active = CompactGeometryModel.layout(coreWidth: 190, state: .active)
    expect(active.coreWidth == 190, "preserves detected physical core width")
    expect(active.surfaceWidth == 356, "active surface adds two 83-point wings")
    expect(active.leftWing == 0..<83, "left wing remains outside the core")
    expect(active.core == 83..<273, "core follows the left wing")
    expect(active.rightWing == 273..<356, "right wing remains outside the core")

    let quiet = CompactGeometryModel.layout(coreWidth: 190, state: .quiet)
    expect(quiet.surfaceWidth == 214, "quiet surface exposes 12 points per side")

    let fallback = CompactGeometryModel.layout(coreWidth: nil, state: .active)
    expect(fallback.coreWidth == 200 && fallback.surfaceWidth == 366,
           "missing notch geometry uses the approved fallback")

    expect(IslandMotion.expansionDuration == 0.26, "expansion lasts 260ms")
    expect(IslandMotion.collapseAnticipationDuration == 0.08, "anticipation lasts 80ms")
    expect(IslandMotion.collapseDuration == 0.24, "collapse lasts 240ms")
    expect(IslandMotion.traceDuration == 0.65, "trace lasts 650ms")
}
```

- [ ] **Step 2: Run the check runner and verify RED**

Run: `swift run NotchIslandChecks`

Expected: compilation fails because `CompactGeometryModel` and `IslandMotion` do not exist.

- [ ] **Step 3: Implement the pure geometry model and constants**

Create `IslandMotion.swift` with this public-in-module surface:

```swift
import AppKit
import Combine

enum IslandMotion {
    static let wingWidth: CGFloat = 83
    static let quietReveal: CGFloat = 12
    static let fallbackCoreWidth: CGFloat = 200
    static let expansionOvershoot: CGFloat = 18
    static let collapseAnticipationWidth: CGFloat = 6
    static let collapseAnticipationHeight: CGFloat = 2

    static let expansionDuration: TimeInterval = 0.26
    static let collapseAnticipationDuration: TimeInterval = 0.08
    static let collapseDuration: TimeInterval = 0.24
    static let traceDuration: TimeInterval = 0.65
    static let pauseSettleDuration: TimeInterval = 0.18

    static let tabIndicatorDuration: TimeInterval = 0.22
    static let tabOutgoingDuration: TimeInterval = 0.14
    static let tabPortalDuration: TimeInterval = 0.28
    static let tabIncomingDuration: TimeInterval = 0.24
    static let tabOverlap: TimeInterval = 0.06
    static let reducedMotionFade: TimeInterval = 0.16
}

enum CompactContentState: Equatable { case quiet, active }

struct CompactGeometry: Equatable {
    let coreWidth: CGFloat
    let surfaceWidth: CGFloat
    let leftWing: Range<CGFloat>
    let core: Range<CGFloat>
    let rightWing: Range<CGFloat>
}

enum CompactGeometryModel {
    static func layout(coreWidth: CGFloat?, state: CompactContentState) -> CompactGeometry {
        let coreWidth = max(0, coreWidth ?? IslandMotion.fallbackCoreWidth)
        let reveal = state == .active ? IslandMotion.wingWidth : IslandMotion.quietReveal
        let surfaceWidth = coreWidth + reveal * 2
        return CompactGeometry(
            coreWidth: coreWidth,
            surfaceWidth: surfaceWidth,
            leftWing: 0..<reveal,
            core: reveal..<(reveal + coreWidth),
            rightWing: (reveal + coreWidth)..<surfaceWidth
        )
    }
}
```

- [ ] **Step 4: Run the check runner and verify GREEN**

Run: `swift run NotchIslandChecks`

Expected: all checks pass, including the new geometry group.

- [ ] **Step 5: Record checkpoint**

Mark Task 1 complete only after noting the fresh check count beside this task during execution.

---

### Task 2: Interruptible shell phase reducer and coordinator

**Files:**
- Modify: `Sources/NotchIslandKit/Island/IslandMotion.swift`
- Modify: `Tests/Checks/main.swift`

**Interfaces:**
- Consumes: `CompactContentState` and `IslandMotion` from Task 1.
- Produces: `IslandMotionPhase`, `IslandMotionEvent`, `IslandMotionReducer.handle(_:)`, and `IslandMotionCoordinator` with `requestExpanded(_:)`, `setCoreWidth(_:)`, `setCompactContentState(_:)`, and published `phase`, `geometry`, `isExpandedTarget`.
- Consumed by: Tasks 3 and 7.

- [ ] **Step 1: Add failing reducer checks**

```swift
group("IslandMotionReducer") {
    var reducer = IslandMotionReducer()
    expect(reducer.handle(.expandRequested) == .expanding, "expand starts immediately")
    expect(reducer.handle(.expansionSettled) == .settled, "expand settles")
    expect(reducer.handle(.collapseRequested) == .anticipatingClose,
           "collapse begins with anticipation")
    expect(reducer.handle(.anticipationFinished) == .collapsing,
           "anticipation advances to monotonic collapse")
    expect(reducer.handle(.collapseFinished) == .resting, "collapse rests")

    var retarget = IslandMotionReducer(phase: .collapsing)
    expect(retarget.handle(.expandRequested) == .expanding,
           "an in-flight collapse retargets instead of queueing")
}
```

- [ ] **Step 2: Run checks and verify RED**

Run: `swift run NotchIslandChecks`

Expected: compilation fails because the reducer types are missing.

- [ ] **Step 3: Implement reducer and observable coordinator**

Add these exact states and events to `IslandMotion.swift`:

```swift
enum IslandMotionPhase: Equatable {
    case resting, expanding, settled, anticipatingClose, collapsing
}

enum IslandMotionEvent {
    case expandRequested, expansionSettled
    case collapseRequested, anticipationFinished, collapseFinished
}

struct IslandMotionReducer {
    private(set) var phase: IslandMotionPhase = .resting
    init(phase: IslandMotionPhase = .resting) { self.phase = phase }

    @discardableResult
    mutating func handle(_ event: IslandMotionEvent) -> IslandMotionPhase {
        switch event {
        case .expandRequested: phase = .expanding
        case .expansionSettled: phase = .settled
        case .collapseRequested: phase = .anticipatingClose
        case .anticipationFinished: phase = .collapsing
        case .collapseFinished: phase = .resting
        }
        return phase
    }
}
```

Implement `@MainActor final class IslandMotionCoordinator: ObservableObject` in
the same file. It must:

- store a private reducer and a cancellable `Task<Void, Never>?`;
- publish `phase`, `geometry`, and `isExpandedTarget`;
- recalculate geometry with `CompactGeometryModel` when core width or compact
  content state changes;
- make `requestExpanded(true)` cancel the prior task, set `.expanding`, then set
  `.settled` after 260 ms;
- make `requestExpanded(false)` cancel the prior task, set
  `.anticipatingClose`, wait 80 ms, set `.collapsing`, wait 240 ms, then set
  `.resting`;
- skip the waits and update to the terminal phase immediately when its
  `reduceMotion` property is true;
- guard every delayed phase update with a monotonically increasing generation
  integer so cancelled/stale tasks cannot mutate the current phase.

- [ ] **Step 4: Run checks and verify GREEN**

Run: `swift run NotchIslandChecks`

Expected: all reducer checks pass.

- [ ] **Step 5: Record checkpoint**

Record the fresh check count and confirm no source outside `IslandMotion.swift`
was required for this deliverable.

---

### Task 3: Use detected notch width and visible wing layout

**Files:**
- Modify: `Sources/NotchIslandKit/Island/IslandRootView.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandCompactView.swift`
- Modify: `Sources/NotchIslandKit/Window/NotchPanelController.swift`
- Modify: `Tests/Checks/main.swift`

**Interfaces:**
- Consumes: `IslandMotionCoordinator` and `CompactGeometry` from Tasks 1–2.
- Produces: `IslandRootSizing.compactWidth(coreWidth:hasMedia:)` and compact rendering with explicit left wing, camera core spacer, and right wing.
- Consumed by: Task 4.

- [ ] **Step 1: Add a failing frame regression**

Extend the existing geometry group:

```swift
let compact = CompactGeometryModel.layout(coreWidth: 190, state: .active)
let activeFrame = NotchPanelFrame.target(
    screenFrame: frame,
    contentSize: CGSize(width: compact.surfaceWidth, height: 44),
    compactHeight: 32,
    alignmentOffset: 0
)
expect(activeFrame.width == 356, "window includes both visible compact wings")
expect(activeFrame.midX == frame.midX, "wing frame stays centred on physical notch")
expect(IslandRootSizing.compactWidth(coreWidth: 190, hasMedia: true) == 356,
       "root sizing uses detected core plus active wings")
expect(IslandRootSizing.compactWidth(coreWidth: 190, hasMedia: false) == 214,
       "root sizing uses quiet reveal without media")
```

- [ ] **Step 2: Run checks and confirm the assertion exposes current width behavior**

Run: `swift run NotchIslandChecks`

Expected: compilation fails because `IslandRootSizing` does not exist. This is
the integration RED that prevents the root from returning to its hard-coded
`max(180, compactHeight * 6)` width.

- [ ] **Step 3: Inject one shared coordinator**

In `NotchPanelController`, create one `IslandMotionCoordinator`, pass it to
`IslandRootView`, and call:

```swift
motionCoordinator.setCoreWidth(geo.notchWidth)
motionCoordinator.setCompactContentState(
    env.mediaPanelVM.track == nil ? .quiet : .active
)
```

Update the media track subscription so this content-state call occurs on every
stable track change, without selecting a tab.

- [ ] **Step 4: Replace hard-coded compact width**

In `IslandRootView`, observe the coordinator and replace:

```swift
.frame(width: max(180, CGFloat(settings.compactHeight) * 6))
```

with:

```swift
.frame(width: motionCoordinator.geometry.surfaceWidth)
```

Add this policy beside `IslandRootView` and use it when setting coordinator
content state and width:

```swift
enum IslandRootSizing {
    static func compactWidth(coreWidth: CGFloat?, hasMedia: Bool) -> CGFloat {
        CompactGeometryModel.layout(
            coreWidth: coreWidth,
            state: hasMedia ? .active : .quiet
        ).surfaceWidth
    }
}
```

Pass `coreWidth` and `wingWidth` to `IslandCompactView`.

- [ ] **Step 5: Split compact content around an occluding spacer**

In `IslandCompactView`, replace the symmetric `Spacer` layout with:

```swift
HStack(spacing: 0) {
    compactLeftWing
        .frame(width: wingWidth, height: height, alignment: .trailing)
        .clipped()
    Color.clear
        .frame(width: coreWidth, height: height)
        .accessibilityHidden(true)
    compactRightWing
        .frame(width: wingWidth, height: height, alignment: .leading)
        .clipped()
}
.frame(width: coreWidth + wingWidth * 2, height: height)
```

When presentation is quiet, render only the core plus 12 pt clear edge on each
side. Do not put track text or controls into the core spacer.

- [ ] **Step 6: Run checks and build**

Run: `swift run NotchIslandChecks`

Run: `./scripts/build_app.sh`

Expected: checks pass and `build/Notch Island.app` is produced.

- [ ] **Step 7: Record checkpoint**

Capture a screenshot on the built-in display showing non-empty content on both
sides of the camera core before continuing.

---

### Task 4: Hybrid B+C compact media choreography

**Files:**
- Create: `Sources/NotchIslandKit/Island/Components/CompactMediaMotionView.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandCompactView.swift`
- Modify: `Tests/Checks/main.swift`

**Interfaces:**
- Consumes: geometry and phase from Tasks 1–3, `MediaTrack`, and `PlaybackState`.
- Produces: `CompactMediaMotionView`, `OrbitalWingModifier`, and deterministic waveform scale/settle behavior.

- [ ] **Step 1: Add failing motion-model checks**

```swift
group("Hybrid compact motion") {
    expect(CompactMediaMotionModel.metadataStartOffset == CGSize(width: 30, height: -10),
           "metadata starts behind and above the left core edge")
    expect(CompactMediaMotionModel.controlStartOffset == CGSize(width: -30, height: -12),
           "controls mirror the metadata path")
    expect(CompactMediaMotionModel.metadataStartScale == 0.84, "metadata starts at 0.84 scale")
    expect(CompactMediaMotionModel.controlStartScale == 0.68, "controls start at 0.68 scale")
    expect(CompactMediaMotionModel.maximumBlur == 6, "orbital reveal caps blur at 6")
    expect(CompactWaveformModel.scale(time: 4, index: 1, animated: false) == 2.0 / 3.0,
           "paused waveform settles to midpoint")
}
```

- [ ] **Step 2: Run checks and verify RED**

Run: `swift run NotchIslandChecks`

Expected: compilation fails because `CompactMediaMotionModel` is missing.

- [ ] **Step 3: Implement fixed motion values and orbital modifier**

Create `CompactMediaMotionView.swift` and define:

```swift
enum CompactMediaMotionModel {
    static let metadataStartOffset = CGSize(width: 30, height: -10)
    static let controlStartOffset = CGSize(width: -30, height: -12)
    static let metadataStartScale: CGFloat = 0.84
    static let controlStartScale: CGFloat = 0.68
    static let maximumBlur: CGFloat = 6
}

struct OrbitalWingModifier: ViewModifier {
    let offset: CGSize
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
        content
            .offset(x: offset.width, y: offset.height)
            .scaleEffect(scale, anchor: .top)
            .blur(radius: min(blur, CompactMediaMotionModel.maximumBlur))
            .opacity(opacity)
    }
}
```

- [ ] **Step 4: Implement composited wing content**

`CompactMediaMotionView` receives:

```swift
let track: MediaTrack
let playbackState: PlaybackState
let phase: IslandMotionPhase
let reduceMotion: Bool
```

It renders metadata only in the left wing and waveform/play state only in the
right wing. Use asymmetric modifier transitions with the exact offsets/scales
above. Keep every waveform capsule at `2 × 12 pt` and vary only
`scaleEffect(y:)` at 30 fps while playing.

When playback changes to paused, apply
`.easeOut(duration: IslandMotion.pauseSettleDuration)` to the transform change
so all bars settle to scale `2/3` in 180 ms.

- [ ] **Step 5: Add one-shot sweep and trace**

Add local `@State` values `sweepProgress` and `traceProgress`. Key them by
`track.sourceAppName + "|" + track.title`; on a new identity:

```swift
sweepProgress = 0
traceProgress = 0
withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.42)) {
    sweepProgress = 1
}
withAnimation(.linear(duration: IslandMotion.traceDuration)) {
    traceProgress = 1
}
```

Render the sweep as a clipped gradient translated across the shell once. Render
the 2 pt trace with `scaleEffect(x: traceProgress, anchor: .leading)`. Do not
restart either effect on a media polling tick whose identity is unchanged.

- [ ] **Step 6: Respect Reduced Motion**

When reduced, do not create the animation timeline, keep sweep/trace hidden,
and use only `.opacity` with `IslandMotion.reducedMotionFade`.

- [ ] **Step 7: Run checks and build**

Run: `swift run NotchIslandChecks`

Run: `./scripts/build_app.sh`

Expected: all checks and release build pass.

- [ ] **Step 8: Record checkpoint**

Record a 60 fps sample showing the shell entry, left/right orbital reveals,
one-shot trace, and smooth pause settle.

---

### Task 5: Preserve media across one failed poll

**Files:**
- Modify: `Sources/NotchIslandKit/Services/MediaService.swift`
- Modify: `Tests/Checks/main.swift`
- Modify: `Tests/NotchIslandTests/ServiceLogicTests.swift`

**Interfaces:**
- Produces: `MediaAvailabilityDebouncer.accept(_:)` and stable `MediaService` output.
- Consumed by: compact state selection in Task 3.

- [ ] **Step 1: Add failing debounce checks**

```swift
group("Media availability debounce") {
    let track = MediaTrack(title: "Stable", sourceAppName: "YouTube")
    var debouncer = MediaAvailabilityDebouncer()
    expect(debouncer.accept(track) == track, "a valid track becomes stable")
    expect(debouncer.accept(nil) == track, "one failed poll preserves stable media")
    expect(debouncer.accept(nil) == nil, "two failed polls clear stable media")
    expect(debouncer.accept(track) == track, "a recovered track resets failures")
}
```

- [ ] **Step 2: Run checks and verify RED**

Run: `swift run NotchIslandChecks`

Expected: compilation fails because `MediaAvailabilityDebouncer` is missing.

- [ ] **Step 3: Implement the debouncer**

Add to `MediaService.swift`:

```swift
struct MediaAvailabilityDebouncer {
    private(set) var stableTrack: MediaTrack?
    private var consecutiveMissing = 0

    mutating func accept(_ candidate: MediaTrack?) -> MediaTrack? {
        if let candidate {
            stableTrack = candidate
            consecutiveMissing = 0
            return candidate
        }
        consecutiveMissing += 1
        if consecutiveMissing < 2 { return stableTrack }
        stableTrack = nil
        return nil
    }
}
```

Use one instance in `MediaService.poll()`. A chosen adapter with a valid
playback state but no track may publish that state, while `currentTrack` uses
the debounced track. Reset missing count on any valid track.

- [ ] **Step 4: Mirror the check in XCTest**

Add `testOneMissingMediaPollPreservesStableTrack()` to
`ServiceLogicTests.swift` with the same four assertions.

- [ ] **Step 5: Run checks and verify GREEN**

Run: `swift run NotchIslandChecks`

Expected: all debounce and existing adapter-selection checks pass.

- [ ] **Step 6: Record checkpoint**

Confirm compact geometry does not switch active → quiet on one simulated nil
poll.

---

### Task 6: Tab transition reducer and retargeting

**Files:**
- Create: `Sources/NotchIslandKit/Island/TabTransitionCoordinator.swift`
- Modify: `Tests/Checks/main.swift`

**Interfaces:**
- Produces: `TabTransitionDirection`, `TabTransitionPhase`, `TabTransitionState`, `TabTransitionReducer.request(target:)`, and `TabTransitionCoordinator.request(target:)`.
- Consumed by: Task 7.

- [ ] **Step 1: Add failing direction and retarget checks**

```swift
group("TabTransitionReducer") {
    var tabs = TabTransitionReducer(initial: .media)
    let toSystem = tabs.request(target: .systemStatus)
    expect(toSystem.direction == .forward, "Media to System travels forward")
    expect(toSystem.source == .media && toSystem.target == .systemStatus,
           "transition preserves both panel identities")

    let retarget = tabs.request(target: .finderShelf)
    expect(retarget.source == .systemStatus && retarget.target == .finderShelf,
           "rapid input retargets from the latest presentation")
    expect(retarget.direction == .forward, "retarget direction follows tab order")

    let reverse = tabs.request(target: .media)
    expect(reverse.direction == .backward, "reverse order travels backward")
}
```

- [ ] **Step 2: Run checks and verify RED**

Run: `swift run NotchIslandChecks`

Expected: compilation fails because tab transition types are missing.

- [ ] **Step 3: Implement pure tab ordering and reducer**

Create `TabTransitionCoordinator.swift` with:

```swift
import SwiftUI

enum TabTransitionDirection: Equatable { case forward, backward, none }
enum TabTransitionPhase: Equatable { case idle, outgoing, portal, incoming }

struct TabTransitionState: Equatable {
    var source: IslandContent
    var target: IslandContent
    var direction: TabTransitionDirection
    var phase: TabTransitionPhase
}

struct TabTransitionReducer {
    private(set) var state: TabTransitionState
    init(initial: IslandContent) {
        state = .init(source: initial, target: initial, direction: .none, phase: .idle)
    }

    mutating func request(target: IslandContent) -> TabTransitionState {
        let source = state.target
        let sourceIndex = Self.index(source)
        let targetIndex = Self.index(target)
        let direction: TabTransitionDirection = targetIndex > sourceIndex ? .forward
            : (targetIndex < sourceIndex ? .backward : .none)
        state = .init(source: source, target: target, direction: direction,
                      phase: direction == .none ? .idle : .outgoing)
        return state
    }

    static func index(_ content: IslandContent) -> Int {
        switch content {
        case .media: return 0
        case .systemStatus: return 1
        case .finderShelf: return 2
        case .notification: return 3
        }
    }
}
```

- [ ] **Step 4: Implement observable scheduling wrapper**

`@MainActor final class TabTransitionCoordinator: ObservableObject` publishes
`state`, `headerContent`, and `portalProgress`. It owns one generation-guarded
task. `request(target:)` must:

1. cancel the prior task and update reducer state;
2. publish `.outgoing` immediately;
3. after 80 ms, publish `.portal` and update `headerContent` to target;
4. after another 60 ms, publish `.incoming`;
5. after another 180 ms, publish `.idle` with source and target both equal to
   the latest target;
6. if Reduced Motion is active, update directly to idle target state and skip
   every wait.

- [ ] **Step 5: Run checks and verify GREEN**

Run: `swift run NotchIslandChecks`

Expected: direction and rapid-retarget checks pass.

- [ ] **Step 6: Record checkpoint**

Record the new check count and verify `.notification` never appears in the
three-button tab rail.

---

### Task 7: Render Orbital Portal tabs and coordinated collapse

**Files:**
- Modify: `Sources/NotchIslandKit/Island/IslandExpandedView.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandRootView.swift`
- Modify: `Sources/NotchIslandKit/Window/NotchPanelController.swift`
- Modify: `Tests/Checks/main.swift`

**Interfaces:**
- Consumes: shell and tab coordinators from Tasks 2 and 6.
- Produces: visible Orbital Portal transitions, anticipation collapse, and outside-click compact return.

- [ ] **Step 1: Add failing outside-click policy check**

Extract a pure policy in `NotchPanelController.swift` and test it:

```swift
enum OutsideClickAction: Equatable { case ignore, collapseToCompact }

expect(NotchPanelInteraction.outsideClickAction(isExpanded: true, isPinned: false)
       == .collapseToCompact, "outside click collapses instead of ordering out")
expect(NotchPanelInteraction.outsideClickAction(isExpanded: false, isPinned: false)
       == .ignore, "compact island remains visible")
expect(NotchPanelInteraction.outsideClickAction(isExpanded: true, isPinned: true)
       == .ignore, "pinned island ignores outside clicks")
```

- [ ] **Step 2: Run checks and verify RED**

Run: `swift run NotchIslandChecks`

Expected: compilation fails because `NotchPanelInteraction` is missing.

- [ ] **Step 3: Add composited panel stack**

In `IslandExpandedView`, keep `panel(for:)` as a reusable `@ViewBuilder`
function. Render source and target in one clipped `ZStack`. Apply:

- outgoing: y +12 pt, scale 0.965, blur 5 pt, opacity 0 over 140 ms;
- incoming start: y -12 pt, scale 1.035, blur 5 pt, opacity 0;
- incoming identity: zero offset, scale 1, blur 0, opacity 1 over 240 ms;
- 60 ms overlap between the two phases.

Header title reads `tabCoordinator.headerContent`, not the raw target content.

- [ ] **Step 4: Add moving indicator and portal icon**

Use `matchedGeometryEffect` for the selected tab indicator with
`.timingCurve(0.77, 0, 0.175, 1, duration: IslandMotion.tabIndicatorDuration)`.
Render a transitional duplicate SF Symbol above the rail while phase is
`.portal`. Move it along a quadratic path by implementing a `GeometryEffect`
whose control point is 46 pt above and 18 pt toward the travel direction. Its
progress reaches identity over 280 ms. Keep the real tab buttons present and
clickable throughout.

Use this effect so the implementation does not substitute a linear offset:

```swift
struct OrbitalPortalEffect: GeometryEffect {
    var progress: CGFloat
    let direction: TabTransitionDirection

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let sign: CGFloat = direction == .backward ? -1 : 1
        let start = CGPoint.zero
        let control = CGPoint(x: sign * 18, y: -46)
        let end = CGPoint(x: 0, y: -82)
        let inverse = 1 - progress
        let x = inverse * inverse * start.x
            + 2 * inverse * progress * control.x
            + progress * progress * end.x
        let y = inverse * inverse * start.y
            + 2 * inverse * progress * control.y
            + progress * progress * end.y
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}
```

- [ ] **Step 5: Wire tab clicks without passive selection**

On a tab click:

```swift
tabCoordinator.request(target: tab.0)
viewModel.select(content: tab.0)
```

Do not call this path from `MediaPanelViewModel`, media publishers, `onAppear`,
or hover handlers. In `onChange(of: content)`, synchronize only when the change
originated from state restoration or notification handling and the coordinator
is idle.

- [ ] **Step 6: Implement shell phase timing in Root and AppKit**

When `viewModel.state.isExpandedLike` changes, call
`motionCoordinator.requestExpanded(expanded)`. Map phases to frame application:

- `.expanding`: animate toward expanded target over 260 ms with a strong
  ease-out, allowing the SwiftUI shell to reach 18 pt overshoot before settle;
- `.anticipatingClose`: animate to current width +6 pt and current height -2 pt
  over 80 ms;
- `.collapsing`: animate monotonically to compact frame over 240 ms with
  `CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)`;
- `.resting` and `.settled`: apply the exact target frame and clear transient
  presentation transforms.

Ensure repeated phase updates retarget `panel.animator()` from the current
visible frame rather than resetting to the previous logical target.

- [ ] **Step 7: Replace outside-click orderOut**

Implement `NotchPanelInteraction.outsideClickAction`. In the global monitor,
replace `panel.orderOut(nil)` with `viewModel.dismiss()` when the action is
`.collapseToCompact`. Determine pinned state from `viewModel.state`; pinned
expanded state returns `.ignore`.

- [ ] **Step 8: Implement Reduced Motion**

Thread the combined macOS/app value into both coordinators. In Reduced Motion,
apply the final frame immediately, render no portal duplicate, move the
indicator immediately, and crossfade panel content over 160 ms.

- [ ] **Step 9: Run checks and release build**

Run: `swift run NotchIslandChecks`

Run: `./scripts/build_app.sh`

Run: `codesign --verify --deep --strict 'build/Notch Island.app'`

Expected: all checks pass, release bundle builds, and signature verification
exits 0.

- [ ] **Step 10: Record checkpoint**

Record a 60 fps clip of Media → System → Finder → Media, including a rapid
retarget before the prior 280 ms portal completes.

---

### Task 8: Final integration and manual acceptance

**Files:**
- Modify: `README.md` only if the documented behavior or Chrome permission instructions are stale.
- Modify: `docs/superpowers/plans/2026-08-03-hybrid-orbital-notch-motion.md` to record completion evidence.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified release app and implementation evidence.

- [ ] **Step 1: Run the complete automated verification fresh**

Run: `swift run NotchIslandChecks`

Expected: zero failed checks.

- [ ] **Step 2: Build and verify the release bundle fresh**

Run: `./scripts/build_app.sh`

Run: `codesign --verify --deep --strict 'build/Notch Island.app'`

Expected: both commands exit 0.

- [ ] **Step 3: Replace the running development app**

Quit only the existing `NotchIsland` process and open:

```text
/Users/crossian/Documents/GitHub/just-notch/build/Notch Island.app
```

- [ ] **Step 4: Verify compact geometry and media**

With YouTube playing in Chrome and JavaScript from Apple Events enabled:

- wait one 2-second poll interval;
- confirm metadata is visible in the left 83 pt wing;
- confirm waveform and playback state are visible in the right 83 pt wing;
- pause and resume from the expanded Media panel;
- confirm paused bars settle in 180 ms;
- briefly make one poll fail and confirm the compact shell does not flicker.

- [ ] **Step 5: Verify shell choreography at 60 fps**

Confirm:

- entry uses one elastic overshoot and one-shot sweep/trace;
- trace lasts 650 ms;
- collapse widens 6 pt for 80 ms, then returns monotonically for 240 ms;
- endpoint has no rebound;
- click outside returns to compact instead of hiding the app.

- [ ] **Step 6: Verify Orbital Portal interruption**

Switch through every tab in both directions. Before a portal completes, select
another tab. Confirm the indicator, icon, header, and panels retarget without an
empty frame, stale queued transition, or automatic media-driven tab switch.

- [ ] **Step 7: Verify accessibility and display fallbacks**

Test macOS Reduce Motion and the app setting separately. Then verify the
built-in display, an external display, and simulated-notch mode. Reduced Motion
must keep a 160 ms crossfade while removing all spatial/decorative motion.

- [ ] **Step 8: Update completion evidence**

Append the final check count, build result, signature result, media-control
result, and manual feel-check results under a `## Completion evidence` section
in this plan. Do not mark the plan complete if any manual acceptance item is
unverified.

## Completion evidence

Acceptance run: 2026-08-03 23:24 +07 from
`/Users/crossian/Documents/GitHub/just-notch`.

### Automated and release evidence

- `swift run NotchIslandChecks`: **PASS**, 172/172 checks, zero failures. The
  first sandboxed invocation could not write Swift/Clang user caches; the
  required elevated rerun exited 0.
- `./scripts/build_app.sh`: **PASS**, production `NotchIsland` product built and
  `build/Notch Island.app` assembled. The first sandboxed invocation hit the
  same cache restriction; the required elevated rerun exited 0.
- `codesign --verify --deep --strict 'build/Notch Island.app'`: **PASS**, exit 0.
  The bundle is ad-hoc signed as `com.notchisland.app` with CDHash
  `35dfa7bb1ebf8c42d96552e9f07b0bf461463e72`.
- Bundle metadata: `CFBundleExecutable=NotchIsland`,
  `CFBundleIdentifier=com.notchisland.app`, `LSUIElement=1`, minimum macOS 13.0.
  The assembled executable is the arm64 Mach-O at
  `build/Notch Island.app/Contents/MacOS/NotchIsland`, SHA-256
  `c93d9afb9e3f4515f1ab05996fca921610302baf440100cd18f905de398904ae`.
- Release replacement: confirmed existing exact-name `NotchIsland` PID 55336,
  sent it `TERM`, and opened exactly
  `/Users/crossian/Documents/GitHub/just-notch/build/Notch Island.app` through
  the required GUI escalation. The replacement remained alive as PID 24660;
  `ps` confirmed its executable path was the built bundle above.
- Screenshot: `/private/tmp/notch-island-task-8.png` (3600×2338, captured at
  23:22:45 +07). Inspection showed a uniformly black frame with no discernible
  app or desktop UI, so it is not credited as visual acceptance evidence.
- User-supplied clip:
  `/Users/crossian/Library/Application Support/CleanShot/media/media_E96MtzmvNz/CleanShot 2026-08-03 at 23.28.01.mp4`.
  `ffprobe` reported H.264, 1296×1202, 23.903333 seconds, average frame rate
  `392100/7171` (approximately 54.68 fps), and `120/1` reported frame rate.
  Inspected contact sheets: `/private/tmp/notch-task8-video/contact-sheet.jpg`,
  `/private/tmp/notch-task8-video/sheet-0-8.jpg`,
  `/private/tmp/notch-task8-video/sheet-8-16.jpg`, and
  `/private/tmp/notch-task8-video/sheet-16-24.jpg`. The average frame rate is
  not treated as proof of sustained 60 fps.

### Manual acceptance matrix

1. **PASS** — the clip visibly shows active media compact at top-center around
   the physical camera notch: `The Cursed Traveler` metadata is on the left
   wing, the playback/waveform affordance is on the right wing, and the camera
   core remains unobstructed.
2. **UNVERIFIED** — pause/resume and the 180 ms paused-bar settle were not visibly
   exercised.
3. **UNVERIFIED** — no live missing-poll condition was introduced; automated
   debouncer checks are not sufficient for this manual row.
4. **UNVERIFIED** — the clip does not prove one elastic overshoot or the exact
   420 ms sweep / 650 ms one-shot trace timings.
5. **UNVERIFIED** — the clip does not provide a frame-measured sample proving the
   80 ms anticipation, monotonic 240 ms return, and no endpoint rebound.
6. **UNVERIFIED** — compact persistence after collapse is visible in the clip,
   but the combined outside-click, pinned, and immediate-X matrix is not fully
   exercised.
7. **PASS** — the clip visibly traverses Media, System, and Finder repeatedly in
   both directions with rapid successive selections. Sampled frames retain
   content, header, and indicator with no empty panel or obvious portal
   teleport. Automated code checks support the separate requirement that media
   polling does not passively select a tab.
8. **UNVERIFIED** — app Reduce Animation and macOS Reduce Motion were not toggled;
   the user's accessibility configuration was left unchanged.
9. **UNVERIFIED** — built-in physical-notch, external-display fallback, and
   simulated-notch modes were not all available and visibly exercised.
10. **UNVERIFIED** — the clip averages approximately 54.68 fps and does not prove
    sustained 60 fps/frame pacing.

Summary: **2 PASS, 0 FAIL, 8 UNVERIFIED**. The plan remains incomplete. To
finish acceptance, the user must visibly record pause/resume and the 180 ms
settle, one forced missing poll, exact shell/one-shot timing, the complete
outside-click/pin/X matrix, separate app/macOS Reduce Motion behavior, all
built-in/external/simulated-notch modes, and a sustained 60 fps frame-pacing
sample.
