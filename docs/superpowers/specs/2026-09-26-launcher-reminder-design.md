# Launcher hover + Máy tính/đổi tiền + Nhắc đứng dậy/uống nước

Ngày: 2026-09-26 · Trạng thái: đã duyệt qua trao đổi, triển khai luôn.

## 1. Launcher khi hover lâu
- Hover notch (đang thu) ≥ 0.75s → dưới notch thả ra dải icon (cao 40pt). Có hay không
  có media đều hiện. Không hiện khi: panel mở, HUD đang hiện, shelf đang bung, đang kéo file,
  đang hiện lời nhắc.
- Danh sách tính năng khai báo tập trung ở `LauncherFeature` (enum, CaseIterable) —
  thêm tính năng = thêm 1 case. Bản đầu: `.calculator`.
- Bấm icon → dải chuyển thành màn tính năng (kích thước riêng mỗi tính năng), có nút ←.
- Chỉ đang xem hàng icon + chuột rời notch → thu ngay. Đang trong tính năng → giữ mở tới
  khi bấm ra ngoài / Esc / 20s không hover.
- Bấm vùng trống của dải icon → mở panel lớn như cũ (và đóng launcher).

## 2. Điều khiển nhạc
- Hover KHÔNG còn tự hiện ◀ ⏯ ▶.
- Bấm soundwave (hoặc badge đếm ngược cùng vị trí) → morph thành ◀ ⏯ ▶ (hiệu ứng cũ).
  Chuột rời notch → thu về soundwave.
- Icon nguồn (wing trái) vẫn mở app/tab nguồn. Vùng bấm ~30×30, hover: phóng 1.15 spring,
  quầng sáng màu nguồn, badge ↗, con trỏ bàn tay, nhấn lún. Thu hẹp ShelfDropCatcher để
  nó không che mất một phần icon.

## 3. Máy tính & đổi tiền (`QuickCalc`)
- Ô nhập tự focus, kết quả live. `+ − × ÷ x * / : ( ) % ^`, hậu tố `k`, `tr`/`m`/`triệu`,
  `ty`/`tỷ`/`b`. Số kiểu VN: `1.000.000`, `2,5`; một dấu phân cách + đúng 3 chữ số và phần
  nguyên ≠ 0 ⇒ phân cách nghìn.
- Tiền: mã 3 chữ (theo bảng tỷ giá) hoặc `$ € £ ¥ ₫ đ vnd`. `100usd` → VND; `5tr to usd`
  (`to`/`in`/`sang`/`->`/`=`) → USD. Không ghi đích: khác VND → VND, VND → USD.
  Cộng/trừ khác tiền → quy về tiền đầu tiên.
- Tỷ giá: open.er-api.com (USD base), cache `~/Library/Application Support/JustANotch/rates.json`,
  làm mới khi cũ > 6h. Offline dùng cache; chưa có cache → báo "Chưa có tỷ giá".
- Hiển thị kiểu VN (`2.634.000 ₫`). Enter → copy số, nháy "Đã copy ✓". Esc/← → về hàng icon.
- Không làm: đổi đơn vị, lịch sử.

## 4. Nhắc đứng dậy + uống nước (thụ động)
- Mốc: mỗi 30' trong 9:00–12:00 và 13:00–18:00, bỏ 9:00/12:00/13:00/18:00 ⇒
  9:30…11:30, 13:30…17:30. Thứ 2–6, bỏ ngày lễ nghỉ chính thức (`VietnameseHolidays`, isPublic).
- Hiện ở dạng wing (không bung panel) ~6s: wing trái bé mèo pixel (đứng dậy → vươn vai →
  uống nước, 8fps, vẽ bằng Canvas), wing phải chữ "Đứng dậy nào / uống ngụm nước". Bấm để tắt.
  Âm "ting" riêng (tổng hợp, khác LearnChime). Full màn hình → không kêu. Reduce Motion → khung tĩnh.
- Bỏ lượt nếu máy khoá màn hình / không có input > 5'. Hạn hiển thị mỗi mốc 5': notch đang
  bận (panel mở, popup Learn, HUD, shelf, launcher) thì chờ; quá 5' thì bỏ.
- Learn không bung khi lời nhắc đang hiện (thử lại lượt sau).
- Settings: bật/tắt + âm lượng (+ nghe thử).

## Kiểm thử
- Unit test: `QuickCalc` (số VN, hậu tố, ưu tiên toán tử, tiền tệ), `BreakSchedule`
  (mốc, cuối tuần, lễ, cửa sổ 5').
- Chạy app, kiểm tra bằng mắt: hover → launcher, bấm soundwave, máy tính, lời nhắc (nút test).
