# 001 — Make live media drive a physical notch morph

- **Status**: DONE
- **Commit**: unversioned workspace (no `.git` directory is present)
- **Severity**: HIGH
- **Category**: State indication, physicality, easing, accessibility
- **Estimated scope**: 5 files, roughly 140 lines

## Problem

The compact notch reads the current track through an environment container that
SwiftUI does not observe:

```swift
// Sources/NotchIslandKit/Island/IslandRootView.swift:37 — current
IslandCompactView(
    height: settings.compactHeight,
    event: viewModel.state == .compact ? nil : viewModel.lastEvent,
    track: env.mediaPanelVM.track
)
```

`MediaPanelViewModel.track` is `@Published`, but `IslandRootView` only observes
`IslandViewModel` and `SettingsStore`. A media update therefore does not
invalidate the compact view. The YouTube adapter can read the currently open
Chrome tab title, but the UI remains in its quiet presentation.

When the content does change, its only transition is a fade:

```swift
// Sources/NotchIslandKit/Island/IslandCompactView.swift:24 — current
VStack(spacing: 0) {
    Text(track.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
    Text(track.sourceAppName).font(.system(size: 8)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
}
.transition(.opacity)
```

The outer AppKit panel also teleports between compact and expanded frames:

```swift
// Sources/NotchIslandKit/Window/NotchPanelController.swift:70 — current
let frame = NSRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
panel.setFrame(frame, display: true, animate: false)
```

Together these make the product look static even though a SwiftUI spring is
attached to the `expanded` boolean.

## Target

1. A newly detected track redraws the compact notch immediately.
2. Track entry has spatial meaning: content drops 6 pt from behind the physical
   notch and grows from 0.94 to 1.0, anchored at the top. Opacity may support the
   movement but must not be the only animated property.
3. A three-bar waveform moves at 30 fps only while playback is `.playing`.
   Bar heights are deterministic sine waves, not random values; amplitude is
   4–12 pt and each bar is phase-shifted by 0.7 radians.
4. Compact/expanded resizing remains anchored at screen top-centre and runs for
   260 ms with `CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)`.
5. Entry/exit uses `Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)`.
6. With macOS Reduce Motion or the app's `reduceAnimation` setting enabled,
   offsets, scale, waveform, and window-frame interpolation stop; retain a
   160 ms opacity transition so state changes remain legible.
7. Reversing expand/collapse during the animation retargets from the current
   frame; it must not restart from the compact frame.

## Repo conventions to follow

- Motion preference already combines
  `EnvironmentValues.accessibilityReduceMotion` with
  `SettingsStore.reduceAnimation` in
  `Sources/NotchIslandKit/Island/IslandRootView.swift:19`.
- Keep the existing macOS 13 deployment target. Do not use `PhaseAnimator`,
  `KeyframeAnimator`, or symbol effects introduced after macOS 13.
- Use only SwiftUI and AppKit. Do not add a motion dependency.
- Keep iconography in SF Symbols; do not introduce emoji.

## Steps

1. In `Tests/Checks/main.swift`, add a regression check around a tiny
   `CompactMediaPresentationModel` (introduced in step 2): publish a new
   `MediaTrack` through a test `CurrentValueSubject`, drain the main run loop,
   and assert the model exposes `.media(track)`. Run
   `swift run NotchIslandChecks` and confirm the new check fails because the
   model/API does not exist.
2. In `Sources/NotchIslandKit/Island/PanelViewModels.swift`, add the smallest
   observable compact-media bridge needed by the test, or reuse
   `MediaPanelViewModel` if the test can exercise it without real services. Do
   not duplicate polling or track state.
3. In `Sources/NotchIslandKit/Island/IslandRootView.swift`, add
   `@ObservedObject var mediaViewModel: MediaPanelViewModel`. Pass
   `mediaViewModel.track` and `mediaViewModel.state` to `IslandCompactView`.
   Update the construction site in
   `Sources/NotchIslandKit/Window/NotchPanelController.swift` to pass
   `env.mediaPanelVM`. Do not access the track through `env` inside `body`.
4. In `Sources/NotchIslandKit/Island/IslandCompactView.swift`, accept
   `PlaybackState`. Extract a private `CompactWaveformView` made from three
   2 pt wide capsules. Drive it with `TimelineView(.animation(minimumInterval:
   1.0 / 30.0, paused: state != .playing || reduceMotion))`; calculate each
   height as `8 + sin(time * 5.5 + Double(index) * 0.7) * 4`, clamped to 4...12.
   Keep the capsules white with descending opacities 0.92, 0.72, 0.52.
5. Replace the pure fade on media content with an asymmetric transition whose
   active modifier is `offset(y: -6)`, `scaleEffect(0.94, anchor: .top)`, and
   `opacity(0)`, and whose identity modifier is zero offset, scale 1, opacity 1.
   Apply `Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)` keyed by a
   stable media identity such as title plus source. Keep track changes to one
   compact line where space is constrained; do not marquee continuously.
6. In `Sources/NotchIslandKit/Window/NotchPanelController.swift`, split
   geometry calculation from frame application. For state-driven resizing,
   use `NSAnimationContext.runAnimationGroup`, duration 0.26, and
   `CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)`, then call
   `panel.animator().setFrame(targetFrame, display: true)`. Screen changes,
   wake, and settings changes must continue applying frames immediately. Before
   starting a new state animation, begin from `panel.presentation`/current
   visible frame so rapid reversal is interruptible.
7. Thread the combined reduce-motion flag to compact motion and panel-frame
   motion. In reduced mode pause the timeline, remove scale/offset, apply frame
   immediately, and keep only a 160 ms opacity transition.
8. Run the full check runner and build the distributable app. Manually verify
   with an actively playing YouTube tab after Chrome's **View > Developer >
   Allow JavaScript from Apple Events** setting is enabled.

## Boundaries

- Do NOT use private `MediaRemote` frameworks or synthetic global media keys.
- Do NOT automate changing Chrome security/developer settings.
- Do NOT add artwork scraping, networking, or YouTube API credentials.
- Do NOT animate the notch continuously while playback is paused.
- Do NOT use random bar heights; they cause visual jitter and nondeterministic
  screenshots.
- Do NOT alter Finder or System panel content.

## Verification

- **Mechanical**: run `swift run NotchIslandChecks`; expect all checks to pass.
- **Mechanical**: run `./scripts/build_app.sh`; expect
  `build/Notch Island.app` to be produced without Swift compiler errors.
- **Media feel check**: play a YouTube video in Chrome. Within one poll interval
  (2 seconds), title and source must appear in the compact notch without first
  opening the Media tab.
- **Control check**: with Chrome's JavaScript-from-Apple-Events setting enabled,
  play/pause must change the actual video and the waveform must pause/resume on
  the next refresh.
- **Motion feel check**: screen-record at 60 fps and inspect frame by frame. The
  content must originate from the top edge, and the window's top centre must
  remain fixed while the bottom and sides grow.
- **Interruptibility check**: click to expand and click outside before 260 ms;
  the panel must reverse from its current size without snapping.
- **Reduced-motion check**: enable Reduce Motion in macOS Accessibility and the
  app setting separately. In both cases there must be no translation, scale,
  waveform, or interpolated window resize; the short fade remains.
- **Done when**: live YouTube metadata appears from compact state, Chrome media
  buttons control the video when the required browser permission is enabled,
  and the notch morph is visibly spatial rather than an opacity-only swap.
