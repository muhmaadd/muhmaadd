"""Draw a country outline as the brand's vertical-line pattern with a warm glow.

usage: map_lines.py GEOMETRY.json OUT_DIR --height 820 --pitch 13 --line 4 --glow LON,LAT

Writes (all at the map's pixel size):
  map-lines.png  transparent lines, brighter near the glow point
  map-glow.png   transparent radial glow (low-res; scale it up when placing)
  map-meta.json  map size and the glow point's pixel position
"""
import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

WARMGRAY = np.array([0x8A, 0x79, 0x67], dtype=float)
LIGHT = np.array([0xF4, 0xE6, 0xCC], dtype=float)
TURQUOISE = (0x00, 0x99, 0xA8)

ap = argparse.ArgumentParser()
ap.add_argument("geometry")
ap.add_argument("out_dir")
ap.add_argument("--height", type=int, default=820)
ap.add_argument("--pitch", type=int, default=13)
ap.add_argument("--line", type=int, default=4)
ap.add_argument("--glow", default="46.72,24.69")
ap.add_argument("--glow-radius", type=float, default=0.42, help="fraction of map height")
ap.add_argument("--min-alpha", type=float, default=0.55, help="line opacity far from the glow")
args = ap.parse_args()

geom = json.loads(Path(args.geometry).read_text())
polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
lons = [p[0] for poly in polys for p in poly[0]]
lats = [p[1] for poly in polys for p in poly[0]]
lat_c = math.radians((min(lats) + max(lats)) / 2)
kx = math.cos(lat_c)
w_deg = (max(lons) - min(lons)) * kx
h_deg = max(lats) - min(lats)
H = args.height
W = round(H * w_deg / h_deg)
SS = 4  # supersampling for clean edges

def project(lon, lat, s=1):
    x = (lon - min(lons)) * kx / w_deg * W * s
    y = (max(lats) - lat) / h_deg * H * s
    return x, y

mask = Image.new("L", (W * SS, H * SS), 0)
draw = ImageDraw.Draw(mask)
for poly in polys:
    draw.polygon([project(lon, lat, SS) for lon, lat in poly[0]], fill=255)
    for hole in poly[1:]:
        draw.polygon([project(lon, lat, SS) for lon, lat in hole], fill=0)

cols = np.zeros((H * SS, W * SS), dtype=np.uint8)
xs = np.arange(W * SS)
offset = (W * SS) % (args.pitch * SS) // 2
cols[:, ((xs - offset) % (args.pitch * SS)) < args.line * SS] = 255
lines = np.minimum(np.asarray(mask), cols)
alpha = np.asarray(Image.fromarray(lines).resize((W, H), Image.LANCZOS), dtype=float) / 255

gx, gy = project(*[float(v) for v in args.glow.split(",")])
yy, xx = np.mgrid[0:H, 0:W]
d = np.hypot(xx - gx, yy - gy) / (H * args.glow_radius)
heat = np.exp(-d ** 2)
rgb = WARMGRAY[None, None, :] * (1 - heat[..., None]) + LIGHT[None, None, :] * heat[..., None]
a = alpha * (args.min_alpha + (1 - args.min_alpha) * heat)
out = np.dstack([rgb, a * 255]).clip(0, 255).astype(np.uint8)
out_dir = Path(args.out_dir)
out_dir.mkdir(parents=True, exist_ok=True)
Image.fromarray(out, "RGBA").save(out_dir / "map-lines.png", optimize=True)

# low-res glow, meant to be scaled up 4x when placed
gs = 4
gh, gw = H // gs, W // gs
gyy, gxx = np.mgrid[0:gh, 0:gw]
gd = np.hypot(gxx - gx / gs, gyy - gy / gs) / (gh * 0.55)
ga = (np.exp(-gd ** 2) * 0.42 * 255).astype(np.uint8)
glow = np.dstack([np.full((gh, gw), c, np.uint8) for c in TURQUOISE] + [ga])
Image.fromarray(glow, "RGBA").save(out_dir / "map-glow.png", optimize=True)

(out_dir / "map-meta.json").write_text(json.dumps({"width": W, "height": H, "glow_x": gx, "glow_y": gy}))
print(f"map {W}x{H}, glow point at ({gx:.0f}, {gy:.0f})")
