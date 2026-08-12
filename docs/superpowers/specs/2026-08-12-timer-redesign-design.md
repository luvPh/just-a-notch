# Timer redesign — thiết kế

Ngày: 2026-08-12

## Mục tiêu

Làm lại tab Timer thành công cụ tuỳ biến tối đa, gom mọi kiểu hẹn giờ vào một
carousel 3 trang dễ hiểu, mỗi đoạn/pha có âm báo riêng, và thư viện âm phong phú
hơn (âm dài/êm do người dùng cung cấp).

## Concept cốt lõi: Chuỗi gồm nhiều Đoạn

- **Đoạn (segment)** — viên gạch nhỏ nhất: tên, thời lượng (phút) *hoặc* đếm lên
  (stopwatch), âm báo riêng khi kết thúc, màu.
- **Chuỗi (sequence)** — danh sách đoạn nối nhau + luật lặp.

Mọi kiểu timer chỉ là các dạng của cùng mô hình, chạy trên cùng một cỗ máy
(`TimerService`).

## Ba trang carousel (tab Timer)

Chuyển trang bằng vuốt/scroll ngang; có chấm chỉ trang (dot indicator). Trạng thái
trang hiện tại lưu vào UserDefaults.

### Trang 1 — Đơn
- Đồng hồ + nút nhanh `5′ / 10′ / 25′` + `⋯` (nhập số phút + lời nhắc).
- Công tắc **Đếm ngược ⇄ Đếm lên (stopwatch)**. Ở chế độ đếm lên: bấm chạy, giờ
  tăng dần không giới hạn, có nút dừng/reset; không có âm kết thúc.
- Chạy đúng **một lần**. Hết giờ (đếm ngược) → kêu chuông + hiện lời nhắc → dừng.

### Trang 2 — Pomodoro
- Giữ concept hiện tại nhưng rõ ràng hơn: hiển thị pha (Làm/Nghỉ ngắn/Nghỉ dài),
  tiến trình "Vòng x/N".
- Chỉnh phút Làm / Nghỉ ngắn / Nghỉ dài / Số vòng trước nghỉ dài / Tự chạy pha
  kế tiếp ngay trong trang (dùng `AppSettings.pomo*` sẵn có).
- Tự luân phiên pha theo luật `nextPhase` hiện có; lặp vô hạn tới khi dừng.

### Trang 3 — Chuỗi tự tạo
- Trình dựng chuỗi: **tối đa 4 đoạn**. Mỗi đoạn: tên, số phút, âm báo.
- **Vùng lặp**: chọn một dải đoạn liên tiếp `[start…end]` + số lần lặp `R`
  (2…10). Chuỗi chạy: các đoạn trước vùng (1 lần) → vùng lặp `R` lần → các đoạn
  sau vùng (1 lần). Ví dụ đoạn1+đoạn2 lặp 2 lần rồi tới đoạn3:
  `1 → 2 → 1 → 2 → 3`. Nếu không đặt vùng lặp thì chạy tuần tự 1 lần.
- **Lưu tối đa 5 chuỗi**: đặt tên, chọn từ danh sách để chạy/sửa/xoá.

## Nút cài đặt tổng (⚙️)

- **Luôn hiện khi đang ở tab Timer** (góc trên bên phải vùng panel).
- Bấm → mở panel cài đặt tổng ngay trong tab (slide-over, có nút ◀ quay lại):
  - Thư viện âm (xem dưới) + nghe thử.
  - Âm mặc định cho từng loại pha.
  - Bật/tắt âm, âm lượng chung.

## Thư viện âm

- Liệt kê **toàn bộ âm hệ thống macOS** trong `/System/Library/Sounds` (≈14 âm),
  thay vì 5 âm hardcode.
- Hỗ trợ **âm do người dùng cung cấp**: app đọc thêm thư mục
  `Resources/Sounds/` được đóng gói trong bundle (file `.caf`/`.m4a`/`.aiff`).
  Người dùng sẽ tự tải file về; ta chỉ cần cơ chế nạp + hiển thị chúng trong
  dropdown.
- Mỗi đoạn/pha chọn âm riêng qua `StyledSoundPicker` (đã có), có nghe thử.
- Phát âm: mở rộng lớp phát hiện tại để nạp được `NSSound(contentsOfFile:)` cho
  file bundle, ngoài `NSSound(named:)` cho âm hệ thống.

## Mô hình dữ liệu (Core)

```
struct TimerSegment: Codable, Identifiable {
    var id: UUID
    var name: String
    var minutes: Int          // >0 = đếm ngược; 0 = đếm lên (chỉ dùng ở trang Đơn)
    var soundName: String     // key tra trong thư viện âm
    var colorHex: String
}

struct TimerSequence: Codable, Identifiable {
    var id: UUID
    var name: String
    var segments: [TimerSegment]   // ≤ 4
    var loopStart: Int?            // index bắt đầu vùng lặp
    var loopEnd: Int?             // index kết thúc vùng lặp
    var loopCount: Int            // số lần lặp vùng (mặc định 1)
}
```

- Persist danh sách chuỗi (≤5) + cấu hình âm vào `UserDefaults` (JSON) hoặc
  Application Support. Chọn `UserDefaults` cho đồng bộ với `AppSettings` hiện tại.

## Kiến trúc TimerService

- Tổng quát hoá `TimerService` để chạy **một danh sách đoạn đã "trải phẳng"**
  (expand vùng lặp thành chuỗi tuần tự các đoạn), giữ endDate-clock hiện có.
- Giữ nguyên các đường Pomodoro/plain hiện tại bằng cách map chúng thành chuỗi:
  - Đơn = 1 đoạn.
  - Pomodoro = sinh chuỗi từ `PomodoroConfig` (giữ `nextPhase`).
  - Stopwatch = 1 đoạn `minutes = 0` (đếm lên; nhánh tick riêng cộng dồn).
- Mỗi khi hết một đoạn: phát âm của **đoạn đó** (không phải một âm chung).
- `justFinished`/`label` vẫn dùng cho lời nhắc kết thúc.

## Phạm vi & thứ tự làm (đề xuất tách phase)

1. Core: mô hình `TimerSegment`/`TimerSequence`, tổng quát hoá `TimerService`
   (expand vùng lặp, âm theo đoạn, nhánh stopwatch) + test.
2. Thư viện âm: nạp âm hệ thống + bundle `Resources/Sounds/`, cập nhật
   `StyledSoundPicker` để dùng nguồn động; lớp phát hỗ trợ file.
3. UI carousel 3 trang + dot indicator + lưu trang hiện tại.
4. Trang 3 (trình dựng chuỗi) + lưu tối đa 5 chuỗi.
5. Panel cài đặt tổng (⚙️ luôn hiện) + di chuyển cấu hình âm vào đây.

## Ngoài phạm vi (YAGNI)

- Nested loop nhiều tầng (chỉ hỗ trợ 1 vùng lặp).
- Cửa sổ macOS riêng cho trình dựng (làm ngay trong tab).
- Đồng bộ iCloud/chia sẻ chuỗi.
