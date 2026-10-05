"""Cảnh "Clawd chill" độ nét Retina — bản NHÁP để duyệt.

Chạy:  python3 app/scripts/gen_chill_hd.py <thư-mục>
Vẽ ở 88×30 điểm ảnh thật (= 44×15pt @2x), siêu lấy mẫu ×4 rồi thu nhỏ → nét mịn,
khử răng cưa. Ra: <slug>.gif (phóng ×6) và chill-pill.gif (đặt trong pill, @2x).
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 88, 30          # điểm ảnh thật @2x
SS = 4                 # siêu lấy mẫu
OUT_W, OUT_H = 114, 39 # điểm ảnh xuất ra (pill thu 75% → ~57×19.5pt @2x)
FPS = 12
CLAY = (217, 119, 87)
CLAY_HI = (236, 150, 118)
CLAY_LO = (178, 88, 62)
EYE = (34, 20, 16)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


class Scene:
    def __init__(self):
        self.im = Image.new("RGB", (W * SS, H * SS))
        self.d = ImageDraw.Draw(self.im, "RGBA")

    def S(self, *v):
        return [x * SS for x in v]

    def vgrad(self, top, bottom, y0=0, y1=H):
        for y in range(y0 * SS, y1 * SS):
            t = (y - y0 * SS) / max(1, (y1 - y0) * SS - 1)
            self.d.line([(0, y), (W * SS, y)], fill=lerp(top, bottom, t))

    def rect(self, x0, y0, x1, y1, c, r=0):
        self.d.rounded_rectangle(self.S(x0, y0, x1, y1), radius=r * SS, fill=c)

    def ell(self, cx, cy, rx, ry, c):
        self.d.ellipse(self.S(cx - rx, cy - ry, cx + rx, cy + ry), fill=c)

    def line(self, pts, c, w=1.0):
        self.d.line([(x * SS, y * SS) for x, y in pts], fill=c, width=max(1, int(w * SS)), joint="curve")

    def glow(self, cx, cy, r, c, a=70):
        layer = Image.new("RGBA", self.im.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse(self.S(cx - r, cy - r, cx + r, cy + r), fill=c + (a,))
        layer = layer.filter(ImageFilter.GaussianBlur(r * SS * 0.45))
        self.im.paste(layer, (0, 0), layer)
        self.d = ImageDraw.Draw(self.im, "RGBA")

    def clawd(self, x, y, s=1.0, eyes="open", arms="side", squash=0.0, look=0.0, step=None, legs=True):
        """Clawd mịn: thân bo góc có highlight + bóng, mắt khe, tay ngang, 4 chân.
        (x, y) = góc trên-trái thân; s = tỉ lệ (1 → thân 20×12)."""
        bw, bh = 20 * s, (12 - squash) * s
        y = y + squash * s
        # bóng đổ dưới chân
        self.ell(x + bw / 2, y + bh + 4.6 * s, bw * 0.55, 1.1 * s, (0, 0, 0, 70))
        # chân
        for i, lx in enumerate((2.5, 6, 12.5, 16)):
            if not legs:
                break
            # step = 0/1: nhấc cặp chân xen kẽ khi đi
            up = 1.2 * s if step is not None and (i % 2) == step else 0
            self.rect(x + lx * s, y + bh - 1, x + (lx + 2) * s, y + bh + 4 * s - up, CLAY_LO, 0.6 * s)
        # tay
        if arms in ("side", "upR"):
            ay = y + bh * 0.48
            self.rect(x - 3 * s, ay, x + 1, ay + 2.6 * s, CLAY, 1 * s)
            if arms == "upR":
                self.line([(x + bw - 1, ay + 1), (x + bw + 3 * s, ay - 3 * s)], CLAY, 2.6 * s)
            else:
                self.rect(x + bw - 1, ay, x + bw + 3 * s, ay + 2.6 * s, CLAY, 1 * s)
        # thân + highlight + bóng dưới
        self.rect(x, y, x + bw, y + bh, CLAY, 2.2 * s)
        self.rect(x + 1.2 * s, y + 0.8 * s, x + bw - 1.2 * s, y + 3 * s, CLAY_HI + (160,), 1.4 * s)
        self.rect(x + 1 * s, y + bh - 2.4 * s, x + bw - 1 * s, y + bh - 0.4 * s, CLAY_LO + (150,), 1.2 * s)
        # mắt
        for ex in (5.5, 13.5):
            cx, cy = x + ex * s + look * s, y + bh * 0.42
            if eyes == "open":
                self.rect(cx, cy - 1.6 * s, cx + 1.6 * s, cy + 1.6 * s, EYE, 0.8 * s)
                self.ell(cx + 1.1 * s, cy - 0.8 * s, 0.35 * s, 0.35 * s, (255, 255, 255, 200))
            elif eyes == "down":
                self.rect(cx, cy, cx + 1.6 * s, cy + 1.6 * s, EYE, 0.8 * s)
            else:  # nhắm: vòng cung
                self.d.arc(self.S(cx - 0.4 * s, cy - 1 * s, cx + 2 * s, cy + 1.2 * s), 20, 160,
                           fill=EYE, width=max(1, int(0.7 * s * SS)))

    def out(self):
        return self.im.resize((OUT_W, OUT_H), Image.LANCZOS)


rnd = random.Random(7)
STARS = [(rnd.uniform(0, W), rnd.uniform(0, 13), rnd.uniform(0.25, 0.6), rnd.random()) for _ in range(26)]


def stars(sc, t, ymax=14):
    for x, y, r, ph in STARS:
        if y > ymax:
            continue
        a = int(120 + 135 * (0.5 + 0.5 * math.sin(t / FPS * 2.2 + ph * 6.28)))
        sc.ell(x, y, r, r, (255, 248, 220, a))


NIGHT = ((10, 13, 32), (24, 28, 58))


# 1) Ngồi bàn đọc sách — đèn bàn, sách mở trên bàn, lật trang.
def reading(t):
    sc = Scene()
    sc.vgrad((22, 20, 34), (38, 32, 48))
    sc.rect(4, 3, 22, 17, (52, 54, 74), 1.2)                   # cửa sổ
    sc.d.rectangle(sc.S(5.2, 4.2, 20.8, 15.8), fill=(14, 20, 44))
    for x, y, r, ph in STARS[:6]:
        sc.ell(6 + x % 14, 5 + y % 10, 0.4, 0.4, (255, 248, 220, 200))
    sc.ell(16.5, 7.5, 2.3, 2.3, (250, 240, 200))
    sc.line([(13, 4.2), (13, 15.8)], (52, 54, 74), 1)
    for i, c in enumerate(((150, 70, 60), (70, 110, 160), (200, 160, 80), (90, 140, 100))):   # kệ sách
        sc.rect(68 + i * 3.2, 4 + (i % 2), 70.6 + i * 3.2, 11, c, 0.4)
    sc.rect(66, 11, 84, 12, (90, 62, 44))
    sc.glow(56, 13, 13, (255, 200, 120), 75)                  # đèn bàn
    sc.clawd(30, 6.5, eyes="down", arms="none")
    # bàn che nửa dưới thân
    sc.rect(18, 19, 70, 21, (130, 88, 58), 0.6)
    sc.vgrad((96, 64, 42), (70, 46, 30), 21, 30)
    sc.line([(56, 19), (58, 13), (54, 10)], (60, 60, 70), 0.8)  # cần đèn
    sc.d.polygon([(x * SS, y * SS) for x, y in [(51, 10.5), (57, 9), (56.5, 12.5), (52, 13)]], fill=(255, 214, 140))
    # sách mở nằm trên bàn, hai tay đặt lên
    sc.d.polygon([(x * SS, y * SS) for x, y in [(31, 19), (40, 17.4), (49, 19)]], fill=(70, 98, 190))
    sc.d.polygon([(x * SS, y * SS) for x, y in [(32, 18.8), (40, 17), (40, 19), (32, 19.4)]], fill=(246, 240, 224))
    sc.d.polygon([(x * SS, y * SS) for x, y in [(40, 17), (48, 18.8), (48, 19.4), (40, 19)]], fill=(236, 228, 210))
    sc.rect(28, 17.6, 32, 19.4, CLAY, 0.8); sc.rect(48, 17.6, 52, 19.4, CLAY, 0.8)
    k = (t % 36) / 36
    if k > 0.72:                                              # trang lật
        q = (k - 0.72) / 0.28
        px = 48 - 16 * q
        sc.d.polygon([(x * SS, y * SS) for x, y in [(40, 17), (px, 17.6 - 3 * math.sin(q * math.pi)), (px, 18.9)]],
                     fill=(252, 248, 236))
    return sc.out()


# 2) Ngủ trong phòng — đắp chăn trên giường, trăng ngoài cửa, thở đều, zZz.
def sleeping(t):
    sc = Scene()
    sc.vgrad((16, 16, 34), (28, 26, 46))
    sc.rect(52, 3, 74, 17, (52, 54, 74), 1.2)                  # cửa sổ có trăng
    sc.d.rectangle(sc.S(53.2, 4.2, 72.8, 15.8), fill=(12, 18, 42))
    for x, y, r, ph in STARS[:7]:
        a = int(140 + 110 * math.sin(t / FPS * 2 + ph * 6))
        sc.ell(54 + x % 18, 5 + y % 10, 0.4, 0.4, (255, 248, 220, a))
    sc.glow(67, 8, 6, (220, 220, 255), 40)
    sc.ell(67, 8, 3, 3, (246, 240, 210)); sc.ell(68.4, 7, 2.6, 2.6, (12, 18, 42))
    sc.line([(63, 4.2), (63, 15.8)], (52, 54, 74), 1)
    sc.vgrad((60, 44, 40), (44, 32, 30), 26, 30)               # sàn
    # giường
    sc.rect(6, 6, 9, 26, (120, 80, 56), 0.6)                   # đầu giường
    sc.rect(6, 18, 50, 24, (130, 88, 60), 0.8)
    sc.rect(10, 13, 20, 18.5, (236, 236, 244), 2)              # gối
    breathe = 0.5 + 0.5 * math.sin(t / FPS * 2 * math.pi / 3.2)
    sc.clawd(12, 8 + 0.5 * breathe, s=0.8, eyes="closed", arms="none", legs=False)
    # chăn phủ thân, phập phồng theo nhịp thở
    top = 14.5 - 0.6 * breathe
    sc.d.rounded_rectangle(sc.S(14, top, 49, 20.5), radius=3 * SS, fill=(86, 112, 196))
    for i in range(4):
        sc.line([(20 + i * 7, top + 1), (22 + i * 7, 20)], (70, 94, 172), 0.6)
    sc.rect(14, top, 49, top + 1.4, (120, 146, 220), 0.7)
    for i in range(3):                                         # zZz
        ph = ((t / FPS) + i * 1.1) % 3.3 / 3.3
        zx, zy = 28 + ph * 12, 9 - ph * 8
        sz = 1.3 + ph * 1.6
        sc.line([(zx, zy), (zx + sz, zy), (zx, zy + sz), (zx + sz, zy + sz)], (210, 220, 255, int(255 * (1 - ph))), 0.6)
    return sc.out()


# 3) Câu cá hoàng hôn
def fishing(t):
    sc = Scene()
    sc.vgrad((60, 36, 90), (232, 120, 96), 0, 17)
    sc.glow(62, 16, 10, (255, 190, 110), 90)
    sc.ell(62, 17, 5, 5, (255, 214, 130))
    sc.vgrad((42, 70, 120), (20, 34, 70), 17, 30)
    sc.d.rectangle(sc.S(0, 17, W, 17.6), fill=(255, 190, 130, 120))
    for i in range(7):                                          # vệt sáng mặt trời trên nước
        y = 19 + i * 1.6
        w = 6 - i * 0.6
        off = math.sin(t / FPS * 3 + i) * 1.2
        sc.rect(62 - w + off, y, 62 + w + off, y + 0.6, (255, 200, 140, 150 - i * 18), 0.3)
    for i in range(5):                                          # gợn nước trôi
        x = (i * 19 + t * 0.8) % (W + 10) - 5
        sc.rect(x, 22 + (i % 3) * 2.4, x + 4, 22.5 + (i % 3) * 2.4, (120, 160, 210, 120), 0.3)
    # cầu gỗ
    sc.rect(-2, 21, 30, 23.5, (96, 64, 44), 0.6)
    for x in (4, 22):
        sc.rect(x, 23, x + 2, 30, (70, 46, 32))
    sc.clawd(5, 5.5, arms="upR", look=0.6)
    # cần + dây + phao
    sc.line([(28, 8), (40, 2.5), (52, 1)], (120, 84, 52), 0.9)
    bob = 20 + 0.8 * math.sin(t / FPS * 4)
    sc.line([(52, 1), (52.4, bob - 1)], (230, 230, 240, 200), 0.35)
    sc.ell(52.4, bob, 1.1, 1.1, (240, 70, 60)); sc.ell(52.4, bob - 0.7, 1.1, 0.6, (250, 250, 250))
    # cá nhảy
    k = (t % (FPS * 6)) / FPS
    if 3.5 < k < 4.5:
        p = k - 3.5
        fx, fy = 66 + p * 10, 21 - 7 * math.sin(math.pi * p)
        sc.ell(fx, fy, 1.8, 0.9, (255, 150, 70))
        sc.d.polygon([(x * SS, y * SS) for x, y in [(fx - 1.6, fy), (fx - 3, fy - 1), (fx - 3, fy + 1)]], fill=(255, 150, 70))
    return sc.out()


# 4) Cà phê ngày mưa
RAIN = [(rnd.uniform(0, W), rnd.uniform(0, 30), rnd.uniform(0.6, 1.0)) for _ in range(34)]


# 4) Ngày mưa — đi qua đi lại bên cửa sổ, cốc cà phê bốc hơi trên bàn.
RAIN = [(rnd.uniform(0, W), rnd.uniform(0, 30), rnd.uniform(0.6, 1.0)) for _ in range(34)]


def coffee(t):
    sc = Scene()
    sc.vgrad((22, 30, 52), (40, 48, 70))
    for x, y, sp in RAIN:
        yy = (y + t * 1.6 * sp) % 32 - 2
        xx = (x - t * 0.5 * sp) % W
        sc.line([(xx, yy), (xx - 0.6, yy + 2.4)], (150, 180, 230, 150), 0.35)
    sc.d.rectangle(sc.S(0, 0, W, 1.4), fill=(60, 58, 70))
    sc.d.rectangle(sc.S(43.3, 0, 44.7, 20), fill=(60, 58, 70))
    sc.d.rectangle(sc.S(0, 19.4, W, 20.4), fill=(70, 66, 76))  # bậu cửa
    sc.glow(40, 16, 20, (255, 190, 120), 40)
    sc.vgrad((92, 64, 46), (66, 46, 32), 26, 30)               # sàn
    # bàn nhỏ + cốc bên phải
    sc.rect(66, 18.5, 84, 20, (150, 104, 72), 0.5)
    sc.rect(73.5, 20, 76.5, 26, (110, 76, 52))
    cx = 70
    sc.rect(cx, 12.5, cx + 7, 18.5, (244, 242, 238), 1.3)
    sc.d.arc(sc.S(cx + 5.5, 13.6, cx + 9.4, 17.4), -90, 90, fill=(244, 242, 238), width=int(1.1 * SS))
    sc.ell(cx + 3.5, 12.9, 3.2, 0.7, (110, 66, 40))
    for i in range(3):
        ph = ((t / FPS) + i * 0.9) % 2.7 / 2.7
        pts = [(cx + 2 + i * 1.6 + math.sin(ph * 6 + j) * 0.8, 11 - ph * 8 - j * 1.1) for j in range(4)]
        sc.line(pts, (230, 230, 240, int(170 * (1 - ph))), 0.55)
    # đi qua đi lại: 4s một lượt, dừng ngắm mưa ở hai đầu
    T = (t / FPS) % 8
    if T < 3:   p, walking = T / 3, True
    elif T < 4: p, walking = 1, False
    elif T < 7: p, walking = 1 - (T - 4) / 3, True
    else:       p, walking = 0, False
    x = 6 + p * 34
    bob = abs(math.sin(t / FPS * 9)) * 0.6 if walking else 0
    sc.clawd(x, 9.5 - bob, look=(1.0 if (T < 3.5 or T > 7) else -1.0), step=(t // 2) % 2 if walking else None)
    return sc.out()


# 5) Lửa trại — thi thoảng nhún nhảy, thi thoảng bắn pháo hoa.
FW_COLORS = [(255, 110, 120), (120, 200, 255), (255, 220, 110), (170, 140, 255)]


def firework(sc, cx, cy, p, col):
    """p: 0→1. Nửa đầu bay lên, nửa sau nổ tung + tàn rơi."""
    if p < 0.3:
        y = 26 - (26 - cy) * (p / 0.3)
        sc.ell(cx, y, 0.45, 0.8, (255, 230, 180, 230))
        return
    q = (p - 0.3) / 0.7
    r = 2 + q * 7
    a = int(255 * (1 - q) ** 1.2)
    for k in range(12):
        ang = k * math.pi / 6
        x, y = cx + math.cos(ang) * r, cy + math.sin(ang) * r + q * q * 3
        sc.ell(x, y, 0.55, 0.55, col + (a,))
    sc.glow(cx, cy, 5, col, int(60 * (1 - q)))


def campfire(t):
    sc = Scene()
    sc.vgrad(*NIGHT)
    stars(sc, t)
    sec = t / FPS
    # pháo hoa: mỗi 8s một đợt 2 quả
    cyc = sec % 8
    for j, (cx, cy, dt) in enumerate(((52, 7, 0.0), (74, 5, 0.5))):
        p = (cyc - 4 - dt) / 1.8
        if 0 <= p <= 1:
            firework(sc, cx, cy, p, FW_COLORS[(int(sec // 8) + j) % len(FW_COLORS)])
    sc.ell(14, 36, 34, 12, (20, 26, 48)); sc.ell(76, 36, 30, 12, (16, 22, 42))
    sc.vgrad((34, 52, 40), (24, 36, 28), 26, 30)
    fx = 62
    fl = 0.5 + 0.5 * math.sin(sec * 9) * math.sin(sec * 5.3 + 1)
    sc.glow(fx, 20, 15 + fl * 2, (255, 140, 60), 80)
    # nhún nhảy: mỗi 8s có 1.5s nhảy tưng tưng (ngay trước pháo hoa)
    d = sec % 8
    hop = abs(math.sin((d - 2) * math.pi * 2.6)) * 3 if 2 <= d < 3.5 else 0
    sc.clawd(14, 10 - hop, look=1.0, arms="upR" if hop > 0 else "side", squash=0 if hop else 0.4)
    sc.rect(14, 10 - hop, 34, 22 - hop, (255, 150, 80, int(30 + 25 * fl)), 2.2)
    sc.line([(fx - 6, 26), (fx + 6, 23.5)], (90, 58, 38), 1.6)
    sc.line([(fx - 6, 23.5), (fx + 6, 26)], (76, 48, 32), 1.6)
    for col, hh, ww in (((230, 70, 40), 11, 5), ((255, 150, 50), 8, 3.6), ((255, 226, 120), 5, 2)):
        h2 = hh + fl * 2
        sway = math.sin(sec * 7) * 0.8
        sc.d.polygon([(x * SS, y * SS) for x, y in [(fx - ww, 24), (fx - ww * 0.6, 24 - h2 * 0.5),
                                                    (fx + sway, 24 - h2), (fx + ww * 0.6, 24 - h2 * 0.5), (fx + ww, 24)]],
                     fill=col)
    for i in range(4):
        ph = (sec + i * 0.7) % 2.2 / 2.2
        sc.ell(fx - 2 + i * 1.4 + math.sin(ph * 9 + i) * 1.5, 14 - ph * 12, 0.45, 0.45,
               (255, 200, 110, int(255 * (1 - ph))))
    return sc.out()


SCENES = [("doc-sach", reading, 36), ("ngu", sleeping, 40), ("cau-ca", fishing, 72),
          ("ca-phe", coffee, 96), ("lua-trai", campfire, 96)]


def pill(frame):
    """Pill đen trên thanh menu @2x: icon nhạc trái, cảnh giữa, sóng nhạc phải."""
    pw, ph = W + 92, H + 12
    im = Image.new("RGB", (pw + 24, ph + 24), (232, 228, 220))
    big = Image.new("RGBA", ((pw + 24) * 4, (ph + 24) * 4), (0, 0, 0, 0))
    dr = ImageDraw.Draw(big)
    dr.rounded_rectangle((48, 48, 48 + pw * 4, 48 + ph * 4), radius=ph * 2, fill=(0, 0, 0, 255))
    dr.rounded_rectangle((48 + 40, 48 + ph * 2 - 36, 48 + 112, 48 + ph * 2 + 36), 16, fill=(230, 50, 45, 255))
    for i, hh in enumerate((10, 22, 14, 26, 12)):
        x = 48 + pw * 4 - 110 + i * 16
        dr.rounded_rectangle((x, 48 + ph * 2 - hh * 2, x + 8, 48 + ph * 2 + hh * 2), 4, fill=(240, 90, 80, 255))
    big = big.resize((pw + 24, ph + 24), Image.LANCZOS)
    im.paste(big, (0, 0), big)
    mask = Image.new("L", (W * 4, H * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, W * 4 - 1, H * 4 - 1), radius=20, fill=255)
    im.paste(frame, (12 + (pw - W) // 2, 12 + 6), mask.resize((W, H), Image.LANCZOS))
    return im


def export_sheets(dirp):
    """Mỗi cảnh → 1 PNG ngang (các khung 88×30 nối nhau) cho app đọc."""
    os.makedirs(dirp, exist_ok=True)
    for slug, fn, n in SCENES:
        sheet = Image.new("RGB", (OUT_W * n, OUT_H))
        for t in range(n):
            sheet.paste(fn(t), (t * OUT_W, 0))
        sheet.save(os.path.join(dirp, f"{slug}.png"), optimize=True)
        print("sheet", slug, n)


if __name__ == "__main__":
    if sys.argv[1] == "--export":
        export_sheets(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Resources/Chill"))
        sys.exit(0)
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    seq = []
    for slug, fn, n in SCENES:
        frames = [fn(t) for t in range(n)]
        big = [f.resize((W * 6, H * 6), Image.LANCZOS) for f in frames]
        big[0].save(os.path.join(d, f"{slug}.gif"), save_all=True, append_images=big[1:],
                    duration=1000 // FPS, loop=0)
        p = [pill(f).resize(((W + 116) * 3, (H + 36) * 3), Image.LANCZOS) for f in frames]
        seq += p + p
        print(slug, n)
    seq[0].save(os.path.join(d, "chill-pill.gif"), save_all=True, append_images=seq[1:],
                duration=1000 // FPS, loop=0)
