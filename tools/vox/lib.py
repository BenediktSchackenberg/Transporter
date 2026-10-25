"""Palette, Materialien und Bausteine fuer Voxelgebaeude, -grundstuecke und -objekte.
Sichtbar sind nur Sued- (+y) und Ostseite (+x); Details werden nur dort ausgearbeitet."""
import math
import random

from engine import Model, mat, M

# ------------------------------------------------------------------ Palette (ART_DIRECTION.md §4)
P = {
    # Boden
    "grass": "#5f9a3e", "grass2": "#6eab48", "grass3": "#54893a", "lawn": "#73b04c",
    "soil": "#7a5636", "gravel": "#b8ad98", "asphalt": "#4a4d55", "asphalt2": "#55585f",
    "paving": "#c9c0ae", "paving2": "#b9af9b", "sand": "#d9c38c", "curb": "#d4cfc4",
    "concrete": "#a3a29d", "concrete2": "#8f8e89", "deck": "#9c6b43", "deck2": "#8a5c38",
    # Mauern / Putz
    "plaster_cream": "#e8dcc0", "plaster_ochre": "#d9b77a", "plaster_rose": "#d9a594", "plaster_white": "#eeeae2",
    "plaster_grey": "#c9c7c1", "plaster_sage": "#b9c4a6", "sandstone": "#c99f6e", "sandstone2": "#b88d5e",
    "brick": "#a65a3e", "brick2": "#8f4b33", "timber": "#5b3b26", "stone_base": "#8d877c",
    # Daecher
    "tile_terra": "#b4553a", "tile_terra2": "#9b4630", "tile_red": "#9e3b32", "tile_red2": "#86312a",
    "slate": "#4c5563", "slate2": "#414955", "zinc": "#8a949e", "gravel_roof": "#8b8a86",
    # Glas / Metall
    "glass": "#5d86a8", "glass_dark": "#3e5d7a", "frame_white": "#f2f0ea", "frame_wood": "#6e4a2c",
    "frame_dark": "#3a3d44", "steel": "#8c949c", "steel_dark": "#5c636b", "rail": "#2f3238",
    # Pflanzen
    "leaf1": "#3f7a35", "leaf2": "#4f9140", "leaf3": "#66a64c", "leaf4": "#2f6330", "conifer": "#2c5a3a",
    "flower_r": "#d0463f", "flower_y": "#e6c547", "flower_p": "#c46fb5", "flower_w": "#f0ede0", "trunk": "#6b4a2f",
    # Sonstiges
    "water": "#4aa3c9", "water2": "#3a8db5", "red": "#c23b33", "yellow": "#e3b53c", "blue": "#3d6fb3",
    "green_acc": "#4c9a5a", "orange": "#e07a2a", "white": "#f2f0ea", "black": "#22242a", "wood": "#9b6a3e",
    "fabric_w": "#efe9dc", "fabric_r": "#c4493e", "fabric_b": "#4f7db8", "terracotta": "#b9673f",
}


def _m(name, **kw):
    return mat(name, P.get(name, kw.pop("rgb", "#ff00ff")), **kw)


def init_materials():
    for k in P:
        noise = 0.05
        if k.startswith(("grass", "lawn", "leaf", "soil", "gravel")):
            noise = 0.12
        if k.startswith(("glass", "water")):
            noise = 0.02
        top = not k.startswith(("glass", "water"))
        mat(k, P[k], noise=noise, top=top)
    # Leuchtende Fenster in Varianten (warm, hell, kuehl/Buero)
    # Tagsueber sehen beleuchtete Fenster wie Glas aus (leicht variiert); das Licht wirkt nur ueber die Emission.
    mat("glass_lit", "#6488a6", noise=0.03, emit="#ffcf6a", top=False)
    mat("glass_lit2", "#6d90ac", noise=0.03, emit="#ffe3a0", top=False)
    mat("glass_office", "#7398b6", noise=0.02, emit="#cfe6ff", top=False)
    mat("lamp", "#fff1c2", noise=0.0, emit="#ffe9a8", top=False)
    mat("lamp_red", "#ff5a4a", noise=0.0, emit="#ff4a3a", top=False)
    mat("lamp_blue", "#9fd6ff", noise=0.0, emit="#8ccfff", top=False)
    mat("neon_g", "#7dffb0", noise=0.0, emit="#62f59c", top=False)
    mat("comp", "#b8b8b8", noise=0.02, comp=True)          # Firmenfarbe (Maske)
    mat("comp_dark", "#8a8a8a", noise=0.02, comp=True)


