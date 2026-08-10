# Calendar tab (Dương + Âm + ngày lễ VN) — Design

Date: 2026-08-10
Status: Approved (pending spec review)

## Mục tiêu

Thay tab placeholder **Clock** bằng tab **Lịch (Calendar)** thật, tính toán hoàn
toàn **offline, không cần cấp quyền**. Hiển thị được cả **lịch dương** và **lịch
âm Việt Nam**, đánh dấu **ngày lễ Việt Nam**.

Không dùng EventKit / Calendar.app (không đọc sự kiện cá nhân, không xin quyền).

## Phạm vi (scope)

Trong phạm vi:
- Đổi rail tab `.clock` → `.calendar`, bỏ nội dung placeholder cho tab này.
- Lõi chuyển đổi Dương↔Âm (thuật toán Hồ Ngọc Đức), Can Chi năm, múi giờ +7.
- Panel lịch với 2 chế độ (toggle **Dương / Âm**), điều hướng tháng, nút "Hôm nay".
- Đánh dấu ngày lễ VN (dương cố định + âm cố định) bằng chấm + tên lễ.
- Unit test cho lõi âm lịch và bộ ngày lễ.

Ngoài phạm vi (YAGNI):
- Sự kiện cá nhân, nhắc nhở, thêm/sửa sự kiện.
- Can Chi cho tháng/ngày/giờ, giờ hoàng đạo (chỉ làm Can Chi **năm**).
- Đồng bộ nhiều năm ngày lễ đặc thù (chỉ dùng quy tắc cố định theo dương/âm).

## Kiến trúc & thành phần

### 1. `Core/VietnameseLunar.swift` (mới)
Bộ chuyển đổi thuần Swift, không phụ thuộc UI. Đơn vị độc lập, test được riêng.

Public API (struct/enum thuần giá trị):
```
struct LunarDate { let day, month, year: Int; let isLeapMonth: Bool }

enum VietnameseLunar {
    static let timeZoneOffset = 7.0   // giờ, cho múi giờ VN

    /// Đổi 1 ngày dương (y,m,d) sang âm.
    static func lunar(fromSolar y: Int, _ m: Int, _ d: Int) -> LunarDate

    /// Đổi 1 ngày âm sang dương (dùng để dựng lưới chế độ Âm).
    static func solar(fromLunar l: LunarDate) -> (y: Int, m: Int, d: Int)

    /// Số ngày trong 1 tháng âm (29 hoặc 30).
    static func daysInLunarMonth(month: Int, year: Int, isLeap: Bool) -> Int

    /// Can Chi của năm âm, ví dụ "Giáp Thìn".
    static func canChi(year: Int) -> String
}
```
Thuật toán: Julian day number ↔ ngày; `getNewMoonDay`, `getSunLongitude`,
`getLunarMonth11`, `getLeapMonthOffset` theo Hồ Ngọc Đức, `timeZone = 7`.

### 2. `Core/VietnameseHolidays.swift` (mới)
Bộ ngày lễ VN, tra bằng ngày dương và ngày âm. Trả về tên lễ (nếu có).

```
struct Holiday { let name: String; let isPublic: Bool }  // isPublic = nghỉ chính thức

enum VietnameseHolidays {
    /// Lễ theo ngày dương cố định.
    static func solarHoliday(month: Int, day: Int) -> Holiday?
    /// Lễ theo ngày âm cố định.
    static func lunarHoliday(month: Int, day: Int) -> Holiday?
    /// Gộp: cho 1 ngày dương cụ thể, trả mọi lễ (dương + âm) khớp.
    static func holidays(solarY: Int, solarM: Int, solarD: Int, lunar: LunarDate) -> [Holiday]
}
```

Dữ liệu ngày lễ:
- Dương cố định (isPublic=true): 1/1 Tết Dương lịch; 30/4 Giải phóng miền Nam;
  1/5 Quốc tế Lao động; 2/9 Quốc khánh.
- Âm cố định:
  - public: mùng 1,2,3/1 Tết Nguyên Đán; 10/3 Giỗ Tổ Hùng Vương.
  - lễ/tết truyền thống (isPublic=false): 15/1 Rằm tháng Giêng; 5/5 Tết Đoan Ngọ;
    15/7 Vu Lan; 15/8 Tết Trung Thu; 23/12 Ông Công Ông Táo; 30/12 (hoặc 29 nếu
    tháng thiếu) Giao thừa.
- Ngày lễ dương phổ biến không nghỉ (isPublic=false, tùy chọn hiển thị nhạt):
  14/2 Valentine, 8/3, 20/10, 20/11, 24–25/12. → Chốt: **có** đánh dấu nhưng ở
  mức phụ (chấm mờ, chỉ hiện tên khi chọn ngày).

### 3. UI — `CalendarPanel`
Đặt trong `UI/NotchRootView.swift` (hoặc tách `UI/CalendarPanel.swift` nếu file
gốc đã lớn — quyết định lúc code theo độ dài file).

State cục bộ trong `NotchRootView`:
- `@State private var calMode: CalMode = .solar`  (`enum CalMode { case solar, lunar }`)
- `@State private var calAnchor: Date = Date()`   (tháng đang xem, mốc là ngày 1)
- `@State private var calSelected: Date? = nil`   (ngày được chọn để hiện tên lễ)

