"""Fleischkette (Auftrag 21 Teil 2, docs/HIGHWAY.md): Schweinemast, Rindermast, Schlachthof, Metzgerei.

Je Gebaeudetyp vier strukturell verschiedene Varianten (Anordnung von Stall, Silos, Auslauf/Weide, Kuehlhaus, Laden). Die Tiere stehen
als Voxel im Bild (Ruhebild); die Bewegung auf Weide und im Auslauf zeichnet zusaetzlich die Kartenleben-Ebene (ambient_view).
Sichtbar sind Sued- (+y) und Ostseite (+x). Boden z = 0, Gebaeude ab z = 1. Sprite-Namen: <typ>_<v>, z. B. pig_farm_2."""
import random

from engine import Model, mat, M
from lib import (Win, window, door, block, gable_roof, flat_roof, slab, grass_fn, paving_fn, fence, tree, bush, lamp_post, bin_)

T = 32
VARIANTS = 4


def init():
    mat("pig", "#e9a9a1", noise=0.04)
    mat("pig2", "#d98f88", noise=0.04)
    mat("cow_w", "#f1f0ea", noise=0.03)
    mat("cow_b", "#2b2a2c", noise=0.03)
    mat("cow_br", "#7a4b2c", noise=0.05)
    mat("mud", "#6a4c33", noise=0.08)
    mat("straw", "#d8bd6a", noise=0.08)
    mat("silage", "#5d6b39", noise=0.08)
    mat("panel_w", "#e8ecef", noise=0.02)
    mat("panel_b", "#4f7fa8", noise=0.02)
    mat("awning_r", "#c0392b", noise=0.02)
    mat("awning_w", "#f4f1ea", noise=0.02)
    mat("shopglass", "#9cc6d9", noise=0.02)
    mat("meat", "#b5453c", noise=0.05)


# ------------------------------------------------------------------ Bausteine
def pig(m, x, y, face=0):
    """Mastschwein (7x4 Voxel): Koerper, Kopf mit Ruessel, Ohren."""
    if face == 0:
        m.box(x, y, 1, x + 6, y + 4, 4, M("pig"))
        m.box(x + 6, y + 1, 2, x + 8, y + 3, 4, M("pig2"))
        m.box(x + 8, y + 1, 2, x + 9, y + 3, 3, M("pig2"))
        m.box(x + 5, y, 4, x + 6, y + 1, 5, M("pig2"))
    else:
        m.box(x, y, 1, x + 4, y + 6, 4, M("pig"))
        m.box(x + 1, y + 6, 2, x + 3, y + 8, 4, M("pig2"))
        m.box(x + 1, y + 8, 2, x + 3, y + 9, 3, M("pig2"))


def cow(m, x, y, kind=0):
    """Rind (12x5 Voxel): Holstein schwarz-weiss oder braun, Kopf, Beine."""
    body = "cow_w" if kind != 2 else "cow_br"
    m.box(x, y, 4, x + 10, y + 5, 10, M(body))
    if kind == 0:   # Flecken
        m.box(x + 2, y, 6, x + 5, y + 5, 10, M("cow_b"))
        m.box(x + 7, y, 4, x + 9, y + 5, 7, M("cow_b"))
    m.box(x + 10, y + 1, 7, x + 13, y + 4, 11, M("cow_b" if kind == 0 else body))
    for lx in (x + 1, x + 8):
        for ly in (y, y + 4):
            m.box(lx, ly, 1, lx + 1, ly + 1, 4, M("cow_b"))


