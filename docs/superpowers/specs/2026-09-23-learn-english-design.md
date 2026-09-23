# Learn — học tiếng Anh trên notch (design)

Tham khảo mô hình EngZone (`~/Documents/repo/EngZone`) nhưng chạy **độc lập**, dữ liệu **local**.

## Mục tiêu
- Tab **Learn** gọn trên notch + **cửa sổ học riêng** (NSWindow thường) cho học sâu.
- Cứ **30 phút** notch tự bung 1 lượt: ưu tiên sense **đến hạn** (SRS), rồi tới **sense mới**; ~1/3 lượt là **quiz 4 đáp án**.
- Kho từ = **seed đóng gói** (B1–C2) + **AI bổ sung dần** (Claude CLI).
- Cửa sổ học gồm Ôn tập, Kho từ, **Essay**, **Grammar**, Thống kê.

## Mô hình mục từ (kiểu từ điển Cambridge + tiếng Việt)
```
Word    { id, headword, pos, ipaUK, ipaUS, senses[], source: seed|ai, addedAt }
Sense   { id, guideword ("VERY GREAT"), level (A2…C2), defEN, defVI, examples[] }
Example { en, vi }
```
Nội dung seed do Claude tự viết — chỉ mượn **cách trình bày**, không chép định nghĩa từ điển.

## SRS
- Đơn vị ôn = **sense** (`SenseKey = wordId#senseId`).
- `ReviewState { ease=2.5, intervalDays, reps, lapses, due, lastReviewed }`.
- Thuật toán SM-2 rút gọn với 4 mức: again / hard / good / easy. Quiz đúng = good, sai = again.
- Sense mới chưa có state; khi "học" lần đầu mới tạo state.

## Lưu trữ
`~/Library/Application Support/Just a Notch/Learn/`
- `words_ai.json` — từ AI thêm. Seed đọc từ bundle `Resources/Learn/words_seed.json` (không copy).
- `reviews.json` — `[SenseKey: ReviewState]`.
- `stats.json` — streak, số lượt ôn theo ngày.
- (bước sau) `essays.json`, `grammar.json`.

## Notch
- Tab Learn: số sense đến hạn, streak, 1 thẻ ôn nhanh (lật → 4 nút SRS), nút "Mở cửa sổ học".
- Auto-popup 30' (bật/tắt, chỉnh phút trong Settings); bỏ qua lượt nếu notch đang mở/đang có hoạt động.

## Essay (theo EngZone)
Essay theo chủ đề + độ khó 1–5 (tối thiểu 100/200/300/400/500 từ, văn phong tự nhiên) → bấm từ tra nghĩa theo ngữ cảnh → vocab list (word/pos/ipa/short/meaning/example, xoá từ đã biết, vào SRS) → word family (mindmap + luyện) → bài luyện: vocab, nghe-chép (TTS), dịch câu, đọc to (SFSpeechRecognizer), có Bỏ qua.

## Grammar
Logic-first 6 phần: one-line answer · tại sao · đối chiếu tiếng Việt · ví dụ · lỗi người Việt · quick check. Thư viện chủ đề + ô hỏi thêm.

## AI
`ClaudeCLIService` gọi `claude -p` với prompt trả JSON (chuyển thể từ `english-master`). Không có CLI → vẫn học được bằng seed.

## Lộ trình
1. Core (Word/Sense, SRS, LearnStore, seed ~300 từ) + tab Learn.
2. Auto-popup 30' + quiz.
3. Cửa sổ học: Ôn tập + Kho từ + chi tiết mục từ.
4. Claude CLI gen từ; bơm seed ~3000 từ.
5. Essay (bài, tra từ, vocab, family).
6. Bài luyện essay.
7. Grammar.
