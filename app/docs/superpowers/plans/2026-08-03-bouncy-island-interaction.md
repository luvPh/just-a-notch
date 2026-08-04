# Bouncy Island Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Notch Island easy to operate, clear of the physical notch, visually warm and animated, without emoji or accidental dismissal.

**Architecture:** Centralize measurable layout values in `IslandExpandedLayout`, keep panel placement in `NotchPanelController`, and route only explicit dismiss actions to `IslandViewModel`. Apply the cream/ink/cobalt token palette inside the island views using SF Symbols.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, Combine, SwiftPM.

## Global Constraints

- macOS 13+ and public Apple APIs only.
- Use SF Symbols only; do not render emoji in island UI.
- Use cream, ink, white cards, and cobalt as the only functional accent.
- Respect Reduce Motion and `reduceAnimation`.
- Run `swift run NotchIslandChecks`, release build, app assembly, and signature verification.

---

### Task 1: Make layout and tab hit areas measurable

**Files:**
- Modify: `Sources/NotchIslandKit/Island/IslandExpandedView.swift`
- Modify: `Tests/Checks/main.swift`
- Modify: `Tests/NotchIslandTests/GeometryAndShortcutTests.swift`

**Interfaces:**
- Produces: `IslandExpandedLayout.tabHitHeight: CGFloat`, `bottomRailHeight: CGFloat`, and `minimumPanelHeight(for:)`.

- [ ] **Step 1: Write failing layout assertions**

```swift
expect(IslandExpandedLayout.tabHitHeight >= 58,
       "each tab has a full-height hit target")
expect(IslandExpandedLayout.bottomRailHeight >= 70,
       "the bottom rail clears panel content")
```

- [ ] **Step 2: Confirm the check runner fails because the new metrics are absent**

Run: `swift run NotchIslandChecks`

Expected: compile error for `tabHitHeight` and `bottomRailHeight`.

- [ ] **Step 3: Implement measured tab layout**

```swift
enum IslandExpandedLayout {
    static let tabHitHeight: CGFloat = 58
    static let bottomRailHeight: CGFloat = 70
}
```

Apply `.frame(maxWidth: .infinity, minHeight: IslandExpandedLayout.tabHitHeight)` to every tab button and reserve `bottomRailHeight` for the rail.

- [ ] **Step 4: Verify checks pass**

Run: `swift run NotchIslandChecks`

Expected: all checks pass with the new hit-area assertions.

### Task 2: Stop accidental dismissal and clear the physical notch

**Files:**
- Modify: `Sources/NotchIslandKit/Island/IslandRootView.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandExpandedView.swift`
- Modify: `Sources/NotchIslandKit/Window/NotchPanelController.swift`
- Modify: `Tests/Checks/main.swift`

**Interfaces:**
- Consumes: `NotchGeometry.notchHeight`, `IslandViewModel.dismiss()`.
- Produces: `expandedTopClearance(notchHeight:) -> CGFloat` and an explicit close button.

- [ ] **Step 1: Write the failing safe-clearance test**

```swift
expect(IslandExpandedLayout.expandedTopClearance(notchHeight: 32) >= 32,
       "expanded content starts below the physical notch")
```

- [ ] **Step 2: Confirm the check runner fails for the missing function**

Run: `swift run NotchIslandChecks`

Expected: compile error for `expandedTopClearance`.

- [ ] **Step 3: Implement explicit dismiss and placement**

```swift
static func expandedTopClearance(notchHeight: CGFloat) -> CGFloat {
    max(notchHeight, 32)
}
```

Remove the expanded root `.onTapGesture`; add an SF Symbol `xmark` button in the header. Position the panel frame below `geo.notchHeight` when expanded, while compact state remains anchored to the notch.

- [ ] **Step 4: Verify release compile**

Run: `swift build -c release --product NotchIsland`

Expected: successful build with no parent gesture competing with child controls.

### Task 3: Apply the cream/ink/cobalt Bouncy visual system

**Files:**
- Create: `Sources/NotchIslandKit/Island/Components/IslandTheme.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandRootView.swift`
- Modify: `Sources/NotchIslandKit/Island/IslandExpandedView.swift`
- Modify: `Sources/NotchIslandKit/Island/Components/FeaturePanels.swift`

**Interfaces:**
- Produces: `IslandTheme.cream`, `ink`, `cobalt`, `card`, and SF Symbol-only controls.

- [ ] **Step 1: Add a compile-time usage fixture for the theme API**

```swift
let themeColors = [IslandTheme.cream, IslandTheme.ink, IslandTheme.cobalt, IslandTheme.card]
expect(themeColors.count == 4, "island visual tokens are available")
```

- [ ] **Step 2: Confirm the check runner fails because `IslandTheme` is absent**

Run: `swift run NotchIslandChecks`

Expected: compile error for `IslandTheme`.

- [ ] **Step 3: Implement palette, cards, and controlled motion**

```swift
enum IslandTheme {
    static let cream = Color(red: 1.0, green: 0.96, blue: 0.89)
    static let ink = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let cobalt = Color(red: 0.35, green: 0.34, blue: 0.93)
    static let card = Color.white
}
```

Use the token colors in expanded panels, convert metric/tab glyphs to SF Symbols, and use `.spring(response: 0.26, dampingFraction: 0.82)` unless motion is reduced.

- [ ] **Step 4: Verify checks and release build**

Run: `swift run NotchIslandChecks && swift build -c release --product NotchIsland`

Expected: all checks pass and the release product compiles.

### Task 4: Protect Settings lifecycle and package the app

**Files:**
- Modify: `Sources/NotchIslandKit/App/AppDelegate.swift`
- Modify: `README.md`

- [ ] **Step 1: Keep the Settings window lifecycle independent**

Ensure settings presentation does not recreate `NotchPanelController` and only the Settings scene/window owns its close event. Update user-facing documentation to describe explicit island dismissal and the current check count.

- [ ] **Step 2: Run final verification**

Run: `swift run NotchIslandChecks && swift build -c release --product NotchIsland && ./scripts/build_app.sh release && codesign --verify --deep --strict --verbose=2 'build/Notch Island.app'`

Expected: checks pass, release build succeeds, and the app bundle is valid.
