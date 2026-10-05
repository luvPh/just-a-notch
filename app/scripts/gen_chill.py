"""Cảnh "Clawd chill" cho phần giữa pill — bản NHÁP để duyệt (chưa ghi vào Swift).

Chạy:  python3 app/scripts/gen_chill.py <thư-mục-xem-trước>
Ra:    <dir>/<cảnh>.gif (phóng to) + <dir>/chill-pill.gif (đặt trong pill như thật).

Mỗi cảnh là lưới 44×15 ô vuông (cùng tỉ lệ Clawd trong gen_sprites.py: 1 hàng logo
= 2 hàng lưới), có nền đầy đủ; Clawd dùng lại `clawd_frame`.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_sprites import Grid, clawd_frame, PALETTES  # noqa: E402

W, H = 44, 15
FPS = 8

PAL = dict(PALETTES["Clawd"])
PAL.update({
    "N": (0.06, 0.08, 0.17), "n": (0.10, 0.12, 0.24),       # trời đêm (đậm / nhạt)
    "U": (0.22, 0.14, 0.30), "u": (0.50, 0.24, 0.32),       # hoàng hôn (tím / hồng)
    "e": (0.86, 0.46, 0.30),                                 # vệt nắng chân trời
    "S": (1.00, 0.97, 0.82), "s": (0.55, 0.58, 0.72),       # sao sáng / mờ
    "M": (0.98, 0.94, 0.75),                                 # trăng
    "G": (0.16, 0.30, 0.20), "j": (0.22, 0.40, 0.26),       # cỏ
    "W": (0.40, 0.26, 0.17), "x": (0.28, 0.18, 0.12),       # gỗ (sàn / bóng)
    "A": (0.10, 0.24, 0.42), "a": (0.32, 0.56, 0.80),       # nước / gợn
    "X": (0.30, 0.30, 0.38),                                 # khung cửa sổ
    "L": (1.00, 0.86, 0.52), "l": (0.13, 0.12, 0.20),       # đèn / quầng sáng
    "B": (0.32, 0.46, 0.86), "p": (0.96, 0.94, 0.86),       # bìa sách / trang giấy
    "R": (0.58, 0.42, 0.26), "r": (0.78, 0.80, 0.86),       # cần câu / dây
    "F": (1.00, 0.62, 0.26),                                 # cá
    "C": (0.94, 0.94, 0.96), "c": (0.42, 0.26, 0.16),       # cốc / cà phê
    "T": (0.72, 0.74, 0.80),                                 # hơi nước
    "D": (0.45, 0.66, 0.95),                                 # giọt mưa
    "Z": (0.82, 0.86, 1.00),                                 # chữ z
    "f": (1.00, 0.55, 0.20), "Q": (1.00, 0.85, 0.35), "i": (0.85, 0.25, 0.15),  # lửa
})


def blit(g, rows, ox, oy=0):
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != ".":
                g.put(ox + x, oy + y, ch)


def fill(g, ch, y0=0, y1=H):
    for y in range(y0, y1):
        for x in range(W):
            g.put(x, y, ch)


def stars(g, t, pts, seed=0):
    for i, (x, y) in enumerate(pts):
        tw = (t // 3 + i * 5 + seed) % 11
        g.put(x, y, "s" if tw in (0, 1) else "S")


STAR_PTS = [(2, 1), (7, 3), (12, 0), (20, 2), (26, 1), (31, 4), (37, 1), (41, 3), (16, 5), (34, 0)]


# 1) Đọc sách bên đèn ngủ — lật trang mỗi ~3s.
def reading():
    out = []
    for t in range(48):
        g = Grid(W, H)
        fill(g, "N")
        # cửa sổ có trăng
        for x in range(2, 11):
            g.put(x, 1, "X"); g.put(x, 8, "X")
        for y in range(1, 9):
            g.put(2, y, "X"); g.put(10, y, "X"); g.put(6, y, "X")
        for y in range(2, 8):
            for x in (3, 4, 5, 7, 8, 9):
                g.put(x, y, "n")
        g.put(8, 3, "M"); g.put(9, 3, "M"); g.put(8, 4, "M"); g.put(4, 5, "S")
        # đèn cây bên phải + quầng sáng
        g.ellipse(38, 6.5, 5, 4.5, "l")   # quầng sáng rất nhẹ quanh chụp đèn
        for y in range(5, 14):
            g.put(38, y, "x")
        for x in range(35, 42):
            g.put(x, 4, "L")
        for x in range(36, 41):
            g.put(x, 3, "L")
        fill(g, "W", 14, 15)
        cl = clawd_frame(eyes="down", crouch=True, arms="none")
        blit(g, cl, 14)
        # sách mở trước thân, hai tay giữ
        bx, by = 14 + 5, 9
        for x in range(bx, bx + 8):
            g.put(x, by + 2, "B")
            g.put(x, by, "p"); g.put(x, by + 1, "p")
        g.put(bx + 4, by, "q"); g.put(bx + 4, by + 1, "q")       # gáy sách
        g.put(bx - 1, by + 1, "O"); g.put(bx + 8, by + 1, "O")    # tay
        # lật trang: 6 khung cuối mỗi vòng, trang chạy phải → trái
        k = t % 24
        if k >= 18:
            px = bx + 7 - (k - 18)
            g.put(px, by - 1, "p"); g.put(px, by, "C")
        out.append(g.rows())
    return out


# 2) Ngủ dưới trời sao — thở phập phồng, "z" bay lên.
def sleeping():
    out = []
    for t in range(48):
        g = Grid(W, H)
        fill(g, "N")
        stars(g, t, STAR_PTS)
        g.ellipse(39, 3, 2.2, 2.2, "M")
        g.ellipse(40, 2.6, 1.6, 1.6, "N")            # trăng khuyết
        fill(g, "G", 14, 15)
        for x in range(0, W, 3):
            g.put(x, 13, "j")
        breathe = (t // 8) % 2 == 0
        cl = clawd_frame(eyes="closed", crouch=breathe, arms="side")
        blit(g, cl, 12, 1)
        # z bay lên chéo phải, 3 chữ lệch pha
        for i in range(3):
            ph = (t + i * 16) % 48
            zx, zy = 30 + ph // 8, 9 - ph // 6
            if 0 <= zy < H:
                # chữ Z 3×3: gạch trên, chéo giữa, gạch dưới (nhỏ dần khi bay xa)
                if ph < 32:
                    for dx in range(3):
                        g.put(zx + dx, zy - 2, "Z"); g.put(zx + dx, zy, "Z")
                    g.put(zx + 1, zy - 1, "Z")
                else:
                    g.put(zx, zy, "Z"); g.put(zx + 1, zy, "Z")
        out.append(g.rows())
    return out


# 3) Câu cá lúc hoàng hôn — phao nhấp nhô, thỉnh thoảng cá nhảy.
def fishing():
    out = []
    for t in range(64):
        g = Grid(W, H)
        fill(g, "U", 0, 5); fill(g, "u", 5, 8); fill(g, "e", 8, 9)
        g.ellipse(30, 8.6, 3.2, 2.4, "L", only=lambda x, y: y < 9)   # mặt trời lặn
        fill(g, "A", 9, 15)
        for i, x in enumerate(range(16, W, 5)):                       # gợn nước trôi
            xx = (x + t // 2) % W
            g.put(xx, 10 + i % 3 * 2, "a"); g.put((xx + 1) % W, 10 + i % 3 * 2, "a")
        for x in range(0, 15):                                        # cầu gỗ
            g.put(x, 11, "W"); g.put(x, 12, "x")
        for x in (2, 11):
            for y in range(13, 15):
                g.put(x, y, "x")
        cl = clawd_frame(arms="upR", crouch=True)
        blit(g, cl, 0, -3)
        # cần câu từ tay phải lên phải + dây xuống phao
        rod = [(17, 2), (21, 1), (25, 0), (29, 0)]
        for (ax, ay), (bx2, by2) in zip(rod, rod[1:]):
            n = max(abs(bx2 - ax), abs(by2 - ay))
            for s in range(n + 1):
                g.put(round(ax + (bx2 - ax) * s / n), round(ay + (by2 - ay) * s / n), "R")
        bob = 10 if (t // 6) % 2 == 0 else 11
        for y in range(1, bob - 1):
            g.put(29, y, "r")
        g.put(29, bob, "i"); g.put(29, bob - 1, "C")
        # cá nhảy vòng cung ở khung 40..52
        if 40 <= t < 52:
            k = t - 40
            fx, fy = 34 + k // 2, 10 - round(3 * math.sin(math.pi * k / 12))
            g.put(fx, fy, "F"); g.put(fx + 1, fy, "F"); g.put(fx - 1, fy + 1, "F")
        out.append(g.rows())
    return out


# 4) Cà phê ngày mưa — mưa rơi ngoài cửa, hơi nước bốc lên, chớp mắt.
def coffee():
    rnd = random.Random(3)
    drops = [(rnd.randrange(W), rnd.randrange(H)) for _ in range(14)]
    out = []
    for t in range(48):
        g = Grid(W, H)
        fill(g, "n")
        for (x, y) in drops:
            yy = (y + t) % 12
            xx = (x - t // 2) % W
            g.put(xx, yy, "D")
        for x in range(W):                                            # khung cửa sổ
            g.put(x, 0, "X")
        for y in range(H):
            g.put(0, y, "X"); g.put(W - 1, y, "X"); g.put(22, y, "X")
        fill(g, "W", 12, 15)                                           # mặt bàn
        for x in range(W):
            g.put(x, 12, "R")
        blink = t % 24 in (20, 21)
        cl = clawd_frame(eyes="closed" if blink else "open", crouch=True)
        blit(g, cl, 6, -2)
        # cốc + hơi nước uốn lượn
        cx = 28
        for y in range(8, 12):
            for x in range(cx, cx + 5):
                g.put(x, y, "C")
        for x in range(cx + 1, cx + 4):
            g.put(x, 8, "c")
        g.put(cx + 5, 9, "C"); g.put(cx + 6, 10, "C"); g.put(cx + 5, 11, "C")
        for i in range(2):
            ph = (t + i * 12) % 24
            sy = 7 - ph // 4
            sx = cx + 1 + i * 2 + (1 if (ph // 3) % 2 else 0)
            if sy >= 1:
                g.put(sx, sy, "T")
        out.append(g.rows())
    return out


# 5) Lửa trại dưới trời sao — lửa bập bùng, tàn lửa bay.
def campfire():
    out = []
    for t in range(48):
        g = Grid(W, H)
        fill(g, "N")
        stars(g, t, STAR_PTS, seed=4)
        # đồi xa
        g.ellipse(8, 15, 14, 5, "n"); g.ellipse(36, 16, 16, 6, "n")
        fill(g, "G", 14, 15)
        cl = clawd_frame(eyes="open", crouch=True, arms="side")
        blit(g, cl, 4, 0)
        # củi + lửa
        fx = 31
        for x in range(fx - 3, fx + 4):
            g.put(x, 13, "W")
        g.put(fx - 3, 12, "x"); g.put(fx + 3, 12, "x")
        h = 4 + (t % 3 == 0) - (t % 5 == 0)
        for y in range(h):
            half = max(0, 2 - y // 2) + (1 if y == 0 else 0)
            for x in range(fx - half, fx + half + 1):
                ch = "i" if y == 0 else ("f" if y < h - 1 else "Q")
                g.put(x + (1 if (t + y) % 4 == 0 and y > 1 else 0), 12 - y, ch)
        g.put(fx, 11, "Q"); g.put(fx, 10, "Q")
        # tàn lửa bay lên
        for i in range(3):
            ph = (t + i * 11) % 22
            g.put(fx - 1 + (i + ph // 4) % 3, 7 - ph // 3, "Q" if ph < 10 else "f")
        out.append(g.rows())
    return out


SCENES = [("doc-sach", "Đọc sách", reading), ("ngu", "Ngủ", sleeping), ("cau-ca", "Câu cá", fishing),
          ("ca-phe", "Cà phê ngày mưa", coffee), ("lua-trai", "Lửa trại", campfire)]


def render(frame, px):
    from PIL import Image
    im = Image.new("RGB", (W * px, H * px))
    d = im.load()
    for y, row in enumerate(frame):
        for x, ch in enumerate(row):
            r, g, b = PAL.get(ch, (0, 0, 0))
            for yy in range(px):
                for xx in range(px):
                    d[x * px + xx, y * px + yy] = (int(r * 255), int(g * 255), int(b * 255))
    return im


def pill(frame, px):
    """Đặt cảnh vào pill đen như trên thanh menu (icon nhạc trái, sóng nhạc phải)."""
    from PIL import Image, ImageDraw
    pad = 26 * px // 2
    pw, ph = W * px + 2 * pad + 40 * px, H * px + 6 * px
    im = Image.new("RGB", (pw + 40, ph + 40), (232, 228, 220))
    dr = ImageDraw.Draw(im)
    dr.rounded_rectangle((20, 20, 20 + pw, 20 + ph), radius=ph // 2, fill=(0, 0, 0))
    dr.rounded_rectangle((20 + 6 * px, 20 + ph // 2 - 5 * px, 20 + 16 * px, 20 + ph // 2 + 5 * px), 2 * px,
                         fill=(230, 50, 45))
    for i, hh in enumerate((3, 6, 4, 7, 3)):
        x = 20 + pw - 16 * px + i * 2 * px
        dr.rectangle((x, 20 + ph // 2 - hh * px // 2, x + px, 20 + ph // 2 + hh * px // 2), fill=(240, 90, 80))
    sc = render(frame, px)
    mask = Image.new("L", sc.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sc.size[0] - 1, sc.size[1] - 1), radius=3 * px, fill=255)
    im.paste(sc, (20 + (pw - sc.size[0]) // 2, 20 + 3 * px), mask)
    return im


if __name__ == "__main__":
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    pills = []
    for slug, _, fn in SCENES:
        frames = fn()
        ims = [render(f, 12) for f in frames]
        ims[0].save(os.path.join(d, f"{slug}.gif"), save_all=True, append_images=ims[1:],
                    duration=1000 // FPS, loop=0)
        pills.append([pill(f, 4) for f in frames])
        print(slug, len(frames), "frames")
    # Một GIF dài: lần lượt 5 cảnh trong pill (mỗi cảnh 2 vòng).
    seq = [im for p in pills for im in p + p]
    seq[0].save(os.path.join(d, "chill-pill.gif"), save_all=True, append_images=seq[1:],
                duration=1000 // FPS, loop=0)
