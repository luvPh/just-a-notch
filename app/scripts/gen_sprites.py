#!/usr/bin/env python3
"""Sinh sprite pixel (mèo nhắc nghỉ + Clawd) từ keyframe tư thế → Swift + ảnh xem trước.

Chạy:  python3 app/scripts/gen_sprites.py [--preview <dir>]
Ghi:   app/Sources/JustANotch/UI/SpriteData.swift

Mỗi khung là lưới ký tự; bảng màu ở `PALETTES`. Vẽ bằng vài hình cơ bản (ellipse,
đa giác, nét dày) rồi thêm viền 1px quanh silhouette cho nét pixel-art sắc.
"""
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Sources/JustANotch/UI/SpriteData.swift")


class Grid:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.c = [["."] * w for _ in range(h)]

    def put(self, x, y, ch):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.c[y][x] = ch

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.c[y][x]
        return "."

    def ellipse(self, cx, cy, rx, ry, ch, only=None):
        for y in range(self.h):
            for x in range(self.w):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0 and (only is None or only(x, y)):
                    self.put(x, y, ch)

    def poly(self, pts, ch):
        for y in range(self.h):
            for x in range(self.w):
                if inside(pts, x + 0.5, y + 0.5):
                    self.put(x, y, ch)

    def stroke(self, pts, r, ch):
        """Nét dày bán kính r qua các điểm (capsule nối tiếp)."""
        for y in range(self.h):
            for x in range(self.w):
                px, py = x + 0.5, y + 0.5
                for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                    if seg_dist(px, py, ax, ay, bx, by) <= r:
                        self.put(x, y, ch)
                        break

    def outline(self, body, ch):
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.c[y][x] != ".":
                    continue
                if any(self.get(x + dx, y + dy) in body for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    add.append((x, y))
        for x, y in add:
            self.c[y][x] = ch

    def rows(self):
        return ["".join(r) for r in self.c]


def inside(pts, x, y):
    n, j, res = len(pts), len(pts) - 1, False
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            res = not res
        j = i
    return res


def seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L = vx * vx + vy * vy
    t = 0 if L == 0 else max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / L))
    qx, qy = ax + t * vx, ay + t * vy
    return math.hypot(px - qx, py - qy)


def lerp(a, b, t):
    return a + (b - a) * t


def rot(pts, cx, cy, ang):
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]


# ---------------------------------------------------------------- Mèo 28×30

CAT_W, CAT_H = 28, 30
CAT_BODY = set("PHSLCDWc")


