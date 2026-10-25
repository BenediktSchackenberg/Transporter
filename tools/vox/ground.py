"""Bodenkacheln (32x32 Voxel = eine Karten-Zelle) fuer die isometrische Stadt.
road_mask: Bit 1 = Nachbar im Norden (-y), 2 = Osten (+x), 4 = Sueden (+y), 8 = Westen (-x)."""
import math
import random

from engine import Model, mat, M
from lib import P, grass_fn, lawn_fn, paving_fn

T = 32


def init():
    mat("road_white", "#e6e2d4", noise=0.03)
    mat("road_yellow", "#d9b73e", noise=0.03)
    mat("curb_top", "#dedad0", noise=0.04)
    mat("ballast", "#8b867c", noise=0.14)
    mat("furrow", "#5c4029", noise=0.08)
    mat("soil_d", "#6c4a2e", noise=0.1)
    mat("crop1", "#7aa83c", noise=0.12)
    mat("crop2", "#b7b94a", noise=0.12)
    mat("water_hi", "#8fd0e6", noise=0.02, top=False)
    mat("water_dk", "#2f7aa0", noise=0.02, top=False)
    mat("water_mid", "#3f94bb", noise=0.02, top=False)
    mat("asph_a", "#4a4d55", noise=0.07)
    mat("asph_b", "#51545c", noise=0.07)
    mat("shell", "#efe6cf", noise=0.02)
    mat("stone_b", "#9a948a", noise=0.06)
    mat("stone_c", "#857f75", noise=0.06)
    mat("daisy", "#f4f1e6", noise=0.0)


def _model():
    return Model(T, T, 4)


def grass(variant=0, seed=0):
    r = random.Random(seed * 31 + variant)
    m = _model()
    f = grass_fn(seed * 7 + variant)
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, f(x, y))
            v = r.random()
            if v < 0.05:
                m.put(x, y, 0, M("grass3"))
            elif v < 0.09:
                m.put(x, y, 0, M("lawn"))
    for _ in range(3 + variant * 2):
        m.put(r.randrange(T), r.randrange(T), 1, M(r.choice(["grass2", "lawn", "leaf3"])))
    if variant == 2:
        for _ in range(3):
            m.put(r.randrange(T), r.randrange(T), 1, M(r.choice(["daisy", "flower_y"])))
    return m


def park(variant=0, seed=0):
    r = random.Random(seed * 17 + variant)
    m = _model()
    f = lawn_fn(seed)
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, f(x, y) if variant == 0 else (M("grass2") if (x // 3 + y // 3) % 3 else M("lawn")))
    for _ in range(10 if variant == 0 else 6):
        m.put(r.randrange(T), r.randrange(T), 1, M(r.choice(["flower_y", "flower_w", "flower_r", "flower_p", "daisy"])))
    for _ in range(5):
        m.put(r.randrange(T), r.randrange(T), 1, M(r.choice(["leaf2", "leaf3"])))
    return m


def gravel(seed=0):
    r = random.Random(seed + 5)
    m = _model()
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, M("gravel") if r.random() < 0.8 else M("concrete2"))
            if r.random() < 0.04:
                m.put(x, y, 1, M("stone_base"))
    return m


def sidewalk():
    m = _model()
    f = paving_fn(8, "paving", "paving2")
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, f(x, y))
    return m


def plaza():
    m = _model()
    for x in range(T):
        for y in range(T):
            cx, cy = x // 8, y // 8
            base = "sandstone" if (cx + cy) % 2 == 0 else "paving"
            edge = x % 8 == 0 or y % 8 == 0
            m.put(x, y, 0, M("sandstone2") if edge and base == "sandstone" else (M("paving2") if edge else M(base)))
    for x in range(12, 20):
        for y in range(12, 20):
            if (x - 15.5) ** 2 + (y - 15.5) ** 2 < 14:
                m.put(x, y, 0, M("stone_base"))
    return m


def concrete():
    m = _model()
    for x in range(T):
        for y in range(T):
            joint = x % 16 == 0 or y % 16 == 0
            m.put(x, y, 0, M("concrete2") if joint else M("concrete"))
    return m


def quay():
    m = _model()
    for x in range(T):
        for y in range(T):
            off = 4 if (y // 4) % 2 else 0
            edge = (x + off) % 8 == 0 or y % 4 == 0
            m.put(x, y, 0, M("stone_c") if edge else M("stone_b"))
    for x in range(0, T, 8):
        m.put(x + 3, 30, 1, M("steel_dark"))
    return m


def sand(seed=0):
    r = random.Random(seed + 9)
    m = _model()
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, M("sand") if r.random() < 0.85 else M("plaster_ochre"))
            if r.random() < 0.012:
                m.put(x, y, 1, M("shell"))
    return m


