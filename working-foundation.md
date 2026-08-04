# Backend / logic đã hoạt động (giữ lại khi xây lại UI)

**Ngày:** 2026-08-04
**Bối cảnh:** Tầng view/animation của compact notch sẽ được đập đi làm lại. Tài liệu
này ghi lại các phần **logic thuần + service đã chạy ổn và có test**, để không phải
viết lại từ đầu. Kiểm chứng bằng `swift run NotchIslandChecks` → **223/223 pass**;
`swift build -c release --product NotchIsland` xanh (CLT, không cần Xcode).

## 1. Pure models đã test (an toàn để giữ)

Tất cả tách khỏi SwiftUI, deterministic, có check trong `Tests/Checks/main.swift`.

| Model | File | Vai trò |
| --- | --- | --- |
| `AsymmetricCompactGeometry` + `AsymmetricCompactGeometryModel` | `Sources/NotchIslandKit/Island/IslandMotion.swift` | Reveal trái/phải bất đối xứng, origin neo theo tâm lõi camera (`coreCentreX = screenMidX + alignmentOffset`). States: quiet 12/12, mediaResting 44/76, mediaReading 156/76. |
| `CompactReadingReducer` (+ `CompactReadingState`, `CompactReadingEvent`) | `Sources/NotchIslandKit/Island/CompactReadingReducer.swift` | Vòng đời "reading": identity (`sourceApp\|title`), phase reading/resting, `generation` làm token retarget/hủy, chặn stale-timer, unchanged-poll không restart. |
| `CompactTitleMarqueePolicy` | `Sources/NotchIslandKit/Island/CompactTitleMarqueePolicy.swift` | Quyết định fit (hold 2.2s) / one-pass scroll (delay 0.4s, 26pt/s, hold 0.5s) / static-truncated (Reduce Motion). `readingWindow(for:)` tính thời lượng mở. |
| `TabRailLayout` + `TabRailLayoutModel` | `Sources/NotchIslandKit/Island/TabRailLayout.swift` | Active capsule 152 / inactive 58 / gap 8; narrow fallback active ≥116; cờ `animates`. |
| `CompactWaveformModel` | `Sources/NotchIslandKit/Island/IslandCompactView.swift` | Waveform 3 bar tất định theo frame-index (30fps), tĩnh khi pause/Reduce Motion; `isSettling(sinceStart:)` để settle 180ms không chồng loop. |
| `NotchPanelFrame.compactTarget` | `Sources/NotchIslandKit/Window/NotchPanelController.swift` | Frame compact neo-lõi (không drift), fold `alignmentOffset`, hỗ trợ simulated-notch. |

**Bài học quan trọng đã rút ra (đừng lặp lại):**
- **KHÔNG** animate frame cửa sổ AppKit song song với layout SwiftUI cho reveal →
  lệch timeline, giật. Hướng đúng: cửa sổ giữ **kích thước cố định (envelope =
  reading width)**, animate cánh trái + offset **hoàn toàn trong SwiftUI**, dùng
  offset `envelopeLeft - currentLeft` để lõi đứng yên. (Đã thử, build xanh, nhưng
  UI vẫn bị quyết định đập lại — giữ nguyên tắc, làm lại phần render cho gọn.)
- Chiều cao expanded để **theo tab hiện tại** (Media/Finder gọn), KHÔNG ép cố định
  = max cả 3 tab (làm panel phình quá to).

## 2. Nền tảng service/state cũ vẫn hoạt động tốt (không đụng tới)

Giữ nguyên, đã chạy ổn từ trước:

- **Media adapters + polling + debouncer** (`Services/MediaAdapters.swift`,
  `MediaService.swift`, `YouTubeBrowserAdapter.swift`) — one-missing-poll debouncer.
- **State machine đảo** (`Island/IslandStateMachine.swift`) — compact/hover/expanded/
  pinned, no-auto-tab-selection.
- **Tab transition coordinator** (`Island/TabTransitionCoordinator.swift`) — portal/
  phase scheduler.
- **AppKit panel anchoring + outside-click** (`Window/NotchPanel*.swift`,
  `NotchGeometryProvider.swift`) — dò notch vật lý qua `safeAreaInsets`, fallback
  simulated/external display.
- **Services khác:** `SystemMonitorService`, `FinderService`, `ShortcutService`,
  `NotificationService`, `LaunchAtLoginService`, `SettingsStore`.

## 3. Check runner

- `swift run NotchIslandChecks` — 223 check dependency-free (chạy bằng CLT).
- `swift test` cần Xcode (chưa cài) — xem `memory/just-notch-toolchain.md`.
- Đóng gói `.app`: `./scripts/build_app.sh release` → `build/Notch Island.app`.

## 4. Phần bị đập đi (làm lại tầng render/animation)

`IslandCompactView`, `CompactMediaMotionView`, `IslandExpandedView` (tab rail),
và phần nối reveal trong `IslandRootView` + `NotchPanelController`. Logic ở mục 1
có thể tái sử dụng; chỉ cần dựng lại cách vẽ + animate.

Spec tham chiếu: `docs/superpowers/specs/2026-08-03-asymmetric-compact-notch-design.md`.
