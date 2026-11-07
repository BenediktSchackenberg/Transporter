"""Spielbare 4x4-Hotels im vorhandenen Voxelmassstab, mit Gast- und Lieferseite."""
import random

from engine import Model, M
from lib import (Win, block, window, door, hip_roof, gable_roof, flat_roof, balcony,
                 slab, paving_fn, grass_fn, deck_fn, flowerbed, bush, tree,
                 patio_set, lounger, lamp_post, bin_, pallet_stack, car)

T = 32


def hotel(level=0, seed=1):
    rng = random.Random(seed + level * 51)
    m = Model(4 * T, 4 * T, 136)
    slab(m, 0, 0, 128, 128, grass_fn(seed))
    slab(m, 6, 84, 108, 128, paving_fn(4, "sandstone", "sandstone2"))
    slab(m, 108, 2, 128, 94, paving_fn(2))  # Lieferhof hinten/rechts
    slab(m, 42, 85, 66, 128, paving_fn(3))  # Gastweg, getrennt vom Lieferhof
    floors = [2, 3, 4][level]
    facade = ["plaster_cream", "plaster_white", "plaster_ochre"][level]
    accent = ["plaster_rose", "plaster_sage", "sandstone"][level]
    roof = ["tile_red", "tile_terra", "slate"][level]
    x0, y0, x1, y1 = (17, 15, 97, 83) if level == 0 else (12, 12, 104, 86)
    top = 3 + floors * 23
    block(m, x0, y0, 1, x1, y1, top, facade, base="stone_base", base_h=4, cornice=accent)
    m.box(x0 - 1, y1 - 1, 25, x1 + 1, y1 + 1, 27, M(accent))
    for floor in range(floors):
        z = 7 + floor * 23
        for x in range(x0 + 8, x1 - 5, 16):
            window(m, "s", x, z, y1, Win(8, 12, frame="frame_white", lit=0.75, lit_mat="glass_lit2"), rng)
        for y in range(y0 + 9, y1 - 7, 17):
            window(m, "e", y, z, x1, Win(7, 11, frame="frame_white", lit=0.65), rng)
        if floor > 0:
            for x in range(x0 + 7, x1 - 14, 22):
                balcony(m, "s", x, x + 16, z - 2, y1, depth=5, rng=rng)
    door(m, "s", 48, 2, y1, w=10, h=17, canopy=True, mat_door="glass_dark")
    # Eigenstaendige Dachsilhouetten und sichtbare Staffelung.
    if level == 0:
        gable_roof(m, x0, y0, x1, y1, top, ridge="x", tile=roof, tile2="tile_red2", pitch=0.8)
        m.box(22, 13, 2, 28, 20, 34, M("timber"))
        m.box(88, 13, 2, 94, 20, 34, M("timber"))
    elif level == 1:
        hip_roof(m, x0, y0, x1, y1, top, tile=roof, tile2="tile_terra2", pitch=0.55)
        block(m, 77, 35, 1, 107, 86, 30, accent, base_h=3)
        flat_roof(m, 77, 35, 107, 86, 30, parapet="sandstone2", tech=False)
    else:
        flat_roof(m, x0, y0, x1, y1, top, parapet="sandstone2", tech=False)
        block(m, 84, 24, 1, 112, 86, 72, accent, base_h=4)
        hip_roof(m, 84, 24, 112, 86, 72, tile="slate", tile2="slate2", pitch=0.45)
        for x in (19, 38, 65):
            m.box(x, y1 + 2, 1, x + 12, y1 + 8, 3, M("sandstone2"))
    # Terrasse, Garten und klare Hotelseite zum Strand.
    slab(m, 5, 89, 43, 125, deck_fn())
    for x, y, color in ((10, 94, "fabric_r"), (29, 102, "fabric_b"), (15, 115, "fabric_w")):
        patio_set(m, x, y, 2, umbrella=color)
    for x in (72, 86, 99):
        lounger(m, x, 111, 2)
    flowerbed(m, 63, 88, 104, 92, 1, rng)
    for x, y in ((5, 80), (112, 99), (109, 5)):
        tree(m, x, y, 1, kind="round", size=0.75, rng=rng)
    lamp_post(m, 58, 106, 1, h=13)
    lamp_post(m, 106, 86, 1, h=12)
    # Rueckseite: Anlieferung, Lagerzugang, Personal und Abfall. Der Gastweg kreuzt den Warenhof nicht.
    door(m, "e", 32, 2, x1, w=7, h=14, canopy=False, mat_door="frame_dark")
    pallet_stack(m, 114, 27, 1, h=2)
    bin_(m, 117, 54, 1)
    car(m, 110, 69, 1, color="blue", along="y")
    if level >= 1:
        slab(m, 70, 111, 93, 125, "sandstone")
        m.clear(74, 114, 1, 89, 122, 3)
        slab(m, 74, 114, 89, 122, "water", z=1)
    return m, {"w": 4, "h": 4, "entrance": [53, 128], "delivery": [128, 42], "height": top + 22}


