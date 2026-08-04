# Focused Island Design

## Goal

Make Notch Island a focused, non-disruptive status surface: it must not behave
as a launcher, it must not switch the user away from the content they chose,
and its media experience must accurately describe availability and playback.

## Scope

- Remove the Quick Actions feature from the island UI and remove all bundled
  launcher-style defaults (Downloads, Screenshots, Apple, and Toggle Island).
- Make the compact island open the most useful available content: active media
  first, otherwise System; it must never target removed Quick Actions.
- Remove the launch-time welcome takeover. High-priority alerts may surface only
  when the user is not actively interacting with expanded or pinned content.
- Preserve the current user-selected content while an alert is pending; when an
  alert is dismissed or expires, do not reopen a previous pinned screen.
- Keep Media, System, and Finder as user-selected tabs. Finder search must be
  able to take keyboard input while the floating panel remains non-activating
  in all other cases.
- Provide an explicit media availability state: unsupported when no supported
  source is running, unavailable when the source cannot be read/controlled,
  and a visible track/playback state once a source responds.
- Apply the menu-bar-icon preference immediately.

## Interaction Rules

1. Opening the island selects Media when a supported player is available;
   otherwise it selects System. It never opens an Actions screen.
2. Media polling starts when its tab appears, stops when it disappears, and
   presents a clear empty state rather than pretending a source is playing.
3. User actions win over transient events. An event may take over only from the
   compact/hover states. Dismissal cancels any active transient restoration.
4. The Finder search field makes the panel key only for text entry and releases
   that capability when editing ends.
5. Menu-bar-icon changes create or remove the status item immediately.

## Architecture

- Delete the launcher-facing island wiring; retain service code only where it
  is needed by persisted user data or can be safely removed in the same change.
- Put content-selection policy in `IslandViewModel` and test it through the
  pure state machine where possible.
- Add a small panel focus callback from Finder UI to `NotchPanelController`.
- Keep source adapters public-API-only; model their result conservatively and
  expose actionable unavailable copy in the Media view.

## Testing

- Extend the dependency-free check runner and XCTest suite with regressions for
  default island content, event non-interruption/cancellation, and no default
  quick actions.
- Add unit tests for any pure selection or event policy introduced.
- Run `swift run NotchIslandChecks` and a release build. XCTest is run where
  full Xcode is installed; this environment has Command Line Tools only.

## Non-goals

- Private MediaRemote APIs, notification mirroring, browser scraping beyond the
  existing public AppleScript integrations, and a new configurable launcher.
- Redesigning the visual brand beyond removing the launcher grid and making
  empty/media states coherent.
