"""Bauteile fuer oeffentliche Anlagen und Denkmaeler (Auftrag 19): Spielgeraete, Marktstaende, Sportgeraete, Statuen, Obelisk,
Triumphbogen sowie Gabelstapler und Palettenregal fuer das Grosslager. Ein Feld = 32x32 Voxel, Boden z = 1, mittig im Grundriss.
Statuen und Bogen tragen eine Farbmaske ("comp"): im Spiel bekommt jedes Denkmal die Farbe seines Buergermeisters."""
import math
import random

from engine import Model, mat, M
from lib import tree, bush, bench, lamp_post

T = 32


def init():
    mat("bronze", "#a8743a", noise=0.05)
    mat("bronze_dark", "#7c5527", noise=0.05)
    mat("marble", "#e7e3d9", noise=0.03)
    mat("marble2", "#d3cec2", noise=0.03)
    mat("granite", "#8b8b8f", noise=0.06)
    mat("rubber", "#3b3d42", noise=0.03)
    mat("play_red", "#d4483c", noise=0.03)
    mat("play_yel", "#ecc23a", noise=0.03)
    mat("play_blu", "#3f86cf", noise=0.03)
    mat("play_grn", "#5cae4e", noise=0.03)
    mat("sand_pit", "#e0cb8e", noise=0.08)
    mat("net", "#e8e8e8", noise=0.02)
    mat("awning_r", "#c84a3c", noise=0.02)
    mat("awning_w", "#f1ece0", noise=0.02)
    mat("awning_g", "#4f9a5a", noise=0.02)
    mat("awning_b", "#4a78b8", noise=0.02)
    mat("fruit_o", "#e8902e", noise=0.10)
    mat("fruit_g", "#7cbf45", noise=0.10)
    mat("flood", "#fff6c8", noise=0.0, emit="#fff3b0")
    mat("seat_b", "#3f74c2", noise=0.03)
    mat("seat_w", "#e9e6dd", noise=0.03)
    mat("fork_yel", "#e6b52a", noise=0.04)
    mat("pallet", "#b48a58", noise=0.08)
    mat("box_brn", "#a0754a", noise=0.06)


def _m(h=70):
    return Model(T, T, h)


# ------------------------------------------------------------------ Spielplatz
def swing():
    m = _m(30)
    for x in (5, 26):
        m.box(x, 8, 1, x + 1, 9, 22, M("steel_dark"))
        m.box(x, 22, 1, x + 1, 23, 22, M("steel_dark"))
    m.box(5, 8, 22, 27, 23, 23, M("steel_dark"))
    for sx, col in ((10, "play_red"), (19, "play_blu")):
        m.box(sx, 15, 9, sx + 1, 16, 22, M("steel"))
        m.box(sx + 3, 15, 9, sx + 4, 16, 22, M("steel"))
        m.box(sx, 14, 8, sx + 4, 17, 9, M(col))
    return m


def slide():
    m = _m(32)
    m.box(4, 10, 1, 12, 18, 14, M("play_yel"))           # Plattform mit Leiter
    m.box(4, 10, 14, 12, 18, 15, M("play_red"))
    m.box(4, 10, 15, 5, 18, 20, M("play_red"))
    for z in range(2, 14, 3):
        m.box(2, 12, z, 4, 16, z + 1, M("steel"))
    for i in range(16):                                   # Rutschbahn
        z = 14 - int(i * 0.85)
        m.box(12 + i, 11, z, 13 + i, 17, z + 1, M("play_blu"))
        m.box(12 + i, 10, z + 1, 13 + i, 11, z + 2, M("play_blu"))
        m.box(12 + i, 17, z + 1, 13 + i, 18, z + 2, M("play_blu"))
    return m


