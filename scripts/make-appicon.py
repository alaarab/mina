#!/usr/bin/env python3
"""Draws the Mina app icon: a cream crescent moon and two stars on a coral-to-apricot sky."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

S = 1024
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Mina/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

top, bottom = (0xE4, 0x82, 0x6F), (0xF5, 0xB0, 0x7A)
sky = Image.new("RGB", (S, S))
px = sky.load()
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
    for x in range(S):
        px[x, y] = c

def circle(mask, cx, cy, r, fill):
    ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)

moon = Image.new("L", (S, S), 0)
circle(moon, 470, 540, 300, 255)
circle(moon, 600, 460, 260, 0)

shadow = moon.filter(ImageFilter.GaussianBlur(28))
sky.paste((0xB8, 0x5C, 0x4E), (0, 0), Image.eval(shadow, lambda v: v * 0.35 // 1).point(lambda v: int(v)))
sky.paste((0xFF, 0xF4, 0xE6), (0, 0), moon)

def star(draw, cx, cy, r, fill):
    pts = []
    for i in range(8):
        rad = r if i % 2 == 0 else r * 0.38
        import math
        a = math.pi / 4 * i - math.pi / 2
        pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    draw.polygon(pts, fill=fill)

d = ImageDraw.Draw(sky)
star(d, 700, 300, 58, (0xFF, 0xF4, 0xE6))
star(d, 790, 430, 34, (0xFF, 0xF4, 0xE6))

OUT.parent.mkdir(parents=True, exist_ok=True)
sky.save(OUT)
print(f"wrote {OUT}")
