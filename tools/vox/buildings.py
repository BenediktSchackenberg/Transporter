"""Gebaeude als vollstaendige Grundstuecke (1 Feld = 32 Voxel). Ursprung = hintere (Nord-West-)Ecke, Boden z = 0.
Jede Funktion liefert (Model, meta) mit meta = {w, h (Felder), entrance (Voxel auf der Grundstueckskante),
delivery, height}."""
import random

from engine import Model, M
from lib import (Win, window, door, block, facade_windows, gable_roof, hip_roof, flat_roof, chimney, dormer,
                 balcony, tree, bush, hedge, flowerbed, fence, wall_fence, lamp_post, bin_, bike, mailbox, bench,
                 patio_set, lounger, car, pallet_stack, container, slab, grass_fn, lawn_fn, paving_fn, deck_fn)

T = 32


def villa(seed=1):
    """Mediterrane Villa (4x4 Felder): Hauptbau mit Walmdach, hoeherer Turmteil, eingeschossiger Fluegel mit
    Dachterrasse, Garage, Terrasse mit Pergola, Pool, Kiesauffahrt, Natursteinmauer mit Tor, Zypressen."""
    rng = random.Random(seed)
    W = H = 4 * T
    m = Model(W, H, 120)
    slab(m, 0, 0, W, H, lawn_fn(seed))
    # Wege, Auffahrt, Terrasse, Pool
    slab(m, 84, 66, 112, H, "gravel")                      # Kiesauffahrt zur Garage
    slab(m, 58, 86, 66, H, paving_fn(3))                    # Gartenweg zum Tor
    slab(m, 66, 84, 84, 92, paving_fn(3))
    slab(m, 38, 62, 82, 84, deck_fn())                      # Holzterrasse
    m.box(38, 62, 1, 82, 84, 2, M("deck"))
    slab(m, 12, 88, 54, 118, paving_fn(4, "sandstone", "sandstone2"))   # Poolumrandung
    m.box(12, 88, 1, 54, 118, 2, M("sandstone"))
    m.clear(16, 92, 1, 50, 114, 2)
    slab(m, 16, 92, 50, 114, lambda x, y: M("water") if (x + y) % 7 else M("water2"))
    # Hauptbau (2 Geschosse) mit Walmdach
    fh = 28
    block(m, 14, 20, 1, 76, 62, 1 + 2 * fh, "plaster_cream", base_h=3)
    m.box(13, 61, 1 + fh, 77, 63, 2 + fh, M("sandstone"))        # Gesims zwischen den Geschossen
    m.box(75, 19, 1 + fh, 77, 63, 2 + fh, M("sandstone"))
    shut = rng.choice(["leaf4", "blue", "frame_wood"])
    win = Win(6, 12, shutters=shut, lit=0.6)
    win_up = Win(6, 11, shutters=shut, lit=0.4)
    # Erdgeschoss Sued: Terrassentueren (bodentief), Obergeschoss: Fenster + Balkon
    for u in (20, 34, 48):
        window(m, "s", u, 3, 62, Win(7, 18, frame="frame_white", shutters=None, lit=0.7, cross=True, sill=False), rng)
    for u in (20, 34, 48, 62):
        window(m, "s", u, 5 + fh, 62, win_up, rng)
    balcony(m, "s", 30, 58, 1 + fh, 62, depth=6, rng=rng)
    # Ost: Eingang mit Vordach, Fenster
    door(m, "e", 34, 2, 76, w=6, h=14, canopy=True)
    for u in (24, 48):
        window(m, "e", u, 6, 76, win, rng)
    for u in (24, 36, 48):
        window(m, "e", u, 5 + fh, 76, win_up, rng)
    top = hip_roof(m, 14, 20, 76, 62, 1 + 2 * fh, overhang=3, pitch=0.62)
    chimney(m, 24, 30, 1 + 2 * fh + 6, h=14)
    chimney(m, 60, 26, 1 + 2 * fh + 4, h=12)
    # Turmteil (3 Geschosse)
    block(m, 50, 26, 1, 72, 48, 1 + 3 * fh - 4, "plaster_ochre", base_h=3)
    for u in (54, 63):
        window(m, "s", u, 5 + 2 * fh, 48, Win(5, 12, frame="frame_white", arch=True, lit=0.7), rng)
    window(m, "e", 33, 5 + 2 * fh, 72, Win(6, 12, arch=True, lit=0.5), rng)
    hip_roof(m, 50, 26, 72, 48, 1 + 3 * fh - 4, overhang=3, pitch=0.9)
    # Westfluegel eingeschossig mit Dachterrasse
    block(m, 14, 62, 1, 38, 84, 1 + fh, "plaster_cream", base_h=3)
    window(m, "s", 18, 5, 84, Win(6, 12, shutters=shut), rng)
    window(m, "s", 28, 5, 84, Win(6, 12, shutters=shut), rng)
    window(m, "e", 68, 5, 38, Win(6, 12, shutters=shut), rng)
    m.box(14, 62, 1 + fh, 38, 84, 2 + fh, M("paving"))
    for x in range(14, 38):
        for z in range(2 + fh, 7 + fh):
            if x % 3 == 0 or z == 6 + fh:
                m.put(x, 83, z, M("frame_white"))
    for y in range(62, 84):
        for z in range(2 + fh, 7 + fh):
            if y % 3 == 0 or z == 6 + fh:
                m.put(37, y, z, M("frame_white"))
    patio_set(m, 20, 66, 2 + fh, umbrella="fabric_w")
    for yy in (64, 78):
        m.put(34, yy, 2 + fh, M("terracotta"))
        bush(m, 34, yy, 3 + fh, r=2, flowers="flower_r", rng=rng)
    # Pergola ueber der Terrasse mit Weinranken
    for px in (40, 58, 80):
        for py in (82,):
            m.box(px, py, 2, px + 2, py + 2, 26, M("frame_wood"))
    for x in range(38, 82):
        if x % 4 == 0:
            m.box(x, 62, 25, x + 1, 84, 26, M("frame_wood"))
    m.box(38, 82, 25, 82, 84, 27, M("frame_wood"))
    for _ in range(140):
        x, y = rng.randint(38, 81), rng.randint(62, 83)
        m.put(x, y, 26 + rng.randint(0, 1), M(rng.choice(["leaf2", "leaf3", "leaf1", "flower_p"])))
    patio_set(m, 46, 68, 2, umbrella=None)
    lounger(m, 22, 100 - 10, 2)
    for lx in (20, 28, 36):
        lounger(m, lx, 80 + 9, 2) if False else None
    for lx in (56, 62):
        pass
    lounger(m, 18, 116 - 2, 1) if False else None
    for lx in (22, 30, 38):
        m.box(lx, 115, 2, lx + 3, 117, 3, M("fabric_w"))
    # Garage (Flachdach) mit Sektionaltor
    block(m, 84, 38, 1, 112, 66, 25, "plaster_cream", base_h=3)
    flat_roof(m, 83, 37, 113, 67, 24, parapet="sandstone", fill="gravel_roof", tech=False)
    for x in range(88, 108):
        for z in range(2, 20):
            m.put(x, 65, z, 0)
            m.put(x, 64, z, M("frame_white") if z % 3 else M("plaster_grey"))
    lamp_post(m, 86, 67, 1, h=9)
    m.put(110, 66, 18, M("lamp"))
    car(m, 92, 72, 1, color="red", along="y")
    # Grundstuecksmauer mit Tor und Pfeilerleuchten
    wall_fence(m, 0, H - 3, 56, H, h=5)
    wall_fence(m, 68, H - 3, 82, H, h=5)
    wall_fence(m, 114, H - 3, W, H, h=5)
    wall_fence(m, W - 3, 0, W, H, h=5)
    for gx in (56, 66, 82, 112):
        m.box(gx, H - 4, 1, gx + 2, H, 9, M("sandstone2"))
        m.put(gx, H - 1, 9, M("lamp"))
    for x in range(58, 66):            # schmiedeeisernes Tor
        for z in range(1, 8):
            if x % 2 == 0 or z in (1, 7):
                m.put(x, H - 2, z, M("rail"))
    mailbox(m, 54, H - 5, 1, color="yellow")
    # Bepflanzung: Zypressen, Obstbaeume, Hecken, Beete
    for (tx, ty) in ((4, 6), (4, 40), (4, 74), (118, 8), (118, 26), (78, 6)):
        tree(m, tx, ty, 1, kind="conifer", size=1.0, rng=rng)
    for (tx, ty) in ((118, 76), (8, 120 - 22)):
        tree(m, tx, ty, 1, kind="round", size=1.1, rng=rng)
    tree(m, 120, 108, 1, kind="blossom", size=0.9, rng=rng)
    hedge(m, 2, 84, 12, 120, 1, h=6)
    flowerbed(m, 66, 92, 82, 100, 1, rng=rng)
    flowerbed(m, 40, 86, 56, 90, 1, rng=rng)
    for bx, by in ((80, 30), (80, 52), (12, 14), (44, 14)):
        bush(m, bx, by, 1, r=3, flowers=rng.choice(["flower_r", "flower_y", "flower_w", None]), rng=rng)
    for k in range(5):
        m.put(36 + k * 9, 63 + 20, 2, M("terracotta"))
    lamp_post(m, 70, 84, 1, h=12)
    lamp_post(m, 40, 118, 1, h=12)
    meta = {"w": 4, "h": 4, "entrance": [62, H], "delivery": [98, H], "height": top}
    return m, meta
