"""Inline image placeholders in template.html as base64 data URIs."""
import base64
import sys
from pathlib import Path

template, out = Path(sys.argv[1]), Path(sys.argv[2])
assets = dict(arg.split("=", 1) for arg in sys.argv[3:])

html = template.read_text(encoding="utf-8")
for key, path in assets.items():
    data = base64.b64encode(Path(path).read_bytes()).decode("ascii")
    html = html.replace("{{" + key + "}}", "data:image/png;base64," + data)

missing = [p for p in ("{{",) if p in html]
if missing:
    sys.exit("unresolved placeholder left in template")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(html, encoding="utf-8")
print(out, len(html.encode("utf-8")), "bytes")