def cat_frame(p, t):
    g = Grid(CAT_W, CAT_H)
    hx = 13.5 + p["lean"]
    hy = p["hy"]
    bcx, bcy, brx, bry = 13.5, p["bcy"], p["brx"], p["bry"]
    ground = 27.5

    # Đuôi (sau thân): cong lên, đung đưa theo thời gian.
    sway = math.sin(t * 2 * math.pi * 0.9) * 1.6
    x0, y0 = bcx + brx - 1.5, bcy + bry * 0.35
    g.stroke([(x0, y0), (x0 + 2.6, y0 - 0.6), (x0 + 3.6 + sway * 0.4, y0 - 3.4), (x0 + 2.8 + sway, y0 - 6.2)], 1.05, "P")

    # Chân (đứng) hoặc bàn chân trước (ngồi).
    legs_top = bcy + bry * 0.4
    for fx in (bcx - 3.2, bcx + 3.2):
        if ground - legs_top > 1.5:
            g.stroke([(fx, legs_top), (fx, ground - 1.2)], 1.3, "P")
        g.ellipse(fx, ground - 1.0, 2.0, 1.25, "P")

    # Thân + bụng + bóng dưới.
    g.ellipse(bcx, bcy, brx, bry, "P")
    g.ellipse(bcx, bcy + bry * 0.72, brx * 0.95, bry * 0.4, "S", only=lambda x, y: g.get(x, y) == "P")
    g.ellipse(bcx, bcy + 0.8, brx * 0.52, bry * 0.62, "L")

    # Đầu + tai.
    for side in (-1, 1):
        base_out = (hx + side * 7.6, hy - 1.6)
        tip = (hx + side * 6.4, hy - 8.4)
        base_in = (hx + side * 2.4, hy - 5.4)
        g.poly([base_out, tip, base_in], "P")
        g.poly([(hx + side * 6.3, hy - 3.2), (hx + side * 6.0, hy - 6.8), (hx + side * 3.9, hy - 4.8)], "C")
    g.ellipse(hx, hy, 8.3, 6.6, "P")
    # Điểm sáng trên đỉnh đầu.
    g.ellipse(hx - 3.2, hy - 4.2, 2.6, 1.1, "H", only=lambda x, y: g.get(x, y) == "P")

    # Tay (vẽ SAU đầu để không bị che): vai → bàn tay, ngắn. Vươn vai = giơ chéo
    # ra hai bên kiểu "\o/", không vươn thẳng qua đầu.
    sy = bcy - bry + 2.2
    up, cup = p["up"], p["cup"]
    for side in (-1, 1):
        sx = bcx + side * (brx - 1.6)
        down = (sx + side * 1.2, sy + 4.2)
        raised = (sx + side * 5.2, sy - 2.2)
        hand = (lerp(down[0], raised[0], up), lerp(down[1], raised[1], up))
        if side == 1 and cup > 0:
            hand = (lerp(down[0], hx + 5.2, cup), lerp(down[1], hy + 4.6, cup))
        # Tay buông / cầm cốc nằm sau đầu: không tô đè lên vùng mặt.
        on_head = lambda x, y: up < 0.3 and y < hy + 6.6 and abs(x + 0.5 - hx) < 8
        keep = lambda x, y: not on_head(x, y)
        for y in range(g.h):
            for x in range(g.w):
                if seg_dist(x + 0.5, y + 0.5, sx, sy, *hand) <= 1.25 and keep(x, y):
                    g.put(x, y, "P")
        g.ellipse(hand[0], hand[1], 1.35, 1.35, "P", only=keep)

    # Mặt.
    ex = (round(hx - 4.5), round(hx + 3.5))
    ey = round(hy - 0.5)
    for x in ex:
        if p["eyes"] == "open":
            for dy in range(3):
                g.put(x, ey + dy, "D"); g.put(x + 1, ey + dy, "D")
            g.put(x, ey, "W")
        elif p["eyes"] == "blink":
            g.put(x, ey + 2, "D"); g.put(x + 1, ey + 2, "D")
        else:  # nhắm tít ^ ^
            g.put(x - 1 + 1, ey + 1, "D"); g.put(x + 1, ey + 1, "D")
            g.put(x - 1, ey + 2, "D"); g.put(x + 2, ey + 2, "D")
    for x in (ex[0] - 2, ex[1] + 2):
        g.put(x, ey + 3, "C"); g.put(x + 1, ey + 3, "C")
    mx = round(hx - 2.5)
    my = ey + 3
    for dx in (0, 2, 3, 5):
        g.put(mx + dx, my, "c")
    for dx in (1, 4):
        g.put(mx + dx, my + 1, "c")

    g.outline(CAT_BODY, "o")

    # Cốc nước (sau viền để nằm trên tay).
    if cup > 0.05:
        cx, cy = hx + 6.6, hy + 3.6
        tilt = -p["tilt"] * 0.75
        pts = [(cx - 2.2, cy - 3.0), (cx + 2.2, cy - 3.0), (cx + 1.7, cy + 3.0), (cx - 1.7, cy + 3.0)]
        pts = rot(pts, cx, cy, tilt)
        g.poly(pts, "g")
        inner = rot([(cx - 1.3, cy - 2.2), (cx + 1.3, cy - 2.2), (cx + 0.9, cy + 2.2), (cx - 0.9, cy + 2.2)], cx, cy, tilt)
        g.poly(inner, "W")
        level = lerp(-0.6, 0.9, p["tilt"])   # nghiêng uống → nước vơi
        water = rot([(cx - 1.2, cy + level), (cx + 1.2, cy + level), (cx + 0.9, cy + 2.2), (cx - 0.9, cy + 2.2)], cx, cy, tilt)
        g.poly(water, "B")
        g.put(round(cx - 0.8), round(cy + 1.4), "b")
    if p.get("drop"):
        g.put(round(hx + 9), round(hy - 4 - p["drop"]), "B")
    return g.rows()


