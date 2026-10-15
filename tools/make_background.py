"""Generates art/background.png (640x360): a kitchen wall with a tiled
backsplash (gives the liquid's refraction something to bend) and a wooden
counter whose top surface is at y=280. Colors come from ENDESGA 32, same as
palette.gd.

Run from the project root:  python3 tools/make_background.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

W, H = 640, 360
COUNTER_Y = 280

C = {
    "ink": "#181425", "navy": "#262b44", "slate": "#3a4466", "frost": "#c0cbdc", "white": "#ffffff",
    "plum": "#3e2731", "brown": "#733e39", "clay": "#b86f50", "tan": "#c28569", "sand": "#e8b796",
    "peach": "#e4a672", "gold": "#feae34", "green": "#63c74d", "dkgreen": "#3e8948", "mist": "#8b9bb4",
}

img = Image.new("RGB", (W, H), C["plum"])
d = ImageDraw.Draw(img)


def rect(x0, y0, x1, y1, color):
    """Inclusive pixel rectangle."""
    d.rectangle([x0, y0, x1, y1], fill=C[color])


# --- upper wall: faint vertical panelling
for x in range(0, W, 32):
    rect(x, 0, x, 147, "brown") if x % 64 == 0 else None

# --- window (night)
wx0, wy0, wx1, wy1 = 420, 22, 560, 118
rect(wx0 - 4, wy0 - 4, wx1 + 4, wy1 + 6, "tan")
rect(wx0 - 4, wy1 + 4, wx1 + 4, wy1 + 6, "sand")
rect(wx0, wy0, wx1, wy1, "navy")
for y in range(wy0 + 48, wy1 + 1):
    if (y - wy0) % 3 == 0:
        rect(wx0, y, wx1, y, "slate")
rect(wx0, wy0 + 66, wx1, wy1, "slate")
for x, y in [(432, 30), (470, 40), (512, 28), (548, 52), (488, 64), (440, 58), (530, 74)]:
    d.point((x, y), fill=C["white"])
d.ellipse([520, 32, 534, 46], fill=C["sand"])
d.ellipse([525, 31, 537, 43], fill=C["navy"])
rect(wx0 + (wx1 - wx0) // 2 - 1, wy0, wx0 + (wx1 - wx0) // 2 + 1, wy1, "tan")
rect(wx0, wy0 + 46, wx1, wy0 + 48, "tan")

# --- shelf with a few things on it
rect(40, 104, 330, 108, "tan")
rect(40, 104, 330, 104, "sand")
rect(40, 109, 330, 110, "brown")
for bx in (60, 300):
    rect(bx, 111, bx + 2, 122, "brown")
    rect(bx + 3, 111, bx + 3, 116, "brown")
# jars
for jx, h in ((72, 26), (92, 20)):
    rect(jx, 104 - h, jx + 14, 103, "slate")
    rect(jx - 1, 104 - h - 3, jx + 15, 104 - h - 1, "clay")
    rect(jx + 2, 104 - h + 3, jx + 2, 100, "frost")
    rect(jx + 1, 104 - h + 10, jx + 13, 103, "gold" if jx == 72 else "green")
# plant
rect(140, 90, 156, 103, "clay")
rect(138, 88, 158, 90, "peach")
for lx, ly in ((142, 70), (148, 64), (154, 72), (146, 78), (152, 80), (138, 78), (158, 80)):
    rect(lx, ly, lx + 3, ly + 8, "green")
    rect(lx + 1, ly + 2, lx + 1, ly + 7, "dkgreen")
# plates
for i in range(5):
    rect(200, 101 - i * 2, 236, 102 - i * 2, "frost" if i % 2 == 0 else "mist")
# bottle
rect(272, 70, 282, 103, "dkgreen")
rect(275, 58, 279, 70, "dkgreen")
rect(275, 55, 279, 57, "clay")
rect(274, 76, 274, 98, "green")
rect(272, 82, 282, 92, "sand")

# --- backsplash tiles
TOP = 150
rect(0, TOP - 3, W - 1, TOP - 2, "sand")
rect(0, TOP - 1, W - 1, TOP - 1, "brown")
rect(0, TOP, W - 1, COUNTER_Y - 1, "brown")  # grout
TW, TH = 24, 12
for row, y in enumerate(range(TOP, COUNTER_Y, TH)):
    off = 0 if row % 2 == 0 else TW // 2
    for x in range(-TW + off, W, TW):
        x0, y0, x1, y1 = x + 1, y + 1, x + TW - 1, min(y + TH - 1, COUNTER_Y - 1)
        if x1 < 0 or x0 >= W or y0 > y1:
            continue
        rect(max(x0, 0), y0, min(x1, W - 1), y1, "tan")
        rect(max(x0, 0), y0, min(x1, W - 1), y0, "sand")
        rect(max(x0, 0), y1, min(x1, W - 1), y1, "clay")
        if 0 <= x0 + 2 < W:
            d.point((x0 + 2, y0 + 2), fill=C["white"])

# --- counter
rect(0, COUNTER_Y, W - 1, COUNTER_Y, "sand")
rect(0, COUNTER_Y + 1, W - 1, COUNTER_Y + 6, "peach")
rect(0, COUNTER_Y + 7, W - 1, COUNTER_Y + 7, "clay")
rect(0, COUNTER_Y + 8, W - 1, COUNTER_Y + 9, "plum")
rect(0, COUNTER_Y + 10, W - 1, H - 1, "brown")
for dx in range(8, W, 104):
    rect(dx, COUNTER_Y + 16, dx + 95, H - 8, "plum")
    rect(dx + 1, COUNTER_Y + 17, dx + 94, H - 9, "clay")
    rect(dx + 3, COUNTER_Y + 19, dx + 92, H - 11, "brown")
    rect(dx + 3, COUNTER_Y + 19, dx + 92, COUNTER_Y + 19, "plum")
    rect(dx + 44, COUNTER_Y + 26, dx + 51, COUNTER_Y + 28, "sand")

out = Path(__file__).resolve().parent.parent / "art" / "background.png"
img.save(out)
print("wrote", out)
