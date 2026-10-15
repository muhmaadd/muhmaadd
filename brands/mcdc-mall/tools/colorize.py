import sys
from PIL import Image
mask_path, width, out_prefix = sys.argv[1], int(sys.argv[2]), sys.argv[3]
m = Image.open(mask_path).convert("L")
h = round(m.height * width / m.width)
m = m.resize((width, h), Image.LANCZOS)
for name, hexc in [("warmgray", "8A7967"), ("teal", "003B49"), ("white", "FFFFFF")]:
    rgb = tuple(int(hexc[i:i+2], 16) for i in (0, 2, 4))
    im = Image.new("RGBA", m.size, rgb + (0,)); im.putalpha(m)
    im.save(f"{out_prefix}-{name}.png", optimize=True)
print(m.size)
