"""Industrie, Lager, Hafen, Landwirtschaft, Depot, Baustelle, Kran, Brunnen, Frachtterminal (je als vollstaendiges Grundstueck)."""
import math
import random

from engine import Model, M
from lib import (Win, window, door, block, facade_windows, gable_roof, hip_roof, flat_roof, chimney, tree, bush, hedge,
                 fence, wall_fence, lamp_post, bin_, bench, car, pallet_stack, container, slab, grass_fn, paving_fn, deck_fn, flowerbed,
                 _blob)

T = 32


def _roll_door(m, u, w, z, plane, h=16, face="s"):
    for a in range(u, u + w):
        for c in range(z, z + h):
            mm = M("steel") if (c - z) % 3 else M("steel_dark")
            if face == "s":
                m.put(a, plane - 1, c, mm)
            else:
                m.put(plane - 1, a, c, mm)
    for c in range(z, z + h + 1):
        for a in (u - 1, u + w):
            if face == "s":
                m.put(a, plane - 1, c, M("yellow"))
            else:
                m.put(plane - 1, a, c, M("yellow"))


def _ramp_edge(m, x0, x1, y, z=1):
    for x in range(x0, x1, 4):
        m.box(x, y, z, x + 2, y + 1, z + 1, M("yellow"))


def factory(seed=1):
    """Fabrik 4x4: Backstein-Produktionshalle mit Sheddach, Schornstein, Silos, Rohrbruecke, Laderampe und Lkw."""
    rng = random.Random(seed)
    W = H = 4 * T
    m = Model(W, H, 110)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    x0, y0, x1, y1 = 6, 6, 92, 80
    block(m, x0, y0, 1, x1, y1, 34, "brick", base="stone_base", base_h=3)
    facade_windows(m, x0, y0, x1, y1, 1, 1, 30, Win(8, 12, frame="frame_dark", lit=0.5, lit_mat="glass_lit", cross=True, sill=False), rng, spacing=14, margin=6)
    # Sheddach
    for k, xs in enumerate(range(x0, x1, 14)):
        for z in range(34, 44):
            m.box(xs, y0, z, xs + max(1, 14 - (z - 34) * 3 // 2), y1, z + 1, M("zinc" if k % 2 else "steel"))
        m.box(xs + 2, y0, 34, xs + 3, y1, 44, M("glass_lit2" if rng.random() < 0.4 else "glass"))
    _roll_door(m, 20, 14, 1, y1)
    _roll_door(m, 52, 14, 1, y1)
    door(m, "s", 78, 2, y1, w=5, h=11, canopy=True)
    # Schornstein und Silos
    m.box(100, 10, 1, 108, 18, 70, M("brick2"))
    for z in range(66, 70):
        m.box(100, 10, z, 108, 18, z + 1, M("white" if z % 2 else "red"))
    for sx, sy in ((100, 40), (100, 62)):
        for z in range(1, 50):
            r = 7
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    if dx * dx + dy * dy <= r * r:
                        m.put(sx + dx, sy + dy, z, M("steel" if (z // 6) % 2 == 0 else "zinc"))
        for dz in range(0, 6):
            r = 7 - dz
            for dx in range(-r, r + 1):
                for dy in range(-r, r + 1):
                    if dx * dx + dy * dy <= r * r:
                        m.put(sx + dx, sy + dy, 50 + dz, M("steel_dark"))
    for y in range(18, 62, 4):
        m.box(92, y, 24, 100, y + 2, 26, M("orange"))
    m.box(92, 18, 24, 94, 62, 26, M("orange"))
    # Hof
    car(m, 16, 100, 1, "white", "x")
    container(m, 56, 100, 1, "blue", "x")
    pallet_stack(m, 10, 90, 1, h=2, goods="fabric_w")
    pallet_stack(m, 20, 90, 1, h=3, goods="wood")
    lamp_post(m, 90, 90, 1, h=18)
    chimney_smoke = (104, 14)
    return m, {"w": 4, "h": 4, "entrance": [85, H - 20], "delivery": [38, H - 20], "height": 100, "smoke": [chimney_smoke[0] * 2 - chimney_smoke[1] * 2, chimney_smoke[0] + chimney_smoke[1] - 140]}


def warehouse(seed=1):
    """Lagerhalle 4x3: Wellblechhalle mit Rolltoren, Laderampe mit Lkw-Andockstellen, Paletten, Gabelstapler."""
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 60)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    x0, y0, x1, y1 = 6, 6, 96, 60
    block(m, x0, y0, 1, x1, y1, 30, "zinc", base="concrete", base_h=4)
    for u in range(x0 + 2, x1, 4):
        m.box(u, y1 - 1, 4, u + 1, y1, 30, M("steel"))
    m.box(x0 - 1, y1, 30, x1 + 1, y1 + 1, 32, M("steel_dark"))
    gable_roof(m, x0, y0, x1, y1, 30, ridge="x", tile="steel", tile2="steel_dark", pitch=0.28, overhang=1)
    for k in range(4):
        _roll_door(m, 12 + k * 20, 12, 5, y1, h=15)
        m.box(12 + k * 20 - 1, y1, 1, 12 + k * 20 + 13, y1 + 10, 5, M("concrete2"))
        m.box(12 + k * 20, y1 + 9, 5, 12 + k * 20 + 12, y1 + 10, 6, M("black"))
    window(m, "e", 20, 14, x1, Win(8, 8, frame="frame_dark", lit=0.5), rng)
    door(m, "e", 38, 2, x1, w=5, h=11, canopy=True)
    m.box(86, 12, 31, 94, 20, 36, M("steel"))
    pallet_stack(m, 6, 72, 1, h=3, goods="wood")
    pallet_stack(m, 16, 72, 1, h=2, goods="fabric_w")
    car(m, 60, 74, 1, "white", "x")
    m.box(60, 74, 7, 64, 87, 20, M("white")) if False else None
    lamp_post(m, 94, 76, 1, h=16)
    tree(m, 86, 82, 1, kind="conifer", size=0.7, rng=rng)
    return m, {"w": 4, "h": 3, "entrance": [60, H], "delivery": [60, H], "height": 40}


def farm(seed=1):
    """Hof 3x3: Wohnhaus, Scheune mit Dach, Silo, Heuballen, Zaun, Traktor, Obstbaeume."""
    rng = random.Random(seed)
    W = H = 3 * T
    m = Model(W, H, 80)
    slab(m, 0, 0, W, H, grass_fn(9))
    slab(m, 0, 52, W, 80, lambda x, y: M("soil") if (y // 3) % 2 else M("gravel"))
    block(m, 8, 6, 1, 38, 32, 22, "plaster_white", base="stone_base", base_h=3)
    gable_roof(m, 8, 6, 38, 32, 22, ridge="y", tile="tile_red", tile2="tile_red2", pitch=1.0)
    window(m, "s", 12, 6, 32, Win(6, 9, frame="frame_wood", shutters="green_acc", lit=0.6), rng)
    door(m, "s", 26, 2, 32, w=5, h=11, canopy=True)
    window(m, "e", 12, 6, 38, Win(6, 9, frame="frame_wood", lit=0.6), rng)
    block(m, 50, 6, 1, 90, 48, 30, "timber", base=None)
    for u in range(52, 90, 6):
        m.box(u, 47, 3, u + 1, 48, 30, M("plaster_white"))
    m.box(52, 47, 24, 90, 48, 25, M("plaster_white"))
    gable_roof(m, 50, 6, 90, 48, 30, ridge="y", tile="tile_terra2", tile2="tile_terra", pitch=0.75)
    m.clear(60, 46, 1, 78, 48, 22)
    for u in range(60, 78):
        for z in range(1, 22):
            m.put(u, 47, z, M("wood") if (u + z) % 5 else M("timber"))
    for z in range(1, 38):
        for dx in range(-6, 7):
            for dy in range(-6, 7):
                if dx * dx + dy * dy <= 36:
                    m.put(70 + dx, 74 + dy, z, M("zinc" if (z // 5) % 2 == 0 else "steel"))
    for z in range(38, 44):
        r = 6 - (z - 38)
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r:
                    m.put(70 + dx, 74 + dy, z, M("tile_red"))
    for hx, hy in ((8, 70), (16, 76), (10, 84)):
        for z in range(1, 7):
            for dx in range(-4, 5):
                for dy in range(-4, 5):
                    if dx * dx + dy * dy <= 16:
                        m.put(hx + dx, hy + dy, z, M("sand" if z % 2 else "plaster_ochre"))
    fence(m, 0, 92, 96, 93, 1, 4, "frame_wood", posts=6)
    for tx, ty in ((44, 60), (50, 68)):
        tree(m, tx, ty, 1, kind="blossom", size=0.8, rng=rng)
    # Traktor
    m.box(30, 62, 4, 44, 70, 9, M("green_acc"))
    m.box(34, 62, 9, 40, 70, 16, M("glass_dark"))
    m.box(30, 61, 1, 36, 62, 8, M("black"))
    m.box(30, 70, 1, 36, 71, 8, M("black"))
    m.box(40, 61, 1, 44, 62, 5, M("black"))
    m.box(40, 70, 1, 44, 71, 5, M("black"))
    return m, {"w": 3, "h": 3, "entrance": [30, H], "delivery": [30, H], "height": 44}


def port_office(seed=1):
    """Hafenkontor 3x2: Klinkerhaus mit Turmaufsatz, Anleger, Poller, Tonnen."""
    rng = random.Random(seed)
    W, H = 3 * T, 2 * T
    m = Model(W, H, 70)
    slab(m, 0, 0, W, H, paving_fn(4, "concrete", "concrete2"))
    x0, y0, x1, y1 = 8, 6, 78, 42
    block(m, x0, y0, 1, x1, y1, 32, "brick", base="stone_base", base_h=4, cornice="sandstone")
    facade_windows(m, x0, y0, x1, y1, 1, 2, 14, Win(6, 9, frame="frame_white", lit=0.55), rng, spacing=11, margin=6)
    gable_roof(m, x0, y0, x1, y1, 32, ridge="x", tile="slate", tile2="slate2", pitch=0.6)
    block(m, 36, 14, 32, 52, 30, 52, "plaster_white", base=None)
    hip_roof(m, 36, 14, 52, 30, 52, tile="tile_red", tile2="tile_red2", pitch=1.0, overhang=1)
    window(m, "s", 40, 38, 30, Win(8, 8, frame="frame_white", lit=0.9, cross=False), rng)
    door(m, "s", 40, 2, y1, w=6, h=14, canopy=True)
    for k in range(3):
        m.box(10 + k * 24, 54, 1, 14 + k * 24, 58, 5, M("frame_dark"))
        m.box(10 + k * 24, 54, 5, 14 + k * 24, 58, 6, M("steel"))
    for k in range(4):
        m.box(8 + k * 6, 60, 1, 12 + k * 6, 64, 8, M(rng.choice(["red", "blue", "yellow"])))
        m.box(8 + k * 6, 60, 8, 12 + k * 6, 64, 9, M("black"))
    m.box(70, 50, 1, 72, 52, 22, M("steel"))
    m.box(72, 50, 14, 80, 51, 22, M("blue"))
    return m, {"w": 3, "h": 2, "entrance": [43, H], "delivery": [43, H], "height": 58}


def freight_shed(seed=1):
    """Gueterschuppen 5x3: langer Schuppen mit Ladebahnsteig, Rampe, Gleisstueck und Waggon."""
    rng = random.Random(seed)
    W, H = 5 * T, 3 * T
    m = Model(W, H, 60)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    x0, y0, x1, y1 = 8, 6, 146, 46
    block(m, x0, y0, 1, x1, y1, 26, "timber", base="stone_base", base_h=3)
    for u in range(x0 + 3, x1, 6):
        m.box(u, y1 - 1, 3, u + 1, y1, 26, M("plaster_ochre"))
    gable_roof(m, x0, y0, x1, y1, 26, ridge="x", tile="slate", tile2="slate2", pitch=0.45, overhang=3)
    for k in range(5):
        u = 14 + k * 26
        m.clear(u, y1 - 2, 3, u + 14, y1, 22)
        for a in range(u, u + 14):
            for z in range(3, 22):
                m.put(a, y1 - 1, z, M("wood") if (a + z) % 6 else M("timber"))
    m.box(x0 - 2, y1, 1, x1 + 2, y1 + 8, 5, M("plaster_grey"))
    for x in range(x0, x1, 6):
        m.box(x, y1 + 7, 5, x + 2, y1 + 8, 6, M("yellow"))
    # Gleis + Waggon
    for x in range(0, W):
        for dy in (62, 66):
            m.put(x, dy, 2, M("steel_dark"))
        if x % 4 == 0:
            m.box(x, 60, 1, x + 2, 68, 2, M("timber"))
    m.box(20, 59, 4, 80, 69, 24, M("brick2"))
    m.box(20, 59, 24, 80, 69, 26, M("steel_dark"))
    m.box(34, 69, 6, 46, 70, 20, M("wood"))
    for wx in (24, 32, 62, 72):
        m.box(wx, 59, 2, wx + 4, 60, 6, M("black"))
        m.box(wx, 68, 2, wx + 4, 69, 6, M("black"))
    for k in range(3):
        pallet_stack(m, 100 + k * 12, 56, 1, h=2, goods=rng.choice(["wood", "fabric_w"]))
    lamp_post(m, 150, 70, 1, h=16)
    return m, {"w": 5, "h": 3, "entrance": [80, 46], "delivery": [80, 50], "height": 44}


def depot(seed=1):
    """Gewerbehalle (Depot) 3x3: neutrale Halle; die Firmenfarbe liegt auf einer Maskenebene (Tore, Band)."""
    rng = random.Random(seed)
    W = H = 3 * T
    m = Model(W, H, 64)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    x0, y0, x1, y1 = 6, 6, 90, 62
    block(m, x0, y0, 1, x1, y1, 30, "plaster_grey", base="concrete", base_h=4)
    m.box(x0, y1 - 1, 22, x1, y1, 30, M("comp"))      # Firmenband
    m.box(x1 - 1, y0, 22, x1, y1, 30, M("comp_dark"))
    flat_roof(m, x0, y0, x1, y1, 30, rng=rng, tech=True)
    for k in range(3):
        u = 12 + k * 26
        for a in range(u, u + 16):
            for z in range(4, 21):
                m.put(a, y1 - 1, z, M("comp") if (z - 4) % 3 else M("comp_dark"))
        for z in range(4, 22):
            m.put(u - 1, y1 - 1, z, M("steel"))
            m.put(u + 16, y1 - 1, z, M("steel"))
    window(m, "e", 20, 10, x1, Win(8, 8, frame="frame_dark", lit=0.4), rng)
    door(m, "e", 38, 2, x1, w=5, h=11, canopy=False)
    for k in range(4):
        m.box(10 + k * 20, 70, 0, 12 + k * 20, 86, 1, M("white"))
    lamp_post(m, 90, 72, 1, h=16)
    return m, {"w": 3, "h": 3, "entrance": [48, H], "delivery": [48, H], "height": 42}


def containers(seed=1):
    """Containerlager 2x2: gestapelte Container in vier Farben."""
    rng = random.Random(seed)
    W = H = 2 * T
    m = Model(W, H, 70)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    cols = ["red", "blue", "green_acc", "orange", "yellow", "steel"]
    for row in range(2):
        for k in range(2):
            h = rng.choice([1, 2, 3])
            for z in range(h):
                container(m, 4 + k * 3, 6 + row * 20, 1 + z * 17, rng.choice(cols), "x")
    for k in range(2):
        container(m, 10 + k * 22, 50, 1, rng.choice(cols), "y")
    return m, {"w": 2, "h": 2, "entrance": [32, H], "delivery": [32, H], "height": 56}


def crane(seed=1):
    """Hafenkran 2x3 (Portalkran): Beine, Ausleger, Fuehrerhaus, Rotlicht."""
    W, H = 2 * T, 3 * T
    m = Model(W, H, 130)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    for x in range(0, W):
        for y in (14, 18, 78, 82):
            m.put(x, y, 1, M("steel_dark"))
    for px, py in ((8, 10), (52, 10), (8, 78), (52, 78)):
        m.box(px, py, 1, px + 4, py + 4, 80, M("orange"))
    m.box(6, 8, 78, 58, 12, 84, M("orange"))
    m.box(6, 76, 78, 58, 80, 84, M("orange"))
    m.box(6, 8, 78, 10, 80, 84, M("orange"))
    m.box(54, 8, 78, 58, 80, 84, M("orange"))
    m.box(0, 40, 84, 64, 48, 90, M("yellow"))
    m.box(26, 40, 90, 36, 50, 100, M("steel_dark"))
    m.box(28, 42, 100, 34, 48, 104, M("lamp_red"))
    m.box(20, 44, 70, 22, 46, 84, M("steel"))
    m.box(16, 40, 64, 26, 50, 70, M("blue"))
    return m, {"w": 2, "h": 3, "entrance": [32, H], "delivery": [32, H], "height": 104, "blink": [30, 40]}


def fountain(seed=1):
    """Brunnen 2x2 im Stadtpark: Becken, Mittelsaeule, Wasserstrahlen, Pflaster und Baenke."""
    rng = random.Random(seed)
    W = H = 2 * T
    m = Model(W, H, 40)
    slab(m, 0, 0, W, H, paving_fn(4, "paving", "paving2"))
    slab(m, 0, 0, W, 6, grass_fn(2))
    c = 32
    for x in range(W):
        for y in range(H):
            d = math.hypot(x - c, y - c)
            if d < 17:
                m.put(x, y, 1, M("stone_base"))
                if d > 13:
                    m.put(x, y, 2, M("sandstone"))
                    m.put(x, y, 3, M("sandstone2"))
                else:
                    m.put(x, y, 2, M("water"))
            if d < 5:
                m.put(x, y, 3, M("sandstone"))
    m.box(c - 1, c - 1, 3, c + 1, c + 1, 16, M("sandstone"))
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        for z in range(16, 22):
            m.put(c + dx * (z - 15), c + dy * (z - 15), z - 5, M("water2"))
    bench(m, 4, 52, 1)
    bench(m, 48, 52, 1)
    for tx in (4, 54):
        tree(m, tx, 4, 1, kind="round", size=0.8, rng=rng)
    return m, {"w": 2, "h": 2, "entrance": [32, H], "delivery": [32, H], "height": 24}


def construction(seed=1):
    """Baustelle 3x3: Rohbau mit Geruest, Bauzaun, Container, Materialhaufen und Bagger."""
    rng = random.Random(seed)
    W = H = 3 * T
    m = Model(W, H, 70)
    slab(m, 0, 0, W, H, lambda x, y: M("soil") if (x + y) % 5 else M("gravel"))
    block(m, 14, 10, 1, 70, 50, 30, "concrete", base=None)
    for x in range(14, 70, 12):
        m.clear(x + 3, 49, 8, x + 8, 50, 20)
    m.box(14, 10, 30, 70, 50, 32, M("concrete2"))
    for x in range(14, 72, 8):          # Geruest
        m.box(x, 52, 1, x + 1, 53, 34, M("steel"))
    for z in range(8, 34, 8):
        m.box(14, 52, z, 70, 53, z + 1, M("wood"))
    for x in range(14, 70, 8):
        for z in range(1, 34, 8):
            m.put(x + 1, 52, z + 3, M("steel"))
    for k in range(6):
        pallet_stack(m, 76, 12 + k * 8, 1, h=rng.choice([1, 2]), goods=rng.choice(["brick", "wood"]))
    for x in range(0, W, 8):
        m.box(x, 90, 1, x + 7, 91, 7, M("orange") if (x // 8) % 2 else M("white"))
    m.box(8, 70, 1, 30, 80, 9, M("blue"))
    m.box(8, 70, 9, 30, 80, 10, M("steel_dark"))
    m.box(40, 66, 1, 64, 78, 5, M("yellow"))
    m.box(54, 70, 5, 62, 76, 11, M("glass_dark"))
    m.box(36, 64, 1, 40, 80, 5, M("black"))
    m.box(64, 64, 1, 68, 80, 5, M("black"))
    for z in range(5, 20):
        m.box(42 - (z - 5) // 3, 71, z, 44 - (z - 5) // 3, 73, z + 1, M("yellow"))
    return m, {"w": 3, "h": 3, "entrance": [48, H], "delivery": [48, H], "height": 42}


def airport_cargo(seed=1):
    """Flughafen-Frachtterminal 6x4: langes Terminal mit Vorfeld, Rampen, Kontrollturm, Frachtflugzeug."""
    rng = random.Random(seed)
    W, H = 6 * T, 4 * T
    m = Model(W, H, 90)
    slab(m, 0, 0, W, H, paving_fn(12, "concrete", "concrete2"))
    slab(m, 0, 0, W, 8, grass_fn(6))
    x0, y0, x1, y1 = 8, 8, 120, 56
    block(m, x0, y0, 1, x1, y1, 30, "plaster_grey", base="concrete", base_h=4)
    m.box(x0, y1 - 1, 20, x1, y1, 30, M("steel_dark"))
    for u in range(x0 + 2, x1 - 2, 14):
        m.box(u, y1 - 1, 4, u + 12, y1, 19, M("glass_office" if rng.random() < 0.5 else "glass_lit2"))
        m.box(u + 12, y1 - 1, 4, u + 13, y1, 19, M("steel"))
    flat_roof(m, x0, y0, x1, y1, 30, rng=rng, tech=True)
    for k in range(5):
        _roll_door(m, x1 - 8, 14, 4, 0, h=1) if False else None
    for k in range(4):
        u = 16 + k * 26
        m.box(u, y1, 1, u + 16, y1 + 12, 4, M("concrete2"))
        m.box(u, y1 + 11, 4, u + 16, y1 + 12, 5, M("black"))
        for z in range(4, 18):
            for a in range(u, u + 16):
                m.put(a, y1 - 1, z, M("steel") if (z - 4) % 3 else M("steel_dark"))
    # Tower
    m.box(150, 14, 1, 160, 24, 50, M("plaster_white"))
    m.box(146, 10, 50, 164, 28, 60, M("glass_office"))
    m.box(144, 8, 60, 166, 30, 62, M("steel_dark"))
    m.box(154, 18, 62, 156, 20, 72, M("steel"))
    m.box(153, 17, 72, 157, 21, 74, M("lamp_red"))
    # Frachtflugzeug auf dem Vorfeld (entlang x)
    cx, cy = 100, 100
    m.box(cx - 40, cy - 6, 8, cx + 46, cy + 6, 22, M("white"))
    for k in range(0, 8):
        m.box(cx + 46 + k, cy - 5 + k // 2, 12 + k // 2, cx + 47 + k, cy + 5 - k // 2, 20 + k // 2, M("white"))
    m.box(cx - 40, cy - 6, 8, cx - 36, cy + 6, 12, M("blue"))
    m.box(cx - 6, cy - 44, 12, cx + 12, cy + 44, 15, M("white"))
    m.box(cx - 40, cy - 14, 22, cx - 30, cy + 14, 25, M("white"))
    m.box(cx - 40, cy - 1, 22, cx - 32, cy + 1, 40, M("blue"))
    for ex in (cx - 4, cx + 4):
        for ey in (cy - 24, cy + 24):
            m.box(ex, ey - 4, 6, ex + 8, ey + 4, 14, M("steel"))
    for wx in (cx - 30, cx + 20):
        m.box(wx, cy - 5, 1, wx + 4, cy - 3, 8, M("black"))
        m.box(wx, cy + 3, 1, wx + 4, cy + 5, 8, M("black"))
    for x in range(10, 190, 12):     # Rollfeldmarkierung
        m.box(x, 118, 1, x + 6, 119, 2, M("yellow"))
    container(m, 20, 70, 1, "blue", "x")
    container(m, 64, 70, 1, "orange", "x")
    car(m, 150, 80, 1, "yellow", "x")
    lamp_post(m, 186, 100, 1, h=18)
    return m, {"w": 6, "h": 4, "entrance": [100, 56], "delivery": [100, 58], "height": 80}
