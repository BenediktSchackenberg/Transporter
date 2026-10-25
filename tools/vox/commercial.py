"""Laeden, Gastronomie, Bank, Klinik, Jobboerse, Personalbuero, Tankstelle, Autohaus (je als vollstaendiges Grundstueck).
Konventionen wie residential.py: Ursprung hintere (NW-)Ecke, Boden z = 0 (Platte), sichtbar sind Sued (+y) und Ost (+x)."""
import random

from engine import Model, M
from lib import (Win, window, door, block, facade_windows, gable_roof, hip_roof, flat_roof, chimney, balcony, tree, bush,
                 hedge, flowerbed, fence, wall_fence, lamp_post, bin_, bike, bench, patio_set, car, pallet_stack, slab,
                 grass_fn, lawn_fn, paving_fn, deck_fn)

T = 32


def awning(m, u0, u1, plane, z, c1="fabric_r", c2="fabric_w", depth=6):
    """Gestreifte Markise ueber der Suedfassade, nach vorn abfallend."""
    for u in range(u0, u1):
        col = c1 if (u // 3) % 2 == 0 else c2
        for b in range(depth):
            m.put(u, plane + b, z - b // 3, M(col))
        m.put(u, plane + depth - 1, z - depth // 3 - 1, M(col))   # Volant


def sign_board(m, u0, u1, z0, z1, plane, face="s", col="blue", text="white"):
    for u in range(u0, u1):
        for z in range(z0, z1):
            edge = u in (u0, u1 - 1) or z in (z0, z1 - 1)
            mm = M("frame_dark") if edge else M(col)
            if face == "s":
                m.put(u, plane, z, mm)
            else:
                m.put(plane, u, z, mm)
    for u in range(u0 + 2, u1 - 2, 3):
        for z in range(z0 + 2, z1 - 2):
            if face == "s":
                m.put(u, plane + 1, z, M(text))
            else:
                m.put(plane + 1, u, z, M(text))


def crates(m, x, y, z=1, n=3, rng=None):
    rng = rng or random.Random(x * 3 + y)
    for k in range(n):
        col = rng.choice(["flower_r", "flower_y", "leaf3", "orange", "leaf2"])
        m.box(x + k * 5, y, z, x + k * 5 + 4, y + 4, z + 3, M("wood"))
        m.box(x + k * 5 + 1, y + 1, z + 3, x + k * 5 + 3, y + 3, z + 4, M(col))


def shop(variant=0, seed=1):
    """Laden 2x2: Schaufenster, Markise, Firmenschild, Auslage; Varianten Baeckerei, Elektro, Markthalle."""
    rng = random.Random(seed * 3 + variant)
    W = H = 2 * T
    m = Model(W, H, 70)
    slab(m, 0, 0, W, H, paving_fn(4))
    slab(m, 0, 0, W, 8, grass_fn(variant))
    x0, y0, x1, y1 = 6, 6, 58, 40
    if variant == 0:
        block(m, x0, y0, 1, x1, y1, 30, "plaster_cream", base="stone_base", base_h=3, cornice="sandstone")
        gable_roof(m, x0, y0, x1, y1, 30, ridge="x", tile="tile_red", tile2="tile_red2", pitch=0.9)
        chimney(m, 14, 14, 36, h=10)
        window(m, "s", 10, 5, y1, Win(14, 14, frame="frame_wood", cross=True, lit=0.9, lit_mat="glass_lit2"), rng)
        door(m, "s", 32, 2, y1, w=6, h=14, canopy=False)
        window(m, "e", 12, 8, x1, Win(8, 12, frame="frame_wood", lit=0.7), rng)
        awning(m, 8, 27, y1, 22, "fabric_r", "fabric_w")
        sign_board(m, 30, 50, 24, 29, y1 + 1, "s", "wood", "yellow")
        crates(m, 10, y1 + 8, 1, 3, rng)
        window(m, "s", 14, 32, y1, Win(8, 6, frame="frame_white", lit=0.6), rng)
    elif variant == 1:
        block(m, x0, y0, 1, x1, y1, 26, "concrete", base="steel_dark", base_h=2)
        m.box(x0, y1 - 1, 3, x1, y1, 24, M("glass_dark"))
        for u in range(x0 + 1, x1 - 1, 9):
            m.box(u, y1 - 1, 3, u + 8, y1, 24, M("glass_lit2" if rng.random() < 0.7 else "glass_office"))
            m.box(u + 8, y1 - 1, 1, u + 9, y1, 26, M("steel"))
        flat_roof(m, x0, y0, x1, y1, 26, rng=rng, tech=True)
        sign_board(m, 10, 54, 28, 36, y1 - 1, "s", "blue", "white")
        door(m, "s", 30, 2, y1 + 1, w=6, h=14, canopy=True, mat_door="glass_dark")
        for k in range(3):
            m.box(8 + k * 6, y1 + 6, 1, 12 + k * 6, y1 + 9, 3, M("white"))   # Vorfuehrgeraete
        window(m, "e", 12, 8, x1, Win(8, 10, frame="frame_dark", lit=0.8, lit_mat="glass_office"), rng)
    else:
        block(m, x0, y0, 1, x1, y1, 24, "plaster_sage", base="stone_base", base_h=3)
        m.box(x0 - 1, y1, 22, x1 + 1, y1 + 1, 24, M("plaster_white"))
        gable_roof(m, x0, y0, x1, y1, 24, ridge="x", tile="slate", tile2="slate2", pitch=0.6)
        window(m, "s", 8, 5, y1, Win(12, 12, frame="frame_white", lit=0.8, lit_mat="glass_lit2"), rng)
        window(m, "s", 40, 5, y1, Win(12, 12, frame="frame_white", lit=0.8, lit_mat="glass_lit2"), rng)
        door(m, "s", 26, 2, y1, w=6, h=14, canopy=False)
        awning(m, 6, 58, y1, 20, "green_acc", "fabric_w", depth=7)
        crates(m, 8, y1 + 9, 1, 4, rng)
        crates(m, 34, y1 + 9, 1, 4, rng)
        window(m, "e", 14, 6, x1, Win(10, 12, frame="frame_white", lit=0.6), rng)
    bike(m, 58, 46, 1, color=rng.choice(["red", "blue", "yellow"]), face="x")
    lamp_post(m, 60, 56, 1, h=14)
    tree(m, 6, 54, 1, kind="round", size=0.7, rng=rng)
    return m, {"w": 2, "h": 2, "entrance": [35, H], "delivery": [35, H], "height": 60}


def pharmacy(seed=1):
    """Apotheke 2x2 (nutzt den Laden-Korpus mit gruenem Kreuz)."""
    m, meta = shop(1, seed + 40)
    for z in range(48, 55):
        for u in range(28, 36):
            if (28 <= u < 36 and 50 <= z < 53) or (31 <= u < 33):
                m.put(u, 41, z, M("neon_g"))
    return m, meta


def restaurant(seed=1):
    """Restaurant 2x2: Terrasse mit Tischen und Schirmen, Fensterlaeden, Walmdach, Schild."""
    rng = random.Random(seed)
    W = H = 2 * T
    m = Model(W, H, 70)
    slab(m, 0, 0, W, H, grass_fn(seed))
    slab(m, 0, 36, W, H, deck_fn())
    x0, y0, x1, y1 = 6, 6, 46, 36
    block(m, x0, y0, 1, x1, y1, 26, "plaster_ochre", base="stone_base", base_h=3, cornice="sandstone")
    hip_roof(m, x0, y0, x1, y1, 26, tile="tile_terra", tile2="tile_terra2", pitch=0.8)
    window(m, "s", 8, 6, y1, Win(7, 12, frame="frame_wood", shutters="green_acc", lit=0.9, lit_mat="glass_lit2"), rng)
    window(m, "s", 28, 6, y1, Win(7, 12, frame="frame_wood", shutters="green_acc", lit=0.9, lit_mat="glass_lit2"), rng)
    door(m, "s", 19, 2, y1, w=6, h=14, canopy=True, mat_door="frame_wood")
    window(m, "e", 12, 6, x1, Win(8, 12, frame="frame_wood", shutters="green_acc", lit=0.9), rng)
    sign_board(m, 12, 34, 20, 25, y1 + 1, "s", "red", "white")
    for tx, ty, col in ((6, 42, "fabric_r"), (22, 44, "fabric_b"), (40, 42, "fabric_r")):
        patio_set(m, tx, ty, 2, umbrella=col)
    hedge(m, 0, 62, 64, 64, 2, 3)
    lamp_post(m, 58, 38, 2, h=14)
    tree(m, 54, 8, 1, kind="round", size=0.8, rng=rng)
    return m, {"w": 2, "h": 2, "entrance": [22, H], "delivery": [W, 20], "height": 52}


def bank(seed=1):
    """Bank 3x3: Sandsteinbau mit Saeulenportal, Treppe, Flachdach mit Gesims, Fahnen."""
    rng = random.Random(seed)
    W = H = 3 * T
    m = Model(W, H, 90)
    slab(m, 0, 0, W, H, paving_fn(4))
    slab(m, 0, 0, W, 10, lawn_fn(1))
    x0, y0, x1, y1 = 8, 8, 88, 62
    block(m, x0, y0, 1, x1, y1, 50, "sandstone", base="stone_base", base_h=5, cornice="sandstone2")
    for f in range(2):
        facade_windows(m, x0, y0, x1, y1, 5 + f * 20, 1, 20, Win(6, 12, frame="frame_white", lit=0.5, cross=True), rng, spacing=14, margin=6)
    m.box(x0 - 2, y0 - 2, 50, x1 + 2, y1 + 2, 52, M("sandstone2"))
    flat_roof(m, x0, y0, x1, y1, 52, parapet="sandstone2", rng=rng, tech=False)
    # Portal: Saeulen + Giebel
    for sx in range(30, 62, 8):
        m.box(sx, y1 + 2, 1, sx + 3, y1 + 5, 36, M("plaster_white"))
        m.box(sx - 1, y1 + 2, 36, sx + 4, y1 + 6, 38, M("sandstone2"))
    m.box(28, y1 + 1, 38, 64, y1 + 7, 41, M("sandstone2"))
    m.box(32, y1 + 3, 41, 60, y1 + 6, 44, M("sandstone"))
    door(m, "s", 42, 2, y1, w=8, h=20, canopy=False, mat_door="glass_dark")
    for k in range(4):
        m.box(26 - k, y1 + 1 + k, 1, 66 + k, y1 + 2 + k, 2 + (3 - k) // 1 * 0 + 1, M("stone_base"))
    for fx in (14, 78):
        m.box(fx, y1 + 6, 1, fx + 1, y1 + 7, 28, M("steel"))
        m.box(fx + 1, y1 + 6, 22, fx + 8, y1 + 7, 28, M("blue"))
    for tx in (8, 80):
        tree(m, tx, 74, 1, kind="round", size=0.8, rng=rng)
    bench(m, 20, 82, 1)
    lamp_post(m, 66, 80, 1, h=14)
    return m, {"w": 3, "h": 3, "entrance": [46, H], "delivery": [W, 34], "height": 70}


def clinic(seed=1):
    """Klinik 3x3: weisser Baukoerper, Glasfoyer mit Vordach, rotes Kreuz, Rettungswagen, Gartenanlage."""
    rng = random.Random(seed)
    W = H = 3 * T
    m = Model(W, H, 100)
    slab(m, 0, 0, W, H, lawn_fn(2))
    slab(m, 0, 62, W, H, paving_fn(4))
    x0, y0, x1, y1 = 8, 8, 88, 62
    block(m, x0, y0, 1, x1, y1, 60, "plaster_white", base="concrete", base_h=3, cornice="concrete")
    facade_windows(m, x0, y0, x1, y1, 1, 3, 20, Win(6, 11, frame="frame_white", lit=0.55, lit_mat="glass_office", cross=False), rng, spacing=11)
    flat_roof(m, x0, y0, x1, y1, 60, rng=rng, tech=True)
    m.clear(34, y1 - 3, 1, 56, y1, 22)
    m.box(34, y1 - 3, 1, 56, y1 - 2, 22, M("glass_lit2"))
    m.box(31, y1 - 2, 22, 59, y1 + 8, 24, M("white"))
    for px in (32, 58):
        m.box(px, y1 + 6, 1, px + 2, y1 + 8, 22, M("steel"))
    # rotes Kreuz an der Suedfassade
    for u in range(10, 24):
        for z in range(40, 54):
            if (16 <= u < 18) or (45 <= z < 47):
                m.put(u, y1, z, M("red"))
    m.box(10, y1, 40, 24, y1 + 1, 54, M("white")) if False else None
    for u in range(11, 23):
        for z in range(41, 53):
            m.put(u, y1, z, M("white"))
    for u in range(16, 18):
        for z in range(41, 53):
            m.put(u, y1, z, M("red"))
    for u in range(11, 23):
        for z in range(46, 48):
            m.put(u, y1, z, M("red"))
    car(m, 66, 72, 1, "white", "x")
    m.box(70, 72, 7, 76, 73, 9, M("red"))
    for tx in (10, 84):
        tree(m, tx, 70, 1, kind="round", size=0.9, rng=rng)
    bench(m, 28, 80, 1)
    flowerbed(m, 8, 88, 24, 94, 1, rng=rng)
    lamp_post(m, 48, 74, 1, h=14)
    return m, {"w": 3, "h": 3, "entrance": [45, H], "delivery": [W, 40], "height": 74}


def job_board(seed=1):
    """Jobboerse 3x2: niedrige Halle mit Anschlagtafeln, bunte Zettel, Wartebaenke, Schild."""
    rng = random.Random(seed)
    W, H = 3 * T, 2 * T
    m = Model(W, H, 50)
    slab(m, 0, 0, W, H, paving_fn(4, "paving", "paving2"))
    x0, y0, x1, y1 = 6, 6, 90, 36
    block(m, x0, y0, 1, x1, y1, 22, "plaster_grey", base="concrete", base_h=3)
    flat_roof(m, x0, y0, x1, y1, 22, rng=rng, tech=False)
    window(m, "s", 8, 5, y1, Win(10, 11, frame="frame_dark", lit=0.8, lit_mat="glass_office"), rng)
    door(m, "s", 40, 2, y1, w=8, h=14, canopy=True, mat_door="glass_dark")
    window(m, "s", 68, 5, y1, Win(10, 11, frame="frame_dark", lit=0.8, lit_mat="glass_office"), rng)
    sign_board(m, 30, 66, 24, 31, y1 + 1, "s", "orange", "white")
    for k in range(3):
        bx = 10 + k * 28
        m.box(bx, y1 + 10, 1, bx + 1, y1 + 11, 11, M("frame_dark"))
        m.box(bx + 14, y1 + 10, 1, bx + 15, y1 + 11, 11, M("frame_dark"))
        m.box(bx, y1 + 10, 11, bx + 15, y1 + 11, 22, M("wood"))
        for u in range(bx + 1, bx + 14, 3):
            for z in range(13, 21, 4):
                m.box(u, y1 + 11, z, u + 2, y1 + 12, z + 3, M(rng.choice(["white", "flower_y", "flower_p", "leaf3", "fabric_b"])))
    bench(m, 24, 58, 1)
    bench(m, 60, 58, 1)
    tree(m, 86, 50, 1, kind="round", size=0.7, rng=rng)
    lamp_post(m, 4, 56, 1, h=14)
    return m, {"w": 3, "h": 2, "entrance": [44, H], "delivery": [44, H], "height": 34}


def staffing(seed=1):
    """Personalbuero 2x2: freundlicher Bau mit Fahne und Wartebereich."""
    rng = random.Random(seed)
    W = H = 2 * T
    m = Model(W, H, 60)
    slab(m, 0, 0, W, H, paving_fn(4))
    slab(m, 0, 0, 12, H, grass_fn(5))
    x0, y0, x1, y1 = 8, 6, 58, 38
    block(m, x0, y0, 1, x1, y1, 30, "plaster_rose", base="stone_base", base_h=3, cornice="plaster_white")
    facade_windows(m, x0, y0, x1, y1, 1, 2, 14, Win(6, 9, frame="frame_white", lit=0.6), rng, spacing=11, margin=5)
    hip_roof(m, x0, y0, x1, y1, 30, tile="slate", tile2="slate2", pitch=0.9)
    door(m, "s", 28, 2, y1, w=6, h=13, canopy=True)
    sign_board(m, 14, 44, 18, 23, y1 + 1, "s", "green_acc", "white") if False else None
    m.box(60, 40, 1, 61, 41, 40, M("steel"))
    m.box(61, 40, 28, 70, 41, 40, M("green_acc"))
    bench(m, 14, 46, 1)
    bush(m, 12, 52, 1, 3, flowers="flower_y", rng=rng)
    lamp_post(m, 50, 52, 1, h=13)
    return m, {"w": 2, "h": 2, "entrance": [31, H], "delivery": [31, H], "height": 46}


def gas_station(seed=1):
    """Tankstelle 3x2: Vordach auf Pfeilern, zwei Zapfsaeulen, kleiner Shop, Preismast."""
    rng = random.Random(seed)
    W, H = 3 * T, 2 * T
    m = Model(W, H, 50)
    slab(m, 0, 0, W, H, paving_fn(6, "asphalt2", "asphalt"))
    slab(m, 0, 0, W, 6, grass_fn(3))
    block(m, 8, 6, 1, 40, 30, 16, "plaster_white", base="concrete", base_h=2)
    m.box(8, 30, 14, 40, 31, 16, M("red"))
    m.box(7, 29, 16, 41, 31, 17, M("frame_dark"))
    window(m, "s", 12, 4, 30, Win(10, 8, frame="frame_dark", lit=0.9, lit_mat="glass_lit2", cross=False), rng)
    door(m, "s", 28, 2, 30, w=6, h=11, canopy=False)
    # Vordach
    m.box(30, 36, 20, 88, 56, 22, M("white"))
    m.box(30, 36, 22, 88, 38, 24, M("red"))
    m.box(30, 54, 22, 88, 56, 24, M("red"))
    m.box(30, 36, 19, 88, 56, 20, M("steel"))
    for px, py in ((34, 40), (84, 40), (34, 52), (84, 52)):
        m.box(px, py, 1, px + 2, py + 2, 20, M("steel_dark"))
    for px in (48, 70):
        for py in (42, 48):
            m.box(px, py, 1, px + 4, py + 3, 9, M("white"))
            m.box(px, py, 9, px + 4, py + 3, 11, M("red"))
            m.box(px + 1, py + 3, 5, px + 3, py + 4, 8, M("lamp_blue"))
    m.box(92, 8, 1, 94, 10, 28, M("steel"))
    m.box(88, 8, 28, 96, 12, 36, M("white"))
    m.box(89, 12, 29, 95, 13, 35, M("red"))
    car(m, 42, 58, 1, rng.choice(["blue", "yellow"]), "x")
    lamp_post(m, 4, 40, 1, h=14)
    return m, {"w": 3, "h": 2, "entrance": [60, H], "delivery": [60, H], "height": 40}


def dealer(seed=1):
    """Autohaus 4x3: Glas-Showroom, Flachdach mit Schriftband, Fahrzeuge auf dem Hof, Fahnen."""
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 60)
    slab(m, 0, 0, W, H, paving_fn(6, "concrete", "concrete2"))
    slab(m, 0, 0, W, 8, lawn_fn(3))
    x0, y0, x1, y1 = 8, 8, 100, 50
    m.box(x0, y0, 1, x1, y1, 24, M("concrete"))
    m.box(x0, y1 - 1, 3, x1, y1, 22, M("glass_dark"))
    for u in range(x0 + 1, x1 - 1, 12):
        m.box(u, y1 - 1, 3, u + 11, y1, 22, M("glass_lit2" if rng.random() < 0.7 else "glass_office"))
        m.box(u + 11, y1 - 1, 1, u + 12, y1, 24, M("steel"))
    m.box(x1 - 1, y0, 3, x1, y1, 22, M("glass_dark"))
    flat_roof(m, x0, y0, x1, y1, 24, rng=rng, tech=True)
    sign_board(m, 30, 80, 26, 33, y1 + 1, "s", "red", "white")
    for k, col in enumerate(["red", "blue", "white", "yellow"]):
        m.box(x0 + 8 + k * 20, y1 - 12, 1, x0 + 24 + k * 20 - 2, y1 - 2, 8, M(col))
        m.box(x0 + 10 + k * 20, y1 - 11, 8, x0 + 22 + k * 20 - 2, y1 - 3, 12, M("glass_dark"))
    for k, col in enumerate(["blue", "red", "black", "white", "orange"]):
        car(m, 10 + k * 22, 68 + (k % 2) * 8, 1, col, "x")
    for fx in range(14, 100, 24):
        m.box(fx, 84, 1, fx + 1, 85, 30, M("steel"))
        m.box(fx + 1, 84, 22, fx + 9, 85, 30, M(rng.choice(["blue", "red", "yellow"])))
    lamp_post(m, 4, 60, 1, h=15)
    return m, {"w": 4, "h": 3, "entrance": [60, 50], "delivery": [60, H], "height": 40}