def hotel_pension(seed=1):
    return hotel(0, seed)


def hotel_strand(seed=1):
    return hotel(1, seed)


def hotel_grand(seed=1):
    return hotel(2, seed)


def kneipe(seed=1):
    rng = random.Random(seed)
    m = Model(64, 64, 76)
    slab(m, 0, 0, 64, 64, paving_fn(3, "sandstone", "sandstone2"))
    block(m, 5, 5, 56, 48, 37, 36, "plaster_ochre", base="stone_base", base_h=4)
    gable_roof(m, 5, 5, 56, 48, 36, ridge="x", tile="tile_red", tile2="tile_red2", pitch=0.72)
    for x in (11, 39):
        window(m, "s", x, 7, 37, Win(10, 12, frame="frame_wood", lit=0.95, lit_mat="glass_lit2"), rng)
    door(m, "s", 28, 2, 37, w=7, h=16, canopy=True, mat_door="wood")
    slab(m, 3, 41, 49, 62, deck_fn())
    patio_set(m, 6, 45, 1, umbrella="fabric_r")
    patio_set(m, 27, 47, 1, umbrella="fabric_b")
    lamp_post(m, 55, 51, 1, h=15)
    bin_(m, 57, 24, 1)
    return m, {"w": 2, "h": 2, "entrance": [31, 64], "delivery": [64, 21], "height": 52}


def strandbar(seed=1):
    m = Model(64, 64, 62)
    slab(m, 0, 0, 64, 64, paving_fn(5, "sandstone", "sandstone2"))
    slab(m, 2, 31, 62, 62, deck_fn())
    block(m, 8, 4, 1, 54, 34, 24, "plaster_white", base="stone_base", base_h=3, cornice="plaster_sage")
    flat_roof(m, 8, 4, 54, 34, 24, parapet="sandstone2", tech=False)
    m.box(11, 33, 6, 51, 38, 10, M("wood"))  # sichtbare Theke
    for x in (5, 25, 46):
        patio_set(m, x, 43, 1, umbrella="fabric_b" if x != 25 else "fabric_w")
    door(m, "e", 17, 2, 54, w=7, h=15, canopy=False, mat_door="frame_dark")
    lamp_post(m, 59, 36, 1, h=13)
    bin_(m, 57, 12, 1)
    return m, {"w": 2, "h": 2, "entrance": [30, 64], "delivery": [64, 17], "height": 30}


def disco(seed=1):
    rng = random.Random(seed)
    m = Model(96, 96, 72)
    slab(m, 0, 0, 96, 96, paving_fn(4))
    block(m, 8, 7, 1, 88, 69, 43, "plaster_rose", base="steel_dark", base_h=4, cornice="blue")
    flat_roof(m, 8, 7, 88, 69, 43, parapet="steel_dark", tech=False)
    for x in (15, 35, 55, 75):
        window(m, "s", x, 13, 69, Win(10, 14, frame="frame_dark", lit=0.95, lit_mat="glass_lit2"), rng)
    door(m, "s", 43, 2, 69, w=10, h=19, canopy=True, mat_door="glass_dark")
    slab(m, 27, 74, 69, 96, deck_fn())
    m.box(21, 73, 1, 24, 94, 4, M("steel_dark"))  # Einlass-Wegfuehrung
    m.box(73, 73, 1, 76, 94, 4, M("steel_dark"))
    lamp_post(m, 14, 78, 1, h=16)
    lamp_post(m, 83, 78, 1, h=16)
    bin_(m, 90, 42, 1)
    return m, {"w": 3, "h": 3, "entrance": [48, 96], "delivery": [96, 34], "height": 50}
