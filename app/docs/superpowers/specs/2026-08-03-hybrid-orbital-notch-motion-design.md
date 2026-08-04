# Hybrid Orbital Notch Motion Design

**Date:** 2026-08-03  
**Status:** Approved  
**Scope:** Compact notch geometry, compact media choreography, collapse choreography, and expanded tab transitions

## Objective

Make Notch Island feel like one continuous, physical surface rather than a
collection of fades. The compact surface must always extend beyond the physical
camera notch so live media metadata and controls remain visible. Motion should
combine the atmospheric layering of Cinematic Media with the elastic spatial
behavior of Elastic Orbit.

The selected direction is **Hybrid B+C** with **Orbital Portal** tab
transitions.

## Product principles

1. The camera notch is an occluding core, never a content container.
2. The black island shell is the primary moving object. Content motion follows
   the shell instead of animating independently without spatial context.
3. Complex motion is event-driven. Decorative effects do not loop after the
   interface settles; only a playing waveform remains alive.
4. Every transition is interruptible. A new click retargets from the current
   presentation rather than waiting for the previous transition to finish.
5. Media polling updates media state only. It never selects a tab or expands the
   island automatically.
6. Reduced Motion retains state legibility while removing orbit, anticipation,
   blur, glow, and spatial displacement.

## Compact geometry

### Physical-notch display

The compact surface is divided into three horizontal regions:

```text
left wing (83 pt) | physical notch core | right wing (83 pt)
```

The active compact width is:

```text
physicalNotchWidth + 166 pt
```

The left wing contains track metadata. The right wing contains the waveform and
compact playback affordance. Neither wing may place content inside the physical
notch core.

### No-notch and detection fallback

When no physical notch is detected, use a 200 pt simulated core plus the same
83 pt wings. The resulting active compact width is 366 pt. The shell remains
centred on the configured screen anchor.

### Quiet state

When no media or transient event exists, the shell may contract to the physical
notch width plus 24 pt. This leaves a subtle 12 pt edge on each side without
presenting empty controls. When media becomes available, the shell expands to
the full wing geometry without changing tabs.

## Motion architecture

### `CompactGeometryModel`

A pure, testable model receives the detected notch width and content state. It
returns the quiet and active compact widths, core bounds, and visible left/right
wing bounds. It contains no AppKit or SwiftUI animation code.

### `IslandMotionCoordinator`

One coordinator owns shell motion across AppKit window geometry and SwiftUI
content presentation. Its phases are:

```text
resting
expanding
settled
anticipatingClose
collapsing
```

The coordinator exposes the current phase and target geometry. A second request
during an active transition retargets from the current presentation values.
Input is never disabled while motion runs.

The coordinator prevents the current architecture's AppKit frame animation and
SwiftUI view transition from running as unrelated timelines.

### `TabTransitionCoordinator`

The tab coordinator owns:

- source tab and source index;
- target tab and target index;
- transition direction;
- current tab-transition phase;
- the presentation identities for outgoing and incoming panels.

Only explicit user selection starts a tab transition. Media polling, system
monitoring, hover, and focus changes cannot select a tab.

During a transition, outgoing and incoming panels coexist in a clipped stack.
This avoids empty frames and permits reversal from the current presentation.

## Hybrid compact choreography

### Expansion

1. **0–90 ms — shell catch-up:** the shell grows horizontally from the quiet
   width. Its top centre stays fixed to the screen anchor.
2. **90–260 ms — elastic settle:** the width reaches 18 pt beyond its final
   target, then settles to the active compact width. If that frame would exceed
   the screen bounds, reduce the overshoot only by the amount required to keep
   the shell on-screen.
3. **60–240 ms — orbital reveal:** metadata moves out from behind the core on
   the left; controls follow the mirrored path on the right. The metadata starts
   at x +30 pt, y -10 pt, scale 0.84, 6 pt blur, and zero opacity. Controls start
   at x -30 pt, y -12 pt, scale 0.68, 6 pt blur, and zero opacity. Identity
   values are zero offset, unit scale, zero blur, and full opacity.
4. **One-shot cinematic accents:** a light sweep crosses the shell once. The
   bottom progress trace begins after shell motion is readable and takes
   650 ms to complete.
5. **Settled live state:** the sweep stops. The trace represents known playback
   progress when available and otherwise disappears after its one-shot reveal.
   Only the three-bar waveform continues moving.

Inner motion uses transform and opacity wherever possible. Waveform capsules
keep fixed frames and animate only their vertical scale at 30 fps.

### Playback state changes

- Playing: waveform bars use deterministic phase-shifted motion.
- Paused: bars settle to their midpoint over 180 ms instead of snapping.
- Track change: shell remains at active width. Old metadata exits toward the
  core with a 2 pt blur; new metadata emerges along the same path. The light
  sweep and 650 ms trace may replay once.
- Media unavailable: controls and metadata retract. The service must debounce a
  single failed poll so the shell does not flicker between active and quiet.

## Collapse choreography

Collapse deliberately uses anticipation but no endpoint overshoot:

