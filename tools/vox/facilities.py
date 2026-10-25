"""Betriebseinrichtungen des Firmengrundstuecks (15 Typen). Jede Funktion liefert ein Modell fuer die Grundflaeche
(w x h Felder) in der Ausrichtung 0; die gedrehte Variante entsteht in build_iso.py (Grundriss h x w)."""
import random

from engine import Model, M
from lib import (Win, window, door, block, facade_windows, gable_roof, flat_roof, hip_roof, tree, bush, bench, lamp_post, car,
                 pallet_stack, slab, paving_fn, bin_, hedge, patio_set)
from commercial import sign_board

T = 32
SIZES = {"buero": (2, 2), "disposition": (2, 2), "stellplatz": (2, 2), "garage": (2, 2), "werkstatt": (3, 2), "laderampe": (2, 1),
         "lager": (3, 3), "kuehllager": (3, 2), "tankstelle": (2, 2), "ladepunkt": (1, 2), "pausenraum": (2, 2),
         "schulung": (2, 2), "sicherheit": (1, 1), "waschplatz": (2, 2), "mietbuero": (3, 2)}


def _floor(m, W, H, a="concrete", b="concrete2", size=8):
    slab(m, 0, 0, W, H, paving_fn(size, a, b))


def _roll(m, u, w, plane, h=14, z=1, mname="comp"):
    for a in range(u, u + w):
        for c in range(z, z + h):
            m.put(a, plane - 1, c, M(mname) if (c - z) % 3 else M("comp_dark"))
    for c in range(z, z + h + 1):
        m.put(u - 1, plane - 1, c, M("steel"))
        m.put(u + w, plane - 1, c, M("steel"))


def make(name, seed=1):
    rng = random.Random(seed)
    w, h = SIZES[name]
    W, H = w * T, h * T
    m = Model(W, H, 80)
    _floor(m, W, H)
    fn = globals()["_" + name]
    fn(m, W, H, rng)
    return m


def _buero(m, W, H, rng):
    block(m, 8, 6, 1, 56, 40, 36, "plaster_white", base="concrete", base_h=3, cornice="plaster_grey")
    facade_windows(m, 8, 6, 56, 40, 1, 2, 16, Win(6, 9, frame="frame_dark", lit=0.6, lit_mat="glass_office", cross=False), rng, spacing=11, margin=5)
    m.box(8, 39, 26, 56, 40, 34, M("comp"))
    flat_roof(m, 8, 6, 56, 40, 36, rng=rng, tech=True)
    door(m, "s", 28, 2, 40, w=7, h=13, canopy=True, mat_door="glass_dark")
    m.box(60, 44, 1, 61, 45, 30, M("steel"))
    m.box(61, 44, 22, 69, 45, 30, M("comp"))
    bench(m, 12, 50, 1)
    tree(m, 54, 50, 1, kind="round", size=0.7, rng=rng)


def _disposition(m, W, H, rng):
    block(m, 8, 8, 1, 50, 38, 24, "steel", base=None)
    for u in range(8, 50, 7):
        m.box(u, 37, 3, u + 6, 38, 22, M("glass_office" if rng.random() < 0.7 else "glass_lit2"))
    flat_roof(m, 8, 8, 50, 38, 24, rng=rng, tech=False)
    m.box(40, 14, 25, 42, 16, 56, M("steel"))
    for z in range(36, 56, 6):
        m.box(37, 14, z, 45, 16, z + 1, M("steel"))
    m.box(39, 13, 56, 43, 17, 58, M("lamp_red"))
    door(m, "s", 14, 2, 38, w=5, h=11, canopy=False)
    m.box(10, 46, 1, 54, 58, 2, M("asphalt"))
    car(m, 14, 46, 2, "blue", "x")


def _stellplatz(m, W, H, rng):
    slab(m, 2, 2, W - 2, H - 2, lambda x, y: M("asph_a") if (x + y) % 7 else M("asph_b"))
    for k in range(3):
        m.box(10 + k * 22, 8, 1, 11 + k * 22, 54, 2, M("road_white"))
    m.box(10, 8, 1, 55, 9, 2, M("road_white"))
    for k in range(2):
        m.box(12 + k * 22, 54, 1, 14 + k * 22, 56, 5, M("yellow"))


def _garage(m, W, H, rng):
    block(m, 8, 6, 1, 56, 44, 28, "plaster_grey", base="concrete", base_h=3)
    flat_roof(m, 8, 6, 56, 44, 28, rng=rng, tech=False)
    _roll(m, 12, 16, 44, 18)
    _roll(m, 36, 16, 44, 18)
    m.box(8, 43, 22, 56, 44, 28, M("comp"))
    window(m, "e", 16, 10, 56, Win(8, 8, frame="frame_dark", lit=0.4), rng)
    lamp_post(m, 4, 52, 1, h=14)