# ------------------------------------------------------------------ Boden und Flaechen
def slab(m, x0, y0, x1, y1, fn_or_mat, z=0):
    if callable(fn_or_mat):
        for x in range(x0, x1):
            for y in range(y0, y1):
                mm = fn_or_mat(x, y)
                if mm:
                    m.put(x, y, z, mm)
    else:
        m.box(x0, y0, z, x1, y1, z + 1, M(fn_or_mat) if isinstance(fn_or_mat, str) else fn_or_mat)


def grass_fn(seed=0):
    r = random.Random(seed)
    cache = {}

    def f(x, y):
        k = (x // 2, y // 2)
        if k not in cache:
            v = r.random()
            cache[k] = M("grass") if v < 0.55 else (M("grass2") if v < 0.85 else M("grass3"))
        return cache[k]
    return f


def lawn_fn(seed=0):
    def f(x, y):
        return M("lawn") if ((x // 4) + (y // 4)) % 2 == 0 else M("grass2")   # Maehstreifen
    return f


def paving_fn(size=4, a="paving", b="paving2"):
    def f(x, y):
        bx, by = x // size, (y + (size // 2 if (x // size) % 2 else 0)) // size
        edge = (x % size == 0) or ((y + (size // 2 if (x // size) % 2 else 0)) % size == 0)
        return M(b) if edge else M(a)
    return f


def deck_fn():
    def f(x, y):
        return M("deck2") if y % 3 == 0 else M("deck")
    return f


# ------------------------------------------------------------------ Waende, Fenster, Tueren
class Win:
    """Fenster in einer sichtbaren Fassade. face: 's' (+y) oder 'e' (+x)."""

    def __init__(self, w=4, h=6, frame="frame_white", shutters=None, sill=True, cross=True, lit=0.5,
                 glass="glass", lit_mat="glass_lit", arch=False):
        self.w, self.h, self.frame, self.shutters, self.sill, self.cross = w, h, frame, shutters, sill, cross
        self.lit, self.glass, self.lit_mat, self.arch = lit, glass, lit_mat, arch


def window(m, face, u, z, plane, win, rng):
    """u = Position entlang der Fassade, z = Unterkante, plane = Koordinate der Fassadenflaeche (aussen)."""
    lit = rng.random() < win.lit
    g = M(win.lit_mat if lit else win.glass)
    fr = M(win.frame)

    def P3(a, b, c, mm):   # a entlang Fassade, b Tiefe (0 = Fassade, -1 = eingelassen, +1 = vorstehend), c Hoehe
        if face == "s":
            m.put(a, plane + b, c, mm)
        else:
            m.put(plane + b, a, c, mm)

    def clear3(a, b, c):
        P3(a, b, c, 0)

    for a in range(u, u + win.w):
        for c in range(z, z + win.h):
            if win.arch and c == z + win.h - 1 and a in (u, u + win.w - 1):
                continue
            P3(a, -1, c, 0)          # Laibung
            P3(a, -2, c, g)          # Glas eingelassen
    # Rahmen: aussen umlaufend auf der Fassadenebene -1
    for a in range(u - 1, u + win.w + 1):
        P3(a, -1, z - 1, fr)
        P3(a, -1, z + win.h, fr)
    for c in range(z - 1, z + win.h + 1):
        P3(u - 1, -1, c, fr)
        P3(u + win.w, -1, c, fr)
    if win.cross and win.w >= 4:
        mid = u + win.w // 2
        for c in range(z, z + win.h):
            P3(mid, -2, c, fr)
        if win.h >= 6:
            for a in range(u, u + win.w):
                P3(a, -2, z + win.h * 2 // 3, fr)
    if win.sill:
        for a in range(u - 1, u + win.w + 1):
            P3(a, 0, z - 1, M("stone_base"))
    if win.shutters:
        sm = M(win.shutters)
        for c in range(z, z + win.h):
            for k in range(2):
                P3(u - 3 + k, 0, c, sm if (c - z) % 2 == 0 else sm)
                P3(u + win.w + 1 + k, 0, c, sm)


def door(m, face, u, z, plane, w=4, h=9, mat_door="frame_wood", canopy=True, lamp=True, glass_top=True):
    def P3(a, b, c, mm):
        if face == "s":
            m.put(a, plane + b, c, mm)
        else:
            m.put(plane + b, a, c, mm)
    for a in range(u, u + w):
        for c in range(z, z + h):
            P3(a, -1, c, 0)
            P3(a, -2, c, M(mat_door) if not (glass_top and c >= z + h - 2) else M("glass_lit"))
    for c in range(z, z + h + 1):
        P3(u - 1, -1, c, M("frame_white"))
        P3(u + w, -1, c, M("frame_white"))
    for a in range(u - 1, u + w + 1):
        P3(a, -1, z + h, M("frame_white"))
    P3(u + w - 1, -2, z + h // 2, M("yellow"))        # Tuergriff
    if canopy:
        for a in range(u - 2, u + w + 2):
            for b in range(0, 4):
                P3(a, b, z + h + 2, M("slate"))
        for b in range(0, 4):
            P3(u - 2, b, z + h + 3, M("slate2"))
            P3(u + w + 1, b, z + h + 3, M("slate2"))
    if lamp:
        P3(u + w + 1, 0, z + h - 1, M("lamp"))
        P3(u + w + 1, 0, z + h - 2, M("frame_dark"))
    # Stufe
    for a in range(u - 1, u + w + 1):
        for b in range(0, 3):
            P3(a, b, z - 1 if z > 1 else 1, M("stone_base"))


def block(m, x0, y0, z0, x1, y1, z1, wall, base="stone_base", base_h=2, cornice=None):
    m.box(x0, y0, z0, x1, y1, z1, M(wall))
    if base:
        m.box(x0, y0, z0, x1, y1, z0 + base_h, M(base))
    if cornice:
        m.box(x0 - 1, y0 - 1, z1 - 1, x1 + 1, y1 + 1, z1, M(cornice))


def facade_windows(m, x0, y0, x1, y1, z0, floors, floor_h, win, rng, faces="se", spacing=8, margin=4, skip=None):
    """Fensterreihen auf Sued- und Ostfassade. skip(face, u, floor) -> True laesst eine Achse frei."""
    for f in range(floors):
        zz = z0 + f * floor_h + 4
        if "s" in faces:
            n = max(1, (x1 - x0 - 2 * margin + 2) // spacing)
            start = x0 + (x1 - x0 - (n * spacing - (spacing - win.w))) // 2
            for i in range(n):
                u = start + i * spacing
                if skip and skip("s", u, f):
                    continue
                window(m, "s", u, zz, y1, win, rng)
        if "e" in faces:
            n = max(1, (y1 - y0 - 2 * margin + 2) // spacing)
            start = y0 + (y1 - y0 - (n * spacing - (spacing - win.w))) // 2
            for i in range(n):
                u = start + i * spacing
                if skip and skip("e", u, f):
                    continue
                window(m, "e", u, zz, x1, win, rng)


# ------------------------------------------------------------------ Daecher
def gable_roof(m, x0, y0, x1, y1, z0, ridge="x", tile="tile_terra", tile2="tile_terra2", overhang=2, pitch=1.0,
               gutter=True, gable_wall=None):
    """Satteldach. ridge='x': First parallel zur x-Achse (Giebel an Ost/West)."""
    span = (y1 - y0) if ridge == "x" else (x1 - x0)
    half = span / 2.0
    hmax = int(math.ceil(half * pitch)) + 1
    t1, t2 = M(tile), M(tile2)
    for k in range(hmax + 1):
        inset = k / pitch
        z = z0 + k
        if ridge == "x":
            a0, a1 = y0 - overhang + inset, y1 + overhang - inset
            if a1 - a0 < 1:
                break
            for x in range(x0 - overhang, x1 + overhang):
                for y in range(int(math.floor(a0)), int(math.ceil(a1))):
                    edge = y < a0 + 1.0 / pitch + 1 or y >= a1 - 1.0 / pitch - 1
                    mm = t2 if (k % 2 == 0) else t1
                    if (x + k) % 6 == 0 and edge:
                        mm = t2
                    m.put(x, y, z, mm)
            if gable_wall:
                for y in range(int(math.floor(a0 + overhang)), int(math.ceil(a1 - overhang))):
                    m.put(x1 - 1, y, z, M(gable_wall))
        else:
            a0, a1 = x0 - overhang + inset, x1 + overhang - inset
            if a1 - a0 < 1:
                break
            for y in range(y0 - overhang, y1 + overhang):
                for x in range(int(math.floor(a0)), int(math.ceil(a1))):
                    mm = t2 if (k % 2 == 0) else t1
                    m.put(x, y, z, mm)
            if gable_wall:
                for x in range(int(math.floor(a0 + overhang)), int(math.ceil(a1 - overhang))):
                    m.put(x, y1 - 1, z, M(gable_wall))
    # Firstreihe
    if ridge == "x":
        yc = (y0 + y1) // 2
        m.box(x0 - overhang, yc - 1, z0 + hmax - 1, x1 + overhang, yc + 1, z0 + hmax + 1, M(tile2))
    else:
        xc = (x0 + x1) // 2
        m.box(xc - 1, y0 - overhang, z0 + hmax - 1, xc + 1, y1 + overhang, z0 + hmax + 1, M(tile2))
    if gutter:
        if ridge == "x":
            m.box(x0 - overhang, y1 + overhang - 1, z0 - 1, x1 + overhang, y1 + overhang, z0, M("zinc"))
        else:
            m.box(x1 + overhang - 1, y0 - overhang, z0 - 1, x1 + overhang, y1 + overhang, z0, M("zinc"))
    return z0 + hmax


def hip_roof(m, x0, y0, x1, y1, z0, tile="tile_terra", tile2="tile_terra2", overhang=2, pitch=0.8, gutter=True):
    k = 0
    while True:
        inset = k / pitch
        ax0, ax1 = x0 - overhang + inset, x1 + overhang - inset
        ay0, ay1 = y0 - overhang + inset, y1 + overhang - inset
        if ax1 - ax0 < 2 or ay1 - ay0 < 2:
            break
        mm = M(tile2) if k % 2 == 0 else M(tile)
        m.box(int(ax0), int(ay0), z0 + k, int(math.ceil(ax1)), int(math.ceil(ay1)), z0 + k + 1, mm)
        k += 1
    if gutter:
        m.box(x0 - overhang, y1 + overhang - 1, z0 - 1, x1 + overhang, y1 + overhang, z0, M("zinc"))
        m.box(x1 + overhang - 1, y0 - overhang, z0 - 1, x1 + overhang, y1 + overhang, z0, M("zinc"))
    return z0 + k


def flat_roof(m, x0, y0, x1, y1, z0, parapet="concrete", fill="gravel_roof", rng=None, tech=True, solar=False):
    m.box(x0, y0, z0, x1, y1, z0 + 1, M(fill))
    m.box(x0, y0, z0, x1, y0 + 1, z0 + 3, M(parapet))
    m.box(x0, y1 - 1, z0, x1, y1, z0 + 3, M(parapet))
    m.box(x0, y0, z0, x0 + 1, y1, z0 + 3, M(parapet))
    m.box(x1 - 1, y0, z0, x1, y1, z0 + 3, M(parapet))
    rng = rng or random.Random(1)
    if tech:
        for i in range(max(1, (x1 - x0) * (y1 - y0) // 500)):
            w, d = rng.randint(4, 8), rng.randint(4, 7)
            tx, ty = rng.randint(x0 + 3, max(x0 + 3, x1 - w - 3)), rng.randint(y0 + 3, max(y0 + 3, y1 - d - 3))
            m.box(tx, ty, z0 + 1, tx + w, ty + d, z0 + 5, M("steel"))
            m.box(tx + 1, ty + 1, z0 + 5, tx + w - 1, ty + d - 1, z0 + 6, M("steel_dark"))
    if solar:
        for sx in range(x0 + 4, x1 - 6, 7):
            for sy in range(y0 + 4, y1 - 5, 6):
                m.box(sx, sy, z0 + 2, sx + 6, sy + 4, z0 + 3, M("glass_dark"))
    return z0 + 3


def chimney(m, x, y, z0, h=8, mat_c="brick"):
    m.box(x, y, z0, x + 3, y + 3, z0 + h, M(mat_c))
    m.box(x - 1, y - 1, z0 + h, x + 4, y + 4, z0 + h + 1, M("stone_base"))


def dormer(m, x, y_face, z, w=6, h=6, face="s"):
    """Dachgaube auf der Suedseite."""
    if face == "s":
        m.box(x, y_face - 6, z, x + w, y_face, z + h, M("plaster_white"))
        m.box(x - 1, y_face - 7, z + h, x + w + 1, y_face + 1, z + h + 1, M("slate"))
        window(m, "s", x + 1, z + 1, y_face, Win(w - 2, h - 3, sill=False, cross=False), random.Random(x))


def balcony(m, face, u0, u1, z, plane, depth=5, rail="rail", floor="concrete", plants=True, rng=None):
    rng = rng or random.Random(u0)
    for a in range(u0, u1):
        for b in range(0, depth):
            if face == "s":
                m.put(a, plane + b, z, M(floor))
            else:
                m.put(plane + b, a, z, M(floor))
    for a in range(u0, u1):
        for c in (z + 1, z + 5):
            pass
    # Gelaender: Pfosten + Handlauf
    for a in range(u0, u1):
        for c in range(z + 1, z + 6):
            post = (a - u0) % 3 == 0 or c == z + 5
            if post:
                if face == "s":
                    m.put(a, plane + depth - 1, c, M(rail))
                else:
                    m.put(plane + depth - 1, a, c, M(rail))
    for b in range(0, depth):
        for c in range(z + 1, z + 6):
            if b % 3 == 0 or c == z + 5:
                if face == "s":
                    m.put(u1 - 1, plane + b, c, M(rail))
                else:
                    m.put(plane + b, u1 - 1, c, M(rail))
    if plants:
        for a in range(u0 + 1, u1 - 1, 5):
            if rng.random() < 0.7:
                pot = (a, depth - 2)
                col = rng.choice(["flower_r", "flower_p", "leaf2", "flower_y"])
                if face == "s":
                    m.put(a, plane + depth - 2, z + 1, M("terracotta"))
                    m.put(a, plane + depth - 2, z + 2, M(col))
                    m.put(a + 1, plane + depth - 2, z + 2, M("leaf2"))
                else:
                    m.put(plane + depth - 2, a, z + 1, M("terracotta"))
                    m.put(plane + depth - 2, a, z + 2, M(col))


# ------------------------------------------------------------------ Vegetation
def tree(m, x, y, z=1, kind="round", size=1.0, rng=None):
    rng = rng or random.Random(x * 31 + y)
    th = int(rng.randint(8, 12) * size)
    m.box(x, y, z, x + 2, y + 2, z + th, M("trunk"))
    if kind == "conifer":
        h = int(26 * size)
        for k in range(h):
            r = (h - k) * 0.33 + 1
            _disc(m, x + 1, y + 1, z + th - 3 + k, r, ["conifer", "leaf4"], rng)
        return
    r = rng.uniform(6, 8) * size
    cz = z + th + r * 0.6
    cols = ["leaf1", "leaf2", "leaf3", "leaf4"] if kind == "round" else ["leaf2", "leaf3", "flower_p", "leaf2"]
    for _ in range(4):
        ox, oy, oz = rng.uniform(-2.5, 2.5) * size, rng.uniform(-2.5, 2.5) * size, rng.uniform(-1.5, 2.5) * size
        _blob(m, x + 1 + ox, y + 1 + oy, cz + oz, r * rng.uniform(0.7, 0.95), cols, rng)


def _disc(m, cx, cy, z, r, cols, rng):
    for dx in range(int(-r) - 1, int(r) + 2):
        for dy in range(int(-r) - 1, int(r) + 2):
            if dx * dx + dy * dy <= r * r:
                m.put(int(cx + dx), int(cy + dy), int(z), M(cols[rng.randrange(len(cols))]))


def _blob(m, cx, cy, cz, r, cols, rng):
    ri = int(r) + 1
    for dx in range(-ri, ri + 1):
        for dy in range(-ri, ri + 1):
            for dz in range(-ri, ri + 1):
                d = (dx * dx + dy * dy + (dz * 1.25) ** 2) ** 0.5
                if d <= r - rng.random() * 1.2:
                    # obere/vordere Voxel heller (Licht), untere dunkler
                    c = cols[min(len(cols) - 1, max(0, int(rng.random() * 3 + (1 if dz > 1 else 0))))]
                    if dz < -r * 0.4:
                        c = cols[-1]
                    m.put(int(cx + dx), int(cy + dy), int(cz + dz), M(c))


def bush(m, x, y, z=1, r=3, flowers=None, rng=None):
    rng = rng or random.Random(x * 7 + y)
    _blob(m, x, y, z + r * 0.6, r, ["leaf2", "leaf3", "leaf1", "leaf4"], rng)
    if flowers:
        for _ in range(int(r * 3)):
            m.put(x + rng.randint(-r + 1, r - 1), y + rng.randint(-r + 1, r - 1), z + int(r * 1.1), M(flowers))


def hedge(m, x0, y0, x1, y1, z=1, h=5):
    rng = random.Random(x0 * 13 + y0)
    for x in range(x0, x1):
        for y in range(y0, y1):
            for zz in range(z, z + h + (1 if rng.random() < 0.3 else 0)):
                m.put(x, y, zz, M(rng.choice(["leaf1", "leaf4", "leaf1", "leaf2"])))


def flowerbed(m, x0, y0, x1, y1, z=1, rng=None):
    rng = rng or random.Random(x0 + y0 * 5)
    m.box(x0, y0, z - 1, x1, y1, z, M("soil"))
    for x in range(x0, x1):
        for y in range(y0, y1):
            if rng.random() < 0.55:
                m.put(x, y, z, M(rng.choice(["leaf2", "leaf3", "flower_r", "flower_y", "flower_p", "flower_w"])))


# ------------------------------------------------------------------ Kleinobjekte
def fence(m, x0, y0, x1, y1, z=1, h=5, mat_f="frame_white", posts=4):
    for x in range(x0, x1):
        for y in range(y0, y1):
            along = (x - x0) if (x1 - x0) > (y1 - y0) else (y - y0)
            if along % posts == 0:
                m.box(x, y, z, x + 1, y + 1, z + h + 1, M(mat_f))
            m.put(x, y, z + h - 1, M(mat_f))
            m.put(x, y, z + 2, M(mat_f))


def wall_fence(m, x0, y0, x1, y1, z=1, h=4, mat_w="sandstone", cap="stone_base"):
    m.box(x0, y0, z, x1, y1, z + h, M(mat_w))
    m.box(x0, y0, z + h, x1, y1, z + h + 1, M(cap))


def lamp_post(m, x, y, z=1, h=16, head="lamp"):
    """Laterne: Mast, Leuchtenkopf (3x3 leuchtend) mit Kappe."""
    m.box(x - 1, y - 1, z, x + 2, y + 2, z + 2, M("frame_dark"))
    m.box(x, y, z, x + 1, y + 1, z + h, M("frame_dark"))
    m.box(x - 1, y - 1, z + h, x + 2, y + 2, z + h + 2, M(head))
    m.box(x - 2, y - 2, z + h + 2, x + 3, y + 3, z + h + 3, M("frame_dark"))


def bin_(m, x, y, z=1, color="green_acc"):
    m.box(x, y, z, x + 3, y + 3, z + 5, M(color))
    m.box(x, y, z + 5, x + 3, y + 3, z + 6, M("black"))


def bike(m, x, y, z=1, color="red", face="x"):
    # zwei Raeder + Rahmen, entlang x
    if face == "x":
        for dx in (0, 5):
            for c in range(3):
                m.put(x + dx, y, z + c, M("black"))
            m.put(x + dx - 1, y, z + 1, M("black"))
            m.put(x + dx + 1, y, z + 1, M("black"))
        for dx in range(1, 5):
            m.put(x + dx, y, z + 2, M(color))
        m.put(x + 4, y, z + 3, M("black"))
        m.put(x + 1, y, z + 3, M(color))
    else:
        for dy in (0, 5):
            for c in range(3):
                m.put(x, y + dy, z + c, M("black"))
        for dy in range(1, 5):
            m.put(x, y + dy, z + 2, M(color))
        m.put(x, y + 4, z + 3, M("black"))


def mailbox(m, x, y, z=1, color="yellow"):
    m.box(x, y, z, x + 1, y + 1, z + 5, M("frame_dark"))
    m.box(x - 1, y - 1, z + 5, x + 2, y + 1, z + 8, M(color))


def bench(m, x, y, z=1, along="x", length=6):
    if along == "x":
        m.box(x, y, z + 2, x + length, y + 2, z + 3, M("wood"))
        m.box(x, y + 1, z + 3, x + length, y + 2, z + 5, M("wood"))
        m.box(x, y, z, x + 1, y + 2, z + 2, M("frame_dark"))
        m.box(x + length - 1, y, z, x + length, y + 2, z + 2, M("frame_dark"))
    else:
        m.box(x, y, z + 2, x + 2, y + length, z + 3, M("wood"))
        m.box(x + 1, y, z + 3, x + 2, y + length, z + 5, M("wood"))


def patio_set(m, x, y, z=1, umbrella="fabric_r"):
    m.box(x + 2, y + 2, z, x + 3, y + 3, z + 3, M("frame_dark"))
    m.box(x, y, z + 3, x + 5, y + 5, z + 4, M("white"))
    for cx, cy in ((x - 2, y + 1), (x + 6, y + 1), (x + 1, y + 6)):
        m.box(cx, cy, z, cx + 2, cy + 2, z + 2, M("wood"))
        m.box(cx, cy, z + 2, cx + 2, cy + 1, z + 4, M("wood"))
    if umbrella:
        m.box(x + 2, y + 2, z + 4, x + 3, y + 3, z + 11, M("white"))
        for r in range(5):
            _disc(m, x + 2.5, y + 2.5, z + 11 - r // 2, 5 - r, [umbrella], random.Random(1))


def lounger(m, x, y, z=1):
    m.box(x, y, z + 1, x + 3, y + 7, z + 2, M("fabric_w"))
    m.box(x, y, z + 2, x + 3, y + 2, z + 4, M("fabric_w"))
    m.box(x, y, z, x + 3, y + 7, z + 1, M("frame_dark"))


def car(m, x, y, z=1, color="blue", along="x"):
    L, W = 28, 13
    if along == "x":
        m.box(x, y, z + 1, x + L, y + W, z + 6, M(color))
        m.box(x + 7, y + 1, z + 6, x + L - 7, y + W - 1, z + 11, M(color))
        m.box(x + 8, y + 1, z + 6, x + L - 8, y + W - 1, z + 10, M("glass_dark"))
        m.box(x + 9, y + 2, z + 10, x + L - 9, y + W - 2, z + 11, M(color))
        for wx in (x + 4, x + L - 8):
            m.box(wx, y - 0, z, wx + 4, y + 1, z + 3, M("black"))
            m.box(wx, y + W - 1, z, wx + 4, y + W, z + 3, M("black"))
        m.box(x + L - 1, y + 2, z + 3, x + L, y + 4, z + 5, M("lamp"))
        m.box(x + L - 1, y + W - 4, z + 3, x + L, y + W - 2, z + 5, M("lamp"))
    else:
        m.box(x, y, z + 1, x + W, y + L, z + 6, M(color))
        m.box(x + 1, y + 7, z + 6, x + W - 1, y + L - 7, z + 11, M(color))
        m.box(x + 1, y + 8, z + 6, x + W - 1, y + L - 8, z + 10, M("glass_dark"))
        m.box(x + 2, y + 9, z + 10, x + W - 2, y + L - 9, z + 11, M(color))
        for wy in (y + 4, y + L - 8):
            m.box(x, wy, z, x + 1, wy + 4, z + 3, M("black"))
            m.box(x + W - 1, wy, z, x + W, wy + 4, z + 3, M("black"))
        m.box(x + 2, y + L - 1, z + 3, x + 4, y + L, z + 5, M("lamp"))
        m.box(x + W - 4, y + L - 1, z + 3, x + W - 2, y + L, z + 5, M("lamp"))


def pallet_stack(m, x, y, z=1, h=2, goods="wood"):
    for k in range(h):
        m.box(x, y, z + k * 6, x + 8, y + 8, z + k * 6 + 1, M("wood"))
        m.box(x + 1, y + 1, z + k * 6 + 1, x + 7, y + 7, z + k * 6 + 6, M(goods))


def container(m, x, y, z=1, color="red", along="x"):
    L, W, H = 40, 16, 17
    if along == "x":
        m.box(x, y, z, x + L, y + W, z + H, M(color))
        for xx in range(x, x + L, 3):
            m.box(xx, y + W - 1, z + 1, xx + 1, y + W, z + H - 1, M("black"))
    else:
        m.box(x, y, z, x + W, y + L, z + H, M(color))
        for yy in range(y, y + L, 3):
            m.box(x + W - 1, yy, z + 1, x + W, yy + 1, z + H - 1, M("black"))
