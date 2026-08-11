# Clipboard History + Timer/Pomodoro — Design

Ngày: 2026-08-11
App: just-a-notch (macOS notch utility, SwiftUI)

## Mục tiêu

Thêm 2 tính năng mới, mỗi tính năng là 1 tab trên rail của notch, bật/tắt được
trong Settings như các tab Files/Notifications/Calendar hiện có:

1. **Clipboard history** — lưu lịch sử copy (text + ảnh), click để copy lại.
2. **Timer / Pomodoro** — đếm ngược + chu kỳ làm/nghỉ tuỳ biến, báo bằng chuông.

## Kiến trúc chung

- Thêm 2 case vào `RailTab` (UI/NotchRootView.swift): `.clipboard`, `.timer`,
  kèm `icon` + `title`.
- Mỗi tính năng theo khuôn hiện có: **Model → Store/Service (ObservableObject)
  → Panel (SwiftUI)**. Persist theo pattern `FileShortcutStore`
  (JSON atomic trong `~/Library/Application Support/Just a Notch/`).
- Toggle hiển thị tab + toàn bộ preference lưu trong `AppSettings` (UserDefaults).
- Wiring tab: cập nhật `visibleTabs`, `selectTab`, các cờ `*TabActive` trong
  NotchRootView giống các tab hiện có.

---

## Module 1 — Clipboard

### Model — `ClipboardItem`
- `id: UUID`, `createdAt: Date`, `pinned: Bool`
- `kind: .text(String) | .image` (Codable qua enum có associated value)
- Ảnh KHÔNG nhét vào JSON: lưu file PNG riêng tại
  `.../Just a Notch/Clipboard/<uuid>.png`; item chỉ giữ tên file.

### Store — `ClipboardStore: ObservableObject`
- `@Published var items: [ClipboardItem]`
- Theo dõi clipboard bằng `Timer` ~0.4s poll `NSPasteboard.general.changeCount`
  (macOS không có API sự kiện clipboard; đây là cách chuẩn, rất nhẹ, không cần
  quyền bổ sung).
- Khi `changeCount` đổi: đọc pasteboard — ưu tiên `.string`; nếu không có text
  thì thử ảnh (`NSImage` / `.png` / `.tiff`).
- **Chống trùng:** nếu nội dung trùng mục đầu danh sách → bỏ qua (không thêm mới,
  không nhân đôi).
- **Chống loop:** khi user click "copy lại", store tự ghi `changeCount` mà nó
  vừa tạo ra và bỏ qua lần poll tương ứng để không tự thêm lại chính mục đó.
- **Giới hạn:** giữ tối đa **25 mục CHƯA ghim**; mục `pinned` không tính vào
  giới hạn và không bao giờ bị đẩy ra.
- Khi 1 item ảnh bị đẩy khỏi list (hoặc bị xoá) → xoá file PNG kèm theo.
- Persist JSON atomic (chỉ metadata + tên file ảnh). Nạp lại lúc khởi động.

### UI — `ClipboardPanel`
- Danh sách cuộn dọc:
  - text: hiện 1–2 dòng rút gọn (monospaced nhẹ), tooltip full.
  - ảnh: hiện thumbnail.
- Mỗi mục: click = copy lại vào clipboard (KHÔNG auto-paste — tránh cần quyền
  Accessibility). Hover hiện nút **Ghim (📌)** và **Xoá**.
- Nút **Clear all** (xoá tất cả trừ pinned) ở góc panel.
- (Tuỳ chọn, không bắt buộc) Wing trái hiện số mục đang ghim.

### Paste behaviour
- **A**: click chỉ copy lại vào clipboard; user tự ⌘V ở app đích. Không xin thêm
  quyền hệ thống.

---

## Module 2 — Timer / Pomodoro

### Settings — `PomodoroSettings` (trong `AppSettings`, UserDefaults)
Tuỳ biến tối đa:
- `workMinutes` (mặc định 25)
- `shortBreakMinutes` (5)
- `longBreakMinutes` (15)
- `roundsBeforeLongBreak` (4)
- `autoStartNext: Bool` — tự chạy pha kế tiếp, hay dừng chờ user bấm "Bắt đầu"
- `soundEnabled: Bool`, `soundName: String`, `volume: Double`

### Service — `TimerService: ObservableObject`
- Trạng thái: `phase: .work | .shortBreak | .longBreak`,
  `remaining: TimeInterval`, `isRunning: Bool`, `completedWorkRounds: Int`,
  và chế độ `mode: .pomodoro | .plain`.
- Đếm bằng `Timer` 1s NHƯNG tính theo **`endDate` tuyệt đối** (lưu mốc kết thúc)
  → chính xác kể cả khi máy ngủ/đánh thức; mỗi tick chỉ tính `endDate - now`.
- Hết pha:
  - Phát chuông qua `NSSound` theo `soundName`/`volume` nếu `soundEnabled`.
  - Pomodoro: tăng `completedWorkRounds` sau pha `.work`; chọn pha kế tiếp theo
    luật (đủ `roundsBeforeLongBreak` vòng làm → `.longBreak`, reset đếm vòng;
    ngược lại `.shortBreak`; sau break → `.work`). Nếu `autoStartNext` thì tự
    chạy pha kế, không thì để `isRunning = false` chờ user.
  - Plain timer: đếm về 0 → chuông, dừng (không chuyển pha).
- API: `startPomodoro()`, `startPlain(minutes:)`, `pause()`, `resume()`,
  `reset()`, `skip()`.

### UI — `TimerPanel`
- Vòng tròn tiến trình lớn + `mm:ss` ở giữa; màu đổi theo pha (làm vs nghỉ).
- Nút **Start / Pause / Reset / Skip**.
- Preset nhanh cho plain timer (5 / 10 / 25) + ô nhập phút tự do.
- Nhãn tiến trình vòng: "Vòng 2/4".

### Wing notch
- Khi `isRunning`, hiện vòng đếm ngược nhỏ + số phút còn lại trên wing (kể cả
  khi panel đóng), màu theo pha. Wiring qua NotchViewModel giống các chỉ báo wing
  hiện có.

### Settings panel
- Thêm mục "Timer / Pomodoro": các trường số ở trên + chọn âm + slider âm lượng
  + nút "Nghe thử".

---

## Ngoài phạm vi (YAGNI)
- Auto-paste (cần Accessibility) — để dành cho sau.
- Alarm theo giờ đồng hồ — trùng vai với app Clock/Calendar.
- Clipboard lưu file path / rich types — chỉ text + ảnh ở bản này.
- Đồng bộ đám mây, tìm kiếm full-text clipboard.

## Kiểm thử
- ClipboardStore: thêm text/ảnh, chống trùng, chống loop khi copy lại, cắt giới
  hạn 25 (giữ pinned), dọn file PNG khi item bị đẩy ra.
- TimerService: chuyển pha đúng luật, đếm theo endDate qua mô phỏng thời gian,
  long break sau N vòng, autoStartNext bật/tắt, plain timer về 0.