SIT = dict(hy=14.0, bcy=22.0, brx=7.2, bry=4.8, lean=0, up=0, cup=0, tilt=0, eyes="open")
STAND = dict(hy=11.0, bcy=19.5, brx=6.2, bry=5.2, lean=0, up=0, cup=0, tilt=0, eyes="open")
STRETCH = dict(hy=9.4, bcy=18.4, brx=5.8, bry=5.9, lean=0, up=1, cup=0, tilt=0, eyes="closed")
HOLD = dict(STAND, cup=1)
DRINK = dict(STAND, cup=1, tilt=1, lean=-0.4, eyes="closed")

# (khung bắt đầu, tư thế). Nội suy các số giữa hai keyframe; mắt theo keyframe trước.
CAT_KEYS = [
    (0, SIT), (5, SIT), (9, STAND), (11, STAND), (15, STRETCH), (21, STRETCH), (24, STAND),
    (26, STAND), (29, HOLD), (31, DRINK), (37, DRINK), (39, HOLD), (41, STAND), (44, SIT), (48, SIT),
]
CAT_FPS = 12


def interp(keys, i):
    for (a, pa), (b, pb) in zip(keys, keys[1:]):
        if a <= i <= b:
            t = 0 if b == a else (i - a) / (b - a)
            t = t * t * (3 - 2 * t)   # smoothstep cho chuyển động mềm
            out = {k: (lerp(pa[k], pb[k], t) if isinstance(pa[k], (int, float)) else pa[k]) for k in pa}
            return out
    return dict(keys[-1][1])


def cat_frames():
    n = CAT_KEYS[-1][0]
    frames = []
    for i in range(n):
        p = interp(CAT_KEYS, i)
        if i in (2, 3):
            p["eyes"] = "blink"
        if 31 <= i < 37:
            p["drop"] = (i - 31) * 0.8
        frames.append(cat_frame(p, i / CAT_FPS))
    return frames


# ---------------------------------------------------------------- Clawd 18×15 (low-pixel)
#
# Đúng tỉ lệ Clawd trong màn chào Claude Code: logo vẽ bằng ký tự ¼ khối nên mỗi
# "pixel" logo cao gấp đôi rộng → ở đây mỗi hàng logo = 2 hàng lưới. Nhờ vậy nhún /
# nhấc chân được nửa pixel logo cho mượt, mà nhìn vẫn khối to như bản gốc.

CL_W, CL_H = 18, 15
CL_GROUND = 13          # hàng cuối của chân khi đứng trên đất
CL_TOP = 4              # đỉnh thân khi đứng


