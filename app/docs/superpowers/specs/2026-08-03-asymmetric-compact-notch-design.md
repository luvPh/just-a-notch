# Asymmetric compact notch redesign

**Status:** Implemented (pure models + rendering wiring) — pending physical-device acceptance  
**Date:** 2026-08-03

## Problem and evidence

The current physical-device photo shows that the equal 83 pt media wings do
not read as one object with the MacBook camera housing:

- each wing uses its own material while the core is transparent, producing hard
  seams where the software surface meets the hardware notch;
- the compact surface has inconsistent silhouette and optical weight around the
  core;
- title and source are compressed into a too-small left wing;
- the right play affordance is visually oversized and is not an interactive
  control, so its parent compact tap expands the panel instead;
- equal-width tab cells do not contract as the user expects and their content
  transitions feel more like layout replacement than a continuous rail motion.

The current media adapters, debouncer, shell coordinator, tab coordinator,
AppKit panel anchoring, outside-click policy, and accessibility foundations are
retained. This is a controlled UI-layer rebuild, not an application rewrite.

## Goals

1. Make compact media appear as a single continuous extension of the physical
   notch, with no visible core/wing seam.
2. Give track title legibility a deliberate temporary reveal instead of
   permanently widening the island.
3. Make compact play/pause directly actionable without expanding the panel.
4. Make the right wing quiet, balanced, and recognizably media-related.
5. Make the active tab expand while inactive tabs contract to icons, with
   continuous retargeting and stable expanded-panel geometry.
6. Preserve Reduce Motion, keyboard/accessibility behavior, media polling,
   physical notch anchoring, external/simulated display fallback, and all
   existing no-auto-tab-selection guarantees.

## Non-goals

- Do not replace media adapters, browser Automation, or the one-missing-poll
  media debouncer.
- Do not fetch album art or add network/image dependencies. Until artwork is
  available from a supported adapter, the compact thumbnail is a source-aware
  SF Symbol treatment.
- Do not change the approved 80 ms anticipation / 240 ms shell collapse,
  420 ms sweep, 650 ms trace, 180 ms waveform settle, or the tab coordinator's
  80 + 60 + 180 ms phase scheduler.
- Do not use emoji, private APIs, or third-party dependencies.

## Compact geometry and silhouette

### Anchored asymmetric geometry

Replace symmetric `CompactGeometry` reveals with explicit left and right
reveals. The physical core remains the anchor; the panel is **not** centred by
its total width when reveals differ.

```text
screen core centre
        │
left reveal | physical camera core | right reveal
```

The compact panel frame origin is:

```text
coreCentreX - coreWidth / 2 - leftReveal
```

where `coreCentreX = screenFrame.midX + alignmentOffset`. The existing
`notchAlignmentOffset` setting (used everywhere today by `NotchPanelFrame` and
`NotchGeometryProvider`) MUST be folded into `coreCentreX`; it is not dropped by
the asymmetric model. On simulated-notch / external-display fallback the same
formula applies with the simulated core width, so off-notch and offset users do
not drift.

Its width is `leftReveal + coreWidth + rightReveal`. The physical camera core
therefore remains exactly stationary while the left wing opens or closes.

### States and metrics

The geometry model has these named presentation states:

| State | Left reveal | Right reveal | Visible content |
| --- | ---: | ---: | --- |
| quiet | 12 pt | 12 pt | none |
| mediaResting | 44 pt | 76 pt | source thumbnail; waveform + play/pause |
| mediaReading | 156 pt | 76 pt | title marquee + source; waveform + play/pause |

The right reveal remains 76 pt in both active media states. The left reveal is
the only temporary expansion. Values may be rounded only at the AppKit window
frame boundary.

### Expanded ↔ compact horizontal transition

The expanded panel keeps its current **screen-centred** geometry
(`midX + alignmentOffset`), while compact media states are **core-anchored** and
left-heavy. These two anchors differ, so the collapse path must be defined
explicitly rather than left to `phaseTarget(.collapsing)` returning the raw
compact frame:

