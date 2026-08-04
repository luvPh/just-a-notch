# Bouncy Island Interaction Design

## Goal

Make the expanded Notch Island feel deliberate and pleasant: easy to operate,
clear of the physical notch, stable while settings are edited, and visually
aligned with the supplied Bouncy design system without using emoji.

## Visual System

- Use warm cream as the expanded-surface background, ink for text, white cards,
  and cobalt as the single functional accent.
- Use SF Symbols exclusively for icons. Do not render emoji in labels, metrics,
  tabs, or controls.
- Use 16-20pt card corners, restrained shadows, and high-contrast text.
- Apply a 260ms spring for expand/collapse and tab selection. Metric values may
  animate opacity or bar width only; respect Reduce Motion and the existing
  `reduceAnimation` setting.

## Interaction and Layout

- Tabs are full-width buttons, at least 58pt tall, with an accessible label and
  selected state. The icon and label are decorative content inside the same tap
  target.
- The expanded panel must begin below the physical notch/safe-area region.
  Its content and media artwork must never occupy the notch or menu-bar area.
- Give each tab an explicit content minimum height. System reserves space for
  its four metrics and a fixed bottom tab rail.
- Remove the expanded root tap-to-dismiss gesture. The panel stays open while a
  user interacts with tab controls, meters, Finder search, and Settings.
- Dismissal remains available via a visible SF Symbol close control, global
  shortcut, click outside, or the menu command.
- Settings is a native independent window and must not be closed, recreated, or
  affected by island state/auto-collapse timers while it is open.

## Architecture

- Introduce a small visual token layer used by IslandRootView, IslandExpandedView,
  and feature panels to avoid unrelated hard-coded black/white treatments.
- Keep expanded layout metrics pure/testable where feasible, including minimum
  content heights, bottom-rail height, and safe vertical clearance.
- Pass explicit interaction callbacks into the island view rather than letting a
  parent gesture compete with child buttons.
- Keep `NotchPanelController` responsible for display geometry and use the
  selected screen's safe-area/notch height to position the panel below it.

## Testing

- Add check-runner and XCTest regressions for full tab tap-target height,
  safe vertical clearance, and System layout minimum height.
- Retain existing regression coverage for physical-notch display selection.
- Run the check runner, release build, app-bundle assembly, and signature
  verification. XCTest runs on a machine with full Xcode.

## Non-goals

- No private APIs, custom icon assets, emoji, or broad visual redesign outside
  the island and its expanded feature panels.
- No automatic screen changes or notification takeover while the user is
  interacting with an expanded/pinned island.