def _werkstatt(m, W, H, rng):
    block(m, 8, 6, 1, 88, 42, 30, "brick", base="stone_base", base_h=3)
    flat_roof(m, 8, 6, 88, 42, 30, rng=rng, tech=True)
    m.box(8, 41, 22, 88, 42, 30, M("comp"))
    _roll(m, 12, 18, 42, 16)
    _roll(m, 36, 18, 42, 16)
    door(m, "s", 62, 2, 42, w=6, h=12, canopy=True)
    window(m, "s", 74, 8, 42, Win(10, 10, frame="frame_dark", lit=0.7, lit_mat="glass_lit2"), rng)
    for k in range(4):
        m.box(12 + k * 5, 50, 1, 16 + k * 5, 54, 6, M("black"))      # Reifenstapel
        m.box(13 + k * 5, 51, 6, 15 + k * 5, 53, 8, M("black"))
    m.box(60, 50, 1, 80, 60, 12, M("steel_dark"))
    m.box(62, 52, 12, 78, 58, 13, M("orange"))
    for z in range(1, 12):
        m.box(64, 50, z, 66, 52, z + 1, M("yellow"))
    m.box(70, 56, 40, 72, 58, 52, M("steel")) if False else None


def _laderampe(m, W, H, rng):
    m.box(4, 6, 1, 60, 26, 8, M("concrete2"))
    m.box(4, 6, 8, 60, 26, 9, M("concrete"))
    m.box(4, 26, 7, 60, 28, 9, M("yellow"))
    m.box(4, 6, 24, 60, 28, 26, M("comp"))
    for px in (6, 58):
        m.box(px, 24, 9, px + 2, 26, 24, M("steel"))
    for k in range(4):
        m.box(10 + k * 12, 28, 4, 14 + k * 12, 29, 7, M("black"))
    pallet_stack(m, 12, 10, 9, h=2, goods="fabric_w")
    pallet_stack(m, 40, 10, 9, h=1, goods="wood")


def _lager(m, W, H, rng):
    block(m, 6, 6, 1, 90, 88, 34, "zinc", base="concrete", base_h=4)
    gable_roof(m, 6, 6, 90, 88, 34, ridge="x", tile="steel", tile2="steel_dark", pitch=0.3, overhang=1)
    for k in range(3):
        _roll(m, 12 + k * 26, 14, 88, 16, 4)
    door(m, "e", 36, 2, 90, w=5, h=11, canopy=True)
    for k in range(3):
        pallet_stack(m, 8 + k * 10, 92 if False else 4, 1, h=1) if False else None


def _kuehllager(m, W, H, rng):
    block(m, 6, 6, 1, 90, 44, 32, "plaster_white", base="steel", base_h=3)
    flat_roof(m, 6, 6, 90, 44, 32, rng=rng, tech=False)
    for k in range(3):
        m.box(12 + k * 24, 12, 33, 28 + k * 24, 28, 38, M("steel"))
        m.box(14 + k * 24, 14, 38, 26 + k * 24, 26, 39, M("steel_dark"))
    m.box(6, 43, 14, 90, 44, 18, M("blue"))
    _roll(m, 14, 14, 44, 16, 3, "glass_office")
    _roll(m, 50, 14, 44, 16, 3, "glass_office")
    for k in range(6):
        m.box(18 + k * 12 if False else 10 + k * 14, 52, 1, 12 + k * 14, 54, 6, M("steel"))


def _tankstelle(m, W, H, rng):
    slab(m, 0, 0, W, H, paving_fn(6, "asph_a", "asph_b"))
    m.box(6, 12, 20, 58, 52, 22, M("white"))
    m.box(6, 12, 22, 58, 14, 24, M("comp"))
    m.box(6, 50, 22, 58, 52, 24, M("comp"))
    for px, py in ((8, 14), (54, 14), (8, 48), (54, 48)):
        m.box(px, py, 1, px + 2, py + 2, 20, M("steel_dark"))
    for px in (22, 40):
        m.box(px, 28, 1, px + 6, 36, 3, M("concrete"))
        m.box(px + 1, 29, 3, px + 5, 35, 12, M("comp"))
        m.box(px + 1, 29, 12, px + 5, 35, 13, M("white"))
        m.box(px + 2, 35, 6, px + 4, 36, 10, M("lamp_blue"))
    m.box(54, 4, 1, 56, 6, 26, M("steel"))
    m.box(50, 4, 26, 60, 8, 32, M("comp"))


def _ladepunkt(m, W, H, rng):
    m.box(2, 2, 1, 30, 62, 2, M("asph_a"))
    for k in range(2):
        y = 8 + k * 32
        m.box(4, y + 14, 1, 6, y + 16, 2, M("road_white"))
        m.box(6, y + 6, 1, 10, y + 10, 16, M("steel"))
        m.box(7, y + 10, 8, 9, y + 11, 12, M("neon_g"))
        m.box(6, y + 6, 16, 10, y + 10, 18, M("comp"))
    car(m, 10 if False else 6, 14 if False else 26, 2, "green_acc", "y") if False else None


