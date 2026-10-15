import sys
from PIL import Image
src, box, out = sys.argv[1], [float(v) for v in sys.argv[2].split(",")], sys.argv[3]
im = Image.open(src).convert("L")
k = im.width / 949
x0, y0, x1, y1 = box
c = im.crop((int(x0*k), int(y0*k), int(x1*k), int(y1*k)))
# darkness -> alpha (device is a single dark colour on white)
alpha = c.point(lambda v: 0 if v > 235 else min(255, int((255 - v) * 255 / 200)))
bbox = alpha.getbbox(); alpha = alpha.crop(bbox)
alpha.save(out)
print(out, alpha.size)