def field(seed=0):
    m = _model()
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, M("furrow") if (y // 2) % 2 == 0 else M("soil_d"))
            if (y // 2) % 2 == 1:
                m.put(x, y, 1, M("soil"))
    return m


def crop(seed=0):
    r = random.Random(seed + 3)
    m = _model()
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, M("furrow") if (y // 4) % 2 == 0 else M("soil_d"))
            if (y // 4) % 2 == 1 and x % 3 != 2:
                m.put(x, y, 1, M("crop1" if r.random() < 0.7 else "crop2"))
                if r.random() < 0.5:
                    m.put(x, y, 2, M("leaf3"))
    return m


def water(frame=0):
    m = _model()
    for x in range(T):
        for y in range(T):
            v = math.sin((x + y * 0.6) * 0.45 + frame * math.pi / 2) + math.sin((y - x * 0.5) * 0.37 + frame * 1.3)
            name = "water_hi" if v > 1.55 else ("water" if v > 0.2 else ("water_mid" if v > -0.8 else "water_dk"))
            m.put(x, y, 0, M(name))
    return m


def rail(horizontal=True):
    m = _model()
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, M("ballast"))
    for k in range(0, T, 5):
        for y in range(6, 26):
            m.put(k + 1, y, 1, M("timber")) if horizontal else None
    if horizontal:
        for x in range(T):
            m.put(x, 11, 1, M("steel"))
            m.put(x, 20, 1, M("steel"))
            m.put(x, 11, 2, M("steel_dark")) if x % 2 == 0 else None
            m.put(x, 20, 2, M("steel_dark")) if x % 2 == 0 else None
    else:
        r = rail(True)
        m = Model(T, T, 4)
        for x in range(T):
            for y in range(T):
                for z in range(4):
                    m.g[y, x, z] = r.g[x, y, z]
    return m


def parking(seed=0):
    r = random.Random(seed)
    m = _model()
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, M("asph_a") if r.random() < 0.7 else M("asph_b"))
    for k in range(0, T, 8):
        for y in range(2, 22):
            m.put(k, y, 0, M("road_white"))
    return m


def road(mask):
    r = random.Random(mask * 13 + 1)
    m = _model()
    for x in range(T):
        for y in range(T):
            m.put(x, y, 0, M("asph_a") if r.random() < 0.72 else M("asph_b"))
    n, e, s, w = (mask & 1) > 0, (mask & 2) > 0, (mask & 4) > 0, (mask & 8) > 0
    # Bordsteine an Seiten ohne Strassenanschluss (nur wenn die Strasse dort wirklich endet)
    cw = 3
    if not n:
        m.box(0, 0, 1, T, cw, 2, M("curb_top"))
    if not s:
        m.box(0, T - cw, 1, T, T, 2, M("curb_top"))
    if not w:
        m.box(0, 0, 1, cw, T, 2, M("curb_top"))
    if not e:
        m.box(T - cw, 0, 1, T, T, 2, M("curb_top"))
    # Mittellinien (gestrichelt) von der Mitte nach aussen, an Kreuzungen erst hinter dem Zebrastreifenbereich
    junction = bin(mask).count("1") >= 3
    for k, on in (("n", n), ("s", s), ("w", w), ("e", e)):
        if not on:
            continue
        for t in range(0, 16):
            if (t // 3) % 2 != 0 or (junction and t < 5):
                continue
            if k == "n":
                cells = ((15, 15 - t), (16, 15 - t))
            elif k == "s":
                cells = ((15, 16 + t), (16, 16 + t))
            elif k == "w":
                cells = ((15 - t, 15), (15 - t, 16))
            else:
                cells = ((16 + t, 15), (16 + t, 16))
            for cx, cy in cells:
                m.put(cx, cy, 0, M("road_white"))
    if junction:   # Zebrastreifen an den Armen
        for k, on in (("n", n), ("s", s), ("w", w), ("e", e)):
            if not on:
                continue
            for u in range(4, 28, 4):
                for t in range(3, 7):
                    if k == "n":
                        m.put(u, t, 0, M("road_white")); m.put(u + 1, t, 0, M("road_white"))
                    elif k == "s":
                        m.put(u, T - 1 - t, 0, M("road_white")); m.put(u + 1, T - 1 - t, 0, M("road_white"))
                    elif k == "w":
                        m.put(t, u, 0, M("road_white")); m.put(t, u + 1, 0, M("road_white"))
                    else:
                        m.put(T - 1 - t, u, 0, M("road_white")); m.put(T - 1 - t, u + 1, 0, M("road_white"))
    return m
