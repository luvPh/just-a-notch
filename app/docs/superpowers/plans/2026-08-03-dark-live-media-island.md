# Dark Live Media Island Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render currently playing media in the compact island and restore a concise dark-gradient island UI with controlled motion.

**Architecture:** AppEnvironment owns continuous media lifecycle; IslandRootView passes live media state into IslandCompactView. A pure compact-presentation helper makes display priority testable; dark colors live in IslandTheme and panels consume them.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Combine, SwiftPM.

## Global Constraints

- Use SF Symbols only; no emoji or text glyph icons.
- Use near-black with a blue-violet gradient and cobalt accent.
- Respect Reduce Motion and `reduceAnimation`.
- Run checks, release build, app assembly, and signature verification.

---

### Task 1: Keep live media available to compact island

**Files:**
- Modify: `Sources/NotchIslandKit/App/AppEnvironment.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandRootView.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandCompactView.swift`
- Modify: `Tests/Checks/main.swift`

- [ ] **Step 1: Write failing compact-media assertions**

```swift
let track = MediaTrack(title: "Example", sourceAppName: "YouTube")
expect(CompactIslandPresentation.select(track: track) == .media(track),
       "compact island prefers an active track")
```

- [ ] **Step 2: Run `swift run NotchIslandChecks` and confirm `CompactIslandPresentation` is missing.**

- [ ] **Step 3: Implement `CompactIslandPresentation`, subscribe IslandRootView to media panel state, and start media service in AppEnvironment while enabled.**

- [ ] **Step 4: Re-run `swift run NotchIslandChecks` and confirm all assertions pass.**

### Task 2: Restore concise dark System and feature panels

**Files:**
- Modify: `Sources/NotchIslandKit/Island/Components/IslandTheme.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandRootView.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandExpandedView.swift`
- Modify: `Sources/NotchIslandKit/Island/Components/FeaturePanels.swift`

- [ ] **Step 1: Add a failing assertion requiring `minimumPanelHeight(for: .systemStatus) <= 280`.**
- [ ] **Step 2: Run check runner and confirm the current 230pt layout check needs the compact-height assertion.**
- [ ] **Step 3: Replace cream/card colors with near-black, muted gray, cobalt and a SwiftUI radial gradient; remove per-metric card backgrounds and keep four slim rows.**
- [ ] **Step 4: Re-run checks and release build.**

### Task 3: Add controlled animations and package

**Files:**
- Modify: `Sources/NotchIslandKit/Island/IslandRootView.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandCompactView.swift`
- Modify: `README.md`

- [ ] **Step 1: Add a failing check for `IslandMotion.trackUpdateDuration == 0.18`.**
- [ ] **Step 2: Run check runner and confirm `IslandMotion` is missing.**
- [ ] **Step 3: Implement `IslandMotion`, apply a 180ms opacity transition to track changes and a 260ms spring to expand/tab state only when motion is enabled.**
- [ ] **Step 4: Run `swift run NotchIslandChecks && swift build -c release --product NotchIsland && ./scripts/build_app.sh release && codesign --verify --deep --strict --verbose=2 'build/Notch Island.app'`.**
