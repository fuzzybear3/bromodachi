#!/usr/bin/env python3
"""Render the Gitea buddy: a chibi Naruto on the same rig as the cat.

Same idea as make_cat.py (whose Canvas and helpers this borrows): every
frame is primitives drawn in layers, outlined per layer, then stacked, so a
pose is a handful of numbers. Cells are 32x32 (he stands taller than the
cat is long), facing right; the view mirrors for left.

Outputs (next to this file):
  naruto/naruto_sheet.png, naruto_sheet_3x.png   one row per animation
  naruto/naruto_sheet.json   {anim: {row, frames, fps, loop}}
  naruto/preview.png         6x contact sheet, labelled
"""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

import make_cat
from make_cat import Canvas, PALETTE, stack

W, H = 32, 32
OUT = Path(__file__).parent / "naruto"
FLOOR = 30.5  # where his sandals stand

PALETTE.update({
    "o": (0xF2, 0x8C, 0x28, 255),  # jumpsuit orange
    "r": (0xC9, 0x6A, 0x14, 255),  # jumpsuit shade, far limbs
    "s": (0xFA, 0xD9, 0xB5, 255),  # skin
    "h": (0xF8, 0xD8, 0x3A, 255),  # hair
    "b": (0x2F, 0x5F, 0xB3, 255),  # blue: shoulders, sandals, eyes
    "w": (0xFF, 0xFF, 0xFF, 255),  # collar, bowl, eye white
    "c": (0x6F, 0xC8, 0xF5, 255),  # rasengan
    "n": (0xE8, 0xC8, 0x8A, 255),  # noodles
    "g": (0xB5, 0x3A, 0x2E, 255),  # ramen bowl red, the knocked-out bump
})


def cv():
    return Canvas(W, H)


# ------------------------------------------------------------ parts
def head(hd, hair, hx, hy, eyes="open", mouth="smile", front=False):
    """Big chibi head at (hx, hy): spiky hair, forehead protector, whisker
    marks. Side view looks right; front=True is face-on (dangling, eating).
    Returns what face() needs; call that after outlining."""
    # hair: a cap over the top and spikes fanning out behind and above it
    if front:
        spikes = [((-6, -2), (-10, -6), (-3, -5)), ((-4, -4), (-6, -11), (-1, -6)),
                  ((-2, -5), (0, -12), (2, -5)), ((1, -6), (6, -11), (4, -4)),
                  ((3, -5), (10, -6), (6, -2)), ((-6, 0), (-10, 1), (-6, -3)), ((6, 0), (10, 1), (6, -3))]
    else:
        spikes = [((-6, 1), (-10.5, 0), (-6, -3)), ((-6, -2), (-10, -6), (-3, -5)),
                  ((-4, -4), (-5.5, -11), (-0.5, -6)), ((-1.5, -5), (1, -12), (3, -5)),
                  ((2, -5), (6.5, -10), (5.5, -3))]
    for a, b, c in spikes:
        hair.tri((hx + a[0], hy + a[1]), (hx + b[0], hy + b[1]), (hx + c[0], hy + c[1]), "h")
    hd.disc(hx, hy, 6.2, 5.8, "s")
    hd.disc(hx - (0 if front else 0.6), hy - 3.2, 6.2, 3.6, "h", where=lambda x, y: y <= hy - 2)
    # forehead protector: cloth band, metal plate with the leaf mark
    hd.recolor("N", lambda x, y, col: int(hy) - 3 <= y <= int(hy) - 2)
    plate = range(int(hx) - 3, int(hx) + 4) if front else range(int(hx), int(hx) + 6)
    for x in plate:
        for y in (int(hy) - 3, int(hy) - 2):
            if (x, y) in hd.px:
                hd.px[(x, y)] = "M"
    return (hx, hy, eyes, mouth, front)