- Collapse always targets **`mediaResting`** (44 / 76), never `mediaReading`.
  The reading reveal is torn down first (see collapse behavior below), so the
  window never has to travel the full 156 pt left offset while closing.
- The horizontal origin interpolates continuously from the centred expanded
  frame to the core-anchored `mediaResting` frame over the existing
  240 ms shell collapse; there must be no discrete X snap between the last
  expanded frame and the first compact frame.
- The physical core still ends stationary: the end-state compact frame is
  computed from `coreCentreX`, so any residual horizontal travel is only the
  small delta between screen-centre and the (near-symmetric 44/76) resting
  surface centre, not the full reading offset.

### Wing content width budget

To prevent clipping at accessibility text sizes, reserve explicit padding rather
than assuming content fits the reveal:

| Region | Reveal | Budget |
| --- | ---: | --- |
| left resting | 44 pt | 22 pt symbol centred, ≥ 11 pt total side padding |
| left reading | 156 pt | 7 pt lead + 22 pt thumbnail + 8 pt gap + 112 pt title viewport + 7 pt trail |
| right | 76 pt | waveform block + 8 pt gap + 28 pt button, laid out horizontally, never overlapping; 36 pt hit target may bleed into padding but not past the surface edge |

If measured content still exceeds the reveal at the current system text size,
the title viewport clamps to the available width (marquee decides fit from the
clamped width); the reveal itself is never grown past its state value.

### Unified surface

`IslandCompactView` owns one near-black surface spanning both reveals and the
empty core. The camera-core region remains content-free and accessibility
hidden, but it uses the same black base material as the wings so it visually
merges with the hardware housing. A single blue-violet sheen at no more than
8% opacity is masked over the full surface; there must be no independently
shaded wing backgrounds or one-pixel core separator.

Because the true hardware notch is pure black, the sheen must **not** be applied
to the core column or the top edge strip that abut the physical housing: keep
that region pure black so the software/hardware boundary reads as one black
mass. The sheen ramps in only across the wing area away from the core. Verify on
a real device that the 8% sheen does not itself reintroduce a faint tonal seam
at the housing boundary; if it does, reduce the sheen or widen the pure-black
core margin.

The compact silhouette has one flat top edge and matched outer bottom radii.
It is clipped once, after the full surface is composed. No individual wing may
apply a competing corner radius or clip that creates a join line.

## Compact media behavior

### Resting state

- Left wing: one 22 pt source-aware SF Symbol thumbnail, centred in the 44 pt
  reveal. Use `music.note`, `play.rectangle`, or another existing SF Symbol
  chosen from the source type; do not use an emoji.
- Right wing: deterministic **three-bar** waveform plus an explicit 28 pt
  circular play/pause `Button`. Each bar is a fixed `2 × 12 pt` capsule; only its
  vertical scale transform changes, quantized to a 30 fps step (heights derived
  from a deterministic function of frame index, not wall-clock, so it is
  testable and identical run to run). The waveform animates only while playing;
  when paused the bars hold their last committed frame. This 30 fps play loop is
  distinct from the one-shot **180 ms waveform settle** accent: the settle runs
  once when compact media first appears / on a new identity, then hands off to
  the steady 30 fps loop. The two must not run simultaneously.
- The button uses `.buttonStyle(.plain)`, a 36 pt interactive hit target, an
  accessibility label describing the next action, and calls the existing media
  play/pause action directly.
- A tap in any other compact background region opens the expanded island. The
  control button must consume its own interaction and must never trigger the
  parent expansion gesture.

### Track-change reading reveal

On a *new* stable media identity (`sourceAppName + "|" + title`):

1. Left reveal grows from 44 pt to 156 pt over 250 ms with a smooth,
   critically damped visual response. The core anchor never moves.
2. The source thumbnail remains at the left edge. Title is one line with a
   112 pt viewport; source is smaller and static below it.
3. If the title fits, it remains still for 2.2 s. If it overflows, wait 400 ms,
   scroll once at 26 pt/s to the end, hold 500 ms, then continue.
