# Dark Live Media Island Design

## Goal

Restore a compact Dynamic Island feel: black with a subtle blue-violet gradient,
live media visible without opening its tab, and a concise System panel.

## Behavior

- Start media observation at app launch while Media is enabled. Compact island
  receives the service's current track and playback state.
- When a track exists, compact island shows SF Symbol playback status, track
  title, and source name. When no track exists, it shows the normal quiet
  compact state.
- System uses four slim metric rows with progress bars; no individual white
  metric cards. Expanded System target height is 250-280pt.
- Keep all explicit dismissal, full-card tab tap targets, screen preference,
  notch clearance, Settings lifecycle, and Reduce Motion behavior from the
  preceding interaction design.

## Visual System

- Use near-black base with a restrained blue-violet radial/linear gradient.
- Use white and muted gray typography with cobalt only for active states and
  progress accents.
- Use SF Symbols only. Do not use emoji or text glyph icons.
- Animate track updates and tab selection with a short fade/spring; never
  animate the whole content on every polling tick.

## Testing

- Add check-runner/XCTest coverage for compact media presentation selection and
  System compact layout height.
- Run check runner, release build, bundle assembly, and signature verification.