def face(hd, f):
    hx, hy, eyes, mouth, front = f
    hx, hy = int(hx), int(hy)
    cx = hx if front else hx + 2
    hd.put(cx + (0 if front else 1), hy - 3, "K")  # leaf mark on the plate

    def eye(ex):
        if eyes == "closed":
            hd.put(ex, hy + 1, "K"); hd.put(ex + 1, hy + 1, "K")
        elif eyes == "happy":  # ^ ^
            hd.put(ex, hy + 1, "K"); hd.put(ex + 1, hy, "K")
        elif eyes == "swirl":  # knocked out
            hd.put(ex, hy, "K"); hd.put(ex + 1, hy + 1, "K"); hd.put(ex + 1, hy, "w"); hd.put(ex, hy + 1, "w")
        elif eyes == "wide":
            hd.put(ex, hy, "w"); hd.put(ex + 1, hy, "w"); hd.put(ex, hy + 1, "b"); hd.put(ex + 1, hy + 1, "K")
        else:
            hd.put(ex, hy, "b"); hd.put(ex + 1, hy, "w"); hd.put(ex, hy + 1, "K"); hd.put(ex + 1, hy + 1, "b")

    if front:
        eye(hx - 4); eye(hx + 2)
        for sx in (-1, 1):  # whisker marks on both cheeks
            for dy in (2, 4):
                hd.put(hx + sx * 5, hy + dy, "K"); hd.put(hx + sx * 4, hy + dy, "K")
        mx = hx - 1
    else:
        eye(hx + 2)
        for dy in (2, 4):  # whisker marks on the cheek
            hd.put(hx - 1, hy + dy, "K"); hd.put(hx, hy + dy, "K")
        mx = hx + 3
    if mouth == "smile":
        hd.put(mx, hy + 3, "K"); hd.put(mx + 1, hy + 3, "K")
    elif mouth == "grin":
        hd.put(mx - 1, hy + 3, "K"); hd.put(mx, hy + 3, "w"); hd.put(mx + 1, hy + 3, "w"); hd.put(mx + 2, hy + 3, "K")
        hd.put(mx, hy + 4, "K"); hd.put(mx + 1, hy + 4, "K")
    elif mouth == "open":
        hd.put(mx, hy + 3, "K"); hd.put(mx + 1, hy + 3, "K"); hd.put(mx, hy + 4, "g"); hd.put(mx + 1, hy + 4, "K")
    elif mouth == "flat":
        hd.put(mx, hy + 3, "K")


def band_tails(c, hx, hy, k=0, back=True):
    """The headband's tails, streaming behind the knot."""
    if back:
        c.line([(hx - 6, hy - 2.5), (hx - 9, hy - 0.5 + k), (hx - 11, hy + 1.5 - k)], 1.2, "N")
        c.line([(hx - 6, hy - 2), (hx - 8.5, hy + 2 - k), (hx - 9.5, hy + 4.5 + k)], 1.2, "N")


def torso(c, bx, by, lean=0):
    """Jumpsuit top: a compact orange block with blue shoulders and a white
    collar. (bx, by) is its centre; lean shifts the shoulders forward."""
    c.disc(bx + lean * 0.5, by, 3.9, 4.3, "o")
    c.disc(bx + lean, by - 1.5, 3.7, 2.8, "o")
    c.recolor("b", lambda x, y, col: col == "o" and y <= by - 2.6)
    c.recolor("w", lambda x, y, col: col == "b" and y <= by - 3.8 and abs(x + 0.5 - bx - lean) <= 2.2)


def limb(c, *pts, col="o", end="s", w=2.3):
    """An arm or a leg: sleeve/trouser along the points (an elbow or knee
    is just a middle point), a hand or sandal at the last one."""
    c.line(list(pts), w, col)
    if end:
        x, y = pts[-1]
        c.put(x, y, end)
        c.put(x + 0.6, y, end)