1. **80 ms anticipation:** the shell widens by 6 pt and compresses vertically by
   2 pt. Content tightens slightly toward the core. This signals
   the upcoming direction.
2. **240 ms monotonic return:** the shell moves continuously from the
   anticipation pose to the quiet or hidden width. It never contracts below the
   destination and never rebounds after arriving.
3. Content returns along the inverse orbital paths and completes before the
   shell exposes any empty wing area.

Outside-click collapse follows this choreography and returns the expanded panel
to its compact active or quiet state; it does not order the whole panel out.
App termination from the X button remains immediate and does not play a
decorative exit animation.

## Orbital Portal tab transitions

The expanded panel retains the three tabs: Media, System, and Finder.

### Sequence

1. The selected indicator moves to the target tab in 220 ms using a strong
   ease-in-out curve.
2. The outgoing panel recedes downward, scales slightly below 1, blurs, and
   reaches zero opacity in 140 ms.
3. The target tab icon follows a curved path from the bottom rail toward the
   header over 280 ms. The icon is a transitional duplicate; the real bottom
   icon remains available for input.
4. The incoming panel starts 60 ms before the outgoing panel finishes. It opens
   from above with reduced scale and blur, reaching identity in 240 ms.
5. The header title changes when the incoming content crosses 50 percent
   visibility, preventing title/content mismatch.

The path direction reflects the source and target tab order. Rapid tab clicks
retarget the indicator and portal from their current presentation values. No
queue of stale transitions is allowed.

## Visual treatment

- Base shell: near-black to blue-violet gradient, matching the existing dark
  direction.
- Light sweep: subtle violet-white highlight, clipped to the shell, one-shot.
- Progress trace: 2 pt maximum thickness with violet gradient.
- Icons: SF Symbols only. No emoji or raster control icons.
- Blur used during transitions is capped at 6 pt.
- The shell must cover the title/menu-bar area as it does now.

## Accessibility and performance

### Reduced Motion

When either macOS Reduce Motion or the app's Reduce Animation setting is active:

- apply geometry changes immediately;
- remove expansion overshoot and collapse anticipation;
- remove orbital paths, blur, light sweep, and animated progress trace;
- stop waveform motion;
- retain a 160 ms opacity crossfade and immediate selected-tab indicator update.

### Performance constraints

- Inner continuous animation is limited to transform and opacity.
- The waveform runs only while playback is playing.
- AppKit window resizing is limited to explicit shell transitions, not media
  polling ticks.
- No random waveform values, unbounded animation timers, private frameworks, or
  third-party motion dependency.
- Do not animate every expanded-panel row on each tab selection. The panel moves
  as one composited layer.

## Error handling

- If physical geometry cannot be read, use the 200 pt fallback core.
- If media controls are unavailable, metadata may remain visible but controls
  must communicate the unavailable state in the expanded Media panel.
- A single failed media poll preserves the last stable presentation. A
  subsequent failure may transition to unavailable according to the media
  service's debounce policy.
- Screen changes, wake, or display disconnection cancel in-flight geometry
  motion and apply the correct frame immediately on the new target screen.
- A tab view that fails to produce content falls back to the target tab's empty
  state without leaving the transition coordinator active.

## Testing strategy

### Automated checks

1. `CompactGeometryModel` produces 83 pt visible wings for detected and fallback
   notch widths.
2. Quiet width never exceeds active width and never becomes narrower than the
   physical core.
3. `IslandMotionCoordinator` follows valid phase transitions and retargets
   expansion/collapse without queuing stale work.
4. Collapse anticipation widens by 6 pt, and the return samples are monotonic.
5. `TabTransitionCoordinator` derives correct direction from tab indices,
   handles rapid retargeting, and finishes on the latest selected tab.
6. Media updates do not mutate the selected tab.
7. Waveform pause settles to midpoint and Reduced Motion disables continuous
   motion.
8. Existing media, geometry, state-machine, and settings checks remain green.

### Manual verification

- Record at 60 fps and inspect shell expansion, anticipation, monotonic collapse,
  and Orbital Portal frame by frame.
- Play, pause, and change YouTube tracks; verify the compact wings remain visible
  beside the physical camera core.
- Switch Media → System → Finder and reverse direction rapidly.
- Click outside during expansion and click another tab during a portal
  transition; neither action may snap or wait for prior motion.
- Test macOS Reduce Motion and the app setting independently.
- Test the built-in notched display, an external display, and simulated-notch
  mode.

## Out of scope

- Artwork scraping or YouTube API integration.
- Private MediaRemote frameworks or synthetic global media keys.
- Gesture dragging of the island.
- Redesigning System or Finder panel content.
- Adding or removing feature tabs.

## Acceptance criteria

The design is complete when:

1. compact media is visibly rendered in two wings outside the physical notch;
2. expansion uses the approved Hybrid B+C choreography;
3. collapse uses 80 ms anticipation followed by a 240 ms monotonic return;
4. tab changes use the approved Orbital Portal choreography and remain
   interruptible;
5. passive media polling never switches tabs;
6. Reduced Motion removes spatial/decorative motion while preserving state
   clarity;
7. automated checks, release build, signing, and manual browser/media checks
   pass.
