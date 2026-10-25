"""Erzeugt alle Pixel-Grafiken und Soundeffekte fuer Pixel Transport Rivals.

Aufruf:  python tools/gen_assets.py
Ausgabe: assets/gfx/*.png, assets/gfx/manifest.json, assets/sfx/*.wav
Deterministisch (fester Seed), damit die Assets reproduzierbar sind.

HINWEIS: Seit der isometrischen Umstellung kommen Boden, Gebaeude, Fahrzeuge, Figuren und Requisiten aus
tools/build_iso.py (-> assets/iso/). Von diesem Skript werden nur noch die Symbole (i_*), Lichtflecken (glow_*), Rauch,
Regen, Sprechblasen und die Soundeffekte benoetigt; die uebrigen hier erzeugten Draufsicht-Grafiken sind veraltet
und wurden aus assets/gfx/ entfernt (nicht erneut erzeugen).
"""
import json
import math
import os
import random
import struct
import wave

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
GFX = os.path.join(ROOT, "assets", "gfx")
SFX = os.path.join(ROOT, "assets", "sfx")
T = 32
rng = random.Random(1337)


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def shade(c, f):
    return (max(0, min(255, int(c[0] * f))), max(0, min(255, int(c[1] * f))), max(0, min(255, int(c[2] * f))), c[3])


OUT = hexc("#1b1b26")
P = {
    "grass": [hexc("#4f8a3a"), hexc("#5d9a44"), hexc("#467f34"), hexc("#6fae4f")],
    "park": [hexc("#5fa84a"), hexc("#6cb554"), hexc("#559a42")],
    "asphalt": hexc("#3d414c"),
    "asphalt2": hexc("#454a56"),
    "yellow": hexc("#e8c95a"),
    "white": hexc("#e6e6e0"),
    "curb": hexc("#b9b7ae"),
    "sidewalk": hexc("#a9a7a0"),
    "plaza": hexc("#c9b18a"),
    "concrete": hexc("#8a8d92"),
    "water": [hexc("#2d6aa3"), hexc("#3780bd"), hexc("#5aa6dc")],
    "sand": hexc("#d9c38c"),
    "field": hexc("#8a6a3c"),
    "crop": hexc("#7fa040"),
    "glow": hexc("#ffd86b"),
    "glass": hexc("#5f93bb"),
}