def silo(m, cx, cy, r, h, mat_s="zinc", cap="tile_red"):
    for z in range(1, h):
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r:
                    m.put(cx + dx, cy + dy, z, M(mat_s if (z // 4) % 2 == 0 else "steel"))
    for z in range(h, h + r):
        rr = r - (z - h)
        for dx in range(-rr, rr + 1):
            for dy in range(-rr, rr + 1):
                if dx * dx + dy * dy <= rr * rr:
                    m.put(cx + dx, cy + dy, z, M(cap))


def tank(m, cx, cy, r, h, mat_t="concrete"):
    """Guellebehaelter bzw. Wassertank: flacher Rundbehaelter."""
    for z in range(1, h):
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                d = dx * dx + dy * dy
                if d <= r * r and (d >= (r - 1) * (r - 1) or z == 1):
                    m.put(cx + dx, cy + dy, z, M(mat_t))
    for dx in range(-r + 1, r):
        for dy in range(-r + 1, r):
            if dx * dx + dy * dy < (r - 1) * (r - 1):
                m.put(cx + dx, cy + dy, h - 2, M("mud"))


def bale(m, x, y, round_=True):
    if round_:
        for z in range(1, 6):
            for dx in range(-3, 4):
                for dy in range(-3, 4):
                    if dx * dx + dy * dy <= 9:
                        m.put(x + dx, y + dy, z, M("straw"))
    else:
        m.box(x, y, 1, x + 7, y + 4, 5, M("straw"))


def barn(m, x0, y0, x1, y1, h, wall="plaster_white", roof="tile_red", ridge="x", vents=0, rng=None, doors=1):
    """Stall: niedriger Langbau mit Lichtband und Lueftern auf dem Dach."""
    block(m, x0, y0, 1, x1, y1, h, wall, base="concrete", base_h=3)
    for u in range(x0 + 3, x1 - 3, 5):   # Lichtband
        m.box(u, y1 - 1, h - 6, u + 3, y1, h - 3, M("glass_dark"))
    if ridge == "x":
        gable_roof(m, x0, y0, x1, y1, h, ridge="x", tile=roof, tile2=roof + "2" if roof in ("tile_red", "tile_terra") else roof, pitch=0.6)
    else:
        gable_roof(m, x0, y0, x1, y1, h, ridge="y", tile=roof, tile2=roof + "2" if roof in ("tile_red", "tile_terra") else roof, pitch=0.6)
    for i in range(vents):
        vx = x0 + 6 + i * ((x1 - x0 - 12) // max(1, vents - 1) if vents > 1 else 0)
        m.box(vx, (y0 + y1) // 2 - 1, h + 7, vx + 3, (y0 + y1) // 2 + 2, h + 12, M("steel"))
        m.box(vx - 1, (y0 + y1) // 2 - 2, h + 12, vx + 4, (y0 + y1) // 2 + 3, h + 13, M("steel_dark"))
    for d in range(doors):
        u = x0 + 4 + d * 14
        m.box(u, y1 - 1, 1, u + 8, y1, 12, M("frame_wood"))


def paddock(m, x0, y0, x1, y1, ground="mud"):
    slab(m, x0, y0, x1, y1, lambda x, y: M(ground) if (x * 7 + y * 3) % 5 else M("soil"))
    fence(m, x0, y0, x1, y0 + 1, 1, 4, "frame_wood", posts=6)
    fence(m, x0, y1 - 1, x1, y1, 1, 4, "frame_wood", posts=6)
    fence(m, x0, y0, x0 + 1, y1, 1, 4, "frame_wood", posts=6)
    fence(m, x1 - 1, y0, x1, y1, 1, 4, "frame_wood", posts=6)


# ------------------------------------------------------------------ Schweinemast 4x3
def pig_farm(v, seed):
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 70)
    slab(m, 0, 0, W, H, grass_fn(seed))
    slab(m, 0, H - 14, W, H, paving_fn(6, "gravel", "concrete2"))
    if v == 0:      # zwei parallele Maststaelle, Silos rechts, Guellebehaelter hinten
        barn(m, 4, 4, 84, 26, 16, vents=4, rng=rng)
        barn(m, 4, 32, 84, 54, 16, vents=4, rng=rng)
        silo(m, 96, 18, 5, 34)
        silo(m, 110, 18, 5, 34)
        tank(m, 104, 46, 10, 7)
        paddock(m, 4, 60, 60, 80)
        for i, (px, py) in enumerate(((10, 64), (24, 70), (40, 66), (48, 72))):
            pig(m, px, py, i % 2)
    elif v == 1:    # L-Stall um den Auslauf, Futterkueche mit Silo
        barn(m, 4, 4, 120, 24, 16, vents=6, rng=rng, ridge="x")
        barn(m, 96, 24, 120, 70, 16, vents=2, rng=rng, ridge="y")
        paddock(m, 8, 30, 90, 70)
        for i, (px, py) in enumerate(((14, 36), (30, 44), (48, 38), (60, 56), (74, 46), (22, 60))):
            pig(m, px, py, i % 2)
        silo(m, 16, 82, 6, 30, cap="zinc")
    elif v == 2:    # Offenfrontstall mit Strohauslauf, Strohlager, Silo-Reihe
        barn(m, 30, 6, 124, 36, 18, wall="timber", roof="zinc", vents=3, rng=rng)
        paddock(m, 30, 40, 124, 72, ground="straw")
        for i, (px, py) in enumerate(((40, 46), (58, 54), (76, 48), (96, 60), (108, 50))):
            pig(m, px, py, i % 2)
        for k in range(3):
            silo(m, 10, 12 + k * 16, 5, 28)
        for bx in (10, 20):
            bale(m, bx, 66, round_=False)
    else:           # kompakter Stall mit Abluftwaescher, Guellerundbehaelter vorn, Verladerampe
        barn(m, 6, 6, 92, 40, 18, wall="plaster_white", roof="tile_terra", vents=5, rng=rng, doors=2)
        m.box(94, 10, 1, 120, 30, 22, M("concrete2"))   # Abluftwaescher
        m.box(98, 14, 22, 116, 26, 26, M("steel"))
        tank(m, 30, 60, 12, 8)
        m.box(70, 46, 1, 92, 60, 4, M("concrete"))   # Verladerampe
        silo(m, 108, 54, 6, 30)
        paddock(m, 50, 62, 92, 80)
        pig(m, 58, 66)
        pig(m, 74, 70, 1)
    lamp_post(m, 2, H - 3, 1, h=14)
    return m, {"w": 4, "h": 3, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 50}


# ------------------------------------------------------------------ Rindermast 4x4
def cattle_farm(v, seed):
    rng = random.Random(seed)
    W = H = 4 * T
    m = Model(W, H, 80)
    slab(m, 0, 0, W, H, grass_fn(seed))
    if v == 0:      # Laufstall hinten, grosse Weide vorn, Fahrsilo rechts
        barn(m, 4, 4, 90, 40, 20, wall="timber", roof="zinc", vents=0, rng=rng)
        m.box(96, 8, 1, 124, 40, 5, M("concrete"))   # Fahrsilo mit Plane
        m.box(98, 10, 5, 122, 38, 8, M("silage"))
        paddock(m, 4, 48, 124, 124, ground="grass_dark" if False else "soil")
        slab(m, 6, 50, 122, 122, grass_fn(seed + 3))
        for i, (cx, cy) in enumerate(((14, 60), (40, 70), (70, 62), (92, 84), (30, 96), (60, 104))):
            cow(m, cx, cy, i % 3)
        tank(m, 108, 110, 5, 4, mat_t="steel")   # Traenke
    elif v == 1:    # Winkelstall, Weide links, Heuballenlager
        barn(m, 4, 4, 124, 30, 20, wall="plaster_white", roof="tile_red", vents=0, rng=rng)
        barn(m, 96, 30, 124, 90, 20, wall="plaster_white", roof="tile_red", ridge="y", rng=rng)
        paddock(m, 4, 36, 90, 124, ground="soil")
        slab(m, 6, 38, 88, 122, grass_fn(seed + 5))
        for i, (cx, cy) in enumerate(((12, 48), (40, 56), (60, 78), (20, 92), (52, 106))):
            cow(m, cx, cy, i % 3)
        for bx, by in ((104, 100), (114, 100), (104, 112), (114, 112)):
            bale(m, bx, by)
    elif v == 2:    # Offenstall mit Futtertisch, Silos, Weide mit Baumgruppe
        m.box(4, 4, 1, 70, 44, 2, M("concrete"))
        for px in (4, 26, 48, 68):   # Pfosten des Offenstalls
            for py in (4, 42):
                m.box(px, py, 1, px + 2, py + 2, 18, M("timber"))
        gable_roof(m, 4, 4, 70, 44, 18, ridge="x", tile="zinc", tile2="zinc", pitch=0.5)
        for i, (cx, cy) in enumerate(((10, 14), (30, 26), (50, 12))):
            cow(m, cx, cy, i % 3)
        silo(m, 90, 14, 7, 40)
        silo(m, 110, 14, 6, 34)
        paddock(m, 4, 52, 124, 124, ground="soil")
        slab(m, 6, 54, 122, 122, grass_fn(seed + 7))
        tree(m, 100, 96, 1, kind="round", size=1.1, rng=rng)
        for i, (cx, cy) in enumerate(((16, 64), (46, 80), (74, 66), (30, 104))):
            cow(m, cx, cy, (i + 1) % 3)
    else:           # Hof mit Wohnhaus, kleiner Stall, Weide hinten
        block(m, 90, 70, 1, 122, 100, 22, "plaster_ochre", base="stone_base", base_h=3)
        gable_roof(m, 90, 70, 122, 100, 22, ridge="y", tile="tile_red", tile2="tile_red2", pitch=1.0)
        door(m, "s", 102, 2, 100, w=5, h=11, canopy=True)
        barn(m, 6, 70, 80, 100, 18, wall="timber", roof="tile_terra", rng=rng, doors=2)
        paddock(m, 4, 4, 124, 62, ground="soil")
        slab(m, 6, 6, 122, 60, grass_fn(seed + 9))
        for i, (cx, cy) in enumerate(((12, 12), (40, 20), (70, 14), (96, 34), (24, 44))):
            cow(m, cx, cy, i % 3)
        bale(m, 20, 110)
        bale(m, 30, 112)
    lamp_post(m, 2, H - 3, 1, h=14)
    return m, {"w": 4, "h": 4, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 56}


# ------------------------------------------------------------------ Schlachthof 4x3
def slaughterhouse(v, seed):
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 80)
    slab(m, 0, 0, W, H, paving_fn(6, "concrete2", "concrete"))

    def coldstore(x0, y0, x1, y1, h):
        block(m, x0, y0, 1, x1, y1, h, "panel_w", base="concrete", base_h=2)
        for u in range(x0, x1, 6):
            m.box(u, y1 - 1, 2, u + 1, y1, h, M("panel_b"))
        flat_roof(m, x0, y0, x1, y1, h, parapet="panel_b", rng=rng, tech=False)
        for i in range(2):   # Kaelteaggregate auf dem Dach
            m.box(x0 + 4 + i * 10, y0 + 4, h + 1, x0 + 12 + i * 10, y0 + 10, h + 6, M("steel"))
            m.box(x0 + 6 + i * 10, y0 + 6, h + 6, x0 + 10 + i * 10, y0 + 8, h + 7, M("steel_dark"))

    def cattle_ramp(x0, y0, x1, y1):
        m.box(x0, y0, 1, x1, y1, 4, M("concrete"))
        fence(m, x0, y0, x1, y0 + 1, 4, 5, "steel", posts=5)
        fence(m, x0, y1 - 1, x1, y1, 4, 5, "steel", posts=5)

    def reefer_dock(x0, y, n):
        for i in range(n):
            m.box(x0 + i * 16, y - 1, 1, x0 + i * 16 + 12, y, 14, M("steel_dark"))
            m.box(x0 + i * 16 - 1, y - 2, 14, x0 + i * 16 + 13, y + 2, 15, M("steel"))

    if v == 0:      # Schlachthalle links, Kuehlhaus rechts, Viehrampe hinten, Kuehl-Lkw-Rampen vorn
        block(m, 4, 8, 1, 64, 64, 26, "plaster_white", base="concrete", base_h=3)
        gable_roof(m, 4, 8, 64, 64, 26, ridge="x", tile="zinc", tile2="zinc", pitch=0.4)
        coldstore(66, 20, 124, 64, 24)
        cattle_ramp(10, 66, 40, 80)
        reefer_dock(70, 64, 3)
        m.box(50, 12, 26, 56, 18, 48, M("brick"))   # Schornstein
    elif v == 1:    # Kompaktbau, Kuehlhaus obenauf, Wartestall mit Treibgang
        coldstore(4, 4, 90, 50, 20)
        block(m, 92, 4, 1, 124, 50, 14, "timber", base="concrete", base_h=2)
        gable_roof(m, 92, 4, 124, 50, 14, ridge="y", tile="tile_red", tile2="tile_red2", pitch=0.6)
        cattle_ramp(96, 52, 124, 70)
        reefer_dock(10, 50, 4)
        m.box(70, 30, 20, 76, 36, 40, M("brick"))
    elif v == 2:    # Zwei Hallen (Schwein, Rind) mit Verbindungsgang, Kuehlhaus dazwischen
        block(m, 4, 6, 1, 44, 60, 22, "plaster_white", base="concrete", base_h=3)
        gable_roof(m, 4, 6, 44, 60, 22, ridge="y", tile="zinc", tile2="zinc", pitch=0.5)
        coldstore(46, 14, 84, 60, 26)
        block(m, 86, 6, 1, 124, 60, 22, "plaster_white", base="concrete", base_h=3)
        gable_roof(m, 86, 6, 124, 60, 22, ridge="y", tile="zinc", tile2="zinc", pitch=0.5)
        cattle_ramp(4, 64, 40, 80)
        cattle_ramp(88, 64, 124, 80)
        reefer_dock(52, 60, 2)
    else:           # Halle mit Sheddach, Kuehlhaus als Turm, Kuehltransporter-Hof
        block(m, 4, 4, 1, 84, 48, 22, "concrete2", base="concrete", base_h=2)
        for sx in range(4, 84, 12):
            m.box(sx, 4, 22, sx + 12, 48, 24, M("zinc"))
            m.box(sx + 9, 4, 24, sx + 12, 48, 30, M("glass_dark"))
        coldstore(88, 4, 124, 40, 40)
        cattle_ramp(20, 50, 60, 66)
        reefer_dock(90, 40, 2)
        car(m, 70, 70, 1, color="white") if False else None
    for bx in (4, 116):
        bin_(m, bx, H - 6, 1, color="red_acc" if False else "green_acc")
    lamp_post(m, 2, H - 3, 1, h=16)
    return m, {"w": 4, "h": 3, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 60, "smoke": [52, 14, 48]}


# ------------------------------------------------------------------ Metzgerei 2x2
def butcher(v, seed):
    rng = random.Random(seed)
    W = H = 2 * T
    m = Model(W, H, 70)
    slab(m, 0, 0, W, H, paving_fn(4, "paving", "paving2"))
    walls = ["plaster_white", "brick", "plaster_ochre", "timber"][v]
    floors = 2 if v != 2 else 3
    block(m, 6, 6, 1, 58, 46, floors * 11 + 1, walls, base="stone_base", base_h=3)
    # Schaufenster mit Kuehltheke und Fleischauslage
    m.box(12, 45, 3, 44, 46, 11, M("shopglass"))
    m.box(14, 44, 3, 42, 45, 6, M("panel_w"))
    for u in range(15, 41, 4):
        m.box(u, 44, 6, u + 2, 45, 7, M("meat"))
    door(m, "s", 46, 2, 46, w=6, h=10, canopy=False)
    # Markise rot-weiss gestreift
    for u in range(8, 56):
        m.box(u, 46, 12, u + 1, 52, 13, M("awning_r" if (u // 3) % 2 == 0 else "awning_w"))
    # Schild (Schweinekopf-Silhouette)
    m.box(22, 45, 15, 40, 46, 20, M("awning_w"))
    m.box(27, 45, 16, 33, 46, 19, M("pig"))
    m.box(33, 45, 17, 35, 46, 18, M("pig2"))
    for fl in range(1, floors):
        for u in (12, 26, 40):
            window(m, "s", u, 1 + fl * 11 + 3, 46, Win(5, 6, frame="frame_white", lit=0.5), rng)
    roof_kind = ["gable_x", "gable_y", "flat", "gable_x"][v]
    zt = floors * 11 + 1
    if roof_kind == "flat":
        flat_roof(m, 6, 6, 58, 46, zt, rng=rng)
    else:
        gable_roof(m, 6, 6, 58, 46, zt, ridge="x" if roof_kind == "gable_x" else "y", tile="tile_red" if v != 3 else "tile_terra",
                   tile2="tile_red2" if v != 3 else "tile_terra2", pitch=0.9)
    # Verkaufsstand draussen (Grill/Wurststand) bei zwei Varianten
    if v in (1, 3):
        m.box(48, 54, 1, 60, 60, 7, M("frame_wood"))
        m.box(48, 54, 7, 60, 60, 8, M("meat"))
        m.box(47, 53, 12, 61, 61, 13, M("awning_r"))
    lamp_post(m, 2, H - 3, 1, h=14)
    return m, {"w": 2, "h": 2, "entrance": [46, H], "delivery": [20, H], "height": 46}


BUILDERS = {"pig_farm": pig_farm, "cattle_farm": cattle_farm, "slaughterhouse": slaughterhouse, "butcher": butcher}


def specs():
    s = {}
    for bt, fn in BUILDERS.items():
        for v in range(VARIANTS):
            s["%s_%d" % (bt, v)] = (lambda fn=fn, v=v, sd=31 + 13 * v: fn(v, sd))
    return s
