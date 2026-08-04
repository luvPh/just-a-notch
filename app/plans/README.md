# Animation implementation plans

| # | Plan | Severity | Status |
|---|---|---|---|
| 001 | [Make live media drive a physical notch morph](001-live-media-notch-motion.md) | HIGH | DONE |

## Recommended order

Execute plan 001 as one dependency chain: fix observable media wiring first,
then add compact waveform/content motion, then animate the AppKit panel frame.
The media state is the trigger for the animation, so motion verification is not
meaningful until the observation fix is in place.