# ------------------------------------------------------------ poses
def stand(eyes="open", mouth="smile", arms=0, k=0):
    """Standing, facing right. arms: 0 at his sides, 1 hands on his head
    (worried), 2 scratching his head (confused), 3 thumbs-up."""
    back, body, hair, hd, front = cv(), cv(), cv(), cv(), cv()
    bx, by, hx, hy = 15.5, 22, 16.5, 11 + (k if arms == 0 else 0)
    limb(back, (bx - 1.8, by + 3.5), (bx - 1.8, FLOOR), col="r", end="b")      # far leg
    if arms == 1:    # far hand on his head, elbow out behind
        limb(back, (bx - 2.5, by - 2.5), (bx - 7.5, by - 5 + k), (hx - 6, hy - 4), col="r")
    else:
        limb(back, (bx - 2.8, by - 2.5), (bx - 4.5, by + 2.5), col="r")
    band_tails(back, hx, hy, k)
    torso(body, bx, by)
    limb(front, (bx + 1.8, by + 3.5), (bx + 1.8, FLOOR), col="o", end="b")     # near leg
    f = head(hd, hair, hx, hy, eyes, mouth)
    arm = cv()
    if arms == 1:    # near hand on his head, elbow out front
        limb(arm, (bx + 2.5, by - 2.5), (bx + 8.5, by - 5 + k), (hx + 6, hy - 4))
    elif arms == 2:  # scratching the top of his head
        limb(arm, (bx + 2.5, by - 2.5), (bx + 9, by - 6), (hx + 5 - k, hy - 6))
    elif arms == 3:  # thumbs-up, out front
        limb(arm, (bx + 2.5, by - 2.5), (bx + 8, by - 3.5 - k))
        arm.put(bx + 8, by - 5.2 - k, "s")
    else:
        limb(arm, (bx + 2.8, by - 2.5), (bx + 4.5, by + 2.5))
    for l in (back, body, hair, hd, front, arm):
        l.outline()
    face(hd, f)
    if arms == 1:  # a drop of sweat
        hd.put(hx - 9, hy - 6 + k, "c"); hd.put(hx - 9, hy - 5 + k, "c")
    if arms == 2:  # ?
        for dx, dy in ((0, 0), (1, 0), (2, 1), (1, 2), (1, 4)):
            hd.put(hx - 11 + dx, hy - 10 + dy + k, "K")
    return stack(back, hair, front, body, hd, arm)


def walk(phase, run=False):
    """Walking; run=True is the lean-forward, arms-trailing ninja run."""
    back, body, hair, hd, front, arm = cv(), cv(), cv(), cv(), cv(), cv()
    a = 2 * math.pi * phase
    stride = 4.6 if run else 2.6
    lean = 2.4 if run else 0
    bob = 1 if math.cos(2 * a) > 0.3 else 0
    bx, by = 14.5, 22 + bob
    hx, hy = bx + 1 + lean * 1.4, 11 + bob + (1 if run else 0)
    for off, near in ((math.pi, False), (0, True)):
        fx = bx + (1.8 if near else -1.8) + stride * math.sin(a + off)
        fy = FLOOR - (2.2 if math.cos(a + off) > 0.2 else 0)
        limb(front if near else back, (bx + (1.8 if near else -1.8), by + 3.5), (fx, fy),
             col="o" if near else "r", end="b")
    if run:  # both arms straight out behind him
        limb(back, (bx - 1, by - 3), (bx - 8, by - 3.5), col="r", w=2.0)
        limb(arm, (bx + 1, by - 1.5), (bx - 6.5, by + 0.5), w=2.0)
    else:
        sw = 2.2 * math.sin(a)
        limb(back, (bx - 2.8, by - 2.5), (bx - 4 - sw, by + 2.5), col="r")
        limb(arm, (bx + 2.8, by - 2.5), (bx + 4 + sw, by + 2.5))
    band_tails(back, hx, hy, bob)
    torso(body, bx, by, lean)
    f = head(hd, hair, hx, hy, "open", "grin" if run else "smile")
    for l in (back, body, hair, hd, front, arm):
        l.outline()
    face(hd, f)
    return stack(back, hair, front, body, hd, arm)


