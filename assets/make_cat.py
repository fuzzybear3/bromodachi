#!/usr/bin/env python3
"""Render the bromodachi cat: a tiny 2D rig drawn into 32x24 pixel frames.

Every frame is built from primitives (discs, thick polylines, triangles) in
parts order far-legs -> tail -> body -> head -> near-legs, then shaded, then
outlined automatically, so a pose is just a handful of numbers and a walk
cycle is legs moving, not frames drawn by hand.

Outputs (next to this file):
  cat/cat_sheet.png   one row per animation, 32x24 cells, facing right
  cat/cat_sheet_3x.png  the same at 3x (96x72 cells), what cat.qml loads
  cat/cat_sheet.json  {anim: {row, frames, fps, loop}} for the QML side
  cat/preview.png     8x contact sheet, labelled
  cat/preview.gif     8x, every animation played in sequence
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

W, H = 32, 24
OUT = Path(__file__).parent / "cat"

PALETTE = {
    "K": (0x2B, 0x21, 0x1B, 255),  # outline, pupils, closed eyes
    "B": (0xE8, 0x96, 0x4A, 255),  # orange tabby base
    "D": (0xC2, 0x6B, 0x2C, 255),  # stripes, far legs
    "C": (0xF9, 0xE4, 0xC2, 255),  # cream belly / muzzle / paws
    "P": (0xF0, 0x8F, 0x8F, 255),  # nose, inner ear
    "G": (0xA6, 0xC8, 0x4E, 255),  # eye green
    "W": (0xFF, 0xFF, 0xFF, 255),  # eye catchlight, laptop logo
    "L": (0xB8, 0xBE, 0xC8, 255),  # laptop lid
    "E": (0x6E, 0x76, 0x82, 255),  # laptop base / hinge
    "S": (0x9C, 0xE0, 0xFF, 255),  # screen glow
    "T": (0xD6, 0xF3, 0xFF, 255),  # screen glow, brighter flicker
    "N": (0x2E, 0x3A, 0x6B, 255),  # ninja navy: headband, mask
    "M": (0xC9, 0xD1, 0xDA, 255),  # headband plate
    "O": (0x8B, 0x5A, 0x2B, 255),  # log bark
    "Q": (0x5E, 0x3A, 0x1A, 255),  # bark grooves, rings
    "R": (0xE3, 0xC0, 0x84, 255),  # log cut face
    "V": (0x6F, 0xB8, 0x4B, 255),  # leaf
    "F": (0xF4, 0xF4, 0xF6, 255),  # smoke
    "Y": (0xB9, 0xBE, 0xCC, 255),  # smoke shade / soft outline
    "U": (0x45, 0x55, 0x92, 255),  # ninja suit highlight
    "Z": (0x1C, 0x23, 0x42, 255),  # ninja suit, far limbs
    "A": (0xC8, 0x3C, 0x3C, 255),  # red sash
}


# ------------------------------------------------------------ primitives
class Canvas:
    def __init__(self):
        self.px = {}

    def put(self, x, y, col):
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < W and 0 <= y < H:
            self.px[(x, y)] = col

    def disc(self, cx, cy, rx, ry, col, where=None):
        for y in range(H):
            for x in range(W):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0 and (where is None or where(x, y)):
                    self.put(x, y, col)

    def line(self, pts, w, col):
        """Thick polyline: stamp a disc of diameter w along every segment."""
        r = w / 2.0
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = max(2, int(math.hypot(x1 - x0, y1 - y0) * 4))
            for i in range(n + 1):
                t = i / n
                cx, cy = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                for y in range(int(cy - r - 1), int(cy + r + 2)):
                    for x in range(int(cx - r - 1), int(cx + r + 2)):
                        if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                            self.put(x, y, col)

    def tri(self, a, b, c, col):
        def side(p, q, r):
            return (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1])
        for y in range(H):
            for x in range(W):
                p = (x + 0.5, y + 0.5)
                d1, d2, d3 = side(p, a, b), side(p, b, c), side(p, c, a)
                neg = d1 < 0 or d2 < 0 or d3 < 0
                pos = d1 > 0 or d2 > 0 or d3 > 0
                if not (neg and pos):
                    self.put(x, y, col)

    def recolor(self, col, where):
        for (x, y), c in list(self.px.items()):
            if where(x, y, c):
                self.px[(x, y)] = col

    def outline(self, col="K"):
        edge = {}
        for y in range(H):
            for x in range(W):
                if (x, y) in self.px:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if (x + dx, y + dy) in self.px:
                        edge[(x, y)] = col
                        break
        self.px.update(edge)

    def image(self):
        im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        for (x, y), c in self.px.items():
            im.putpixel((x, y), PALETTE[c])
        return im


# ------------------------------------------------------------ body parts
def head(c, hx, hy, eyes="open", ears=0, front=False):
    """Round head at (hx, hy). ears: 0 relaxed, 1 perked (alert).
    front=True draws a face-on head (two eyes) for the dangle pose."""
    lift = ears
    if front:
        c.tri((hx - 5, hy - 1), (hx - 4, hy - 7 - lift), (hx - 1, hy - 4), "B")
        c.tri((hx + 5, hy - 1), (hx + 4, hy - 7 - lift), (hx + 1, hy - 4), "B")
        c.disc(hx, hy, 5.2, 4.6, "B")
        c.disc(hx, hy + 2.2, 3.2, 2.2, "C")
        c.put(hx - 4, hy - 4 - lift, "P")
        c.put(hx + 3, hy - 4 - lift, "P")
    else:
        c.tri((hx - 5, hy - 2), (hx - 3, hy - 8 - lift), (hx, hy - 4), "B")
        c.tri((hx - 1, hy - 4), (hx + 2, hy - 8 - lift), (hx + 4, hy - 2), "B")
        c.disc(hx, hy, 5.0, 4.4, "B")
        c.disc(hx + 2.6, hy + 2.0, 2.6, 1.8, "C")  # muzzle
        c.put(hx + 1, hy - 5 - lift, "P")          # inner ear
    return (hx, hy, eyes, front)


def face(c, h):
    """Eyes and nose go on after the outline so they sit on the fill."""
    hx, hy, eyes, front = h
    hx, hy = int(hx), int(hy)
    if front:
        for ex in (hx - 3, hx + 2):
            if eyes == "closed":
                c.put(ex, hy, "K"); c.put(ex + 1, hy, "K")
            else:
                c.put(ex, hy - 1, "G"); c.put(ex + 1, hy - 1, "G")
                c.put(ex, hy, "K"); c.put(ex + 1, hy, "K")
        c.put(hx, hy + 1, "P")
        c.put(hx - 1, hy + 2, "K"); c.put(hx + 1, hy + 2, "K")
        return
    ex = hx + 1
    if eyes == "closed":
        c.put(ex, hy, "K"); c.put(ex + 1, hy, "K")
    elif eyes == "wide":
        c.put(ex, hy - 1, "G"); c.put(ex + 1, hy - 1, "W")
        c.put(ex, hy, "K"); c.put(ex + 1, hy, "G")
        c.put(ex, hy + 1, "K")
    else:
        c.put(ex, hy - 1, "G"); c.put(ex, hy, "K"); c.put(ex + 1, hy, "K")
    c.put(hx + 5, hy + 1, "P")  # nose


def stripes(c, xs, ytop, ybot):
    c.recolor("D", lambda x, y, col: col == "B" and x in xs and ytop <= y <= ybot)


def belly(c, cy):
    c.recolor("C", lambda x, y, col: col == "B" and y >= cy)


def leg(c, hip, foot, col="B", paw=True):
    c.line([hip, foot], 2.2, col)
    if paw:
        c.put(int(foot[0]), int(foot[1]), "C" if col == "B" else "D")


# ------------------------------------------------------------ poses
# Each pose draws its parts into separate layers (back legs + tail, body,
# head, front legs). Every layer is outlined on its own, then stacked, so the
# head and the near legs get a dark line where they cross the body.
def stack(*layers):
    out = Canvas()
    for l in layers:
        out.px.update(l.px)
    return out


def stand(phase=None, bob=0, tail=0, eyes="open"):
    """Standing / walking, facing right. phase in [0, 1) drives the gait."""
    back, body, hd, front = Canvas(), Canvas(), Canvas(), Canvas()
    by = 13 + bob
    legs = [  # (hip_x, offset, near?) diagonal pairs move together
        (19.5, 0.0, False), (8.5, 0.5, False),
        (21.5, 0.5, True), (10.5, 0.0, True),
    ]
    for hx, off, near in legs:
        if phase is None:
            fx, fy = hx, 21.5
        else:
            a = 2 * math.pi * (phase + off)
            fx = hx + 2.2 * math.sin(a)
            fy = 21.5 - (1.2 if math.cos(a) > 0.3 else 0)  # lift on the swing
        if near:
            leg(front, (hx, by + 2), (fx, fy))
        else:
            leg(back, (hx, by + 2), (fx, fy), "D")
    back.line([(6, by), (3, by - 3), (2 + tail, by - 7), (3 + tail, by - 10)], 2.4, "B")
    body.disc(14.5, by + 1, 9.2, 4.6, "B")
    stripes(body, {10, 11, 14, 15, 18}, by - 3, by - 1)
    belly(body, by + 3)
    h = head(hd, 24.5, by - 3 + (1 if bob else 0))
    for l in (back, body, hd, front):
        l.outline()
    face(hd, (h[0], h[1], eyes, False))
    return stack(back, body, hd, front)


def loaf(breath=0):
    """Asleep: lying down, head on paws, tail wrapped along the front."""
    back, body, hd, front = Canvas(), Canvas(), Canvas(), Canvas()
    body.disc(13, 17.5 - breath * 0.5, 10, 5 + breath * 0.5, "B")
    stripes(body, {7, 8, 11, 12, 15}, 13, 15)
    belly(body, 21)
    h = head(hd, 23.5, 16.8)
    front.line([(3.2, 17.5), (3.4, 20.4), (6.5, 21.4), (11, 21.2), (12.6, 20.0)], 2.2, "B")  # tail curled round
    front.line([(21.5, 21), (27.5, 21.2)], 2.2, "C")             # paws under the chin
    for l in (back, body, hd, front):
        l.outline()
    face(hd, (h[0], h[1], "closed", False))
    return stack(back, body, hd, front)


def sit(eyes="open", ears=0, paw=False):
    """Sitting upright, facing right, tail curled round the feet."""
    back, body, hd, front = Canvas(), Canvas(), Canvas(), Canvas()
    back.line([(9, 19.5), (4.5, 19.5), (3.8, 21.6), (9, 21.8)], 2.2, "B")
    leg(back, (15.5, 15), (15.5, 21.5), "D")
    body.disc(13.5, 16.5, 6, 6.2, "B")
    body.disc(9.5, 19.2, 4, 3.2, "B")
    stripes(body, {9, 10, 12, 13}, 11, 15)
    body.recolor("C", lambda x, y, col: col == "B" and x >= 17 and 12 <= y <= 18)
    h = head(hd, 18, 8.5, ears=ears)
    if paw:
        front.line([(18, 14.5), (21, 12.5), (22.5, 10.5)], 2.2, "B")
        front.put(22.5, 10.5, "C")
    else:
        leg(front, (18.5, 14.5), (18.5, 21.5))
    for l in (back, body, hd, front):
        l.outline()
    face(hd, (h[0], h[1], eyes, False))
    return stack(back, body, hd, front)


def stretch(k):
    """Waking stretch. k=0 crouch, k=1 full bow (butt up, front legs long)."""
    back, body, hd, front = Canvas(), Canvas(), Canvas(), Canvas()
    butt = (9, 16 - 4.5 * k)
    chest = (20, 18 - k)
    back.line([(butt[0] - 3, butt[1]), (4, butt[1] - 2 - 2 * k), (5.5, butt[1] - 4 - 2.5 * k)], 2.4, "B")
    leg(back, (butt[0] + 1, butt[1] + 2), (butt[0] + 1, 21.5), "D")
    body.line([butt, chest], 8.5, "B")
    stripes(body, {10, 11, 14, 15}, 0, int(butt[1]) + 1)
    h = head(hd, 25 + k, 15.5 + k)
    front.line([(21, 21), (27 + 2 * k, 21.2)], 2.4, "C")
    leg(front, (butt[0] + 3, butt[1] + 2), (butt[0] + 3, 21.5))
    for l in (back, body, hd, front):
        l.outline()
    face(hd, (h[0], h[1], "closed" if k > 0.5 else "open", False))
    return stack(back, body, hd, front)


def dangle(sway=0):
    """Held by the scruff: face-on, limp, legs and tail hanging."""
    back, body, hd, front = Canvas(), Canvas(), Canvas(), Canvas()
    cx = 16
    back.line([(cx + 1, 18), (cx + 2 + sway, 21.5), (cx + 1 + sway, 22.5)], 2.2, "D")
    leg(back, (cx - 2.5, 16), (cx - 3 + sway * 0.5, 22), "D")
    leg(back, (cx + 2.5, 16), (cx + 3 + sway * 0.5, 22), "D")
    body.disc(cx, 14.5, 4.6, 6, "B")
    body.recolor("C", lambda x, y, col: col == "B" and cx - 2 <= x <= cx + 1 and 13 <= y <= 19)
    h = head(hd, cx, 7.5, eyes="closed", front=True)
    leg(front, (cx - 3, 11.5), (cx - 4 + sway * 0.4, 17.5))
    leg(front, (cx + 3, 11.5), (cx + 4 + sway * 0.4, 17.5))
    for l in (back, body, hd, front):
        l.outline()
    face(hd, h)
    return stack(back, body, hd, front)


def fall(k=0):
    """Mid-air: legs splayed, eyes wide, tail up."""
    back, body, hd, front = Canvas(), Canvas(), Canvas(), Canvas()
    by = 11
    leg(back, (19, by + 2), (24 + k, by + 8), "D")
    leg(back, (9, by + 2), (4 - k, by + 7), "D")
    back.line([(6, by), (3, by - 4), (4, by - 8 - k)], 2.4, "B")
    body.disc(14.5, by + 1, 9, 4.4, "B")
    stripes(body, {10, 11, 14, 15, 18}, by - 3, by - 1)
    belly(body, by + 3)
    h = head(hd, 24.5, by - 3, ears=1)
    leg(front, (21, by + 2), (27, by + 7 - k))
    leg(front, (11, by + 2), (7, by + 8))
    for l in (back, body, hd, front):
        l.outline()
    face(hd, (h[0], h[1], "wide", False))
    return stack(back, body, hd, front)


def wall(k=0):
    """Clinging to a wall on the right (x=31) and sliding down it: body
    upright, front claws reaching up the wall, hind feet braced against it,
    tail hanging. k alternates the scrabbling paws."""
    back, body, hd, front = Canvas(), Canvas(), Canvas(), Canvas()
    back.line([(18.5, 20), (15.5, 21.8), (13, 22.6)], 2.4, "B")              # tail
    leg(back, (23.5, 14), (28.8, 8.5 + 2 * k), "D")                           # far front
    leg(back, (23.5, 20.5), (28.8, 18.5 - k), "D")                            # far hind
    body.disc(21.5, 17.5, 4.4, 5.2, "B")
    stripes(body, {18, 19}, 13, 21)
    body.recolor("C", lambda x, y, col: col == "B" and x >= 24 and 14 <= y <= 22)
    h = head(hd, 22.5, 9.2, ears=0)
    leg(front, (25, 14.5), (29.5, 7 + 2 * (1 - k)))                           # near front
    leg(front, (22.5, 21), (28.8, 22 - k))                                    # near hind
    for l in (back, body, hd, front):
        l.outline()
    face(hd, (h[0], h[1], "wide", False))
    return stack(back, body, hd, front)


def leap(k=0):
    """Jumping in from the side, facing right. k=0 on the way up: stretched
    out, front paws forward, hind legs pushing off behind. k=1 on the way
    down: front paws reaching for the floor, hind legs tucking under."""
    back, body, hd, front = Canvas(), Canvas(), Canvas(), Canvas()
    by = 11 + k
    if k == 0:
        leg(back, (19, by + 2), (26, by + 5), "D")
        leg(back, (8.5, by + 2), (2, by + 4), "D")
        back.line([(6, by), (2.5, by - 1.5), (0.8, by - 4)], 2.4, "B")
    else:
        leg(back, (19, by + 2), (22, by + 9), "D")
        leg(back, (8.5, by + 2), (10.5, by + 8), "D")
        back.line([(6, by), (2.5, by - 3), (2.5, by - 6.5)], 2.4, "B")
    body.disc(14.5, by + 1, 9.6, 4.2, "B")
    stripes(body, {10, 11, 14, 15, 18}, by - 3, by - 1)
    belly(body, by + 3)
    h = head(hd, 25, by - 3)
    if k == 0:
        leg(front, (21, by + 2), (28.5, by + 4))
        leg(front, (10.5, by + 2), (3.5, by + 6))
    else:
        leg(front, (21, by + 2), (24.5, by + 10))
        leg(front, (10.5, by + 2), (12.5, by + 9))
    for l in (back, body, hd, front):
        l.outline()
    face(hd, (h[0], h[1], "open", False))
    return stack(back, body, hd, front)


def laptop(lid=5, paws=(0, 0), eyes="glow", flicker=False):
    """Face-on, sitting behind a tiny laptop. We see the back of the lid (a
    fish where the fruit would be). lid: 0 closed slab, 3 half open, 5 open.
    paws: (left, right), 1 = raised over the lid edge mid-keystroke.
    eyes: glow (reflecting the screen, looking down), look (caught you
    watching), closed (blink)."""
    back, body, hd, arms, lap = Canvas(), Canvas(), Canvas(), Canvas(), Canvas()
    cx = 16
    back.line([(21, 21.5), (25.5, 20.5), (27, 17.5), (26, 15)], 2.2, "B")  # tail
    body.disc(cx, 15.5, 6.4, 6.2, "B")
    body.recolor("C", lambda x, y, col: col == "B" and cx - 2 <= x <= cx + 1 and 12 <= y <= 21)
    h = head(hd, cx, 7.2, ears=1 if eyes == "look" else 0, front=True)
    # arms reach in over the lid; a raised paw pops up above its top edge
    for sx, up in ((-1, paws[0]), (1, paws[1])):
        leg(arms, (cx + 5 * sx, 12.2), (cx + 3.4 * sx, 13.0 if up else 17.5))
    top = 21 - lid
    if lid == 0:
        for y in range(19, 22):
            for x in range(8, 25):
                lap.put(x, y, "E" if y == 21 else "L")
    else:
        for y in range(top, 21):
            for x in range(8, 25):
                lap.put(x, y, "L")
        for x in range(7, 26):
            lap.put(x, 21, "E")
            lap.put(x, 22, "E")
    for l in (back, body, hd, arms, lap):
        l.outline()
    face(hd, (h[0], h[1], "closed" if eyes == "closed" else "open", True))
    hx, hy = int(h[0]), int(h[1])
    if eyes == "glow":
        # the screen reflected in both eyes
        g = "T" if flicker else "S"
        for ex in (hx - 3, hx - 2, hx + 2, hx + 3):
            hd.put(ex, hy - 1, g)
    elif eyes == "look":
        hd.put(hx - 2, hy - 1, "W")
        hd.put(hx + 3, hy - 1, "W")
    if lid >= 5:
        # fish logo, nose to the left
        fy = top + 2
        for dx, dy in ((0, 0), (1, -1), (1, 0), (1, 1), (2, -1), (2, 0), (2, 1), (3, 0), (4, -1), (4, 1)):
            lap.put(cx - 2 + dx, fy + dy, "W")
    return stack(back, body, hd, arms, lap)


# ------------------------------------------------------------ ninja
# Substitution jutsu (変わり身の術): the outfit only exists for the jutsu.
# Outfit switches (user pick 2026-09-25: suit + hood, "for now"). With both
# off it is just the headband and a mask on the orange tabby.
NINJA_SUIT = True   # navy suit, red sash; tail and paw tips stay out
NINJA_HOOD = True   # head wrapped too, leaving an eye slit and the ears


def suit(layer, col="N"):
    """Dress a layer: its orange goes suit-coloured; cream paw tips stay."""
    if NINJA_SUIT:
        layer.recolor(col, lambda x, y, c: c in ("B", "D"))


def hood(hd, h):
    if NINJA_HOOD:
        hx, hy = int(h[0]), int(h[1])
        hd.recolor("N", lambda x, y, col: col in ("B", "C", "P") and not (hy - 2 <= y <= hy) and y > hy - 5)

def ninja_gear(hd, gear, h, k, front):
    """Headband with a plate across the forehead, tails streaming back from
    the knot, and a mask over the lower face. Call before outlining."""
    hx, hy = int(h[0]), int(h[1])
    # mask: wraps the whole head below the eyes, front and side view alike
    # (covering only the snout in profile read as a surgical mask)
    hd.recolor("B", lambda x, y, col: col == "C" and y <= hy)  # no muzzle peeking over it
    hd.recolor("N", lambda x, y, col: y >= hy + 1 and col in ("B", "C", "P"))
    hd.recolor("N", lambda x, y, col: y == hy - 3 and col in ("B", "P"))
    if front:
        for x in range(hx - 2, hx + 3):
            for y in (hy - 4, hy - 3):
                hd.put(x, y, "M")
        hd.put(hx, hy - 4, "K")  # the village mark
        knot = (hx - 5, hy - 3)
    else:
        for x in range(hx + 1, hx + 4):
            for y in (hy - 4, hy - 3):
                hd.put(x, y, "M")
        hd.put(hx + 2, hy - 4, "K")
        knot = (hx - 4.5, hy - 3)
    gear.line([knot, (knot[0] - 3, knot[1] + 0.5 + k), (knot[0] - 6.5, knot[1] - 0.5 - k)], 1.2, "N")
    gear.line([(knot[0], knot[1] + 1), (knot[0] - 2.5, knot[1] + 2.5 - k), (knot[0] - 5, knot[1] + 3 + k)], 1.2, "N")


def ninja_eyes(hd, h, front):
    hx, hy = int(h[0]), int(h[1])
    if front:
        for ex in (hx - 3, hx + 2):
            hd.put(ex, hy - 1, "G"); hd.put(ex + 1, hy - 1, "W")
            hd.put(ex, hy, "K"); hd.put(ex + 1, hy, "K")
    else:
        hd.put(hx + 1, hy - 1, "G"); hd.put(hx + 2, hy - 1, "W")
        hd.put(hx + 1, hy, "K"); hd.put(hx + 2, hy, "K")


def seal(k=0):
    """Hand seal: face-on, sitting tall, paws pressed together in front of
    the chest, headband tails fluttering. k alternates the flutter."""
    back, body, hd, gear, arms = Canvas(), Canvas(), Canvas(), Canvas(), Canvas()
    cx = 16
    back.line([(21, 21.5), (25.5, 20.5), (27, 17.5), (26, 15)], 2.2, "B")  # tail
    body.disc(cx, 15.5, 6.4, 6.2, "B")
    if NINJA_SUIT:
        suit(body)
        body.recolor("U", lambda x, y, col: col == "N" and cx - 2 <= x <= cx + 1 and 12 <= y <= 17)  # jacket front
        body.recolor("A", lambda x, y, col: y in (17, 18))                                              # sash
    else:
        body.recolor("C", lambda x, y, col: col == "B" and cx - 2 <= x <= cx + 1 and 13 <= y <= 21)
    feet = Canvas()
    leg(feet, (cx - 3, 19), (cx - 3.5, 21.5), "B")
    leg(feet, (cx + 3, 19), (cx + 3.5, 21.5), "B")
    suit(feet)
    body.px.update(feet.px)
    h = head(hd, cx, 7.2, ears=1, front=True)
    ninja_gear(hd, gear, h, k, True)
    hood(hd, h)
    # forearms up, paws pressed together under the mask
    arms.line([(cx - 5.5, 16), (cx - 3, 14.5), (cx - 1, 13)], 2.2, "B")
    arms.line([(cx + 5.5, 16), (cx + 3, 14.5), (cx + 1, 13)], 2.2, "B")
    suit(arms)
    arms.disc(cx - 0.6, 12.6, 1.3, 1.7, "C")
    arms.disc(cx + 0.6, 12.6, 1.3, 1.7, "C")
    for l in (back, body, gear, hd, arms):
        l.outline()
    ninja_eyes(hd, h, True)
    return stack(back, body, gear, hd, arms)


def crouch(k=0):
    """Ninja landing: low on one knee, facing right, a front paw planted,
    tail up, headband tails streaming behind. k flutters them."""
    back, body, hd, gear, front = Canvas(), Canvas(), Canvas(), Canvas(), Canvas()
    back.line([(7, 15), (4, 12.5), (3.5, 9)], 2.4, "B")               # tail up
    far = Canvas()
    leg(far, (10, 17), (6.5, 21.5), "D")                              # far hind, shin flat
    leg(far, (19, 17), (21, 21.5), "D")                               # far front
    suit(far, "Z")
    back.px.update(far.px)                                            # (the tail stays orange)
    body.line([(9.5, 16.5), (18.5, 15.5)], 8.0, "B")                  # hunched low
    if NINJA_SUIT:
        suit(body)
        body.recolor("U", lambda x, y, col: col == "N" and y <= 13 and x >= 11)  # light along the back
        body.recolor("A", lambda x, y, col: x in (12, 13))                      # sash round the waist
    else:
        stripes(body, {10, 11, 14, 15}, 11, 14)
        belly(body, 19)
    h = head(hd, 22.5, 11.5, ears=1)
    ninja_gear(hd, gear, h, k, False)
    hood(hd, h)
    leg(front, (11.5, 18), (15.5, 21.5))                              # near knee on the floor
    leg(front, (15.5, 21.5), (10.5, 21.5))                            # ...shin back along it
    leg(front, (20, 17.5), (24, 21.5))                                # near front paw planted
    suit(front)
    for l in (back, body, gear, hd, front):
        l.outline()
    ninja_eyes(hd, h, False)
    return stack(back, body, gear, hd, front)


def log_prop(k=0):
    """What's left behind: a stubby cut log on the floor, rings on the cut
    end, a leaf sprouting on top. k rocks it (-1, 0, 1)."""
    bark, cut, leaf = Canvas(), Canvas(), Canvas()
    y0, t = 18, k * 0.9
    bark.line([(7.5, y0 - t), (22.5, y0 + t)], 7, "O")
    bark.recolor("Q", lambda x, y, col: col == "O" and (x + 2 * y) % 7 == 0)  # grain
    cut.disc(23.5, y0 + t, 2.7, 3.6, "R")
    cut.disc(23.5, y0 + t, 1.5, 2.0, "Q")
    cut.put(23.5, y0 + t, "R")
    leaf.line([(13, y0 - 3.5 - t * 0.4), (12.5, y0 - 6)], 1.1, "V")
    leaf.disc(14.5, y0 - 6.5, 1.8, 1.1, "V")
    for l in (bark, cut, leaf):
        l.outline()
    return stack(bark, cut, leaf)


def smoke(k):
    """ドロン! A burst that swells to cover the cat, then breaks into puffs
    and thins out. k = 0..4."""
    blobs = [
        [(16, 17, 4), (11, 19, 3), (21, 19, 3)],
        [(16, 14, 7), (9, 17, 5), (23, 17, 5), (16, 19.5, 5)],
        [(16, 12, 8.5), (7, 16, 6), (25, 16, 6), (11, 19.5, 5), (21, 19.5, 5), (16, 5.5, 5)],
        [(8, 10, 4.5), (24, 9, 4.5), (5, 18, 4), (27, 18, 4), (16, 4.5, 4), (16, 16, 3)],
        [(5, 7, 2.2), (27, 6, 2.2), (3, 16, 1.8), (29, 16, 1.8), (16, 2, 1.8)],
    ][k]
    c = Canvas()
    for bx, by, r in blobs:
        c.disc(bx + 0.6, by + 0.6, r, r * 0.85, "Y")  # shade peeks out bottom-right
    for bx, by, r in blobs:
        c.disc(bx - 0.3, by - 0.3, r * 0.92, r * 0.8, "F")
    c.outline("Y")
    return c


# ------------------------------------------------------------ animations
# name -> (frames, fps, loop). Facing right; QML mirrors for left.
ANIMS = {
    "sleep": ([loaf(b) for b in (0, 0, 1, 1)], 2, True),
    "sit": ([sit(), sit(), sit(), sit(eyes="closed")], 3, True),
    "stretch": ([stretch(0), stretch(0.5), stretch(1), stretch(1), stretch(0.5), stand()], 5, False),
    "walk": ([stand(phase=i / 6, bob=1 if i in (1, 4) else 0, tail=(1 if i < 3 else 0)) for i in range(6)], 9, True),
    "stand": ([stand()], 1, True),
    "held": ([dangle(0), dangle(1), dangle(0), dangle(-1)], 4, True),
    "fall": ([fall(0), fall(1)], 8, True),
    "alert": ([sit(eyes="wide", ears=1), sit(eyes="wide", ears=1, paw=True)], 3, True),
    "wallslide": ([wall(0), wall(1)], 6, True),
    # 2 frames at 3 fps: the switch lands near the apex of the ~0.65 s leap
    "leap": ([leap(0), leap(1)], 3, False),
    "laptop_open": ([laptop(0, eyes="look"), laptop(3, eyes="look"), laptop(5)], 5, False),
    "laptop": ([
        laptop(paws=(1, 0)), laptop(paws=(0, 1), flicker=True),
        laptop(paws=(1, 0)), laptop(paws=(0, 1), flicker=True),
        laptop(paws=(1, 0)), laptop(paws=(0, 1)),
        laptop(eyes="closed"), laptop(flicker=True),
        laptop(paws=(1, 0)), laptop(paws=(0, 1), flicker=True),
    ], 6, True),
    "laptop_look": ([laptop(eyes="look"), laptop(eyes="look", paws=(1, 0))], 2, True),
    "laptop_close": ([laptop(5), laptop(3, eyes="look"), laptop(0, eyes="look")], 5, False),
    # the walk cycle at a trot: hurrying to another monitor for a question
    "run": ([stand(phase=i / 6, bob=1 if i in (1, 4) else 0, tail=(1 if i < 3 else 0)) for i in range(6)], 16, True),
    # substitution jutsu: seal, POOF (a log is left behind), POOF, landing
    "ninja_seal": ([seal(0), seal(1)], 6, True),
    "ninja_crouch": ([crouch(0), crouch(1)], 6, True),
    # props, not cat poses: cat.qml plays these on their own
    "log": ([log_prop(0), log_prop(1), log_prop(-1)], 10, False),
    "smoke": ([smoke(k) for k in range(5)], 14, False),
}


def main():
    OUT.mkdir(exist_ok=True)
    cols = max(len(f) for f, _, _ in ANIMS.values())
    sheet = Image.new("RGBA", (W * cols, H * len(ANIMS)), (0, 0, 0, 0))
    meta = {}
    for row, (name, (frames, fps, loop)) in enumerate(ANIMS.items()):
        for i, fr in enumerate(frames):
            sheet.paste(fr.image(), (i * W, row * H))
        meta[name] = {"row": row, "frames": len(frames), "fps": fps, "loop": loop}
    sheet.save(OUT / "cat_sheet.png")
    # pre-scaled copy for the view: AnimatedSprite has no nearest-neighbour
    # option, so the pixels are made crisp here instead
    sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(OUT / "cat_sheet_3x.png")
    (OUT / "cat_sheet.json").write_text(json.dumps(meta, indent=2) + "\n")

    # contact sheet for humans: 8x, labelled, on a light floor
    S, lab = 8, 90
    prev = Image.new("RGBA", (lab + W * S * cols, H * S * len(ANIMS)), (236, 232, 222, 255))
    d = ImageDraw.Draw(prev)
    for row, name in enumerate(ANIMS):
        d.text((6, row * H * S + H * S // 2 - 6), name, fill=(40, 30, 25, 255))
        for i in range(ANIMS[name][0].__len__()):
            cell = sheet.crop((i * W, row * H, (i + 1) * W, (row + 1) * H)).resize((W * S, H * S), Image.NEAREST)
            prev.alpha_composite(cell, (lab + i * W * S, row * H * S))
        d.line([(lab, (row + 1) * H * S - 1), (prev.width, (row + 1) * H * S - 1)], fill=(200, 194, 180, 255))
    prev.save(OUT / "preview.png")

    # animated preview: each animation for ~2 s, in order
    gif = []
    durs = []
    for name, (frames, fps, loop) in ANIMS.items():
        reps = max(1, round(2 * fps / len(frames))) if loop else 1
        for _ in range(reps):
            for fr in frames:
                bg = Image.new("RGBA", (W * S, H * S + 20), (236, 232, 222, 255))
                bg.alpha_composite(fr.image().resize((W * S, H * S), Image.NEAREST), (0, 20))
                ImageDraw.Draw(bg).text((6, 4), name, fill=(40, 30, 25, 255))
                gif.append(bg.convert("P", palette=Image.ADAPTIVE))
                durs.append(int(1000 / fps))
        if not loop:
            durs[-1] = 900
    gif[0].save(OUT / "preview.gif", save_all=True, append_images=gif[1:], duration=durs, loop=0, disposal=2)
    print(f"wrote {OUT}/cat_sheet.png, {len(ANIMS)} animations")


if __name__ == "__main__":
    main()
