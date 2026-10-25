"""Wohngebaeude, Buero, Hochhaus, Schule, Kindergarten (je als vollstaendiges Grundstueck)."""
import random

from engine import Model, M
from lib import (Win, window, door, block, facade_windows, gable_roof, hip_roof, flat_roof, chimney, dormer,
                 balcony, tree, bush, hedge, flowerbed, fence, lamp_post, bin_, bike, mailbox, bench,
                 patio_set, lounger, car, pallet_stack, slab, grass_fn, paving_fn, deck_fn)

T = 32


def _front_garden(m, x0, y0, x1, y1, rng):
    slab(m, x0, y0, x1, y1, grass_fn(rng.randint(0, 999)))


def house_extra(variant, seed):
    """Weitere Haustypen (variant 4-7): L-Haus, Stadthaus, Bauernhaus mit Scheune, Cottage mit Erker."""
    rng = random.Random(seed * 23 + variant)
    W = H = 2 * T
    m = Model(W, H, 90)
    walls = ["plaster_cream", "plaster_white", "plaster_rose", "plaster_sage", "plaster_ochre", "plaster_grey", "brick", "sandstone"]
    wall = walls[(seed * 3 + variant) % len(walls)]
    wall2 = walls[(seed * 5 + variant + 2) % len(walls)]
    roofs = [("slate", "slate2"), ("tile_red", "tile_red2"), ("tile_terra", "tile_terra2")]
    rt = roofs[(seed + variant + seed // 3) % len(roofs)]
    _front_garden(m, 0, 0, W, H, rng)
    if variant == 4:      # L-foermiges Haus: zwei Giebel, Eingang im Winkel
        slab(m, 44, 46, 52, H, paving_fn(3))
        block(m, 6, 26, 1, 40, 50, 28, wall, base_h=2)
        block(m, 28, 8, 1, 58, 36, 28, wall2, base_h=2)
        window(m, "s", 9, 6, 50, Win(5, 10, shutters="frame_wood", lit=0.5), rng)
        window(m, "s", 26, 6, 50, Win(5, 10, lit=0.5), rng)
        door(m, "e", 38, 2, 58, w=5, h=12)
        window(m, "e", 12, 8, 58, Win(5, 10, lit=0.5), rng)
        window(m, "w", 34, 6, 6, Win(5, 10, lit=0.4), rng)
        top = gable_roof(m, 6, 26, 40, 50, 28, ridge="x", tile=rt[0], tile2=rt[1], pitch=1.0)
        gable_roof(m, 28, 8, 58, 36, 28, ridge="y", tile=rt[0], tile2=rt[1], pitch=1.0)
        chimney(m, 14, 34, 40, h=10)
        for x in range(8, 28, 6):
            flowerbed(m, x, 54, x + 4, 62, 1, rng=rng)
        bin_(m, 56, 50, 1, "green_acc")
        tree(m, 4, 4, 1, kind="round", size=0.9, rng=rng)
        bush(m, 48, 54, 1, r=3, flowers="flower_r", rng=rng)
    elif variant == 5:    # schmales Stadthaus, drei Geschosse, Flachdach mit Solar
        slab(m, 22, 48, 36, H, paving_fn(3))
        block(m, 12, 14, 1, 52, 48, 50, wall, base_h=3)
        for z in (8, 29):
            window(m, "s", 8, z, 48, Win(5, 10, lit=0.5), rng)
            window(m, "s", 28, z, 48, Win(5, 10, lit=0.5), rng)
        door(m, "s", 19, 2, 48, w=6, h=13, mat_door="frame_dark")
        balcony(m, "s", 6, 16, 29, 48, depth=4, rng=rng)
        for z in (10, 30):
            window(m, "e", 24, z, 52, Win(5, 10, lit=0.4), rng)
        top = flat_roof(m, 12, 14, 52, 48, 50, parapet="plaster_white", tech=False, solar=True)
        hedge(m, 0, 52, 20, 58, 1, h=5)
        hedge(m, 38, 52, 64, 58, 1, h=5)
        bike(m, 40, 54, 1, color="red", face="y")
        tree(m, 56, 8, 1, kind="round", size=0.8, rng=rng)
    elif variant == 6:    # Bauernhaus mit Scheune und Veranda
        slab(m, 20, 46, 30, H, paving_fn(3))
        block(m, 4, 22, 1, 34, 48, 26, wall, base_h=2)
        block(m, 34, 12, 1, 62, 48, 36, "brick2", base=None)
        window(m, "s", 7, 6, 48, Win(5, 9, shutters="frame_wood", lit=0.5), rng)
        window(m, "s", 22, 6, 48, Win(5, 9, shutters="frame_wood", lit=0.5), rng)
        door(m, "s", 15, 2, 48, w=5, h=12)
        door(m, "s", 40, 2, 48, w=14, h=22, mat_door="frame_wood", canopy=False, lamp=False)
        top = gable_roof(m, 4, 22, 34, 48, 26, ridge="x", tile=rt[0], tile2=rt[1], pitch=1.0)
        gable_roof(m, 34, 12, 62, 48, 36, ridge="y", tile="slate", tile2="slate2", pitch=0.9)
        for px in (6, 14, 26, 32):
            m.box(px, 52, 1, px + 2, 54, 12, M("frame_wood"))
        m.box(4, 50, 12, 34, 56, 14, M("frame_wood"))
        chimney(m, 10, 30, 36, h=10)
        fence(m, 0, H - 2, 20, H, 1, h=4)
        fence(m, 30, H - 2, W, H, 1, h=4)
        tree(m, 52, 4, 1, kind="round", size=1.0, rng=rng)
        bin_(m, 2, 54, 1, "black")
    else:                 # Cottage mit Walmdach und Erker
        slab(m, 14, 52, 22, H, paving_fn(3))
        block(m, 8, 14, 1, 52, 46, 24, wall, base_h=2)
        block(m, 24, 46, 1, 40, 52, 20, wall2, base_h=2)
        window(m, "s", 10, 6, 46, Win(5, 10, shutters="frame_wood", lit=0.5), rng)
        window(m, "s", 44, 6, 46, Win(5, 10, shutters="frame_wood", lit=0.5), rng)
        window(m, "s", 28, 5, 52, Win(8, 10, lit=0.6), rng)
        door(m, "s", 14, 2, 46, w=5, h=12)
        window(m, "e", 24, 6, 52, Win(5, 10, lit=0.5), rng)
        top = hip_roof(m, 8, 14, 52, 46, 24, tile=rt[0], tile2=rt[1], pitch=0.9)
        hip_roof(m, 24, 46, 40, 52, 20, tile=rt[0], tile2=rt[1], pitch=0.8)
        chimney(m, 44, 20, 30, h=9)
        hedge(m, 0, H - 6, 12, H - 2, 1, h=5)
        hedge(m, 24, H - 6, W, H - 2, 1, h=5)
        bush(m, 4, 40, 1, r=3, flowers="flower_r", rng=rng)
        tree(m, 56, 54, 1, kind="round", size=0.8, rng=rng)
    return m, {"w": 2, "h": 2, "entrance": [29, H], "delivery": [29, H], "height": top}


def house(variant=0, seed=1):
    """Einfamilienhaus 2x2 Felder; Varianten unterscheiden Baukoerper, Dach und Grundstueck."""
    if variant >= 4:
        return house_extra(variant, seed)
    rng = random.Random(seed * 17 + variant)
    W = H = 2 * T
    m = Model(W, H, 90)
    walls = ["plaster_cream", "plaster_white", "plaster_rose", "plaster_sage", "plaster_ochre", "plaster_grey", "brick", "sandstone"]
    wall = walls[(seed * 3 + variant) % len(walls)]
    roofs = [("slate", "slate2"), ("tile_red", "tile_red2"), ("tile_terra", "tile_terra2")]
    rt = roofs[(seed + variant * 2 + seed // 4) % len(roofs)]
    _front_garden(m, 0, 0, W, H, rng)
    if variant == 0:      # Satteldach (First y), Gaube, Garage rechts
        slab(m, 20, 44, 27, H, paving_fn(3))
        block(m, 6, 10, 1, 40, 44, 49, wall)
        window(m, "s", 9, 6, 44, Win(5, 10, shutters="frame_wood", lit=0.5), rng)
        door(m, "s", 21, 2, 44, w=5, h=12)
        window(m, "s", 10, 32, 44, Win(5, 9, lit=0.4), rng)
        window(m, "s", 27, 32, 44, Win(5, 9, lit=0.4), rng)
        window(m, "e", 16, 6, 40, Win(5, 10, lit=0.5), rng)
        window(m, "e", 28, 6, 40, Win(5, 10, lit=0.5), rng)
        top = gable_roof(m, 6, 10, 40, 44, 49, ridge="y", tile=rt[0], tile2=rt[1], pitch=1.1)
        chimney(m, 14, 20, 58, h=12)
        block(m, 42, 18, 1, 62, 44, 22, "plaster_grey", base_h=2)
        flat_roof(m, 41, 17, 63, 45, 22, parapet="zinc", tech=False)
        for x in range(45, 59):
            for z in range(2, 17):
                m.put(x, 43, z, M("frame_white") if z % 3 else M("plaster_grey"))
        slab(m, 42, 44, 62, H, "asphalt2")
        bin_(m, 34, 50, 1, "green_acc")
        bin_(m, 34, 54, 1, "black")
        mailbox(m, 18, 60, 1)
        bush(m, 8, 54, 1, r=3, flowers="flower_r", rng=rng)
        tree(m, 4, 2, 1, kind="round", size=0.8, rng=rng)
        fence(m, 0, H - 2, 20, H, 1, h=4)
        fence(m, 27, H - 2, 42, H, 1, h=4)
    elif variant == 1:    # Bungalow mit Walmdach, Carport, Holzterrasse
        slab(m, 8, 48, 14, H, paving_fn(3))
        block(m, 4, 8, 1, 40, 48, 27, wall, base_h=2)
        for u in (8, 26):
            window(m, "s", u, 6, 48, Win(7, 12, frame="frame_dark", lit=0.6), rng)
        door(m, "e", 30, 2, 40, w=5, h=13, mat_door="frame_dark")
        window(m, "e", 14, 6, 40, Win(6, 12, frame="frame_dark", lit=0.5), rng)
        top = hip_roof(m, 4, 8, 40, 48, 27, tile=rt[0], tile2=rt[1], pitch=0.7)
        for (px, py) in ((44, 14), (60, 14), (44, 46), (60, 46)):
            m.box(px, py, 1, px + 2, py + 2, 22, M("frame_wood"))
        m.box(43, 12, 22, 63, 50, 24, M("frame_wood"))
        m.box(44, 13, 24, 62, 49, 25, M("leaf2"))
        slab(m, 44, 12, 62, H, "paving2")
        car(m, 47, 18, 1, color=rng.choice(["blue", "black", "white", "red"]), along="y")
        slab(m, 16, 50, 36, 62, deck_fn())
        m.box(16, 50, 1, 36, 62, 2, M("deck"))
        patio_set(m, 23, 53, 2, umbrella="fabric_b")
        bike(m, 40, 54, 1, color="blue", face="y")
        flowerbed(m, 1, 50, 7, 62, 1, rng=rng)
    elif variant == 2:    # moderner Kubus, auskragendes Holz-Obergeschoss, Flachdach mit Solar
        slab(m, 26, 46, 32, H, paving_fn(4, "concrete", "concrete2"))
        block(m, 8, 8, 1, 50, 46, 31, "plaster_white", base=None)
        block(m, 8, 8, 31, 36, 36, 56, "deck", base=None)
        for z in range(31, 56):
            for x in range(8, 36):
                if x % 3 == 0:
                    m.put(x, 35, z, M("deck2"))
        window(m, "s", 12, 4, 46, Win(12, 22, frame="frame_dark", cross=False, sill=False, lit=0.6), rng)
        window(m, "s", 36, 6, 46, Win(8, 14, frame="frame_dark", cross=False, lit=0.5), rng)
        window(m, "s", 13, 36, 36, Win(14, 12, frame="frame_dark", cross=False, sill=False, lit=0.5), rng)
        window(m, "e", 16, 36, 36, Win(10, 12, frame="frame_dark", cross=False, sill=False, lit=0.4), rng)
        door(m, "e", 30, 2, 50, w=5, h=14, mat_door="frame_dark", canopy=False)
        flat_roof(m, 8, 8, 50, 46, 31, parapet="plaster_white", tech=False)
        flat_roof(m, 8, 8, 36, 36, 56, parapet="frame_dark", tech=False, solar=True)
        top = 60
        slab(m, 34, 48, 62, 62, "gravel")
        m.box(36, 50, 1, 60, 60, 2, M("concrete"))
        lounger(m, 39, 52, 2)
        lounger(m, 46, 52, 2)
        for k in range(4):
            tree(m, 56, 4 + k * 12, 1, kind="conifer", size=0.55, rng=rng)
        bin_(m, 53, 50, 1, "black")
    else:                 # Fachwerkhaus (Mainzer Altstadt), First x
        slab(m, 26, 46, 32, H, paving_fn(3))
        block(m, 6, 12, 1, 52, 46, 27, "sandstone", base_h=3)
        block(m, 6, 12, 27, 52, 46, 53, "plaster_white", base=None)
        for z in range(27, 53):
            for x in range(6, 52):
                if x % 8 == 0 or z in (27, 39, 52) or ((x % 8) == ((z - 27) % 8) and z < 39):
                    m.put(x, 45, z, M("timber"))
            for y in range(12, 46):
                if y % 8 == 0 or z in (27, 39, 52):
                    m.put(51, y, z, M("timber"))
        for u in (10, 38):
            window(m, "s", u, 6, 46, Win(5, 10, lit=0.6), rng)
        for u in (10, 20, 34, 43):
            window(m, "s", u, 30, 46, Win(4, 7, lit=0.5), rng)
        door(m, "s", 26, 2, 46, w=6, h=13, mat_door="brick2")
        window(m, "e", 20, 6, 52, Win(5, 10, lit=0.5), rng)
        window(m, "e", 30, 30, 52, Win(4, 7, lit=0.5), rng)
        top = gable_roof(m, 6, 12, 52, 46, 53, ridge="x", tile=rt[0], tile2=rt[1], pitch=1.2)
        dormer(m, 26, 46, 58)
        chimney(m, 40, 22, 62, h=12)
        for x in range(2, 24, 6):
            flowerbed(m, x, 50, x + 4, 60, 1, rng=rng)
        bench(m, 36, 54, 1, along="x")
        tree(m, 56, 4, 1, kind="round", size=0.9, rng=rng)
        fence(m, 0, H - 2, 26, H, 1, h=4)
        fence(m, 32, H - 2, W, H, 1, h=4)
    return m, {"w": 2, "h": 2, "entrance": [29, H], "delivery": [29, H], "height": top}


def semi(seed=1):
    """Doppelhaus 4x2 Felder: zwei Wohneinheiten mit getrennten Eingaengen, Gaerten und eigenen Details."""
    rng = random.Random(seed)
    W, H = 4 * T, 2 * T
    m = Model(W, H, 90)
    _front_garden(m, 0, 0, W, H, rng)
    wall_l, wall_r = rng.choice([("plaster_cream", "plaster_rose"), ("plaster_white", "plaster_sage"),
                                 ("plaster_ochre", "plaster_cream"), ("plaster_grey", "brick"), ("sandstone", "plaster_white"),
                                 ("plaster_sage", "plaster_rose")])
    block(m, 10, 8, 1, 64, 40, 53, wall_l, base_h=3)
    block(m, 64, 8, 1, 118, 40, 53, wall_r, base_h=3)
    m.box(63, 8, 1, 65, 41, 54, M("stone_base"))
    for half, (x0, doorc, shut) in enumerate(((10, "frame_wood", "leaf4"), (64, "blue", None))):
        rng2 = random.Random(seed * 3 + half)
        door(m, "s", x0 + 22, 2, 40, w=6, h=13, mat_door=doorc)
        window(m, "s", x0 + 6, 6, 40, Win(7, 11, shutters=shut, lit=0.6), rng2)
        window(m, "s", x0 + 38, 6, 40, Win(7, 11, shutters=shut, lit=0.6), rng2)
        for u in (x0 + 6, x0 + 22, x0 + 38):
            window(m, "s", u, 33, 40, Win(6, 10, lit=0.45), rng2)
        slab(m, x0 + 22, 40, x0 + 28, H, paving_fn(3))
        mailbox(m, x0 + 31, 58, 1, color="yellow" if half == 0 else "red")
        bin_(m, x0 + 2, 44, 1, "green_acc")
        bin_(m, x0 + 2, 48, 1, "blue")
    window(m, "e", 16, 6, 118, Win(6, 11, lit=0.5), rng)
    window(m, "e", 16, 33, 118, Win(6, 10, lit=0.4), rng)
    top = gable_roof(m, 10, 8, 118, 40, 53, ridge="x", tile="tile_terra", tile2="tile_terra2", pitch=1.0)
    dormer(m, 20, 40, 60)
    dormer(m, 98, 40, 60)
    chimney(m, 40, 18, 64, h=12)
    chimney(m, 86, 18, 64, h=12)
    flowerbed(m, 14, 44, 30, 52, 1, rng=rng)
    bike(m, 4, 56, 1, color="red")
    bike(m, 4, 59, 1, color="blue")
    hedge(m, 104, 44, 126, 48, 1, h=5)
    m.box(98, 50, 1, 110, 60, 3, M("wood"))
    m.box(99, 51, 1, 109, 59, 3, M("sand"))
    fence(m, 63, 41, 65, H, 1, h=5, mat_f="frame_wood")
    fence(m, 0, H - 2, 32, H, 1, h=4)
    fence(m, 38, H - 2, 86, H, 1, h=4)
    fence(m, 92, H - 2, W, H, 1, h=4)
    tree(m, 120, 2, 1, kind="round", size=0.9, rng=rng)
    return m, {"w": 4, "h": 2, "entrance": [35, H], "delivery": [89, H], "height": top}


def apartment(variant=0, seed=1):
    """Mehrfamilienhaus 3x3 Felder: Fassadenabschnitte, Balkone, gemeinsamer Eingang mit Briefkaesten,
    Fahrrad- und Muellflaeche, Gemeinschaftsgarten."""
    rng = random.Random(seed * 5 + variant)
    W = H = 3 * T
    floors, fh = (4, 26) if variant == 0 else (5, 25)
    m = Model(W, H, 30 + floors * fh + 34)
    _front_garden(m, 0, 0, W, H, rng)
    slab(m, 0, 70, W, 80, paving_fn(4))
    x0, y0, x1, y1 = 6, 8, 90, 70
    zt = 1 + floors * fh
    walls = [("plaster_ochre", "plaster_cream"), ("plaster_rose", "plaster_white"), ("plaster_sage", "plaster_grey"),
             ("brick", "plaster_cream"), ("plaster_grey", "plaster_white"), ("sandstone", "plaster_rose")]
    wa, wb = walls[(seed + variant) % len(walls)]
    block(m, x0, y0, 1, x1, y1, zt, wa, base="sandstone2", base_h=6)
    block(m, 46, y0, 1, x1, y1, zt, wb, base="sandstone2", base_h=6)
    m.box(44, y1, 1, 48, y1 + 1, zt, M("stone_base"))
    for f in range(1, floors):
        m.box(x0, y1, 1 + f * fh, x1, y1 + 1, 2 + f * fh, M("stone_base"))
    win = Win(5, 11, frame="frame_white", lit=0.5)
    for f in range(floors):
        zz = 1 + f * fh + 6
        for u in (10, 20, 30, 52, 62, 72, 82):
            if f == 0 and u in (30, 52):
                continue
            window(m, "s", u, zz, y1, win, rng)
        for u in (14, 28, 42, 56):
            window(m, "e", u, zz, x1, win, rng)
        if f >= 1:
            balcony(m, "s", 8, 28, 1 + f * fh, y1, depth=6, rail="frame_white", rng=rng)
            balcony(m, "s", 60, 80, 1 + f * fh, y1, depth=6, rail="steel", rng=rng)
    door(m, "s", 38, 2, y1, w=8, h=16, mat_door="glass_dark")
    m.box(30, y1, 4, 36, y1 + 1, 12, M("steel"))
    for k in range(3):
        m.box(31 + k * 2, y1 + 1, 6, 32 + k * 2, y1 + 2, 10, M("frame_dark"))
    if variant == 0:
        top = gable_roof(m, x0, y0, x1, y1, zt, ridge="x", tile="tile_terra", tile2="tile_terra2", pitch=0.75)
        dormer(m, 20, y1, zt + 6)
        dormer(m, 66, y1, zt + 6)
        chimney(m, 30, 20, zt + 14, h=12)
    else:
        flat_roof(m, x0, y0, x1, y1, zt, rng=rng, tech=False)
        block(m, 20, 18, zt, 76, 56, zt + 22, "plaster_white", base=None)   # Staffelgeschoss
        window(m, "s", 26, zt + 4, 56, Win(14, 14, frame="frame_dark", cross=False, lit=0.6), rng)
        window(m, "s", 50, zt + 4, 56, Win(14, 14, frame="frame_dark", cross=False, lit=0.6), rng)
        flat_roof(m, 20, 18, 76, 56, zt + 22, rng=rng, solar=True)
        patio_set(m, 30, 60, zt + 1, umbrella="fabric_r")
        top = zt + 26
    for k in range(5):
        bike(m, 4 + k * 3, 74, 1, color=rng.choice(["red", "blue", "black", "yellow"]), face="y")
    m.box(2, 72, 1, 20, 73, 8, M("frame_dark"))
    m.box(70, 74, 1, 90, 84, 10, M("wood"))           # Muellhaus mit Gruendach
    m.box(70, 74, 10, 90, 84, 11, M("leaf2"))
    for k in range(4):
        bin_(m, 72 + k * 4, 85, 1, rng.choice(["green_acc", "blue", "yellow", "black"]))
    bench(m, 30, 86, 1)
    tree(m, 52, 84, 1, kind="round", size=0.9, rng=rng)
    flowerbed(m, 2, 88, 26, 94, 1, rng=rng)
    lamp_post(m, 62, 90, 1, h=14)
    return m, {"w": 3, "h": 3, "entrance": [42, H], "delivery": [42, H], "height": top}


def office(variant=0, seed=1):
    """Buerogebaeude 3x3: verglaster Eingang, Fassadenraster, Firmenschild, separater Lieferbereich (Ost)."""
    rng = random.Random(seed * 11 + variant)
    W = H = 3 * T
    floors, fh = 5, 26
    m = Model(W, H, 1 + floors * fh + 40)
    slab(m, 0, 0, W, H, paving_fn(4, "concrete", "concrete2"))
    x0, y0, x1, y1 = 6, 6, 78, 66
    zt = 1 + floors * fh
    if variant == 0:      # Glas-Vorhangfassade mit Pfosten-Riegel, Fenstergruppen unterschiedlich beleuchtet
        m.box(x0, y0, 1, x1, y1, zt, M("glass_dark"))
        for f in range(floors):
            m.box(x0, y1 - 1, 1 + f * fh, x1, y1, 3 + f * fh, M("steel"))
            m.box(x1 - 1, y0, 1 + f * fh, x1, y1, 3 + f * fh, M("steel"))
            for gx in range(x0 + 1, x1 - 1, 12):
                if f > 0 and rng.random() < 0.55:
                    lm = M("glass_office") if rng.random() < 0.7 else M("glass_lit")
                    m.box(gx, y1 - 1, 4 + f * fh, min(gx + 11, x1 - 1), y1, (f + 1) * fh, lm)
            for gy in range(y0 + 1, y1 - 1, 12):
                if f > 0 and rng.random() < 0.5:
                    m.box(x1 - 1, gy, 4 + f * fh, x1, min(gy + 11, y1 - 1), (f + 1) * fh, M("glass_office"))
            for x in range(x0, x1, 6):
                m.box(x, y1 - 1, 1 + f * fh, x + 1, y1, (f + 1) * fh, M("steel"))
            for y in range(y0, y1, 6):
                m.box(x1 - 1, y, 1 + f * fh, x1, y + 1, (f + 1) * fh, M("steel"))
    else:                 # Natursteinraster mit tiefen Fensterlaibungen
        block(m, x0, y0, 1, x1, y1, zt, "sandstone", base="stone_base", base_h=4)
        facade_windows(m, x0, y0, x1, y1, 1, floors, fh, Win(6, 15, frame="frame_dark", cross=False, sill=True,
                       lit=0.55, lit_mat="glass_office"), rng, spacing=10)
        for f in range(1, floors):
            m.box(x0, y1, 1 + f * fh, x1, y1 + 1, 3 + f * fh, M("sandstone2"))
    # Eingangshalle (doppelte Hoehe, Glas) mit Vordach und Schild
    m.clear(30, y1 - 4, 1, 52, y1, 36)
    m.box(30, y1 - 4, 1, 52, y1 - 3, 36, M("glass_lit2"))
    m.box(29, y1 - 4, 1, 30, y1 + 1, 37, M("steel"))
    m.box(52, y1 - 4, 1, 53, y1 + 1, 37, M("steel"))
    m.box(26, y1 - 4, 36, 56, y1 + 6, 38, M("steel_dark"))
    m.box(34, y1, 40, 48, y1 + 1, 46, M("blue"))
    m.box(36, y1 + 1, 41, 46, y1 + 2, 45, M("white"))
    flat_roof(m, x0, y0, x1, y1, zt, rng=rng, tech=False)
    block(m, x0 + 14, y0 + 10, zt, x1 - 14, y1 - 14, zt + 18, "concrete", base=None)   # Technikgeschoss
    flat_roof(m, x0 + 14, y0 + 10, x1 - 14, y1 - 14, zt + 18, rng=rng)
    top = zt + 24
    # Lieferbereich Ost: Rolltor, Rampe, Markierung, Paletten
    m.box(x1, 20, 1, x1 + 12, 40, 3, M("concrete2"))
    for y in range(22, 38):
        for z in range(3, 18):
            m.put(x1 - 1, y, z, M("steel") if z % 3 else M("steel_dark"))
    m.box(x1 + 13, 18, 0, x1 + 14, 42, 1, M("yellow"))
    pallet_stack(m, x1 + 2, 44, 1, h=1, goods="fabric_w")
    for tx in (8, 62):
        m.box(tx - 2, 74, 1, tx + 6, 82, 2, M("stone_base"))
        tree(m, tx + 1, 77, 2, kind="round", size=0.85, rng=rng)
    bench(m, 22, 82, 1)
    bench(m, 64, 88, 1)
    lamp_post(m, 56, 76, 1, h=16)
    for k in range(3):
        bike(m, 84, 70 + k * 3, 1, color=rng.choice(["red", "blue", "black"]), face="x")
    return m, {"w": 3, "h": 3, "entrance": [41, H], "delivery": [W, 30], "height": top}


def highrise(variant=0, seed=1):
    """Hochhaus 3x3: Sockel mit Eingangshalle, gegliederter Schaft, zurueckgesetzte obere Geschosse, Dachtechnik."""
    rng = random.Random(seed * 13 + variant)
    W = H = 3 * T
    floors, fh = (13, 24) if variant == 0 else (10, 24)
    zt = 50 + (floors - 2) * fh
    m = Model(W, H, zt + 60)
    slab(m, 0, 0, W, H, paving_fn(4, "paving", "paving2"))
    block(m, 4, 4, 1, 86, 78, 50, "stone_base", base=None)
    m.clear(24, 74, 1, 66, 78, 40)
    m.box(24, 74, 1, 66, 75, 40, M("glass_lit2"))
    for x in range(24, 66, 6):
        m.box(x, 75, 1, x + 1, 78, 40, M("steel"))
    m.box(20, 74, 40, 70, 84, 42, M("steel_dark"))
    wall = "plaster_grey" if variant == 0 else "brick"
    block(m, 10, 10, 50, 80, 72, zt, wall, base=None)
    for f in range(floors - 2):
        zz = 50 + f * fh
        m.box(10, 72, zz, 80, 73, zz + 2, M("concrete"))
        m.box(80, 10, zz, 81, 72, zz + 2, M("concrete"))
        for u in range(13, 77, 8):
            lit = rng.random() < 0.45
            m.box(u, 71, zz + 5, u + 6, 72, zz + 19, M("glass_office" if lit else "glass_dark"))
            m.box(u - 1, 72, zz + 4, u + 7, 73, zz + 5, M("concrete"))
        for u in range(13, 69, 8):
            lit = rng.random() < 0.4
            m.box(79, u, zz + 5, 80, u + 6, zz + 19, M("glass_lit" if lit else "glass_dark"))
            m.box(80, u - 1, zz + 4, 81, u + 7, zz + 5, M("concrete"))
    for x in (10, 44, 79):
        m.box(x, 72, 50, x + 1, 74, zt, M("concrete"))
    block(m, 18, 18, zt, 72, 64, zt + 24, "glass_dark", base=None)
    for x in range(18, 72, 5):
        m.box(x, 63, zt, x + 1, 64, zt + 24, M("steel"))
    flat_roof(m, 10, 10, 80, 72, zt, rng=rng, tech=False)
    flat_roof(m, 18, 18, 72, 64, zt + 24, rng=rng)
    m.box(40, 30, zt + 27, 52, 42, zt + 40, M("steel"))
    m.box(45, 35, zt + 40, 47, 37, zt + 52, M("steel_dark"))
    m.put(46, 36, zt + 52, M("lamp_red"))
    for tx in (6, 74):
        tree(m, tx, 86, 1, kind="round", size=0.8, rng=rng)
    bench(m, 30, 88, 1)
    bench(m, 52, 88, 1)
    return m, {"w": 3, "h": 3, "entrance": [45, H], "delivery": [W, 40], "height": zt + 52}


def school(seed=1):
    """Schule 6x4 Felder: Klinkerbau in L-Form, Schulhof mit Spielfeld, Baeumen, Baenken, Fahrradstaendern,
    Haupteingang mit Uhr, Kuechen-Lieferzugang Ost."""
    rng = random.Random(seed)
    W, H = 6 * T, 4 * T
    m = Model(W, H, 110)
    slab(m, 0, 0, W, H, paving_fn(4, "paving", "paving2"))
    fh = 26
    block(m, 8, 8, 1, 120, 44, 1 + 3 * fh, "brick", base="sandstone2", base_h=5)
    block(m, 120, 8, 1, 156, 96, 1 + 3 * fh, "brick", base="sandstone2", base_h=5)
    for f in range(3):
        zz = 1 + f * fh + 6
        for u in range(12, 116, 9):
            if f == 0 and 52 <= u <= 70:
                continue
            window(m, "s", u, zz, 44, Win(6, 13, frame="frame_white", lit=0.35, lit_mat="glass_lit2"), rng)
        for u in range(12, 92, 9):
            window(m, "e", u, zz, 156, Win(6, 13, frame="frame_white", lit=0.35, lit_mat="glass_lit2"), rng)
        for u in range(124, 152, 9):
            window(m, "s", u, zz, 96, Win(6, 13, lit=0.35), rng)
        m.box(8, 44, 1 + f * fh, 120, 45, 3 + f * fh, M("sandstone"))
    door(m, "s", 56, 3, 44, w=12, h=18, mat_door="frame_dark")
    m.box(52, 44, 1, 72, 52, 3, M("sandstone"))
    m.box(58, 44, 66, 66, 45, 74, M("white"))
    m.box(61, 45, 69, 63, 46, 72, M("black"))
    top = gable_roof(m, 8, 8, 120, 44, 1 + 3 * fh, ridge="x", tile="slate", tile2="slate2", pitch=0.7)
    gable_roof(m, 120, 8, 156, 96, 1 + 3 * fh, ridge="y", tile="slate", tile2="slate2", pitch=0.7)
    door(m, "e", 70, 2, 156, w=8, h=14, mat_door="steel", canopy=True)
    slab(m, 156, 64, W, 84, "asphalt2")
    slab(m, 10, 56, 100, 118, "asphalt")
    for x in range(12, 98):
        for y in (58, 116):
            m.put(x, y, 0, M("white"))
    for y in range(58, 117):
        for x in (12, 55, 97):
            m.put(x, y, 0, M("white"))
    for (hx, hy) in ((14, 86), (94, 86)):
        m.box(hx, hy, 1, hx + 1, hy + 1, 26, M("steel"))
        m.box(hx - 1, hy - 3, 24, hx + 1, hy + 4, 30, M("white"))
        m.put(hx + 1, hy, 23, M("orange"))
    for (tx, ty) in ((110, 60), (110, 100), (140, 106), (176, 20)):
        m.box(tx - 4, ty - 4, 1, tx + 6, ty + 6, 2, M("soil"))
        tree(m, tx, ty, 2, kind="round", size=1.0, rng=rng)
    for k in range(3):
        bench(m, 118 + k * 10, 118, 1)
    m.box(160, 100, 1, 190, 101, 9, M("frame_dark"))
    for k in range(9):
        bike(m, 161 + k * 3, 104, 1, color=rng.choice(["red", "blue", "yellow", "black", "green_acc"]), face="y")
    fence(m, 0, H - 2, 52, H, 1, h=8, mat_f="green_acc")
    fence(m, 72, H - 2, W, H, 1, h=8, mat_f="green_acc")
    lamp_post(m, 50, 122, 1, h=16)
    lamp_post(m, 74, 122, 1, h=16)
    return m, {"w": 6, "h": 4, "entrance": [62, H], "delivery": [W, 74], "height": top}


def kindergarten(seed=1):
    """Kindergarten 4x3 Felder: niedrige Gebaeudeteile mit Farbakzenten, umzaunter Spielgarten mit Rutsche,
    Schaukel und Sandkasten, Lieferzugang Ost."""
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 70)
    slab(m, 0, 0, W, H, grass_fn(seed))
    slab(m, 0, 0, W, 50, "paving")
    parts = [(8, 8, 44, 40, "yellow"), (44, 12, 80, 40, "red"), (80, 8, 120, 40, "blue")]
    for (x0, y0, x1, y1, acc) in parts:
        block(m, x0, y0, 1, x1, y1, 26, "plaster_white", base=acc, base_h=4)
        m.box(x0, y1, 22, x1, y1 + 1, 26, M(acc))
        for u in range(x0 + 4, x1 - 6, 10):
            window(m, "s", u, 7, y1, Win(7, 11, frame=acc, lit=0.5, cross=False), rng)
        flat_roof(m, x0, y0, x1, y1, 26, parapet=acc, tech=False)
    window(m, "e", 16, 7, 120, Win(8, 11, frame="blue", lit=0.5, cross=False), rng)
    door(m, "s", 56, 2, 40, w=8, h=14, mat_door="red")
    m.box(48, 40, 18, 76, 48, 19, M("yellow"))
    slab(m, 6, 52, 120, 92, grass_fn(seed + 1))
    m.box(10, 60, 0, 34, 80, 1, M("sand"))
    for (a, b, c, d) in ((10, 60, 34, 61), (10, 79, 34, 80), (10, 60, 11, 80), (33, 60, 34, 80)):
        m.box(a, b, 1, c, d, 3, M("wood"))
    m.put(16, 66, 1, M("red"))
    m.put(24, 72, 1, M("blue"))
    m.box(50, 60, 1, 58, 68, 14, M("blue"))
    m.box(50, 60, 14, 58, 68, 16, M("yellow"))
    for k in range(14):
        m.box(58 + k, 62, 14 - k, 59 + k, 66, 15 - k, M("red"))
    for px in (82, 100):
        m.box(px, 64, 1, px + 1, 65, 22, M("wood"))
        m.box(px, 72, 1, px + 1, 73, 22, M("wood"))
    m.box(82, 64, 22, 101, 73, 23, M("wood"))
    for sx in (87, 94):
        m.box(sx, 68, 8, sx + 1, 69, 22, M("rail"))
        m.box(sx - 1, 67, 7, sx + 3, 70, 8, M("red"))
    tree(m, 112, 80, 1, kind="round", size=0.9, rng=rng)
    bench(m, 40, 84, 1)
    fence(m, 4, 50, 122, 52, 1, h=7, mat_f="yellow")
    fence(m, 4, H - 2, 122, H, 1, h=7, mat_f="yellow")
    fence(m, 4, 50, 6, H, 1, h=7, mat_f="yellow")
    fence(m, 120, 50, 122, H, 1, h=7, mat_f="yellow")
    lamp_post(m, 44, 46, 1, h=14)
    return m, {"w": 4, "h": 3, "entrance": [60, H], "delivery": [W, 24], "height": 30}
