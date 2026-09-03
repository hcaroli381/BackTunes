#!/usr/bin/env python3
"""Generates the BackTunes app icon (1024x1024 PNG) and the silent
keep-alive WAV used for background playback. No external dependencies.

Usage:  python3 Tools/generate_assets.py
"""

import struct
import wave
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON_PATH = ROOT / "BackTunes" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon1024.png"
WAV_PATH = ROOT / "BackTunes" / "Resources" / "silence.wav"


# ---------------------------------------------------------------- geometry

def in_rounded_rect(x, y, x0, y0, x1, y1, r):
    if x < x0 or x > x1 or y < y0 or y > y1:
        return False
    dx = max(x0 + r - x, 0, x - (x1 - r))
    dy = max(y0 + r - y, 0, y - (y1 - r))
    return dx * dx + dy * dy <= r * r


def in_circle(x, y, cx, cy, radius):
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius


def in_triangle(x, y, p0, p1, p2):
    def edge(a, b):
        return (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0])

    d1, d2, d3 = edge(p0, p1), edge(p1, p2), edge(p2, p0)
    has_neg = d1 < 0 or d2 < 0 or d3 < 0
    has_pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (has_neg and has_pos)


# ---------------------------------------------------------------- icon

def make_icon() -> None:
    size = 1024
    cx = cy = size / 2.0
    apex = (cx + 120.0, cy)
    tri_top = (cx - 90.0, cy - 170.0)
    tri_bottom = (cx - 90.0, cy + 170.0)

    top_color = (18, 18, 22)      # near-black
    bottom_color = (34, 34, 40)   # dark charcoal
    red = (255, 59, 48)
    white = (255, 255, 255)

    pad = 8
    x0, y0, x1, y1 = pad, pad, size - pad - 1, size - pad - 1
    radius = 180 - pad

    rows = []
    for y in range(size):
        t = y / (size - 1)
        base = tuple(top_color[i] + (bottom_color[i] - top_color[i]) * t for i in range(3))
        row = bytearray([0])  # PNG filter type 0
        for x in range(size):
            if not in_rounded_rect(x, y, x0, y0, x1, y1, radius):
                row += bytes((0, 0, 0, 0))  # transparent outside icon
                continue
            # Vertical gradient with a 1px ordered dither to avoid banding.
            dither = 1 if (x + y) % 2 else 0
            r = min(255, max(0, int(base[0]) + dither))
            g = min(255, max(0, int(base[1]) + dither))
            b = min(255, max(0, int(base[2]) + dither))
            if in_circle(x, y, cx, cy, 330):
                r, g, b = red
            if in_triangle(x, y, tri_top, apex, tri_bottom):
                r, g, b = white
            row += bytes((r, g, b, 255))
        rows.append(bytes(row))

    write_png(ICON_PATH, size, size, rows)
    print(f"icon  -> {ICON_PATH.relative_to(ROOT)}")


# ---------------------------------------------------------------- png

def write_png(path: Path, width: int, height: int, rows) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
           + chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


# ---------------------------------------------------------------- wav

def make_silence() -> None:
    """2 seconds of near-silence, looped forever by PlayerModel."""
    WAV_PATH.parent.mkdir(parents=True, exist_ok=True)
    sample_rate = 22050
    seconds = 2
    amplitude = 50  # int16 units; effectively inaudible
    with wave.open(str(WAV_PATH), "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sample_rate)
        frames = bytearray()
        for i in range(sample_rate * seconds):
            value = int(amplitude * ((i % 100) / 100.0) - amplitude / 2)
            frames += struct.pack("<h", value)
        f.writeframes(bytes(frames))
    print(f"audio -> {WAV_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    make_icon()
    make_silence()
