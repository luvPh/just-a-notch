# Compact title reveal choreography

## Goal

When a real media title arrives, show it at the same time as the compact left
wing opens. Long titles pan across the title viewport during that same entrance
animation. After the complete title has been shown, the wing waits at least one
second, then returns to its resting width. The title must remain visible for at
least three seconds in total.

## Behaviour

1. A track with a real title changes the compact state from `resting` to
   `reading`. The left wing and the title enter in the same animation.
2. The title starts at its leading edge and pans at the same time as the spring
   that opens the wing. It does not have an entrance or reading delay.
3. If the title fits the viewport, it stays static until the three-second
   minimum visible duration has elapsed.
4. If the title overflows, it pans at the existing readable speed. Once the
   trailing edge is visible, it remains visible for at least one second and
   long enough for the total reveal duration to be at least three seconds.
5. The left wing then retracts through the existing spring animation.

## Timing model

`revealDuration = panDuration + trailingHold`, where
`trailingHold = max(1 second, 3 seconds - panDuration)`.

`panDuration` is zero for a fitting title and otherwise remains based on the
measured overflow distance and current marquee speed. The marquee has no delay.

## Scope

- Keep the current real-title guard, so a browser placeholder never expands a
  title wing.
- Keep the existing compact geometry and spring settings.
- Change only title-marquee scheduling and the transient reveal timeout.

## Verification

- A short title appears while the wing expands, stays visible for at least
  three seconds, then retracts.
- A long title appears while the wing expands, pans from start to finish
  immediately, and retracts only after the full title has been visible for at
  least three seconds total.
- A placeholder YouTube title still does not open a blank reading wing.