4. After the reading interval, shrink the left reveal to 44 pt over 280 ms.
   The title fades and translates back toward the thumbnail; the thumbnail
   stays visible.
5. A polling update with unchanged identity does not restart any of these
   steps. A new identity immediately retargets from the current presentation;
   it does not queue or jump through the old title's endpoint.

The existing one-shot sweep and trace run once when the reading reveal starts
for a new media identity. They never replay while the compact view is being
remounted solely for collapse.

### Collapse and Reduce Motion

- During shell collapse, metadata reverses toward the left thumbnail. No title
  marquee, sweep, or trace begins while closing. The reading reveal, if open, is
  torn down to `mediaResting` before the shell collapse animates (see the
  expanded ↔ compact transition above), so no left-offset travel overlaps close.
- With Reduce Motion, no marquee, orbital path, blur, sweep, trace, or waveform
  timeline runs, and the waveform bars hold a single static frame rather than
  looping.

  Reduce Motion must **not** cost title legibility (Goal 2). On a new stable
  identity the left reveal still moves to the **reading value (156 pt)**, but the
  change is applied *immediately* (no critically-damped 250 ms animation) and the
  title is shown *statically* — one line, truncated with a trailing ellipsis if
  it overflows the 112 pt viewport, never scrolled. After the reading interval
  the left reveal returns immediately to 44 pt. All content changes use the
  existing 160 ms opacity crossfade. This gives Reduce-Motion users the same
  temporary readable reveal without any positional or marquee motion.

## Tab rail redesign

The three real buttons remain Media, System, and Finder; Notification remains
out of the rail.

### Layout

The active tab is a labelled capsule; inactive tabs are icon-only capsules.

| Selection | Active width | Inactive width | Content |
| --- | ---: | ---: | --- |
| any tab | 152 pt | 58 pt each | active icon + label; inactive icon only |

The rail is horizontally centred. If the expanded width is too narrow for the
three values plus 8 pt gaps, active width reduces first, never below 116 pt;
inactive hit targets remain at least 44 pt.

The selected capsule width, label opacity, icon position, and indicator all
animate from their current presentation values with a critically damped
response around 320–360 ms. Clicking a new tab while this runs retargets the
same geometry; it must not teleport or queue.

### Content stability

Expanded shell height is fixed to the maximum required height of Media, System,
and Finder for the duration of the panel. Existing portal content transitions
run within that stable shell, but switching to System must not resize the
AppKit panel and then snap again when returning to Finder/Media.

Notification is out of the rail and must **not** drive this fixed height: either
it never uses the expanded tab shell, or, if a notification is presented inside
the expanded panel, its content lays out within the same fixed
max(Media, System, Finder) height and does not resize the panel. Confirm which
path is taken so the acceptance test can assert no resize on notification.

The existing quadratic portal duplicate remains as a brief accent. It must
travel with the active capsule's current presentation, never dominate the rail
or cause another full-width violet rectangle.

## Interaction and accessibility

- Compact media button has a dedicated accessible name: `Pause <title>` while
  playing and `Play <title>` otherwise.
- The source thumbnail is decorative only when the compact container exposes
  the title/source label; it must not be announced twice.
- Active/inactive tab state remains announced via selected traits. Icon-only
  inactive tabs retain explicit labels.
- Compact background tap remains available outside the direct play/pause target.
- The parent compact gesture must be tested against button activation to prove
  it does not expand the panel.

## Implementation boundaries

### New pure models

Introduce pure models separate from SwiftUI rendering:

- `CompactWingState` and an asymmetric `CompactGeometryModel` returning core,
  left/right reveals, total width, and an anchor-aware panel origin policy.
- `CompactReadingReducer` / coordinator that owns identity, reading phase, and
  cancellation/retarget generation. It exposes derived `leftReveal`, title
  scroll policy, and whether one-shot accents may run.
