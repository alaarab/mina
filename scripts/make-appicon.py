#!/usr/bin/env python3
"""Regenerates the app icon and site favicons from scripts/appicon.svg (the wooden alphabet block).

Rendering uses macOS Quick Look (qlmanage), so this runs on a Mac only.
"""
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SVG = ROOT / "scripts/appicon.svg"
ICON = ROOT / "Mina/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(["qlmanage", "-t", "-s", "2048", "-o", tmp, str(SVG)], check=True, capture_output=True)
    src = Image.open(Path(tmp) / (SVG.name + ".png")).convert("RGB")
# Quick Look pads its thumbnail with white; crop to the drawn square before resizing.
bbox = ImageChops.difference(src, Image.new("RGB", src.size, (255, 255, 255))).getbbox()
src = src.crop(bbox).resize((1024, 1024), Image.LANCZOS)
src.save(ICON, optimize=True)
for size, name in [(180, "apple-touch-icon.png"), (64, "favicon.png"), (512, "icon.png")]:
    im = src.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.22), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    out.save(ROOT / "docs/assets" / name, optimize=True)
print(f"wrote {ICON} and docs/assets icons")
