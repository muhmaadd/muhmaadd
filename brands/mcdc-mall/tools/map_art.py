"""Full-canvas artwork: the country as brand vertical lines, glowing from one point,
with the lines rising above the map as light pillars (the brand's skyline motif).

usage: map_art.py GEOMETRY.json OUT_DIR [--canvas 1920x1080] [--map-box X,Y,H] [--glow LON,LAT]

Writes OUT_DIR/art.png (RGB, full canvas) and OUT_DIR/art-layer.png (RGBA, art without
the background colour, for placing over a solid shape in Adobe Express).
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

TEAL = np.array([0x00, 0x3B, 0x49], float)
TURQUOISE = np.array([0x00, 0x99, 0xA8], float)
WARMGRAY = np.array([0x8A, 0x79, 0x67], float)
LIGHT = np.array([0xF4, 0xE6, 0xCC], float)
GOLD = np.array([0xC0, 0x82, 0x16], float)
GOLD_LIGHT = np.array([0xF2, 0xD4, 0x9B], float)

ap = argparse.ArgumentParser()
ap.add_argument("geometry")
ap.add_argument("out_dir")
ap.add_argument("--canvas", default="1920x1080")
ap.add_argument("--map-box", default="100,150,800", help="left,top,height of the map in px")
ap.add_argument("--glow", default="46.72,24.69")
ap.add_argument("--pitch", type=int, default=13)
ap.add_argument("--line", type=int, default=4)
ap.add_argument("--rise", type=int, default=230, help="max height of light pillars above the map")
ap.add_argument("--gold", action="store_true", help="gold lines, outline and core instead of cream")
args = ap.parse_args()

CW, CH = (int(v) for v in args.canvas.split("x"))
mx, my, MH = (int(v) for v in args.map_box.split(","))
geom = json.loads(Path(args.geometry).read_text())
polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
lons = [p[0] for poly in polys for p in poly[0]]
lats = [p[1] for poly in polys for p in poly[0]]
kx = math.cos(math.radians((min(lats) + max(lats)) / 2))
w_deg, h_deg = (max(lons) - min(lons)) * kx, max(lats) - min(lats)
MW = round(MH * w_deg / h_deg)
SS = 4

def project(lon, lat, s=1):
    return ((lon - min(lons)) * kx / w_deg * MW + mx) * s, ((max(lats) - lat) / h_deg * MH + my) * s

mask_img = Image.new("L", (CW * SS, CH * SS), 0)
draw = ImageDraw.Draw(mask_img)
for poly in polys:
    draw.polygon([project(lo, la, SS) for lo, la in poly[0]], fill=255)
    for hole in poly[1:]:
        draw.polygon([project(lo, la, SS) for lo, la in hole], fill=0)
mask_hi = np.asarray(mask_img) > 127
outline_img = Image.new("L", (CW * SS, CH * SS), 0)
odraw = ImageDraw.Draw(outline_img)
for poly in polys:
    ring = [project(lo, la, SS) for lo, la in poly[0]]
    odraw.line(ring + ring[:1], fill=255, width=int(1.6 * SS), joint="curve")
outline = np.asarray(outline_img.resize((CW, CH), Image.LANCZOS), float) / 255

gx, gy = project(*[float(v) for v in args.glow.split(",")])
yy, xx = np.mgrid[0:CH, 0:CW]

# columns of the line grid, aligned so pillars and map lines share positions
col_hi = np.zeros(CW * SS, bool)
for x in range(mx % args.pitch, CW, args.pitch):
    col_hi[x * SS:(x + args.line) * SS] = True

# light pillars: from each column's top map edge upward, taller near the glow
pillars_hi = np.zeros_like(mask_hi)
rise_alpha = np.zeros((CH * SS, CW * SS), np.float32)
for x in range(mx % args.pitch, CW, args.pitch):
    xs = slice(x * SS, (x + args.line) * SS)
    col = mask_hi[:, x * SS + (args.line * SS) // 2]
    if not col.any():
        continue
    top = int(np.argmax(col))
    h = args.rise * SS * math.exp(-((x + args.line / 2 - gx) / (MW * 0.3)) ** 2)
    # quantise heights into steps like the brand skyline device
    h = round(h / (18 * SS)) * 18 * SS
    if h < 18 * SS:
        continue
    gap = 14 * SS
    y1 = top - gap
    y0 = max(0, int(y1 - h))
    if y1 <= y0:
        continue
    pillars_hi[y0:y1, xs] = True
    ramp = 0.55 * np.linspace(0.0, 1.0, y1 - y0, dtype=np.float32)[:, None] ** 1.4
    rise_alpha[y0:y1, xs] = ramp

lines_hi = (mask_hi & col_hi[None, :]).astype(np.float32) + rise_alpha * pillars_hi
lines = np.asarray(Image.fromarray((lines_hi.clip(0, 1) * 255).astype(np.uint8)).resize((CW, CH), Image.LANCZOS), float) / 255

d = np.hypot(xx - gx, yy - gy)
heat = np.exp(-(d / (MH * 0.34)) ** 2)
if args.gold:
    # warm gray far away -> brand gold -> light gold at the core
    h1 = np.clip(heat * 2, 0, 1)[..., None]
    h2 = np.clip(heat * 2 - 1, 0, 1)[..., None]
    line_rgb = (WARMGRAY * (1 - h1) + GOLD * h1) * (1 - h2) + GOLD_LIGHT * h2
    CORE = GOLD_LIGHT
    HALO = LIGHT  # neutral cream halo: gold over teal would turn olive
    halo_strength = 0.16
else:
    line_rgb = WARMGRAY * (1 - heat[..., None]) + LIGHT * heat[..., None]
    CORE = LIGHT
    HALO = TURQUOISE
    halo_strength = 0.35
line_a = lines * (0.42 + 0.58 * heat)
line_a = 1 - (1 - line_a) * (1 - outline * 0.55)
# bright core of light at the glow point
core = np.exp(-(d / 38) ** 2)

# faint full-canvas line field so the country emerges from the brand pattern
field = np.zeros(CW, float)
for x in range(mx % args.pitch, CW, args.pitch):
    field[x:x + args.line] = 0.07
field_a = np.broadcast_to(field[None, :], (CH, CW)) * (1 - lines)

glow_a = np.exp(-(d / (MH * 0.55)) ** 2) * halo_strength

# composite over teal
rgb = np.broadcast_to(TEAL, (CH, CW, 3)).copy()
rgb = rgb * (1 - glow_a[..., None]) + HALO * glow_a[..., None]
rgb = rgb * (1 - field_a[..., None]) + WARMGRAY * field_a[..., None]
rgb = rgb * (1 - line_a[..., None]) + line_rgb * line_a[..., None]
rgb = rgb * (1 - core[..., None] * 0.85) + CORE * core[..., None] * 0.85
if args.gold:
    oa = outline[..., None] * 0.9
    rgb = rgb * (1 - oa) + GOLD * oa

out = Path(args.out_dir)
out.mkdir(parents=True, exist_ok=True)
Image.fromarray(rgb.clip(0, 255).astype(np.uint8), "RGB").save(out / "art.png", optimize=True)

# same art as a transparent layer (glow + field + lines), for Express
layer_a = 1 - (1 - glow_a) * (1 - field_a) * (1 - line_a) * (1 - core * 0.85) * (1 - (outline * 0.9 if args.gold else 0))
safe = np.maximum(layer_a, 1e-6)[..., None]
layer_rgb = (rgb - TEAL * (1 - layer_a[..., None])) / safe
Image.fromarray(np.dstack([layer_rgb.clip(0, 255), layer_a * 255]).astype(np.uint8), "RGBA").save(out / "art-layer.png", optimize=True)
print(f"map {MW}x{MH} at ({mx},{my}); glow at ({gx:.0f},{gy:.0f})")