def sit_ramen(k):
    """Idle: cross-legged with a bowl of ramen. k: 0 noodles lifted,
    1 slurping, 2 mouth full and happy."""
    back, body, hair, hd, front = cv(), cv(), cv(), cv(), cv()
    bx, by, hx, hy = 13.5, 24.5, 14.5, 14
    band_tails(back, hx, hy, k % 2)
    body.line([(bx - 4, FLOOR - 0.5), (bx + 6, FLOOR - 0.5)], 3.2, "o")       # crossed legs
    body.put(bx + 7, FLOOR, "b"); body.put(bx - 5, FLOOR, "b")
    torso(body, bx, by - 0.5)
    f = head(hd, hair, hx, hy, "happy" if k == 2 else "open", "flat" if k == 2 else "open")
    # the bowl, held out front; chopsticks lifting noodles to his mouth
    front.disc(bx + 9, by + 2.5, 4.2, 2.6, "w", where=lambda x, y: y >= by + 1.5)
    front.recolor("g", lambda x, y, col: col == "w" and y >= by + 3.5)
    limb(front, (bx + 2, by - 2.5), (bx + 6, by + 3))
    lift = (hy + 4, hy + 5.5, by + 1)[k]
    if k < 2:
        front.line([(bx + 8.5, by + 1.5), (bx + 7.5, lift)], 1.6, "n")
    front.line([(bx + 11, by - 1), (bx + 7, lift - 0.5)], 1.0, "K")
    for l in (back, body, hair, hd):
        l.outline()
    front.outline()
    face(hd, f)
    return stack(back, hair, body, hd, front)


def sleep(k):
    """Idle: asleep sitting up, head drooped, a bubble at his nose."""
    back, body, hair, hd, front = cv(), cv(), cv(), cv(), cv()
    bx, by, hx, hy = 13.5, 24.5, 15.5, 15.5 + k * 0.5
    band_tails(back, hx, hy)
    body.line([(bx - 4, FLOOR - 0.5), (bx + 6, FLOOR - 0.5)], 3.2, "o")
    body.put(bx + 7, FLOOR, "b"); body.put(bx - 5, FLOOR, "b")
    torso(body, bx, by - 0.5)
    limb(front, (bx + 2, by - 2.5), (bx + 4, by + 3))
    f = head(hd, hair, hx, hy, "closed", "flat")
    for l in (back, body, hair, hd, front):
        l.outline()
    face(hd, f)
    hd.disc(hx + 8, hy + 2, 1.2 + k, 1.2 + k, "c")  # the bubble swells as he breathes
    return stack(back, hair, body, hd, front)


def rasengan(size, k):
    """A run is going: a Rasengan spinning up in his palm. size 0..2 grows
    with the run's progress, k spins it."""
    back, body, hair, hd, front, orb = cv(), cv(), cv(), cv(), cv(), cv()
    bx, by, hx, hy = 13, 22, 14, 11
    limb(back, (bx - 1.8, by + 3.5), (bx - 3, FLOOR), col="r", end="b")
    band_tails(back, hx, hy, k)
    torso(body, bx, by, 0.5)
    limb(body, (bx + 1.8, by + 3.5), (bx + 3.5, FLOOR), col="o", end="b")
    f = head(hd, hair, hx, hy, "open", "grin")
    r = (2.2, 3.4, 4.6)[size]
    ox, oy = bx + 9.5, by - 1 - r
    limb(front, (bx + 2, by - 2), (ox - 1, oy + r + 1))                  # palm under it
    limb(back, (bx - 1, by - 2), (ox - r - 0.5, oy - 0.5 + k), col="r")      # other hand shaping it
    orb.disc(ox, oy, r, r, "c")
    for i in range(3):  # the spin
        a = k * 1.3 + i * 2.1
        orb.line([(ox, oy), (ox + (r - 0.8) * math.cos(a), oy + (r - 0.8) * math.sin(a))], 1.0, "w")
    orb.put(ox, oy, "w")
    for l in (back, body, hair, hd, front):
        l.outline()
    orb.outline("b")
    face(hd, f)
    return stack(back, hair, body, hd, front, orb)


