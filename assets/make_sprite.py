#!/usr/bin/env python3
"""Render the bromodachi pixel sprites to PNG. No dependencies.

Each character is a 20x22 ASCII grid, one letter per pixel, mapped through
PALETTE. Every character gets <name>.png, <name>_blink.png, and a 24x
<name>_preview.png.
"""
import struct
import zlib
from pathlib import Path

PALETTE = {
    ".": (0, 0, 0, 0),             # transparent
    "K": (0x2B, 0x21, 0x1B, 255),  # outline / dark
    "W": (0xFF, 0xFF, 0xFF, 255),  # eye catchlight
    # shiba
    "O": (0xE8, 0x96, 0x4A, 255),  # orange
    "C": (0xF9, 0xE4, 0xC2, 255),  # cream
    "P": (0xF0, 0x8F, 0x8F, 255),  # pink
    # robot
    "M": (0x9A, 0xA5, 0xB1, 255),  # light metal
    "D": (0x5C, 0x66, 0x70, 255),  # dark metal / screen
    "B": (0x5C, 0xC9, 0xF0, 255),  # blue glow
    "Y": (0xF0, 0xC4, 0x19, 255),  # yellow
    "G": (0x66, 0xBB, 0x6A, 255),  # green button
    # ninja
    "N": (0x46, 0x4C, 0x66, 255),  # navy suit
    "S": (0xF0, 0xC8, 0xA0, 255),  # skin
    "R": (0xD9, 0x53, 0x4F, 255),  # red band / belt
}

# ---------------------------------------------------------------- shiba
SHIBA_TOP = [
    "..KK............KK..",
    ".KOOK..........KOOK.",
    ".KOPOK........KOPOK.",
    ".KOPPOKKKKKKKKOPPOK.",
    ".KOOOOOOOOOOOOOOOOK.",
    "KOOOOOOOOOOOOOOOOOOK",
    "KOOOOOOOOOOOOOOOOOOK",
    "KOOOCCOOOOOOOOCCOOOK",
]
SHIBA_EYES_OPEN = [
    "KOOOKWOOOOOOOOKWOOOK",
    "KOOOKKOOOOOOOOKKOOOK",
]
SHIBA_EYES_CLOSED = [
    "KOOOOOOOOOOOOOOOOOOK",
    "KOOOKKOOOOOOOOKKOOOK",
]
SHIBA_BOTTOM = [
    "KOPOOOCCCCCCCCOOOPOK",
    "KOOOOCCCCKKCCCCOOOOK",
    ".KOOOCCCCCCCCCCOOOK.",
    ".KOOOOCCCCCCCCOOOOK.",
    "..KKOOOOOOOOOOOOKK..",
    ".KOOOOCCCCCCCCOOOOK.",
    "KOOOOOCCCCCCCCOOOOOK",
    "KOOOOOCCCCCCCCOOOOOK",
    "KOOOOCCCCCCCCCCOOOOK",
    "KOOOCCCCCCCCCCCCOOOK",
    ".KOOCCKCCCCCCKCCOOK.",
    "..KKKKKKKKKKKKKKKK..",
]

# ---------------------------------------------------------------- robot
ROBOT_TOP = [
    "........KYYK........",
    ".........KK.........",
    "...KKKKKKKKKKKKKK...",
    "..KMMMMMMMMMMMMMMK..",
    ".KMMDDDDDDDDDDDDMMK.",
]
ROBOT_EYES_ON = [
    ".KMDDBBDDDDDDBBDDMK.",
    ".KMDDBBDDDDDDBBDDMK.",
]
ROBOT_EYES_OFF = [
    ".KMDDDDDDDDDDDDDDMK.",
    ".KMDDDDDDDDDDDDDDMK.",
]
ROBOT_BOTTOM = [
    ".KMDDDDDDDDDDDDDDMK.",
    ".KMDDDBBBBBBBBDDDMK.",
    ".KMMDDDDDDDDDDDDMMK.",
    "..KMMMMMMMMMMMMMMK..",
    "...KKKKKKKKKKKKKK...",
    "......KMMMMMMK......",
    "..KKKKKKKKKKKKKKKK..",
    ".KMMMMMMMMMMMMMMMMK.",
    ".KMMDDDDDDDDDDDDMMK.",
    ".KMMDRDGDYDDDDDDMMK.",
    ".KMMDDDDDDDDDDDDMMK.",
    ".KMMMMMMMMMMMMMMMMK.",
    "..KKKKKKKKKKKKKKKK..",
    "...KMMK......KMMK...",
    "..KKKKK......KKKKK..",
]

# ---------------------------------------------------------------- ninja
NINJA_TOP = [
    "......KKKKKKKK......",
    "....KKNNNNNNNNKK....",
    "...KNNNNNNNNNNNNK...",
    "..KNNNNNNNNNNNNNNK..",
    "..KNRRRRRRRRRRRRNKR.",
    "..KNRRRRRRRRRRRRNK.R",
    "..KNSSSSSSSSSSSSNK..",
]
NINJA_EYES_OPEN = [
    "..KNSKKSSSSSSKKSNK..",
    "..KNSKWSSSSSSKWSNK..",
]
NINJA_EYES_CLOSED = [
    "..KNSSSSSSSSSSSSNK..",
    "..KNSKKSSSSSSKKSNK..",
]
NINJA_BOTTOM = [
    "..KNNNNNNNNNNNNNNK..",
    "..KNNNNNNNNNNNNNNK..",
    "...KNNNNNNNNNNNNK...",
    "....KKNNNNNNNNKK....",
    "...KKNNNNNNNNNNKK...",
    "..KNNNNNNNNNNNNNNK..",
    "..KNNRRRRRRRRRRNNK..",
    "..KNNNNNNNNNNNNNNK..",
    "..KNNNNNNNNNNNNNNK..",
    "...KNNNNKKKKNNNNK...",
    "...KNNNNK..KNNNNK...",
    "...KNNNNK..KNNNNK...",
    "....KKKK....KKKK....",
]

CHARACTERS = {
    "shiba": {
        "open": SHIBA_TOP + SHIBA_EYES_OPEN + SHIBA_BOTTOM,
        "blink": SHIBA_TOP + SHIBA_EYES_CLOSED + SHIBA_BOTTOM,
    },
    "robot": {
        "open": ROBOT_TOP + ROBOT_EYES_ON + ROBOT_BOTTOM,
        "blink": ROBOT_TOP + ROBOT_EYES_OFF + ROBOT_BOTTOM,
    },
    "ninja": {
        "open": NINJA_TOP + NINJA_EYES_OPEN + NINJA_BOTTOM,
        "blink": NINJA_TOP + NINJA_EYES_CLOSED + NINJA_BOTTOM,
    },
}


def write_png(path: Path, rows: list[str], scale: int = 1) -> None:
    width = len(rows[0])
    for r in rows:
        assert len(r) == width, f"bad row length ({len(r)} != {width}): {r!r}"
    raw = b""
    for r in rows:
        scanline = b"\x00" + b"".join(bytes(PALETTE[ch]) * scale for ch in r)
        raw += scanline * scale
    width *= scale

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, len(rows) * scale, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    path.write_bytes(png)
    print(f"wrote {path} ({width}x{len(rows) * scale})")


here = Path(__file__).parent
for name, frames in CHARACTERS.items():
    for grid in frames.values():
        assert len(grid) == 22, f"{name}: expected 22 rows, got {len(grid)}"
    write_png(here / f"{name}.png", frames["open"])
    write_png(here / f"{name}_blink.png", frames["blink"])
    write_png(here / f"{name}_preview.png", frames["open"], scale=24)