Layout panel (từ trên xuống):
1. Hàng header: `‹`  |  tiêu đề tháng  |  `›`  |  toggle **Dương/Âm**  |  nút "Hôm nay".
   - Chế độ Dương: tiêu đề "Tháng 8, 2026".
   - Chế độ Âm: tiêu đề "Tháng 7 — Giáp Thìn" (Can Chi năm).
2. Hàng nhãn thứ: T2 T3 T4 T5 T6 T7 CN.
3. Lưới 7 cột × (5–6 hàng) các ô ngày.
4. Dòng chân: nếu `calSelected` (hoặc hôm nay) có lễ → hiện **mọi** tên lễ (cả âm
   lẫn dương, không phân biệt); nếu không thì hiện ngày âm/dương đối ứng của ngày
   được chọn.

Ô ngày (`DayCell`):
- **Chế độ Dương**: số dương to giữa ô; góc dưới-phải số âm nhỏ (ô mùng 1 âm →
  `1/M`). Ngày ngoài tháng hiện mờ.
- **Chế độ Âm**: số âm to giữa ô; góc dưới-phải ngày dương `d/M` nhỏ.
- Hôm nay: nền tròn/ago tô `alcoveRed`, chữ trắng.
- Ngày được chọn: viền mảnh.
- **Ngày lễ không phân biệt âm/dương**: mỗi ô đều biết cả ngày dương và ngày âm
  của nó, nên luôn tra `holidays(solarY,solarM,solarD, lunar:)` (gộp lễ dương +
  lễ âm). Ô có lễ public → chấm đỏ dưới số; chỉ lễ phụ → chấm mờ. Áp dụng **giống
  nhau ở cả 2 chế độ** Dương và Âm (một lễ âm như Trung Thu hiện đánh dấu ở cả
  lưới dương lẫn lưới âm, và ngược lại với lễ dương).
- Bấm ô → set `calSelected`.

Điều hướng:
- `‹` / `›`: lùi/tiến 1 tháng (dương hoặc âm tùy chế độ) trên `calAnchor`.
- "Hôm nay": `calAnchor = Date()`, `calSelected = nil`.
- Đổi toggle Dương↔Âm: giữ nguyên "tháng chứa ngày đang xem" hợp lý (đơn giản:
  reset về tháng chứa hôm nay khi đổi chế độ, hoặc giữ anchor — chốt: **giữ anchor
  theo ngày**, dựng lại lưới theo chế độ mới).

### 4. `NotchRootView.content`
Thêm `case .calendar: calendarPanel`. Bỏ nhánh placeholder cho clock (các tab
khác như `.files` vẫn dùng placeholder).

### 5. Kích thước panel (chiều cao)
Lưới lịch cao hơn player. Cần panel mở rộng cao khi ở tab Calendar.
- Thêm trong `NotchViewModel` cờ `@Published var tallExpanded = false` (hoặc tên
  rõ hơn `calendarActive`).
- `NotchRootView` set cờ này `onChange(of: railTab)` (true khi `.calendar`).
- `surfaceHeight` dùng chiều cao lớn (tái dùng `listExpandedHeight` ≈ 340, hoặc
  thêm hằng `calendarExpandedHeight`) khi cờ bật và `expanded`.

## Luồng dữ liệu

- Panel là view thuần, tự tính từ `Date()` và `calAnchor` qua `VietnameseLunar` +
  `VietnameseHolidays`. Không cần service, không timer, không quyền.
- "Hôm nay" xác định bằng `Calendar.current` so khớp y/m/d.

## Xử lý lỗi / biên

- Tháng âm thiếu (29 ngày) và tháng nhuận: lõi phải trả đúng `isLeapMonth` và số
  ngày; lưới chế độ Âm dựng theo `daysInLunarMonth`.
- Giao thừa: ngày cuối tháng Chạp (30 hoặc 29). Bộ holidays xử lý bằng "ngày cuối
  tháng 12 âm" chứ không cứng 30.
- Toàn bộ tính theo múi giờ +7 để không lệch ngày âm quanh nửa đêm.

## Kiểm thử (test)

`Tests/` (SwiftPM test target nếu đã có; nếu chưa, thêm target test tối thiểu):
- `VietnameseLunar`:
  - Tết Nguyên Đán các năm mốc (vd 2024-02-10 = mùng 1/1 âm; 2025-01-29;
    2026-02-17) → đúng (1,1,year).
  - Vài ngày thường đối chiếu giá trị đã biết.
  - Can Chi: 2024 → "Giáp Thìn"; 2025 → "Ất Tỵ".
  - Round-trip solar→lunar→solar khớp trên một dải ngày.
- `VietnameseHolidays`:
  - 30/4, 2/9 dương → có lễ public.
  - 10/3 âm → Giỗ Tổ; 15/8 âm → Trung Thu.

## Việc build lại app

Theo quy tắc dự án: sau khi code, build + chạy lại (`app/scripts/run_app.sh`),
mở tab Lịch, kiểm tra bằng mắt cả 2 chế độ + đánh dấu lễ trước khi báo hoàn thành.