def new(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def rect(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


def speckle(img, x0, y0, w, h, cols, n):
    px = img.load()
    for _ in range(n):
        x = x0 + rng.randrange(w)
        y = y0 + rng.randrange(h)
        px[x, y] = rng.choice(cols)


# ---------------------------------------------------------------- Tiles
tiles = {}
TILE_COLS = 40  # eine Zeile: Animationsframes muessen nebeneinander liegen
tile_imgs = []


def add_tile(name, img):
    idx = len(tile_imgs)
    tile_imgs.append(img)
    tiles[name] = [idx % TILE_COLS, idx // TILE_COLS]


def base_tile(col, speck_cols, n=40):
    img = new(T, T)
    d = ImageDraw.Draw(img)
    rect(d, 0, 0, T - 1, T - 1, col)
    speckle(img, 0, 0, T, T, speck_cols, n)
    return img, d


def gen_tiles():
    g = P["grass"]
    for i in range(3):
        img, d = base_tile(g[i % 2], [g[2], g[3], shade(g[0], 0.9)], 60)
        if i == 2:  # Grashalme
            px = img.load()
            for _ in range(6):
                x, y = rng.randrange(1, 31), rng.randrange(2, 31)
                px[x, y] = g[3]
                px[x, y - 1] = g[3]
        add_tile("grass%d" % i, img)
    # Park mit Blumen
    for i in range(2):
        img, d = base_tile(P["park"][i], [P["park"][2], g[3]], 50)
        px = img.load()
        if i == 1:
            for _ in range(7):
                x, y = rng.randrange(1, 31), rng.randrange(1, 31)
                px[x, y] = rng.choice([hexc("#f2e463"), hexc("#ef6f8f"), hexc("#ffffff"), hexc("#b78ef0")])
        add_tile("park%d" % i, img)
    # Parkweg (Kies)
    img, d = base_tile(hexc("#cdb88f"), [hexc("#b9a37a"), hexc("#ddcaa3")], 90)
    add_tile("gravel", img)
    # Gehweg
    img, d = base_tile(P["sidewalk"], [shade(P["sidewalk"], 0.93), shade(P["sidewalk"], 1.06)], 30)
    for k in range(0, T, 8):
        d.line([k, 0, k, T - 1], fill=shade(P["sidewalk"], 0.85))
        d.line([0, k, T - 1, k], fill=shade(P["sidewalk"], 0.85))
    add_tile("sidewalk", img)
    # Plaza (Innenstadt-Pflaster)
    img, d = base_tile(P["plaza"], [shade(P["plaza"], 0.92)], 20)
    for y in range(0, T, 8):
        off = 0 if (y // 8) % 2 == 0 else 8
        d.line([0, y, T - 1, y], fill=shade(P["plaza"], 0.8))
        for x in range(off, T, 16):
            d.line([x, y, x, y + 7], fill=shade(P["plaza"], 0.8))
    add_tile("plaza", img)
    # Beton (Industrie/Hafen)
    img, d = base_tile(P["concrete"], [shade(P["concrete"], 0.9), shade(P["concrete"], 1.08)], 70)
    d.line([3, 20, 9, 24, 12, 23], fill=shade(P["concrete"], 0.75))
    d.line([0, 0, T - 1, 0], fill=shade(P["concrete"], 0.85))
    add_tile("concrete", img)
    # Kaimauer (Wasser rechts)
    img, d = base_tile(P["concrete"], [shade(P["concrete"], 0.9)], 50)
    rect(d, 26, 0, 31, 31, shade(P["concrete"], 0.7))
    rect(d, 25, 0, 25, 31, P["yellow"])
    for y in (6, 22):
        rect(d, 27, y, 29, y + 3, OUT)
    add_tile("quay", img)
    # Sand, Feld, Acker
    img, d = base_tile(P["sand"], [shade(P["sand"], 0.92), shade(P["sand"], 1.05)], 80)
    add_tile("sand", img)
    img, d = base_tile(P["field"], [shade(P["field"], 0.9)], 40)
    for y in range(2, T, 6):
        d.line([0, y, T - 1, y], fill=shade(P["field"], 0.75))
    add_tile("field", img)
    img, d = base_tile(P["field"], [shade(P["field"], 0.9)], 20)
    for y in range(2, T, 6):
        for x in range(1, T, 3):
            d.point((x, y), fill=P["crop"])
            d.point((x, y - 1), fill=shade(P["crop"], 1.2))
    add_tile("crop", img)
    # Wasser, 4 Animationsframes
    for f in range(4):
        img, d = base_tile(P["water"][0], [P["water"][1]], 30)
        for row in range(4):
            y = row * 8 + 3
            x0 = (f * 4 + row * 11) % T
            for k in range(7):
                d.point(((x0 + k) % T, y + (1 if k in (0, 6) else 0)), fill=P["water"][2])
        add_tile("water%d" % f, img)
    # Gleise
    for name, horiz in (("rail_h", True), ("rail_v", False)):
        img, d = base_tile(hexc("#7a6f63"), [hexc("#6a6055"), hexc("#8d8276")], 120)
        for k in range(2, T, 6):
            if horiz:
                rect(d, k, 6, k + 2, 25, hexc("#5a3f2b"))
            else:
                rect(d, 6, k, 25, k + 2, hexc("#5a3f2b"))
        for off in (9, 22):
            if horiz:
                rect(d, 0, off, T - 1, off + 1, hexc("#c4c9cf"))
            else:
                rect(d, off, 0, off + 1, T - 1, hexc("#c4c9cf"))
        add_tile(name, img)
    # Strassen: 16 Varianten ueber Nachbar-Bitmaske N=1 E=2 S=4 W=8
    for mask in range(16):
        add_tile("road%d" % mask, road_tile(mask))
    # Parkplatz
    img, d = base_tile(P["asphalt2"], [P["asphalt"]], 40)
    for x in range(0, T, 10):
        d.line([x, 0, x, 12], fill=P["white"])
    add_tile("parking", img)


def road_tile(mask):
    img, d = base_tile(P["asphalt"], [P["asphalt2"], shade(P["asphalt"], 0.9)], 50)
    n, e, s, w = mask & 1, mask & 2, mask & 4, mask & 8
    conn = bin(mask).count("1")
    # Bordsteine an Seiten ohne Anschluss
    if not n:
        rect(d, 0, 0, T - 1, 2, P["curb"])
    if not s:
        rect(d, 0, T - 3, T - 1, T - 1, P["curb"])
    if not w:
        rect(d, 0, 0, 2, T - 1, P["curb"])
    if not e:
        rect(d, T - 3, 0, T - 1, T - 1, P["curb"])
    # Ecken-Bordstein bei Kreuzungen
    for cx, cy, a, b in ((0, 0, n, w), (T - 3, 0, n, e), (0, T - 3, s, w), (T - 3, T - 3, s, e)):
        if a and b:
            rect(d, cx, cy, cx + 2, cy + 2, P["curb"])
    if conn >= 3:
        # Zebrastreifen an Kreuzungen
        for side, on in (("n", n), ("s", s), ("w", w), ("e", e)):
            if not on:
                continue
            for k in range(5, T - 4, 5):
                if side == "n":
                    rect(d, k, 0, k + 2, 4, P["white"])
                elif side == "s":
                    rect(d, k, T - 5, k + 2, T - 1, P["white"])
                elif side == "w":
                    rect(d, 0, k, 4, k + 2, P["white"])
                else:
                    rect(d, T - 5, k, T - 1, k + 2, P["white"])
    else:
        # Mittellinie gestrichelt
        if n or s:
            for y in range(0, T, 8):
                if (y < 16 and n) or (y >= 16 and s):
                    rect(d, 15, y + 1, 16, y + 4, P["yellow"])
        if e or w:
            for x in range(0, T, 8):
                if (x < 16 and w) or (x >= 16 and e):
                    rect(d, x + 1, 15, x + 4, 16, P["yellow"])
    return img


# ---------------------------------------------------------------- Buildings
buildings = {}


def save(img, name, sub="gfx"):
    img.save(os.path.join(ROOT, "assets", sub, name + ".png"))


def building(name, w, h, roof, wall, facade, roof_style="pitched", win_cols=None, win_rows=1,
             win_col=None, door=True, awning=None, sign=None, extra=None, smoke=None, blink=None):
    W, H = w * T, h * T
    img, lit = new(W, H), new(W, H)
    d, dl = ImageDraw.Draw(img), ImageDraw.Draw(lit)
    x0, x1 = 2, W - 4
    top, fy = 3, H - facade
    # Schatten rechts / unten
    rect(d, x1 + 1, top + 3, x1 + 3, H - 1, (0, 0, 0, 70))
    # Dach
    rect(d, x0, top, x1, fy, roof)
    if roof_style == "pitched":
        mid = (top + fy) // 2
        for y in range(top, fy):
            if (y - top) % 4 == 3:
                d.line([x0, y, x1, y], fill=shade(roof, 0.82))
        d.line([x0, mid, x1, mid], fill=shade(roof, 1.25))
        rect(d, x0, mid + 1, x1, fy, shade(roof, 0.9))
        for y in range(mid + 1, fy):
            if (y - top) % 4 == 3:
                d.line([x0, y, x1, y], fill=shade(roof, 0.75))
    else:
        rect(d, x0, top, x1, top + 1, shade(roof, 1.2))
        rect(d, x0, top, x0 + 1, fy, shade(roof, 1.1))
        rect(d, x0 + 2, top + 2, x1 - 2, fy - 2, shade(roof, 0.92))
        # Lueftungsgeraete
        for k in range(max(1, w - 1)):
            vx = x0 + 6 + k * 26 + rng.randrange(6)
            vy = top + 5 + rng.randrange(max(1, fy - top - 14))
            rect(d, vx, vy, vx + 7, vy + 5, hexc("#9aa0a8"))
            rect(d, vx, vy + 5, vx + 7, vy + 6, hexc("#5c6068"))
            d.point((vx + 3, vy + 2), fill=OUT)
    # Fassade
    rect(d, x0, fy, x1, H - 1, wall)
    d.line([x0, fy, x1, fy], fill=shade(wall, 0.6))
    rect(d, x0, H - 2, x1, H - 1, shade(wall, 0.7))
    if awning:
        ay = fy + 3
        for x in range(x0, x1 + 1):
            c = awning if ((x - x0) // 4) % 2 == 0 else hexc("#f2efe6")
            d.line([x, ay, x, ay + 4], fill=c)
        d.line([x0, ay + 5, x1, ay + 5], fill=shade(awning, 0.6))
    if sign:
        sw = min(len(sign) * 4 + 6, x1 - x0 - 4)
        sx = (W - sw) // 2
        rect(d, sx, fy + 2, sx + sw, fy + 7, sign)
        rect(d, sx + 2, fy + 4, sx + sw - 2, fy + 5, hexc("#f7f1d0"))
        rect(dl, sx, fy + 2, sx + sw, fy + 7, (*sign[:3], 160))
    # Fenster
    win_col = win_col or P["glass"]
    cols = win_cols or max(2, (x1 - x0) // 9)
    area_top = fy + (12 if (awning or sign) else 4)
    area_bot = H - 4 - (12 if door else 0)
    rows = win_rows
    rh = max(5, (area_bot - area_top) // max(1, rows))
    for r in range(rows):
        for c in range(cols):
            wx = x0 + 4 + c * ((x1 - x0 - 6) // cols)
            wy = area_top + r * rh
            ww, wh = max(3, (x1 - x0 - 6) // cols - 4), min(6, rh - 2)
            if wh < 3:
                continue
            rect(d, wx - 1, wy - 1, wx + ww, wy + wh, shade(wall, 0.55))
            rect(d, wx, wy, wx + ww - 1, wy + wh - 1, win_col)
            d.point((wx, wy), fill=shade(win_col, 1.4))
            if rng.random() < 0.7:
                rect(dl, wx, wy, wx + ww - 1, wy + wh - 1, P["glow"])
    if door:
        dx = W // 2 - 4
        rect(d, dx - 1, H - 13, dx + 8, H - 2, shade(wall, 0.5))
        rect(d, dx, H - 12, dx + 7, H - 2, hexc("#6b4a33"))
        d.point((dx + 5, H - 7), fill=P["yellow"])
        rect(dl, dx, H - 12, dx + 7, H - 2, (255, 200, 110, 110))
    # Umriss
    d.rectangle([x0 - 1, top - 1, x1 + 1, H - 1], outline=OUT)
    if extra:
        extra(d, dl, W, H, x0, x1, top, fy)
    save(img, "b_" + name)
    save(lit, "b_" + name + "_lit")
    entry = {"w": w, "h": h}
    if smoke:
        entry["smoke"] = smoke
    if blink:
        entry["blink"] = blink
    buildings[name] = entry


def chimney(d, dl, W, H, x0, x1, top, fy):
    cx = x1 - 14
    rect(d, cx, top - 2, cx + 7, fy - 6, hexc("#8e4a3a"))
    rect(d, cx, top - 2, cx + 7, top, hexc("#3a2a24"))
    d.rectangle([cx - 1, top - 3, cx + 8, fy - 6], outline=OUT)
    # Saegezahndach-Andeutung
    for k in range(x0 + 4, cx - 10, 12):
        d.polygon([(k, fy - 2), (k + 10, fy - 2), (k + 10, fy - 10)], fill=hexc("#6f8fa8"))


def big_doors(d, dl, W, H, x0, x1, top, fy):
    for k in range(3):
        dx = x0 + 8 + k * ((x1 - x0 - 16) // 3)
        rect(d, dx, H - 18, dx + 20, H - 2, hexc("#7c8590"))
        for y in range(H - 17, H - 2, 3):
            d.line([dx, y, dx + 20, y], fill=hexc("#626a74"))
        d.rectangle([dx, H - 18, dx + 20, H - 2], outline=OUT)


def dealer_lot(d, dl, W, H, x0, x1, top, fy):
    rect(d, x0 + 4, fy + 10, x1 - 4, H - 4, hexc("#9ccbe8"))
    for x in range(x0 + 4, x1 - 4, 12):
        d.line([x, fy + 10, x, H - 4], fill=hexc("#e8eef2"))
    rect(dl, x0 + 4, fy + 10, x1 - 4, H - 4, (255, 240, 200, 150))


def depot_extra(d, dl, W, H, x0, x1, top, fy):
    big_doors(d, dl, W, H, x0, x1, top, fy)


def bank_columns(d, dl, W, H, x0, x1, top, fy):
    for x in range(x0 + 6, x1 - 4, 10):
        rect(d, x, fy + 8, x + 3, H - 3, hexc("#efe9da"))
        d.line([x + 3, fy + 8, x + 3, H - 3], fill=hexc("#bdb5a2"))
    d.polygon([(x0, fy + 7), ((x0 + x1) // 2, fy - 2), (x1, fy + 7)], fill=hexc("#d8cfba"), outline=OUT)


def red_cross(d, dl, W, H, x0, x1, top, fy):
    cx, cy = (x0 + x1) // 2, (top + fy) // 2
    rect(d, cx - 10, cy - 10, cx + 10, cy + 10, hexc("#f2f2ee"))
    rect(d, cx - 3, cy - 8, cx + 3, cy + 8, hexc("#d03030"))
    rect(d, cx - 8, cy - 3, cx + 8, cy + 3, hexc("#d03030"))
    d.rectangle([cx - 10, cy - 10, cx + 10, cy + 10], outline=OUT)


def notice_board(d, dl, W, H, x0, x1, top, fy):
    bx0, bx1 = x0 + 30, x1 - 6
    rect(d, bx0, fy + 12, bx1, H - 6, hexc("#8a5a34"))
    d.rectangle([bx0, fy + 12, bx1, H - 6], outline=OUT)
    for k in range(9):
        px = bx0 + 3 + (k % 5) * ((bx1 - bx0 - 8) // 5)
        py = fy + 14 + (k // 5) * 8
        col = [hexc("#f7f1d0"), hexc("#f2c14e"), hexc("#bfe0f2"), hexc("#f2b6c8")][k % 4]
        rect(d, px, py, px + 6, py + 6, col)
        d.point((px + 3, py), fill=hexc("#d03030"))


def gen_construction():
    W, H = 3 * T, 3 * T
    img, lit = new(W, H), new(W, H)
    d = ImageDraw.Draw(img)
    rect(d, 2, 3, W - 4, H - 2, hexc("#c9a46a"))
    for _ in range(140):
        d.point((rng.randrange(3, W - 4), rng.randrange(4, H - 2)), fill=hexc("#b08c55"))
    # Rohbau
    rect(d, 10, 14, 54, 58, hexc("#9aa0a8"))
    for x in range(10, 55, 11):
        rect(d, x, 14, x + 2, 58, hexc("#6b7078"))
    rect(d, 10, 14, 54, 16, hexc("#6b7078"))
    rect(d, 10, 36, 54, 38, hexc("#6b7078"))
    d.rectangle([10, 14, 54, 58], outline=OUT)
    # Kran
    rect(d, 70, 8, 73, 80, hexc("#e0b020"))
    rect(d, 30, 8, 90, 11, hexc("#e0b020"))
    for x in range(30, 90, 5):
        d.line([x, 8, x + 3, 11], fill=hexc("#a07810"))
    d.line([40, 11, 40, 30], fill=OUT)
    rect(d, 37, 30, 43, 34, hexc("#8a5a34"))
    # Sandhaufen, Kegel, Zaun
    d.ellipse([60, 64, 88, 84], fill=hexc("#d9c38c"), outline=hexc("#a8925c"))
    for x in (16, 30):
        d.polygon([(x + 3, 70), (x, 80), (x + 7, 80)], fill=hexc("#f07818"), outline=OUT)
    for x in range(2, W - 4, 4):
        d.point((x, 3), fill=OUT)
        d.point((x, H - 3), fill=OUT)
    for y in range(3, H - 2, 4):
        d.point((2, y), fill=OUT)
        d.point((W - 4, y), fill=OUT)
    rect(ImageDraw.Draw(lit), 37, 30, 43, 34, (255, 120, 60, 200))
    save(img, "b_construction")
    save(lit, "b_construction_lit")
    buildings["construction"] = {"w": 3, "h": 3, "blink": True}


def gen_buildings():
    roofs = [hexc("#b0483c"), hexc("#46638f"), hexc("#7d5a3c"), hexc("#4a7a5a"), hexc("#6b6f78")]
    walls = [hexc("#e6dcc4"), hexc("#d9c7a3"), hexc("#c9a189"), hexc("#dfe3e8")]
    for i in range(4):
        building("house%d" % i, 2, 2, roofs[i], walls[i % 4], 22, "pitched", win_cols=3)
    building("apartment0", 3, 3, hexc("#6b6f78"), hexc("#c9a189"), 50, "flat", win_cols=5, win_rows=3)
    building("apartment1", 3, 3, hexc("#8f5a4a"), hexc("#e6dcc4"), 50, "flat", win_cols=5, win_rows=3)
    building("shop0", 2, 2, hexc("#5a5e6a"), hexc("#e6dcc4"), 30, "flat", awning=hexc("#c8463c"), win_cols=3)
    building("shop1", 2, 2, hexc("#5a5e6a"), hexc("#dfe3e8"), 30, "flat", awning=hexc("#3c7fc8"), win_cols=3)
    building("shop2", 2, 2, hexc("#7d5a3c"), hexc("#d9c7a3"), 30, "flat", awning=hexc("#3c9a5a"), win_cols=3)
    building("restaurant", 2, 2, hexc("#8f3a32"), hexc("#e6dcc4"), 30, "flat", sign=hexc("#d23c8c"), win_cols=3,
             blink=True)
    building("office0", 3, 3, hexc("#4e5360"), hexc("#c9cdd4"), 64, "flat", win_cols=6, win_rows=4,
             win_col=hexc("#6fa3c9"))
    building("office1", 3, 3, hexc("#3f4452"), hexc("#a8b4c4"), 64, "flat", win_cols=5, win_rows=4,
             win_col=hexc("#4f8fbf"))
    building("bank", 3, 3, hexc("#5f6470"), hexc("#e2dccb"), 46, "flat", win_cols=4, win_rows=1,
             extra=bank_columns, sign=hexc("#2f5f9f"))
    building("factory", 4, 4, hexc("#5a5550"), hexc("#a85a44"), 40, "flat", win_cols=7, win_rows=1,
             door=False, extra=chimney, smoke=[4 * T - 14 + 3, 2])
    building("warehouse", 4, 3, hexc("#6f7a84"), hexc("#b8bcc2"), 34, "flat", win_cols=6, door=False,
             extra=big_doors)
    building("workshop", 3, 2, hexc("#5a5e6a"), hexc("#d9c7a3"), 30, "flat", sign=hexc("#e07a2a"), door=False,
             extra=big_doors)
    building("dealer", 4, 3, hexc("#3f4452"), hexc("#dfe3e8"), 44, "flat", sign=hexc("#2a9ae0"), door=False,
             extra=dealer_lot, blink=True)
    building("depot", 3, 3, hexc("#7a7f88"), hexc("#d4d7dc"), 34, "flat", win_cols=4, door=False, extra=depot_extra)
    building("farm", 3, 3, hexc("#9a3a2e"), hexc("#c9a070"), 26, "pitched", win_cols=2)
    building("port_office", 3, 2, hexc("#46638f"), hexc("#dfe3e8"), 30, "flat", sign=hexc("#1f6fb0"), win_cols=4)
    building("freight_shed", 5, 3, hexc("#6a5a4a"), hexc("#a85a44"), 34, "pitched", win_cols=8, door=False,
             extra=big_doors)
    building("gas_station", 3, 2, hexc("#e8e8e0"), hexc("#dfe3e8"), 22, "flat", sign=hexc("#e03a2a"), win_cols=3,
             blink=True)
    building("clinic", 3, 3, hexc("#d8dde4"), hexc("#f2f2ee"), 40, "flat", win_cols=5, win_rows=2,
             sign=hexc("#d03030"), extra=red_cross)
    building("job_board", 3, 2, hexc("#5a5e6a"), hexc("#e6dcc4"), 34, "flat", sign=hexc("#2f9a5a"), win_cols=2,
             door=False, extra=notice_board, blink=True)
    building("staffing", 2, 2, hexc("#46638f"), hexc("#dfe3e8"), 30, "flat", sign=hexc("#7a4ab0"), win_cols=3)
    gen_construction()
    # Firmenfahne fuer Bueros (einfaerbbar)
    img = new(14, 20)
    d = ImageDraw.Draw(img)
    rect(d, 1, 0, 2, 19, OUT)
    d.polygon([(3, 1), (13, 4), (3, 8)], fill=(255, 255, 255, 255), outline=OUT)
    save(img, "flag")
    # Depot-Akzent (wird per Firmenfarbe eingefaerbt)
    acc = new(3 * T, 3 * T)
    da = ImageDraw.Draw(acc)
    rect(da, 2, 3 * T - 34 + 2, 3 * T - 4, 3 * T - 34 + 6, (255, 255, 255, 255))
    rect(da, 6, 8, 3 * T - 8, 16, (255, 255, 255, 255))
    save(acc, "b_depot_accent")
    # Container-Stapel
    img = new(2 * T, 2 * T)
    d = ImageDraw.Draw(img)
    cc = [hexc("#c0392b"), hexc("#2e86c1"), hexc("#27ae60"), hexc("#d68910"), hexc("#7d3c98")]
    for r in range(3):
        for c in range(2):
            col = rng.choice(cc)
            x, y = 3 + c * 29, 4 + r * 19
            rect(d, x, y, x + 26, y + 15, col)
            for k in range(x + 2, x + 26, 3):
                d.line([k, y + 1, k, y + 14], fill=shade(col, 0.8))
            d.rectangle([x, y, x + 26, y + 15], outline=OUT)
    save(img, "b_containers")
    save(new(2 * T, 2 * T), "b_containers_lit")
    buildings["containers"] = {"w": 2, "h": 2}
    # Hafenkran
    img = new(2 * T, 3 * T)
    d = ImageDraw.Draw(img)
    rect(d, 8, 30, 12, 92, hexc("#d4a017"))
    rect(d, 50, 30, 54, 92, hexc("#d4a017"))
    rect(d, 4, 24, 60, 32, hexc("#e0b020"))
    for x in range(6, 60, 6):
        d.line([x, 24, x + 4, 32], fill=hexc("#a07810"))
    rect(d, 24, 14, 40, 26, hexc("#c0392b"))
    rect(d, 28, 16, 36, 20, P["glass"])
    d.rectangle([4, 24, 60, 32], outline=OUT)
    save(img, "b_crane")
    save(new(2 * T, 3 * T), "b_crane_lit")
    buildings["crane"] = {"w": 2, "h": 3}
    # Brunnen
    img = new(2 * T, 2 * T)
    d = ImageDraw.Draw(img)
    d.ellipse([6, 8, 58, 56], fill=hexc("#bdb8aa"), outline=OUT)
    d.ellipse([11, 13, 53, 51], fill=P["water"][1])
    d.ellipse([27, 26, 37, 36], fill=hexc("#d8d3c5"), outline=OUT)
    d.point((32, 24), fill=P["water"][2])
    save(img, "b_fountain")
    save(new(2 * T, 2 * T), "b_fountain_lit")
    buildings["fountain"] = {"w": 2, "h": 2}


# ---------------------------------------------------------------- Betriebseinrichtungen (Firmengrundstueck)
FAC_SIZES = {"buero": (2, 2), "disposition": (2, 2), "stellplatz": (2, 2), "garage": (2, 2), "werkstatt": (3, 2),
             "laderampe": (2, 1), "lager": (3, 3), "kuehllager": (3, 2), "tankstelle": (2, 2), "ladepunkt": (1, 2),
             "pausenraum": (2, 2), "schulung": (2, 2), "sicherheit": (1, 1), "waschplatz": (2, 2), "mietbuero": (3, 2)}


def _open_pad(W, H):
    img, lit = new(W, H), new(W, H)
    d, dl = ImageDraw.Draw(img), ImageDraw.Draw(lit)
    rect(d, 1, 1, W - 2, H - 2, P["asphalt2"])
    speckle(img, 1, 1, W - 2, H - 2, [P["asphalt"], shade(P["asphalt2"], 1.1)], W * H // 40)
    d.rectangle([0, 0, W - 1, H - 1], outline=shade(P["curb"], 0.8))
    return img, lit, d, dl


def _stellplatz(W, H):
    img, lit, d, dl = _open_pad(W, H)
    vertical = H >= W
    n = 2
    for k in range(n + 1):
        if vertical:
            y = 2 + k * (H - 4) // n
            d.line([4, y, W - 5, y], fill=P["white"])
        else:
            x = 2 + k * (W - 4) // n
            d.line([x, 4, x, H - 5], fill=P["white"])
    # Radstopper und "P"
    for k in range(n):
        if vertical:
            y = 2 + k * (H - 4) // n + (H - 4) // n // 2
            rect(d, W - 10, y - 4, W - 8, y + 4, P["yellow"])
        else:
            x = 2 + k * (W - 4) // n + (W - 4) // n // 2
            rect(d, x - 4, 8, x + 4, 10, P["yellow"])
    rect(d, 3, 3, 9, 11, hexc("#2f5f9f"))
    d.line([5, 5, 5, 9], fill=P["white"])
    d.line([5, 5, 7, 5], fill=P["white"])
    d.line([5, 7, 7, 7], fill=P["white"])
    d.point((7, 6), fill=P["white"])
    return img, lit


def _laderampe(W, H):
    img, lit, d, dl = _open_pad(W, H)
    horiz = W >= H
    # Rampenkante (Beton, erhoeht) mit Torpuffern und Warnstreifen
    if horiz:
        rect(d, 1, 1, W - 2, 10, P["concrete"])
        for x in range(1, W - 1):
            d.point((x, 11), fill=P["yellow"] if (x // 3) % 2 == 0 else OUT)
        for k in range(2):
            x = 6 + k * (W // 2)
            rect(d, x, 2, x + W // 2 - 14, 9, hexc("#7a7f88"))
            rect(d, x + 1, 3, x + W // 2 - 15, 8, hexc("#9aa0a8"))
            rect(d, x - 2, 9, x - 1, 13, OUT)
            rect(dl, x, 12, x + W // 2 - 14, 18, (255, 220, 140, 90))
    else:
        rect(d, 1, 1, 10, H - 2, P["concrete"])
        for y in range(1, H - 1):
            d.point((11, y), fill=P["yellow"] if (y // 3) % 2 == 0 else OUT)
        for k in range(2):
            y = 6 + k * (H // 2)
            rect(d, 2, y, 9, y + H // 2 - 14, hexc("#7a7f88"))
            rect(d, 3, y + 1, 8, y + H // 2 - 15, hexc("#9aa0a8"))
            rect(dl, 12, y, 18, y + H // 2 - 14, (255, 220, 140, 90))
    return img, lit


def _tankstelle(W, H):
    img, lit, d, dl = _open_pad(W, H)
    # Dach (Canopy) mit Zapfsaeulen und Tankdeckeln
    rect(d, 6, 6, W - 7, H // 2 + 2, hexc("#e8e8e0"))
    rect(d, 6, H // 2 + 1, W - 7, H // 2 + 2, hexc("#c03028"))
    d.rectangle([6, 6, W - 7, H // 2 + 2], outline=OUT)
    rect(dl, 6, 6, W - 7, H // 2 + 2, (255, 240, 200, 120))
    for k in range(2):
        x = 12 + k * (W - 30)
        rect(d, x, H // 2 + 6, x + 6, H // 2 + 16, hexc("#c03028"))
        rect(d, x + 1, H // 2 + 7, x + 5, H // 2 + 10, hexc("#2b2b33"))
        d.rectangle([x, H // 2 + 6, x + 6, H // 2 + 16], outline=OUT)
    for k in range(3):
        d.ellipse([8 + k * 14, H - 12, 14 + k * 14, H - 6], fill=hexc("#6b6f78"), outline=OUT)
    return img, lit


def _ladepunkt(W, H):
    img, lit, d, dl = _open_pad(W, H)
    rect(d, 2, H // 2 - 1, W - 3, H // 2, P["white"])
    for k in range(2):
        y = 6 + k * (H // 2)
        rect(d, W // 2 - 4, y, W // 2 + 4, y + 12, hexc("#2e9a5a"))
        rect(d, W // 2 - 2, y + 2, W // 2 + 2, y + 5, hexc("#9fe0b0"))
        d.rectangle([W // 2 - 4, y, W // 2 + 4, y + 12], outline=OUT)
        rect(dl, W // 2 - 2, y + 2, W // 2 + 2, y + 5, (120, 255, 160, 200))
        d.line([W // 2 + 4, y + 8, W // 2 + 9, y + 14], fill=OUT)
    return img, lit


def _sicherheit(W, H):
    img, lit = new(W, H), new(W, H)
    d, dl = ImageDraw.Draw(img), ImageDraw.Draw(lit)
    rect(d, 1, 1, W - 2, H - 2, P["concrete"])
    # Lichtmast mit Kamera und Torpfosten
    rect(d, W // 2 - 1, 4, W // 2, H - 6, hexc("#5c6068"))
    rect(d, W // 2 - 6, 3, W // 2 + 5, 6, hexc("#3a3e46"))
    rect(d, W // 2 + 2, 9, W // 2 + 7, 12, hexc("#2b2b33"))
    d.point((W // 2 + 7, 10), fill=hexc("#e03030"))
    rect(d, W // 2 - 4, H - 6, W // 2 + 3, H - 3, hexc("#3a3e46"))
    dl.ellipse([2, 2, W - 3, H - 3], fill=(255, 240, 180, 110))
    rect(dl, W // 2 - 6, 3, W // 2 + 5, 7, (255, 250, 210, 230))
    return img, lit


def _waschplatz(W, H):
    img, lit, d, dl = _open_pad(W, H)
    rect(d, 4, 4, W - 5, H - 5, hexc("#4f7fa8"))
    for y in range(6, H - 6, 4):
        d.line([6, y, W - 7, y], fill=hexc("#6f9fc8"))
    # Waschbuerstenportal
    rect(d, 4, H // 2 - 3, W - 5, H // 2 + 3, hexc("#d4d7dc"))
    for x in range(8, W - 8, 6):
        d.ellipse([x - 3, H // 2 - 6, x + 3, H // 2 + 6], fill=hexc("#3c7fc8"), outline=OUT)
    d.rectangle([4, 4, W - 5, H - 5], outline=OUT)
    rect(dl, 4, H // 2 - 3, W - 5, H // 2 + 3, (180, 220, 255, 120))
    return img, lit


def _save_custom(name, img, lit, w, h):
    save(img, "b_" + name)
    save(lit, "b_" + name + "_lit")
    buildings[name] = {"w": w, "h": h}


def _fac_building(typ, w, h, suffix):
    styles = {
        "buero": dict(roof=hexc("#3f4452"), wall=hexc("#c9cdd4"), facade=26, roof_style="flat", win_cols=3,
                      win_col=hexc("#6fa3c9"), sign=hexc("#2f5f9f")),
        "disposition": dict(roof=hexc("#46638f"), wall=hexc("#dfe3e8"), facade=24, roof_style="flat", win_cols=4,
                            win_col=hexc("#4f8fbf"), sign=hexc("#e07a2a")),
        "garage": dict(roof=hexc("#6f7a84"), wall=hexc("#b8bcc2"), facade=24, roof_style="flat", door=False,
                       extra=big_doors),
        "werkstatt": dict(roof=hexc("#5a5e6a"), wall=hexc("#d9c7a3"), facade=26, roof_style="flat",
                          sign=hexc("#e07a2a"), door=False, extra=big_doors),
        "lager": dict(roof=hexc("#7a7f88"), wall=hexc("#c4c8ce"), facade=30, roof_style="pitched", win_cols=5,
                      door=False, extra=big_doors),
        "kuehllager": dict(roof=hexc("#e8eef4"), wall=hexc("#9ec4e0"), facade=26, roof_style="flat", win_cols=2,
                           door=False, sign=hexc("#2a9ae0"), extra=big_doors),
        "pausenraum": dict(roof=hexc("#7d5a3c"), wall=hexc("#e6dcc4"), facade=22, roof_style="pitched", win_cols=3,
                           awning=hexc("#3c9a5a")),
        "schulung": dict(roof=hexc("#4a7a5a"), wall=hexc("#e2dccb"), facade=22, roof_style="pitched", win_cols=3,
                         sign=hexc("#2f9a5a")),
        "mietbuero": dict(roof=hexc("#4e5360"), wall=hexc("#a8b4c4"), facade=34, roof_style="flat", win_cols=5,
                          win_rows=2, win_col=hexc("#4f8fbf"), sign=hexc("#7a4ab0")),
    }
    st = dict(styles[typ])
    building("fac_" + typ + suffix, w, h, st.pop("roof"), st.pop("wall"), st.pop("facade"), st.pop("roof_style"), **st)


def gen_facilities():
    custom = {"stellplatz": _stellplatz, "laderampe": _laderampe, "tankstelle": _tankstelle,
              "ladepunkt": _ladepunkt, "sicherheit": _sicherheit, "waschplatz": _waschplatz}
    for typ, (w, h) in FAC_SIZES.items():
        for suffix, (ww, hh) in [("", (w, h)), ("_r", (h, w))]:
            if suffix and w == h:
                continue
            if typ in custom:
                img, lit = custom[typ](ww * T, hh * T)
                _save_custom("fac_" + typ + suffix, img, lit, ww, hh)
            else:
                _fac_building(typ, ww, hh, suffix)
    # Bueroausbau: Stufenschild (1 Stern je Stufe) wird im Spiel gezeichnet; Baustellenzaun als Kachel
    img = new(T, T)
    d = ImageDraw.Draw(img)
    for x in range(0, T, 8):
        rect(d, x, 0, x + 3, T - 1, (230, 120, 40, 210))
    d.rectangle([0, 0, T - 1, T - 1], outline=(40, 30, 20, 220))
    save(img, "fac_site")


# ---------------------------------------------------------------- Deko
def gen_decor():
    for i, (leaf, dark) in enumerate(((hexc("#3f8f3a"), hexc("#2c6a2a")), (hexc("#5aa043"), hexc("#3c7a2e")),
                                      (hexc("#2f7a4a"), hexc("#1f5a36")))):
        img = new(T, T)
        d = ImageDraw.Draw(img)
        d.ellipse([7, 23, 25, 30], fill=(0, 0, 0, 70))
        rect(d, 14, 18, 17, 27, hexc("#6b4a2b"))
        if i == 2:  # Nadelbaum
            for k in range(4):
                d.polygon([(16, 2 + k * 5), (6 + k, 14 + k * 3), (26 - k, 14 + k * 3)], fill=leaf if k % 2 else dark)
            d.polygon([(16, 2), (6, 20), (26, 20)], outline=OUT)
        else:
            d.ellipse([5, 3, 27, 22], fill=dark, outline=OUT)
            d.ellipse([7, 4, 24, 18], fill=leaf)
            for _ in range(10):
                d.point((rng.randrange(9, 23), rng.randrange(6, 17)), fill=shade(leaf, 1.3))
        save(img, "d_tree%d" % i)
    img = new(T, T)
    d = ImageDraw.Draw(img)
    d.ellipse([8, 16, 24, 28], fill=hexc("#3f8f3a"), outline=OUT)
    d.point((13, 20), fill=hexc("#ef6f8f"))
    d.point((19, 22), fill=hexc("#f2e463"))
    save(img, "d_bush")
    # Laterne (16x32)
    img = new(16, 32)
    d = ImageDraw.Draw(img)
    rect(d, 7, 8, 8, 30, hexc("#3a3f4a"))
    rect(d, 4, 5, 11, 8, hexc("#3a3f4a"))
    rect(d, 5, 8, 10, 9, hexc("#fff3b0"))
    rect(d, 6, 30, 9, 31, OUT)
    save(img, "d_lamp")
    # Ampel: 3 Zustaende (rot/gruen/aus) 8x14
    for st, col in (("red", hexc("#ff3b30")), ("green", hexc("#38e060"))):
        img = new(8, 14)
        d = ImageDraw.Draw(img)
        rect(d, 1, 0, 6, 10, OUT)
        rect(d, 3, 10, 4, 13, hexc("#3a3f4a"))
        d.point((3, 2), fill=col if st == "red" else hexc("#552222"))
        d.point((4, 2), fill=col if st == "red" else hexc("#552222"))
        d.point((3, 7), fill=col if st == "green" else hexc("#225522"))
        d.point((4, 7), fill=col if st == "green" else hexc("#225522"))
        save(img, "d_light_" + st)
    # Bank
    img = new(T, 16)
    d = ImageDraw.Draw(img)
    rect(d, 4, 4, 27, 7, hexc("#8a5a34"))
    rect(d, 4, 9, 27, 11, hexc("#8a5a34"))
    rect(d, 5, 12, 6, 15, OUT)
    rect(d, 25, 12, 26, 15, OUT)
    save(img, "d_bench")
    # Lichtkegel (radial, weiss -> transparent)
    for name, size in (("glow_small", 48), ("glow_big", 96)):
        img = new(size, size)
        px = img.load()
        c = size / 2
        for y in range(size):
            for x in range(size):
                r = math.hypot(x + 0.5 - c, y + 0.5 - c) / c
                if r < 1:
                    a = int(255 * (1 - r) ** 2)
                    a = (a // 32) * 32  # gestuft = Pixel-Look
                    px[x, y] = (255, 255, 255, a)
        save(img, name)
    # Rauch-Partikel 8x8
    img = new(8, 8)
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, 7, 7], fill=(220, 220, 220, 255))
    d.ellipse([2, 1, 5, 4], fill=(245, 245, 245, 255))
    save(img, "smoke")
    # Regentropfen 2x6
    img = new(2, 6)
    d = ImageDraw.Draw(img)
    rect(d, 0, 0, 1, 5, (190, 210, 255, 180))
    save(img, "rain")
    # Baustelle
    img = new(T, T)
    d = ImageDraw.Draw(img)
    for k in range(3):
        x = 4 + k * 9
        d.polygon([(x + 3, 6), (x, 24), (x + 7, 24)], fill=hexc("#f07818"), outline=OUT)
        rect(d, x + 1, 14, x + 6, 16, P["white"])
    rect(d, 2, 24, 29, 27, hexc("#e8c95a"))
    for x in range(2, 29, 6):
        rect(d, x, 24, x + 2, 27, OUT)
    save(img, "roadwork")
    # Sprechblase 9-Patch 24x24 + Spitze
    img = new(24, 24)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, 23, 23], radius=5, fill=(250, 248, 238, 245), outline=OUT)
    save(img, "bubble")
    img = new(24, 24)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, 23, 23], radius=5, fill=(238, 230, 255, 245), outline=hexc("#5a3fa0"))
    save(img, "bubble_private")
    img = new(10, 6)
    d = ImageDraw.Draw(img)
    d.polygon([(0, 0), (9, 0), (2, 5)], fill=(250, 248, 238, 245))
    d.line([(0, 0), (2, 5), (9, 0)], fill=OUT)
    save(img, "bubble_tail")
    # Auswahlrahmen
    img = new(T, T)
    d = ImageDraw.Draw(img)
    for (x, y) in ((0, 0), (T - 6, 0), (0, T - 6), (T - 6, T - 6)):
        pass
    for k in range(6):
        for (x, y, dx, dy) in ((0, 0, 1, 1), (T - 1, 0, -1, 1), (0, T - 1, 1, -1), (T - 1, T - 1, -1, -1)):
            d.point((x + dx * k, y), fill=hexc("#ffe14d"))
            d.point((x, y + dy * k), fill=hexc("#ffe14d"))
    save(img, "select")


# ---------------------------------------------------------------- Fahrzeuge
vehicles = {}


def vehicle(name, L, Wd, cab, cargo_style):
    """Draufsicht, Fahrtrichtung nach rechts. body = einfaerbbar (weiss/grau), detail = fest."""
    body, det = new(L + 2, Wd + 2), new(L + 2, Wd + 2)
    db, dd = ImageDraw.Draw(body), ImageDraw.Draw(det)
    x0, y0, x1, y1 = 1, 1, L, Wd
    rect(db, x0, y0, x1, y1, (235, 235, 235, 255))
    rect(db, x0, y1 - 1, x1, y1, (190, 190, 190, 255))
    rect(db, x0, y0, x1, y0, (255, 255, 255, 255))
    # Raeder
    for wx in (x0 + 3, x1 - 6):
        rect(dd, wx, y0 - 1, wx + 3, y0, OUT)
        rect(dd, wx, y1, wx + 3, y1 + 1, OUT)
    # Kabine vorne rechts
    cx = x1 - cab
    rect(dd, cx + cab - 4, y0 + 2, cx + cab - 2, y1 - 2, hexc("#6fb0d8"))   # Windschutzscheibe
    rect(dd, cx + cab - 4, y0 + 2, cx + cab - 4, y1 - 2, hexc("#9fd0f0"))
    rect(dd, cx, y0, cx, y1, (0, 0, 0, 90))                                  # Trennkante
    rect(dd, x1, y0 + 1, x1, y0 + 2, hexc("#fff6b0"))                        # Scheinwerfer
    rect(dd, x1, y1 - 2, x1, y1 - 1, hexc("#fff6b0"))
    rect(dd, x0, y0 + 1, x0, y0 + 2, hexc("#d03030"))                        # Ruecklichter
    rect(dd, x0, y1 - 2, x0, y1 - 1, hexc("#d03030"))
    if cargo_style == "box":
        dd.line([x0 + 2, y0 + 2, cx - 2, y0 + 2], fill=(255, 255, 255, 120))
        dd.line([x0 + 2, (y0 + y1) // 2, cx - 2, (y0 + y1) // 2], fill=(0, 0, 0, 50))
    elif cargo_style == "reefer":
        rect(dd, cx - 5, y0 + 2, cx - 2, y1 - 2, hexc("#b8c0c8"))
        for y in range(y0 + 3, y1 - 2, 2):
            dd.point((cx - 4, y), fill=OUT)
    elif cargo_style == "flat":
        for x in range(x0 + 2, cx - 1, 4):
            dd.line([x, y0 + 1, x, y1 - 1], fill=(0, 0, 0, 60))
    elif cargo_style == "trailer":
        dd.line([cx - 2, y0, cx - 2, y1], fill=OUT)
        rect(dd, cx - 1, y0 + 1, cx, y1 - 1, hexc("#3a3a3a"))
        for wx in (x0 + 3, x0 + 8, x0 + 13):
            rect(dd, wx, y0 - 1, wx + 3, y0, OUT)
            rect(dd, wx, y1, wx + 3, y1 + 1, OUT)
    dd.rectangle([x0 - 1, y0 - 1, x1 + 1, y1 + 1], outline=None)
    db.rectangle([x0, y0, x1, y1], outline=(80, 80, 80, 255))
    save(body, "v_%s_body" % name)
    save(det, "v_%s_detail" % name)
    vehicles[name] = {"w": L + 2, "h": Wd + 2}


def gen_cargobike():
    """Lastenrad in Draufsicht: Box vorne (einfaerbbar), Fahrer und Raeder als Detail."""
    L, Wd = 15, 9
    body, det = new(L + 2, Wd + 2), new(L + 2, Wd + 2)
    db, dd = ImageDraw.Draw(body), ImageDraw.Draw(det)
    rect(db, 8, 1, 15, 9, (235, 235, 235, 255))
    db.rectangle([8, 1, 15, 9], outline=(80, 80, 80, 255))
    rect(dd, 1, 4, 8, 6, hexc("#3a3f4a"))          # Rahmen
    rect(dd, 0, 4, 2, 6, OUT)                       # Hinterrad
    rect(dd, 16, 3, 16, 7, OUT)                     # Vorderraeder
    rect(dd, 3, 2, 6, 8, hexc("#3c7fc8"))           # Fahrer (Jacke)
    rect(dd, 4, 4, 5, 6, hexc("#f1c9a5"))           # Kopf
    save(body, "v_cargobike_body")
    save(det, "v_cargobike_detail")
    vehicles["cargobike"] = {"w": L + 2, "h": Wd + 2}


def gen_vehicles():
    vehicle("car", 17, 9, 10, "car")
    vehicle("van", 21, 10, 7, "box")
    vehicle("transporter", 24, 11, 7, "box")
    vehicle("reefer", 24, 11, 7, "reefer")
    vehicle("truck", 30, 12, 8, "flat")
    vehicle("semi", 40, 12, 9, "trailer")
    gen_cargobike()
    # Ladungs-Icons 12x12
    cargo = {
        "pakete": (hexc("#c8975a"), "box"),
        "lebensmittel": (hexc("#6fc06a"), "crate"),
        "getraenke": (hexc("#3c7fc8"), "crate"),
        "elektronik": (hexc("#8a8f99"), "box"),
        "moebel": (hexc("#9a6a3c"), "box"),
        "baustoffe": (hexc("#b0a89a"), "sack"),
        "maschinenteile": (hexc("#6b7380"), "gear"),
        "container": (hexc("#c0392b"), "cont"),
        "medikamente": (hexc("#f0f0f0"), "cross"),
    }
    for name, (col, style) in cargo.items():
        img = new(12, 12)
        d = ImageDraw.Draw(img)
        if style == "cont":
            rect(d, 0, 2, 11, 9, col)
            for x in range(1, 11, 2):
                d.line([x, 3, x, 8], fill=shade(col, 0.75))
            d.rectangle([0, 2, 11, 9], outline=OUT)
        elif style == "sack":
            d.ellipse([1, 2, 10, 11], fill=col, outline=OUT)
            d.line([4, 3, 7, 3], fill=OUT)
        elif style == "gear":
            d.ellipse([1, 1, 10, 10], fill=col, outline=OUT)
            d.ellipse([4, 4, 7, 7], fill=hexc("#3a3f4a"))
        else:
            rect(d, 1, 2, 10, 10, col)
            d.rectangle([1, 2, 10, 10], outline=OUT)
            if style == "box":
                d.line([5, 2, 5, 10], fill=shade(col, 0.7))
            elif style == "crate":
                d.line([1, 6, 10, 6], fill=shade(col, 0.6))
            elif style == "cross":
                rect(d, 5, 3, 6, 9, hexc("#d03030"))
                rect(d, 3, 5, 8, 6, hexc("#d03030"))
        save(img, "c_" + name)


# ---------------------------------------------------------------- Figuren
def gen_characters():
    FW, FH = 16, 24
    styles = [
        (hexc("#f1c9a5"), hexc("#3a2a1e"), "short"),
        (hexc("#c98e64"), hexc("#141414"), "long"),
        (hexc("#8d5a3b"), hexc("#141414"), "short"),
        (hexc("#f1c9a5"), hexc("#d9a640"), "long"),
        (hexc("#e0b088"), hexc("#a8422e"), "bun"),
        (hexc("#f1c9a5"), hexc("#9a9a9a"), "bald"),
    ]
    pants = hexc("#34405a")
    for si, (skin, hair, hs) in enumerate(styles):
        base, shirt = new(FW * 4, FH * 4), new(FW * 4, FH * 4)
        for dir_i in range(4):  # 0 runter, 1 links, 2 rechts, 3 hoch
            for f in range(4):
                ox, oy = f * FW, dir_i * FH
                db, ds = ImageDraw.Draw(base), ImageDraw.Draw(shirt)
                step = [0, 1, 0, -1][f]
                bob = 1 if f in (1, 3) else 0
                # Schatten
                db.ellipse([ox + 3, oy + 20, ox + 12, oy + 23], fill=(0, 0, 0, 70))
                # Beine
                if dir_i in (0, 3):
                    rect(db, ox + 5, oy + 16, ox + 6, oy + 20 + max(0, step), pants)
                    rect(db, ox + 9, oy + 16, ox + 10, oy + 20 + max(0, -step), pants)
                    rect(db, ox + 5, oy + 21 + max(0, step), ox + 6, oy + 21 + max(0, step), OUT)
                    rect(db, ox + 9, oy + 21 + max(0, -step), ox + 10, oy + 21 + max(0, -step), OUT)
                else:
                    rect(db, ox + 6 + step, oy + 16, ox + 7 + step, oy + 21, pants)
                    rect(db, ox + 8 - step, oy + 16, ox + 9 - step, oy + 21, shade(pants, 0.8))
                # Oberkoerper (Hemd -> Maske)
                rect(ds, ox + 4, oy + 9 + bob, ox + 11, oy + 16, (255, 255, 255, 255))
                rect(ds, ox + 4, oy + 15, ox + 11, oy + 16, (200, 200, 200, 255))
                rect(db, ox + 3, oy + 9 + bob, ox + 12, oy + 16, OUT)
                rect(db, ox + 4, oy + 10 + bob, ox + 11, oy + 15, (0, 0, 0, 0))
                # Arme
                if dir_i in (0, 3):
                    rect(db, ox + 3, oy + 10 + bob + step, ox + 3, oy + 14 + bob + step, skin)
                    rect(db, ox + 12, oy + 10 + bob - step, ox + 12, oy + 14 + bob - step, skin)
                else:
                    ax = ox + 7 + step * 2
                    rect(db, ax, oy + 11 + bob, ax + 1, oy + 15 + bob, skin)
                # Kopf
                hy = oy + 2 + bob
                rect(db, ox + 4, hy, ox + 11, hy + 7, skin)
                db.rectangle([ox + 3, hy - 1, ox + 12, hy + 8], outline=OUT)
                if hs != "bald":
                    rect(db, ox + 4, hy, ox + 11, hy + 2, hair)
                    if dir_i == 3:
                        rect(db, ox + 4, hy, ox + 11, hy + 6, hair)
                    if hs == "long" and dir_i != 0:
                        rect(db, ox + 4, hy + 2, ox + 5 if dir_i == 2 else ox + 11, hy + 8, hair)
                    if hs == "long" and dir_i == 0:
                        rect(db, ox + 4, hy + 2, ox + 4, hy + 8, hair)
                        rect(db, ox + 11, hy + 2, ox + 11, hy + 8, hair)
                    if hs == "bun":
                        rect(db, ox + 6, hy - 3, ox + 9, hy - 1, hair)
                else:
                    rect(db, ox + 4, hy + 1, ox + 11, hy + 1, shade(skin, 0.9))
                # Augen
                if dir_i == 0:
                    db.point((ox + 6, hy + 4), fill=OUT)
                    db.point((ox + 9, hy + 4), fill=OUT)
                elif dir_i == 1:
                    db.point((ox + 5, hy + 4), fill=OUT)
                elif dir_i == 2:
                    db.point((ox + 10, hy + 4), fill=OUT)
        img_base = base
        save(img_base, "ch_%d" % si)
        save(shirt, "ch_%d_shirt" % si)


# ---------------------------------------------------------------- UI-Icons 16x16
def gen_icons():
    icons = {}

    def icon(name, fn):
        img = new(16, 16)
        fn(ImageDraw.Draw(img))
        save(img, "i_" + name)

    icon("money", lambda d: (d.ellipse([1, 1, 14, 14], fill=hexc("#e8c95a"), outline=OUT),
                             d.line([8, 4, 8, 11], fill=hexc("#8a6a1a")), d.line([6, 5, 10, 5], fill=hexc("#8a6a1a")),
                             d.line([6, 10, 10, 10], fill=hexc("#8a6a1a"))))
    icon("truck", lambda d: (rect(d, 1, 4, 10, 11, hexc("#dfe3e8")), rect(d, 10, 6, 14, 11, hexc("#3c7fc8")),
                             d.rectangle([1, 4, 14, 11], outline=OUT), d.ellipse([2, 10, 5, 13], fill=OUT),
                             d.ellipse([10, 10, 13, 13], fill=OUT)))
    icon("star", lambda d: d.polygon([(8, 1), (10, 6), (15, 6), (11, 9), (13, 15), (8, 11), (3, 15), (5, 9), (1, 6),
                                      (6, 6)], fill=hexc("#ffd84a"), outline=OUT))
    icon("clock", lambda d: (d.ellipse([1, 1, 14, 14], fill=hexc("#f2efe6"), outline=OUT),
                             d.line([8, 8, 8, 3], fill=OUT), d.line([8, 8, 11, 9], fill=OUT)))
    icon("chat", lambda d: (d.rounded_rectangle([1, 2, 14, 11], radius=3, fill=hexc("#f2efe6"), outline=OUT),
                            d.polygon([(4, 11), (4, 14), (7, 11)], fill=OUT)))
    icon("warn", lambda d: (d.polygon([(8, 1), (15, 14), (1, 14)], fill=hexc("#f0b020"), outline=OUT),
                            d.line([8, 5, 8, 10], fill=OUT), d.point((8, 12), fill=OUT)))
    icon("bolt", lambda d: d.polygon([(9, 1), (3, 9), (7, 9), (6, 15), (13, 6), (9, 6)], fill=hexc("#ff6040"),
                                     outline=OUT))
    icon("api", lambda d: (rect(d, 2, 3, 13, 12, hexc("#3a3f4a")), d.rectangle([2, 3, 13, 12], outline=OUT),
                           rect(d, 4, 6, 5, 7, hexc("#38e060")), rect(d, 10, 6, 11, 7, hexc("#38e060")),
                           d.line([5, 10, 10, 10], fill=hexc("#38e060"))))
    icon("handshake", lambda d: (rect(d, 1, 6, 6, 10, hexc("#c98e64")), rect(d, 9, 6, 14, 10, hexc("#f1c9a5")),
                                 rect(d, 5, 5, 10, 11, hexc("#e0b088")), d.rectangle([1, 5, 14, 11], outline=OUT)))
    icon("wrench", lambda d: (d.line([3, 12, 10, 5], fill=hexc("#b8c0c8"), width=3), d.ellipse([8, 1, 14, 7], fill=hexc("#b8c0c8"), outline=OUT),
                              d.rectangle([10, 3, 12, 5], fill=(0, 0, 0, 0)), d.line([2, 13, 4, 11], fill=OUT)))
    icon("shield", lambda d: d.polygon([(8, 1), (14, 3), (13, 10), (8, 15), (3, 10), (2, 3)], fill=hexc("#3c7fc8"), outline=OUT))
    icon("eye", lambda d: (d.ellipse([1, 4, 14, 12], fill=hexc("#f2efe6"), outline=OUT), d.ellipse([6, 5, 10, 11], fill=hexc("#3a6a3a")),
                           d.point((8, 8), fill=OUT)))
    icon("crate", lambda d: (rect(d, 2, 3, 13, 13, hexc("#c8975a")), d.rectangle([2, 3, 13, 13], outline=OUT),
                             d.line([2, 3, 13, 13], fill=hexc("#8a5a34")), d.line([13, 3, 2, 13], fill=hexc("#8a5a34"))))
    icon("clipboard", lambda d: (rect(d, 3, 2, 12, 14, hexc("#c89a5a")), d.rectangle([3, 2, 12, 14], outline=OUT),
                                 rect(d, 5, 4, 10, 12, hexc("#f2efe6")), d.line([6, 6, 9, 6], fill=OUT), d.line([6, 8, 9, 8], fill=OUT),
                                 rect(d, 6, 1, 9, 3, hexc("#8a8f99"))))
    icon("drive", lambda d: (d.ellipse([2, 2, 13, 13], outline=OUT, width=2), d.line([7, 7, 7, 12], fill=OUT, width=2),
                             d.line([3, 7, 12, 7], fill=OUT, width=2)))
    icon("envelope", lambda d: (rect(d, 1, 3, 14, 12, hexc("#f2efe6")), d.rectangle([1, 3, 14, 12], outline=OUT),
                                d.line([1, 3, 8, 8, 14, 3], fill=OUT)))


# ---------------------------------------------------------------- Sounds
def write_wav(name, samples, rate=22050):
    with wave.open(os.path.join(SFX, name + ".wav"), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 26000)) for s in samples))


def tone(freqs, dur, rate=22050, wave_type="square", vol=0.35, decay=4.0):
    out = []
    n = int(dur * rate)
    for i in range(n):
        t = i / rate
        f = freqs[min(len(freqs) - 1, int(i / n * len(freqs)))]
        ph = (t * f) % 1.0
        if wave_type == "square":
            s = 1.0 if ph < 0.5 else -1.0
        elif wave_type == "tri":
            s = 4 * abs(ph - 0.5) - 1
        else:
            s = math.sin(2 * math.pi * ph)
        out.append(s * vol * math.exp(-decay * t))
    return out


def gen_sounds():
    write_wav("click", tone([880], 0.05, decay=30, vol=0.25))
    write_wav("cash", tone([988, 1319, 1760], 0.28, decay=5))
    write_wav("message", tone([660, 880], 0.16, wave_type="tri", decay=8))
    write_wav("alert", tone([440, 330, 440, 330], 0.4, decay=3))
    write_wav("horn", tone([370], 0.25, wave_type="square", vol=0.22, decay=2) )
    noise = random.Random(5)
    boom = [(noise.random() * 2 - 1) * 0.6 * math.exp(-6 * i / 22050) for i in range(int(0.5 * 22050))]
    write_wav("sabotage", boom)
    write_wav("deal", tone([523, 659, 784, 1047], 0.45, wave_type="tri", decay=3))
    write_wav("end", tone([523, 659, 784, 659, 784, 1047], 1.0, wave_type="tri", decay=1.5))


def main():
    os.makedirs(GFX, exist_ok=True)
    os.makedirs(SFX, exist_ok=True)
    gen_tiles()
    atlas = new(TILE_COLS * T, ((len(tile_imgs) + TILE_COLS - 1) // TILE_COLS) * T)
    for i, img in enumerate(tile_imgs):
        atlas.paste(img, ((i % TILE_COLS) * T, (i // TILE_COLS) * T))
    atlas.save(os.path.join(GFX, "tiles.png"))
    gen_buildings()
    state = rng.getstate()   # Einrichtungen sollen die uebrigen Zufallsgrafiken nicht veraendern
    gen_facilities()
    rng.setstate(state)
    gen_decor()
    gen_vehicles()
    gen_characters()
    gen_icons()
    gen_sounds()
    with open(os.path.join(GFX, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"tile_size": T, "tiles": tiles, "buildings": buildings, "vehicles": vehicles}, f, indent=1)
    print("tiles:", len(tile_imgs), "buildings:", len(buildings), "vehicles:", len(vehicles))


if __name__ == "__main__":
    main()
