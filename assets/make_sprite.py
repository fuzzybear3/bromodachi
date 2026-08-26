#!/usr/bin/env python3
"""Render the bromodachi pixel sprite(s) to PNG. No dependencies."""
import struct
import zlib
from pathlib import Path

PALETTE = {
    ".": (0, 0, 0, 0),           # transparent
    "K": (0x2B, 0x21, 0x1B, 255),  # outline / dark
    "O": (0xE8, 0x96, 0x4A, 255),  # shiba orange
    "C": (0xF9, 0xE4, 0xC2, 255),  # cream
    "P": (0xF0, 0x8F, 0x8F, 255),  # pink (inner ear, blush)
    "W": (0xFF, 0xFF, 0xFF, 255),  # eye catchlight
}

HEAD_TOP = [
    "..KK............KK..",
    ".KOOK..........KOOK.",
    ".KOPOK........KOPOK.",
    ".KOPPOKKKKKKKKOPPOK.",
    ".KOOOOOOOOOOOOOOOOK.",
    "KOOOOOOOOOOOOOOOOOOK",
    "KOOOOOOOOOOOOOOOOOOK",
    "KOOOCCOOOOOOOOCCOOOK",
]

EYES_OPEN = [
    "KOOOKWOOOOOOOOKWOOOK",
    "KOOOKKOOOOOOOOKKOOOK",
]

EYES_CLOSED = [
    "KOOOOOOOOOOOOOOOOOOK",
    "KOOOKKOOOOOOOOKKOOOK",
]

HEAD_BOTTOM = [
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


def write_png(path: Path, rows: list[str], scale: int = 1) -> None:
    width = len(rows[0])
    for r in rows:
        assert len(r) == width, f"bad row length: {r!r}"
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
write_png(here / "buddy.png", HEAD_TOP + EYES_OPEN + HEAD_BOTTOM)
write_png(here / "buddy_blink.png", HEAD_TOP + EYES_CLOSED + HEAD_BOTTOM)
write_png(here / "buddy_preview.png", HEAD_TOP + EYES_OPEN + HEAD_BOTTOM, scale=24)
