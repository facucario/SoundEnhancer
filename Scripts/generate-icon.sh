#!/bin/bash
# Regenerates Resources/AppIcon.icns from Resources/icon/wave.svg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Resources/icon/wave.svg"
OUT="$ROOT/Resources/AppIcon.icns"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

W=1024

# Render the wave shape at full size (transparent background).
sips -s format png "$SRC" --out "$TMP/wave.png" >/dev/null 2>&1
sips -z $W $W "$TMP/wave.png" --out "$TMP/wave.png" >/dev/null 2>&1

python3 - "$TMP" "$OUT" <<'PY'
import os, sys
from PIL import Image, ImageDraw, ImageFilter

tmp, out = sys.argv[1], sys.argv[2]
W = H = 1024

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def grad(size, c1, c2, vertical):
    w, h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = y / (h - 1) if vertical else x / (w - 1)
            px[x, y] = lerp(c1, c2, t)
    return img

bg = grad((W, H), (246, 248, 255), (247, 244, 249), True)
wave_grad = grad((W, H), (224, 40, 244), (255, 66, 27), False)

wave = Image.open(os.path.join(tmp, "wave.png")).convert("RGBA")
mask = wave.split()[3]

shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(shadow).bitmap((0, 14), mask.point(lambda a: int(a * 0.5)), fill=(0, 0, 0, 255))
shadow = shadow.filter(ImageFilter.GaussianBlur(22))

layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
layer.paste(wave_grad.convert("RGBA"), (0, 0), mask)

canvas = bg.convert("RGBA")
canvas.alpha_composite(shadow)
canvas.alpha_composite(layer)
flat = canvas.convert("RGB")

iconset = os.path.join(tmp, "AppIcon.iconset")
os.makedirs(iconset)
for name, size in {
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
}.items():
    flat.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, name))

os.system(f'iconutil -c icns "{iconset}" -o "{out}"')
print(f"wrote {out}")
PY