def cheer(k):
    """Passed! A hop with a fist in the air."""
    back, body, hair, hd, front = cv(), cv(), cv(), cv(), cv()
    up = 3 * k
    bx, by, hx, hy = 15.5, 23 - up, 16.5, 12 - up
    limb(back, (bx - 1, by + 3), (bx - 3, FLOOR - up * 0.6), col="r", end="b")
    limb(back, (bx - 2, by - 2), (bx - 5, by + 1), col="r")
    band_tails(back, hx, hy, k)
    torso(body, bx, by)
    limb(body, (bx + 1.5, by + 3), (bx + 4, FLOOR - up * 0.6), col="o", end="b")
    f = head(hd, hair, hx, hy, "happy", "grin")
    limb(front, (bx + 2, by - 2), (bx + 6, by - 9 - k))                  # fist up
    for l in (back, body, hair, hd, front):
        l.outline()
    face(hd, f)
    return stack(back, hair, body, hd, front)


def knocked(k):
    """A workflow failed: flat on his back, eyes spinning."""
    back, body, hair, hd, front = cv(), cv(), cv(), cv(), cv()
    y = FLOOR - 2.5
    limb(body, (15, y), (22, y - 1 - k), col="o", end="b")                      # legs up in the air
    limb(body, (15, y + 0.5), (23, y + 1.5), col="r", end="b")
    body.line([(10, y), (16, y)], 6.5, "o")
    limb(front, (12, y - 2), (9, y - 6 + k))                             # an arm flung up
    f = head(hd, hair, 6.5, y - 3, "swirl", "open", front=True)
    for l in (back, body, hair, hd, front):
        l.outline()
    face(hd, f)
    for i in range(2):  # stars circling
        a = k * math.pi + i * math.pi
        hd.put(6.5 + 7 * math.cos(a), y - 12 + 1.5 * math.sin(a), "h")
    return stack(back, hair, body, hd, front)


def seal(k):
    """Shadow-clone seal: fingers crossed in front of him."""
    back, body, hair, hd, front = cv(), cv(), cv(), cv(), cv()
    bx, by, hx, hy = 15.5, 23, 16.5, 12
    limb(back, (bx - 1, by + 3), (bx - 3, FLOOR), col="r", end="b")
    band_tails(back, hx, hy, k)
    torso(body, bx, by)
    limb(body, (bx + 1.5, by + 3), (bx + 4, FLOOR), col="o", end="b")
    f = head(hd, hair, hx, hy, "open", "flat")
    limb(front, (bx - 1, by - 1.5), (bx + 5, by - 1), col="r")
    limb(front, (bx + 2, by - 2), (bx + 5, by - 1.5))
    front.line([(bx + 5.5, by - 4), (bx + 5.5, by + 0.5)], 1.2, "s")     # the crossed fingers
    front.line([(bx + 4, by - 2), (bx + 7.5, by - 2)], 1.2, "s")
    for l in (back, body, hair, hd, front):
        l.outline()
    face(hd, f)
    return stack(back, hair, body, hd, front)


def dangle(sway=0):
    """Held by the collar: face-on, limp, not pleased."""
    back, body, hair, hd, front = cv(), cv(), cv(), cv(), cv()
    cx, hy = 16, 9
    limb(back, (cx - 2, 23), (cx - 2.5 + sway * 0.6, 29), col="r", end="b")
    limb(back, (cx + 2, 23), (cx + 2.5 + sway * 0.6, 29), col="r", end="b")
    torso(body, cx, 20)
    limb(front, (cx - 3.5, 17.5), (cx - 5 + sway * 0.5, 23))
    limb(front, (cx + 3.5, 17.5), (cx + 5 + sway * 0.5, 23))
    f = head(hd, hair, cx, hy, "closed", "flat", front=True)
    for l in (back, body, hair, hd, front):
        l.outline()
    face(hd, f)
    return stack(back, hair, body, hd, front)