def clawd_frame(lift=0, legs="A", arms="side", eyes="open", crouch=False, sparkle=0, shadow=False):
    """lift: số hàng thân nhấc lên (nhảy/nhún). legs: A = đủ 4 chân, B = cặp 1&3 nhấc,
    C = cặp 2&4 nhấc, tuck = thu chân (đang bay)."""
    g = Grid(CL_W, CL_H)
    y = CL_TOP - lift + (1 if crouch else 0)
    x0, x1 = 3, 14

    # Thân: 4 hàng logo × 2 hàng lưới.
    for x in range(x0, x1 + 1):
        g.put(x, y, "h")
        for r in range(1, 7):
            g.put(x, y + r, "O")
        g.put(x, y + 7, "d")
    # Mắt: khe 1×2 ô (= 1 pixel logo). down = nhìn xuống bàn phím (nửa dưới),
    # up = liếc lên góc phải suy nghĩ (nửa trên, lệch phải 1 ô).
    for ex in (5, 12):
        if eyes == "open":
            g.put(ex, y + 2, "."); g.put(ex, y + 3, ".")
        elif eyes == "down":
            g.put(ex, y + 3, ".")
        elif eyes == "up":
            g.put(ex + 1, y + 2, ".")
        else:  # nhắm: chỉ còn vạch tối nửa dưới
            g.put(ex, y + 3, "q")

    # Tay: chìa ngang 2 ô ở hàng logo thứ 3, hoặc giơ chéo lên 2 bậc (ngắn).
    for side, up in ((-1, arms in ("upL", "upBoth")), (1, arms in ("upR", "upBoth"))):
        if arms == "none":
            break
        edge = x0 if side < 0 else x1
        if up:
            for r in (2, 3):
                g.put(edge + side, y + r, "O")
            for r in (0, 1):
                g.put(edge + 2 * side, y + r, "O")
        else:
            for r in (4, 5):
                g.put(edge + side, y + r, "O")
                g.put(edge + 2 * side, y + r, "O")

    # Chân: 4 chân 1 ô rộng, từ đáy thân xuống đất (nhấc = ngắn 1 hàng).
    bottom = y + 8
    for i, lx in enumerate((4, 6, 11, 13)):
        if legs == "tuck":
            end = bottom          # chỉ 1 hàng ló dưới thân
        elif lift >= 2:
            end = bottom + 1      # đang bay: chân giữ độ dài, đi theo thân (không duỗi chạm đất)
        else:
            lifted = (legs == "B" and i in (0, 2)) or (legs == "C" and i in (1, 3))
            end = CL_GROUND - (1 if lifted else 0)
        for r in range(bottom, end + 1):
            g.put(lx, r, "O")

    # Bóng đổ khi đang bay — càng cao càng nhỏ.
    if shadow:
        half = max(2, 6 - lift // 2)
        for x in range(9 - half, 9 + half):
            g.put(x, CL_H - 1, "g")

    # Lấp lánh: 1 = chấm (1×2), 2 = ngôi sao 4 cánh.
    if sparkle:
        for sx, sy in ((1, 1), (16, 0), (17, 6)):
            g.put(sx, sy, "Y"); g.put(sx, sy + 1, "Y")
            if sparkle == 2:
                for dx, dy in ((0, -1), (0, 2), (-1, 0), (1, 0), (-1, 1), (1, 1)):
                    if g.get(sx + dx, sy + dy) == ".":
                        g.put(sx + dx, sy + dy, "y")
    return g.rows()


def clawd_type_frame(left="down", right="down", eyes="down", dots=0):
    """Clawd ngồi gõ phím: thân nguyên vẹn, tay chìa ngang rồi gập xuống bàn phím đặt
    thấp phía trước (down = chạm phím + phím sáng lên, up = nhấc tay để lộ khe hở),
    mắt nhìn xuống / liếc lên, `dots` chấm suy nghĩ nổi trên đầu."""
    g = Grid(CL_W, CL_H)
    g.c = [list(r) for r in clawd_frame(0, "none", "none", eyes=eyes)]
    y = CL_TOP                        # thân: hàng y..y+7
    # Bàn phím sát dưới thân (chân khuất phía sau): mép trên + 1 hàng phím xen kẽ.
    ky = y + 8
    for x in range(0, 18):
        g.put(x, ky, "k")
        g.put(x, ky + 1, "K" if x % 2 == 0 else "k")
    # Tay ngắn: nhấc (up) = chìa ngang như Clawd gốc; gõ (down) = gập xuống chạm phím,
    # phím đó sáng lên.
    for side, state in ((-1, left), (1, right)):
        sx = 2 if side < 0 else 15    # vai (sát thân)
        hx = 1 if side < 0 else 16    # bàn tay
        for r in (4, 5):
            g.put(sx, y + r, "O")
        if state == "down":
            g.put(hx, y + 6, "O"); g.put(hx, y + 7, "O")
            g.put(hx, ky, "w")
        else:
            g.put(hx, y + 4, "O"); g.put(hx, y + 5, "O")
    # Chấm suy nghĩ bay chéo lên góc phải.
    for n, (dx, dy) in enumerate(((13, 2), (15, 1), (17, 0))):
        if n < dots:
            g.put(dx, dy, "b")
    return g.rows()


def clawd_work():
    # Đang làm: gõ phím luân phiên hai tay (mắt nhìn xuống), thỉnh thoảng dừng tay,
    # liếc lên góc trên suy nghĩ với 3 chấm nổi dần, rồi gõ tiếp.
    A = clawd_type_frame("down", "up")
    B = clawd_type_frame("up", "down")
    P = clawd_type_frame("down", "down")
    typing = [A, A, B, B, A, B, A, A, B, B, P, P]
    blink = [A, A, B, B, clawd_type_frame("down", "up", eyes="blink"), B, A, A, B, B, P, P]
    think = [clawd_type_frame(eyes="up", dots=d) for d in (0, 1, 1, 2, 2, 3, 3, 3, 3, 3, 3, 3)]
    back = [clawd_type_frame(eyes="up", dots=0), P]
    return typing + blink + typing + think + back


def clawd_walk():
    # Bò: nhấc so le từng cặp chân, thân nhún nửa pixel theo nhịp; chớp mắt 1 lần/vòng.
    cycle = [clawd_frame(0, "A"), clawd_frame(1, "B"), clawd_frame(1, "B"), clawd_frame(0, "A"),
             clawd_frame(1, "C"), clawd_frame(1, "C")]
    blink = [clawd_frame(0, "A", eyes="blink")] + cycle[1:]
    return cycle + cycle + blink + cycle


def clawd_alert():
    # Chờ duyệt: vẫy luân phiên từng tay kèm nhún nhẹ, rồi giơ cả hai tay nhảy.
    wave = [clawd_frame(0, "A", "upL"), clawd_frame(1, "A", "upL"),
            clawd_frame(0, "A", "upR"), clawd_frame(1, "A", "upR")]
    hop = [clawd_frame(0, "A", "upBoth", crouch=True), clawd_frame(2, "A", "upBoth"),
           clawd_frame(3, "tuck", "upBoth", shadow=True), clawd_frame(2, "A", "upBoth"),
           clawd_frame(0, "A", "upBoth")]
    return wave + wave + hop


def clawd_happy():
    # Xong: ngồi thụp lấy đà → bật nhảy (thu chân, giơ tay) → lấp lánh → tiếp đất.
    return [
        clawd_frame(0, "A", crouch=True),
        clawd_frame(0, "A", crouch=True),
        clawd_frame(2, "A", "upBoth"),
        clawd_frame(3, "tuck", "upBoth", shadow=True, sparkle=1),
        clawd_frame(4, "tuck", "upBoth", eyes="blink", shadow=True, sparkle=2),
        clawd_frame(4, "tuck", "upBoth", eyes="blink", shadow=True, sparkle=2),
        clawd_frame(3, "tuck", "upBoth", shadow=True, sparkle=1),
        clawd_frame(2, "A", "upBoth", sparkle=1),
        clawd_frame(0, "A", crouch=True, sparkle=2),
        clawd_frame(0, "A", sparkle=1),
        clawd_frame(0, "A"),
        clawd_frame(0, "A"),
        clawd_frame(0, "A", eyes="blink"),
        clawd_frame(0, "A"),
    ]


# ---------------------------------------------------------------- Xuất

PALETTES = {
    "PixelCat": {
        "P": (1.00, 0.60, 0.75), "H": (1.00, 0.80, 0.88), "S": (0.90, 0.45, 0.63),
        "L": (1.00, 0.87, 0.92), "D": (0.13, 0.07, 0.12), "W": (0.97, 0.98, 1.00),
        "C": (0.98, 0.40, 0.58), "c": (0.45, 0.14, 0.28), "o": (0.52, 0.20, 0.36),
        "B": (0.40, 0.78, 1.00), "b": (0.23, 0.56, 0.92), "g": (0.62, 0.70, 0.80),
    },
    "Clawd": {
        "O": (0.851, 0.467, 0.341), "h": (0.92, 0.58, 0.45), "d": (0.74, 0.38, 0.27),
        "q": (0.42, 0.19, 0.12), "g": (0.26, 0.19, 0.17),
        "k": (0.42, 0.44, 0.50), "K": (0.66, 0.68, 0.75), "b": (0.86, 0.88, 0.94),
        "w": (0.98, 0.93, 0.78),
        "Y": (1.00, 0.90, 0.52), "y": (1.00, 0.74, 0.32),
    },
}


def swift_frames(name, frames):
    uniq, idx = [], []
    for f in frames:
        if f not in uniq:
            uniq.append(f)
        idx.append(uniq.index(f))
    body = ",\n".join("        [\n" + ",\n".join(f'            "{r}"' for r in f) + ",\n        ]" for f in uniq)
    return f"    static let {name}Frames: [[String]] = [\n{body},\n    ]\n    static let {name}: [Int] = {idx}\n"


def palette_swift(name):
    items = ",\n".join(f'        "{k}": Color(red: {r}, green: {g}, blue: {b})' for k, (r, g, b) in PALETTES[name].items())
    return f"    static let palette: [Character: Color] = [\n{items},\n    ]\n"


def write_swift(cat, work, walk, alert, happy):
    s = ["// Sinh tự động bởi app/scripts/gen_sprites.py — đừng sửa tay.", "import SwiftUI", ""]
    s.append("extension PixelCat {")
    s.append(f"    static let width = {CAT_W}\n    static let height = {CAT_H}\n    static let fps = {float(CAT_FPS)}")
    s.append(palette_swift("PixelCat"))
    s.append(swift_frames("loop", cat))
    s.append("}\n")
    s.append("extension Clawd {")
    s.append(f"    static let width = {CL_W}\n    static let height = {CL_H}\n    static let fps = 8.0")
    s.append(palette_swift("Clawd"))
    s.append(swift_frames("work", work))
    s.append(swift_frames("walk", walk))
    s.append(swift_frames("alert", alert))
    s.append(swift_frames("happy", happy))
    s.append("}\n")
    with open(OUT, "w") as f:
        f.write("\n".join(s))


def preview(dirp, name, frames, pal, px, fps):
    from PIL import Image
    os.makedirs(os.path.join(dirp, name), exist_ok=True)
    h, w = len(frames[0]), len(frames[0][0])
    for i, f in enumerate(frames):
        im = Image.new("RGB", (w * px, h * px), (0, 0, 0))
        for y, row in enumerate(f):
            for x, ch in enumerate(row):
                if ch in pal:
                    r, g, b = pal[ch]
                    for yy in range(px):
                        for xx in range(px):
                            im.putpixel((x * px + xx, y * px + yy), (int(r * 255), int(g * 255), int(b * 255)))
        im.save(os.path.join(dirp, name, f"{i:03d}.png"))
    sheet = Image.new("RGB", ((w * px + 8) * min(len(frames), 12), (h * px + 8) * ((len(frames) + 11) // 12)), (40, 40, 40))
    for i in range(len(frames)):
        tile = Image.open(os.path.join(dirp, name, f"{i:03d}.png"))
        sheet.paste(tile, ((i % 12) * (w * px + 8), (i // 12) * (h * px + 8)))
    sheet.save(os.path.join(dirp, f"{name}-sheet.png"))


if __name__ == "__main__":
    cat = cat_frames()
    work, walk, alert, happy = clawd_work(), clawd_walk(), clawd_alert(), clawd_happy()
    write_swift(cat, work, walk, alert, happy)
    print(f"wrote {OUT}: cat {len(cat)} frames, clawd {len(work)}/{len(alert)}/{len(happy)}")
    if "--preview" in sys.argv:
        d = sys.argv[sys.argv.index("--preview") + 1]
        preview(d, "cat", cat, PALETTES["PixelCat"], 8, CAT_FPS)
        preview(d, "clawd", work + alert + happy, PALETTES["Clawd"], 12, 8)
        preview(d, "clawd-walk", walk, PALETTES["Clawd"], 12, 8)