def climber():
    m = _m(30)
    cols = ["play_red", "play_yel", "play_blu", "play_grn"]
    for i, x in enumerate(range(4, 29, 6)):
        for y in (6, 25):
            m.box(x, y, 1, x + 1, y + 1, 20, M("steel_dark"))
        for z in range(5, 21, 5):
            m.box(x, 6, z, x + 1, 26, z + 1, M(cols[i % 4]))
    for z in range(5, 21, 5):
        m.box(4, 6, z, 29, 7, z + 1, M("steel"))
        m.box(4, 25, z, 29, 26, z + 1, M("steel"))
    m.box(6, 9, 20, 27, 23, 21, M("wood"))
    return m


def sandbox():
    m = _m(10)
    m.box(3, 3, 1, 29, 29, 3, M("wood"))
    m.box(5, 5, 1, 27, 27, 3, M("sand_pit"))
    m.box(9, 10, 3, 13, 13, 5, M("sand_pit"))
    m.box(18, 18, 3, 21, 21, 4, M("play_red"))          # Eimer
    m.box(20, 8, 3, 23, 10, 4, M("play_yel"))           # Schaufel
    return m


def seesaw():
    m = _m(16)
    m.box(14, 14, 1, 18, 18, 6, M("steel_dark"))
    m.box(2, 14, 6, 30, 18, 7, M("play_grn"))
    m.box(3, 15, 7, 5, 17, 10, M("play_red"))
    m.box(27, 15, 7, 29, 17, 10, M("play_red"))
    return m


# ------------------------------------------------------------------ Markt und Park
def market_stall(variant=0):
    m = _m(36)
    awn = [("awning_r", "awning_w"), ("awning_g", "awning_w"), ("awning_b", "awning_w"), ("play_yel", "awning_w")][variant % 4]
    for x, y in ((4, 6), (27, 6), (4, 26), (27, 26)):
        m.box(x, y, 1, x + 1, y + 1, 20, M("frame_wood"))
    m.box(4, 8, 8, 28, 26, 10, M("wood"))               # Verkaufstisch
    goods = ["fruit_o", "fruit_g", "flower_r", "box_brn"]
    for i, x in enumerate(range(6, 26, 5)):
        m.box(x, 12, 10, x + 4, 22, 12, M(goods[(i + variant) % 4]))
    for i, x in enumerate(range(3, 30, 3)):            # gestreiftes Dach
        m.box(x, 4, 20 + (1 if i % 2 else 0), x + 3, 28, 22, M(awn[i % 2]))
    return m


def flowerbed(seed=1):
    m = _m(12)
    m.box(4, 4, 1, 28, 28, 3, M("stone_base"))
    m.box(6, 6, 1, 26, 26, 3, M("soil"))
    rng = random.Random(seed)
    for _ in range(6):
        bush(m, rng.randint(9, 23), rng.randint(9, 23), 3, 3, flowers=rng.choice(["flower_r", "flower_y", "flower_p", "flower_w"]), rng=rng)
    return m


def picnic():
    m = _m(16)
    m.box(8, 10, 6, 24, 22, 7, M("wood"))
    for x in (9, 22):
        m.box(x, 15, 1, x + 1, 17, 6, M("frame_wood"))
    m.box(8, 6, 3, 24, 8, 4, M("wood"))
    m.box(8, 24, 3, 24, 26, 4, M("wood"))
    return m


# ------------------------------------------------------------------ Sport
def goal():
    m = _m(20)
    m.box(4, 14, 1, 5, 15, 12, M("white"))
    m.box(27, 14, 1, 28, 15, 12, M("white"))
    m.box(4, 14, 12, 28, 15, 13, M("white"))
    for x in range(5, 27, 3):
        m.box(x, 15, 1, x + 1, 20, 12, M("net"))
    m.box(5, 19, 1, 27, 20, 12, M("net"))
    return m


def floodlight():
    m = _m(70)
    m.box(15, 15, 1, 17, 17, 56, M("steel_dark"))
    m.box(9, 14, 56, 23, 18, 62, M("frame_dark"))
    m.box(10, 13, 57, 22, 14, 61, M("flood"))
    return m


