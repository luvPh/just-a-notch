# just-a-notch — Quy tắc làm việc

Các quy tắc dưới đây được đọc lại ở **mỗi session mới**. Luôn tuân thủ:

## 1. Commit khi người dùng xác nhận tính năng đã OK
- Khi người dùng xác nhận (nói "oke", "ổn", "được rồi", "ok rồi"...) rằng một tính năng
  hoạt động đúng như mong muốn, hãy **commit ngay** thay đổi đó.
- Viết commit message ngắn gọn, mô tả rõ tính năng vừa hoàn thành.
- Không tự commit trước khi người dùng xác nhận. Chỉ commit sau khi có xác nhận.

## 2. Luôn chạy lại app sau mỗi lần sửa
- Sau **mỗi lần sửa code**, hãy build và chạy lại app để kiểm tra thay đổi có hoạt động không.
- Không tuyên bố "đã xong" khi chưa chạy lại app và xác nhận bằng mắt.
- Nếu build/chạy lỗi, sửa cho đến khi chạy được rồi mới báo người dùng kiểm tra.
- **Đã tự động hoá:** Stop hook trong `.claude/settings.json` tự chạy
  `app/scripts/run_app.sh` (build debug + relaunch) sau mỗi lượt làm việc. Nếu
  build lỗi, hook sẽ tự đánh thức Claude để sửa.