def air(k, kind="fall"):
    """Mid-air. fall: flailing; leap: k=0 on the way up (arms up), k=1 on
    the way down (knees tucking)."""
    back, body, hair, hd, front = cv(), cv(), cv(), cv(), cv()
    bx, by, hx, hy = 15.5, 20, 16.5, 9
    if kind == "fall":
        limb(back, (bx - 1, by + 3), (bx - 5 - k, by + 7), col="r", end="b")
        limb(back, (bx - 2, by - 2), (bx - 7, by - 5 + 2 * k), col="r")
        torso(body, bx, by)
        limb(body, (bx + 1.5, by + 3), (bx + 6 + k, by + 6), col="o", end="b")
        f = head(hd, hair, hx, hy, "wide", "open")
        limb(front, (bx + 2, by - 2), (bx + 8, by - 6 + 2 * (1 - k)))
    else:
        tuck = 3 * k
        limb(back, (bx - 1, by + 3), (bx - 4 + tuck, by + 8 - tuck), col="r", end="b")
        limb(back, (bx - 2, by - 2), (bx - 5, by - 6 + 5 * k), col="r")
        torso(body, bx, by, 1)
        limb(body, (bx + 1.5, by + 3), (bx + 4 - tuck * 0.3, by + 8 - tuck * 0.5), col="o", end="b")
        f = head(hd, hair, hx, hy, "open", "grin")
        limb(front, (bx + 2, by - 2), (bx + 6, by - 7 + 6 * k))
    band_tails(back, hx, hy, k)
    for l in (back, body, hair, hd, front):
        l.outline()
    face(hd, f)
    return stack(back, hair, body, hd, front)


# ------------------------------------------------------------ animations
# name -> (frames, fps, loop). Facing right; the view mirrors for left.
ANIMS = {
    "stand": ([stand(), stand(), stand(), stand(eyes="closed")], 3, True),
    "walk": ([walk(i / 6) for i in range(6)], 9, True),
    # also his wall-run: the view turns it a quarter so his feet are on the wall
    "run": ([walk(i / 6, run=True) for i in range(6)], 14, True),
    "ramen": ([sit_ramen(0), sit_ramen(1), sit_ramen(1), sit_ramen(2), sit_ramen(2)], 3, True),
    "sleep": ([sleep(0), sleep(0), sleep(1), sleep(1)], 2, True),
    "rasengan1": ([rasengan(0, k) for k in range(3)], 8, True),
    "rasengan2": ([rasengan(1, k) for k in range(3)], 8, True),
    "rasengan3": ([rasengan(2, k) for k in range(3)], 8, True),
    "cheer": ([cheer(0), cheer(1), cheer(1), cheer(0)], 6, True),
    "thumbs": ([stand(eyes="happy", mouth="grin", arms=3, k=0), stand(eyes="happy", mouth="grin", arms=3, k=1)], 3, True),
    "knocked": ([knocked(0), knocked(1)], 3, True),
    "worried": ([stand(eyes="wide", mouth="open", arms=1, k=0), stand(eyes="wide", mouth="open", arms=1, k=1)], 3, True),
    "confused": ([stand(eyes="open", mouth="flat", arms=2, k=0), stand(eyes="open", mouth="flat", arms=2, k=1)], 2, True),
    "seal": ([seal(0), seal(1)], 6, True),
    "held": ([dangle(0), dangle(1), dangle(0), dangle(-1)], 4, True),
    "fall": ([air(0), air(1)], 8, True),
    "leap": ([air(0, "leap"), air(1, "leap")], 3, False),
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
    sheet.save(OUT / "naruto_sheet.png")
    sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(OUT / "naruto_sheet_3x.png")
    (OUT / "naruto_sheet.json").write_text(json.dumps(meta, indent=2) + "\n")

    S, lab = 6, 90
    prev = Image.new("RGBA", (lab + W * S * cols, H * S * len(ANIMS)), (236, 232, 222, 255))
    d = ImageDraw.Draw(prev)
    for row, name in enumerate(ANIMS):
        d.text((6, row * H * S + H * S // 2 - 6), name, fill=(40, 30, 25, 255))
        for i in range(len(ANIMS[name][0])):
            cell = sheet.crop((i * W, row * H, (i + 1) * W, (row + 1) * H)).resize((W * S, H * S), Image.NEAREST)
            prev.alpha_composite(cell, (lab + i * W * S, row * H * S))
        d.line([(lab, (row + 1) * H * S - 1), (prev.width, (row + 1) * H * S - 1)], fill=(200, 194, 180, 255))
    prev.save(OUT / "preview.png")
    print(f"wrote {OUT}/naruto_sheet.png, {len(ANIMS)} animations")


if __name__ == "__main__":
    main()