def tribune():
    """Tribuene: Sitzreihen steigen nach hinten an und schauen zum Betrachter (Spielfeld davor)."""
    m = Model(2 * T, T, 30)
    for i in range(5):
        z = 2 + i * 4
        y0 = 26 - i * 5
        m.box(2, y0 - 5, 1, 62, y0, z + 2, M("concrete"))
        for x in range(4, 60, 3):
            m.box(x, y0 - 4, z + 2, x + 2, y0 - 2, z + 4, M("seat_b" if (x // 3 + i) % 4 else "seat_w"))
    m.box(2, 0, 1, 62, 2, 26, M("frame_dark"))
    m.box(2, 0, 24, 62, 16, 26, M("zinc"))
    return m


def basket_hoop():
    m = _m(40)
    m.box(15, 24, 1, 17, 26, 30, M("steel_dark"))
    m.box(11, 21, 28, 21, 22, 36, M("white"))
    m.box(14, 17, 28, 18, 21, 29, M("orange"))
    return m


# ------------------------------------------------------------------ Denkmaeler (Farbmaske = Buergermeister)
def _pedestal(m, x0, y0, x1, y1, h, stone="granite"):
    m.box(x0 - 2, y0 - 2, 1, x1 + 2, y1 + 2, 3, M("stone_base"))
    m.box(x0, y0, 3, x1, y1, h, M(stone))
    m.box(x0 - 1, y0 - 1, h, x1 + 1, y1 + 1, h + 1, M("marble2"))


def _figure(m, cx, cy, z, scale=1.0, body="bronze", sash=True):
    s = scale
    def b(x0, y0, z0, x1, y1, z1, mt):
        m.box(int(cx + x0 * s), int(cy + y0 * s), int(z + z0 * s), int(cx + x1 * s) + 1, int(cy + y1 * s) + 1, int(z + z1 * s) + 1, M(mt))
    b(-3, -1, 0, -1, 1, 7, body)          # Beine
    b(1, -1, 0, 3, 1, 7, body)
    b(-3, -2, 7, 3, 2, 15, body)          # Rumpf
    if sash:
        b(-3, 2, 11, 3, 2, 13, "comp")    # Amtsschaerpe in Buergermeisterfarbe (sichtbare Seiten)
        b(3, -2, 11, 3, 2, 13, "comp")
    b(-5, -1, 9, -4, 1, 15, body)         # Arme, rechter erhoben
    b(4, -1, 13, 5, 1, 20, body)
    b(-2, -2, 15, 2, 2, 19, body)         # Kopf
    b(-2, -2, 19, 2, 2, 20, "comp_dark")  # Hut


def statue_bust():
    m = _m(36)
    _pedestal(m, 11, 11, 21, 21, 14, "marble")
    m.box(12, 13, 15, 20, 19, 20, M("bronze"))
    m.box(13, 13, 18, 19, 19, 19, M("comp"))
    m.box(13, 14, 20, 19, 18, 27, M("bronze"))
    m.box(13, 14, 27, 19, 18, 28, M("comp_dark"))
    return m


def statue_bronze():
    m = _m(56)
    _pedestal(m, 10, 10, 22, 22, 16)
    _figure(m, 16, 16, 17, scale=1.5)
    return m


def statue_rider():
    m = Model(T, T, 64)
    _pedestal(m, 6, 10, 26, 22, 14)
    m.box(9, 13, 15, 23, 19, 24, M("bronze_dark"))       # Pferdeleib
    for x in (9, 21):
        m.box(x, 13, 15, x + 2, 19, 15, M("bronze_dark"))
    m.box(23, 14, 22, 27, 18, 31, M("bronze_dark"))      # Hals und Kopf
    m.box(8, 15, 20, 9, 17, 28, M("bronze_dark"))        # Schweif
    _figure(m, 15, 16, 24, scale=1.0)
    return m


def statue_giant():
    """Monumentale Steinstatue: riesige Figur auf Stufensockel, Grünflaeche, Fackeln."""
    m = Model(2 * T, 2 * T, 120)
    m.box(0, 0, 1, 64, 64, 2, M("lawn"))
    for i, r in enumerate((26, 22, 18)):
        m.box(32 - r, 32 - r, 2 + i * 3, 32 + r, 32 + r, 5 + i * 3, M("granite" if i % 2 else "marble2"))
    _pedestal(m, 22, 22, 42, 42, 24, "marble")
    _figure(m, 32, 32, 25, scale=4.0, body="marble")
    for x, y in ((8, 8), (56, 8), (8, 56), (56, 56)):
        lamp_post(m, x, y, 2, h=14)
    return m


def obelisk():
    m = _m(110)
    _pedestal(m, 9, 9, 23, 23, 10, "granite")
    for i in range(80):
        r = 4 - i // 26
        m.box(16 - r, 16 - r, 11 + i, 16 + r, 16 + r, 12 + i, M("marble"))
    m.box(14, 14, 91, 18, 18, 95, M("comp"))
    m.box(15, 15, 95, 17, 17, 98, M("bronze"))
    return m


def fountain_monument():
    m = Model(2 * T, 2 * T, 60)
    c = 32
    for x in range(64):
        for y in range(64):
            d = math.hypot(x - c, y - c)
            if d < 28:
                m.put(x, y, 1, M("stone_base"))
                if d > 25:
                    m.box(x, y, 2, x + 1, y + 1, 5, M("marble2"))
                else:
                    m.put(x, y, 2, M("water"))
    _pedestal(m, 26, 26, 38, 38, 14, "marble")
    _figure(m, 32, 32, 15, scale=1.8)
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        for k in range(10):
            m.put(c + dx * (8 + k), c + dy * (8 + k), 12 - k // 2, M("water2"))
    return m


def triumph_arch():
    m = Model(2 * T, T, 90)
    m.box(4, 8, 1, 20, 24, 60, M("marble"))
    m.box(44, 8, 1, 60, 24, 60, M("marble"))
    m.box(4, 8, 60, 60, 24, 80, M("marble"))
    m.box(4, 8, 80, 60, 24, 83, M("marble2"))
    m.box(20, 23, 66, 44, 24, 74, M("comp"))             # Inschrift in Buergermeisterfarbe (sichtbare Seite)
    m.box(28, 13, 83, 36, 19, 86, M("bronze"))
    _figure(m, 32, 16, 86, scale=0.8)
    for x in (6, 16, 46, 56):
        m.box(x, 7, 1, x + 2, 8, 60, M("marble2"))
    return m


# ------------------------------------------------------------------ Grosslager
def forklift():
    m = _m(28)
    m.box(8, 10, 2, 22, 22, 9, M("fork_yel"))
    m.box(10, 12, 9, 20, 20, 17, M("fork_yel"))
    m.box(10, 12, 17, 20, 20, 18, M("frame_dark"))
    for x, y in ((8, 9), (20, 9), (8, 22), (20, 22)):
        m.box(x, y, 1, x + 3, y + 1, 4, M("rubber"))
    m.box(6, 12, 1, 7, 20, 24, M("steel_dark"))           # Hubmast
    m.box(1, 13, 3, 7, 14, 4, M("steel"))
    m.box(1, 18, 3, 7, 19, 4, M("steel"))
    m.box(1, 12, 4, 7, 20, 6, M("pallet"))
    m.box(2, 13, 6, 7, 19, 11, M("box_brn"))
    return m


def pallet_rack():
    m = Model(T, T, 64)
    for x in (3, 28):
        for y in (8, 23):
            m.box(x, y, 1, x + 1, y + 1, 58, M("blue"))
    for z in (1, 15, 29, 43):
        m.box(3, 8, z + 12, 29, 24, z + 13, M("orange"))
        for x in range(5, 27, 7):
            m.box(x, 10, z + 13 if z > 1 else 1, x + 6, 22, z + 14 if z > 1 else 2, M("pallet"))
            m.box(x, 11, z + 14 if z > 1 else 2, x + 6, 21, z + 22 if z > 1 else 10, M("box_brn" if (x + z) % 2 else "cardboard"))
    return m