def _pausenraum(m, W, H, rng):
    block(m, 8, 6, 1, 44, 36, 22, "wood", base=None)
    for u in range(8, 44, 4):
        m.box(u, 35, 3, u + 1, 36, 22, M("deck2"))
    flat_roof(m, 8, 6, 44, 36, 22, parapet="timber", rng=rng, tech=False)
    window(m, "s", 12, 6, 36, Win(8, 9, frame="frame_white", lit=0.9, lit_mat="glass_lit2"), rng)
    door(m, "s", 28, 2, 36, w=5, h=11, canopy=True)
    patio_set(m, 8, 44, 1, umbrella="comp")
    bench(m, 36, 46, 1)
    tree(m, 52, 10, 1, kind="round", size=0.8, rng=rng)


def _schulung(m, W, H, rng):
    block(m, 8, 6, 1, 52, 38, 26, "plaster_sage", base="stone_base", base_h=3, cornice="plaster_white")
    facade_windows(m, 8, 6, 52, 38, 1, 1, 22, Win(8, 11, frame="frame_white", lit=0.8, lit_mat="glass_lit2"), rng, spacing=12, margin=5)
    gable_roof(m, 8, 6, 52, 38, 26, ridge="x", tile="tile_terra", tile2="tile_terra2", pitch=0.6)
    door(m, "s", 26, 2, 38, w=5, h=12, canopy=True)
    m.box(14, 46, 1, 15, 47, 26, M("steel"))
    m.box(15, 46, 16, 30, 47, 26, M("blue"))
    bench(m, 32, 50, 1)
    bush(m, 8, 52, 1, 3, flowers="flower_y", rng=rng)


def _sicherheit(m, W, H, rng):
    block(m, 4, 4, 1, 16, 14, 16, "plaster_white", base="concrete", base_h=2)
    flat_roof(m, 4, 4, 16, 14, 16, rng=rng, tech=False)
    window(m, "s", 6, 5, 14, Win(6, 6, frame="frame_dark", lit=0.9, lit_mat="glass_lit2", cross=False), rng)
    m.box(18, 16, 1, 21, 19, 6, M("comp"))
    m.box(21, 17, 5, 31, 18, 7, M("white"))
    for k in range(0, 10, 2):
        m.box(21 + k, 17, 5, 22 + k, 18, 7, M("red"))
    m.box(26, 4, 1, 28, 6, 24, M("steel"))
    m.box(23, 4, 24, 31, 8, 26, M("lamp"))
    m.box(8, 22, 1, 10, 24, 12, M("steel_dark"))
    m.box(7, 21, 12, 12, 25, 14, M("black"))


def _waschplatz(m, W, H, rng):
    slab(m, 0, 0, W, H, paving_fn(6, "concrete", "concrete2"))
    for px in (10, 50):
        m.box(px, 14, 1, px + 3, 17, 30, M("steel"))
        m.box(px, 40, 1, px + 3, 43, 30, M("steel"))
    m.box(8, 14, 30, 56, 43, 33, M("blue"))
    m.box(8, 14, 33, 56, 16, 35, M("comp"))
    for k in range(2):
        m.box(24 + k * 14, 18, 8, 28 + k * 14, 40, 26, M("fabric_b"))
        m.box(25 + k * 14, 19, 26, 27 + k * 14, 39, 30, M("steel"))
    for k in range(8):
        m.put(20 + k * 3, 52, 1 + k % 3, M("white"))
        m.put(21 + k * 3, 54, 2 + k % 2, M("white"))
    m.box(54, 50, 1, 56, 52, 18, M("steel"))


def _mietbuero(m, W, H, rng):
    block(m, 8, 6, 1, 88, 42, 46, "plaster_ochre", base="sandstone2", base_h=5, cornice="plaster_cream")
    facade_windows(m, 8, 6, 88, 42, 1, 2, 20, Win(6, 11, frame="frame_white", lit=0.6, lit_mat="glass_office"), rng, spacing=12, margin=6)
    flat_roof(m, 8, 6, 88, 42, 46, rng=rng, tech=True)
    door(m, "s", 42, 2, 42, w=7, h=14, canopy=True, mat_door="glass_dark")
    m.box(60, 42, 20, 80, 43, 36, M("green_acc"))
    m.box(62, 43, 22, 78, 44, 34, M("white"))
    for u in range(64, 76, 3):
        m.box(u, 44, 24, u + 1, 45, 32, M("green_acc"))
    tree(m, 10, 56, 1, kind="round", size=0.7, rng=rng)
    bench(m, 30, 58, 1)
    lamp_post(m, 86, 56, 1, h=14)