- `CompactTitleMarqueePolicy` that decides fit versus one-pass scroll from text
  width and viewport width. Its timing is deterministic and testable.
- `TabRailLayout` that derives the three widths and label visibility from active
  tab, available width, and Reduce Motion.

The existing shell and tab coordinators keep ownership of expansion/collapse
and panel source/target lifecycle. The compact reading coordinator must not
select tabs or mutate global island state.

### Rendering changes

- `NotchPanelFrame` gains core-anchor-aware compact frame construction; expanded
  frames keep the current centred behavior.
- `NotchPanelController` observes compact left/right geometry and applies only
  the compact frame change required for the reading reveal, anchored to the
  physical core.
- `IslandCompactView` composes one unified surface and contains a direct media
  button plus a background-only expansion gesture.
- `CompactMediaMotionView` renders source thumbnail, title viewport/marquee,
  waveform, and direct button without per-wing shell backgrounds.
- `IslandExpandedView` uses `TabRailLayout` rather than equal-width cells and
  uses a stable maximum content height across visible tabs.

## Testing and acceptance

### Automated checks

Add failing checks before production code for:

1. left/right reveal values and core-anchor frame origin in all compact states,
   including non-zero `alignmentOffset` and simulated-notch core width;
2. transition from reading reveal back to resting with no core-centre drift, and
   collapse targeting `mediaResting` (not `mediaReading`) with a continuous
   horizontal origin from the centred expanded frame (no X snap);
3. identity changes retarget reading state and unchanged polls do not restart;
4. marquee fit, delayed one-pass scroll, completion hold, and — under Reduce
   Motion — an immediate static 156 pt reveal with a truncated, non-scrolling
   title (asserting legibility is preserved, not suppressed);
5. direct control action policy proving a compact control hit does not request
   panel expansion;
6. tab rail widths/labels at normal and narrow expanded widths;
7. stable expanded shell height across Media/System/Finder, and no panel resize
   when a notification is presented;
8. waveform is deterministic per frame index, holds a static frame when paused
   and under Reduce Motion, and the 180 ms settle does not overlap the 30 fps
   play loop.

Run the dependency-free check runner, release build, and strict signature
verification after each finished implementation slice.

### Physical-device acceptance

Use the submitted physical photo as the before reference. A new photo/video on
the built-in display must show:

1. one continuous black silhouette from both wings through the physical notch,
   with no vertical white/different-black seam;
2. readable long title during the temporary reading reveal and a compact
   thumbnail-only left wing afterwards;
3. balanced waveform/play button in the right wing and direct play/pause with
   no island expansion;
4. tab capsules that expand/collapse continuously while content panel height
   remains stable;
5. rapid track and tab changes that retarget without a blank frame, teleport,
   or accidental panel opening.

## Risks and mitigation

- **Asymmetric panel sizing can drift from the camera core.** All compact frame
  calculations use physical core centre (`midX + alignmentOffset`) rather than
  total surface centre; add pure frame tests and compare a real photo.
- **Collapse can slide the window sideways.** Expanded is screen-centred while
  compact is core-anchored and left-heavy; collapse targets `mediaResting` and
  interpolates X continuously, keeping residual travel to the small
  centre-vs-resting delta instead of the full reading offset.
- **Reduce Motion could hide long titles.** RM keeps the temporary 156 pt reveal
  (applied instantly, static truncated title) so legibility is preserved without
  any motion.
- **SwiftUI gesture composition can still leak button taps to the container.**
  Use a real `Button` and explicit background content shape/gesture policy;
  test action routing in a pure interaction model and manually verify.
- **Text measurement differs by system font/accessibility size.** Marquee uses
  measured overflow and clamps reveal to the available display bounds; it never
  assumes character count.
- **A fixed expanded height can leave Finder with empty space.** The space is
  intentional stability; content stays top-aligned and the panel avoids visible
  resize jumps.

## Decision

Proceed with this targeted UI-layer rebuild after user approval. It changes the
compact geometry contract and compact/tab rendering, but preserves the working
service, state, and panel-motion foundations.
