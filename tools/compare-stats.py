#!/usr/bin/env python3
"""compare-stats.py [name...]: how far each bench-out/cmp-<name>-{fulgor,sildur}.png pair is apart.

Each picture is cut into three bands (top: mostly sky, mid: horizon, bot: ground) and their mean colours are compared.
A band passes when no channel is more than LIMIT apart (of 255). Without names, every pair there is.
Needs Pillow. Exit status 1 if a pair fails, so it can gate a tuning loop.
"""
import glob, os, sys
from PIL import Image, ImageStat

LIMIT = 24
OUT = os.path.join(os.path.dirname(__file__), "..", "bench-out")

def bands(path, aspect=None):
    image = Image.open(path).convert("RGB")
    if aspect and image.height > image.width / aspect + 4:  # a window photograph: drop its title bar
        image = image.crop((0, image.height - round(image.width / aspect), image.width, image.height))
    small = image.resize((16, 9), Image.BOX)
    return [ImageStat.Stat(small.crop((0, y, 16, y + 3))).mean for y in (0, 3, 6)], image.width / image.height

names = sys.argv[1:] or sorted(os.path.basename(p)[4:-11] for p in glob.glob(os.path.join(OUT, "cmp-*-sildur.png")))
failed = 0
print("| scene | band | Fulgor | Sildur's | worst channel | |\n|---|---|---|---|---|---|")
for name in names:
    ours, their = (os.path.join(OUT, f"cmp-{name}-{side}.png") for side in ("fulgor", "sildur"))
    if not (os.path.exists(ours) and os.path.exists(their)):
        print(f"| {name} | | missing | | | FAIL |"); failed += 1; continue
    a, aspect = bands(ours)
    b, _ = bands(their, aspect)
    for band, x, y in zip(("top", "mid", "bot"), a, b):
        worst = max(abs(p - q) for p, q in zip(x, y))
        ok = worst <= LIMIT
        failed += not ok
        rgb = lambda c: "%d,%d,%d" % tuple(round(v) for v in c)
        print(f"| {name} | {band} | {rgb(x)} | {rgb(y)} | {worst:.0f} | {'ok' if ok else 'FAIL'} |")
sys.exit(1 if failed else 0)
