import sys
from PIL import Image, ImageChops
src, out_dir = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
k = im.width / 949  # thumbnails were 949px wide
def crop_box(x0, y0, x1, y1, inset=4):
    return im.crop((int((x0+inset)*k), int((y0+inset)*k), int((x1-inset)*k), int((y1-inset)*k)))
def to_alpha(img, bg):
    # unmix a flat background colour into transparency
    px = img.load(); w, h = img.size
    out = Image.new("RGBA", img.size)
    po = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            d = max(abs(r-bg[0]), abs(g-bg[1]), abs(b-bg[2]))
            a = min(255, int(d * 255 / 60)) if d < 60 else 255
            po[x, y] = (r, g, b, a)
    return out
def trim(img):
    bbox = img.getchannel("A").getbbox()
    pad = int(6*k)
    x0, y0, x1, y1 = bbox
    return img.crop((max(0,x0-pad), max(0,y0-pad), min(img.width,x1+pad), min(img.height,y1+pad)))
main = crop_box(449, 99, 620, 185)
rev = crop_box(684, 99, 855, 185)
bg_main = main.getpixel((5, 5)); bg_rev = rev.getpixel((5, 5))
print("bg main", bg_main, "bg reverse", bg_rev)
trim(to_alpha(main, bg_main)).save(f"{out_dir}/logo-main.png")
trim(to_alpha(rev, bg_rev)).save(f"{out_dir}/logo-reverse.png")
