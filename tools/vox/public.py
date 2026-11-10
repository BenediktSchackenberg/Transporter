"""Baukasten fuer kommunale Gebaeude (Auftrag 20, Etappe 2, docs/PUBLIC_SERVICES.md).

Je Typ sechs strukturell verschiedene Grundvarianten (Anordnung von Halle, Verwaltungs-/Stationsbau, Turm, Unterstand, Hof), jede in
vier Stadtstilen (Backstein, modern, gruen/Holz, Industrie). Der Stil waehlt Wandmaterial, Dachform, Fensterart und Gruen; die
Grundvariante die Gebaeudeform. Sprite-Name: pub_<typ>_<variante>_<stil>, z. B. pub_fw_3_backstein.
Sichtbar sind Sued- (+y) und Ostseite (+x): Tore, Eingaenge und Kennzeichen liegen dort. Boden z = 0, Gebaeude ab z = 1."""
import random

from engine import Model, mat, M
from lib import (Win, window, door, block, facade_windows, gable_roof, flat_roof, slab, paving_fn, grass_fn, tree, bush, hedge,
                 fence, lamp_post, bench, car, bin_, bike)

T = 32
STYLES = ["backstein", "modern", "gruen", "industrie"]
VARIANTS = 6

# Gebaeudetyp im Spiel -> (Kuerzel, Breite, Tiefe in Feldern)
TYPES = {
    "fire_station": ("fw", 4, 3),
    "rescue_station": ("rw", 3, 2),
    "hospital": ("kh", 5, 4),
    "municipal_yard": ("bh", 4, 3),
    "bus_depot": ("vb", 5, 3),
    "public_school": ("sc", 6, 4),
    "public_kita": ("ki", 4, 3),
    "recycling_yard": ("rc", 4, 3),
}

ST = {
    "backstein": {"wall": "brick", "wall2": "brick2", "base": "sandstone2", "trim": "sandstone", "roof": "gable", "hall": "gable",
                  "tile": "tile_terra", "tile2": "tile_terra2", "frame": "frame_white", "glass": "glass", "ground": "paving",
                  "win": "classic"},
    "modern": {"wall": "plaster_white", "wall2": "plaster_grey", "base": "concrete", "trim": "concrete2", "roof": "flat", "hall": "flat",
               "tile": "slate", "tile2": "slate2", "frame": "frame_dark", "glass": "glass_office", "ground": "concrete",
               "win": "band"},
    "gruen": {"wall": "pub_larch", "wall2": "pub_larch2", "base": "stone_base", "trim": "timber", "roof": "green", "hall": "green",
              "tile": "slate", "tile2": "slate2", "frame": "frame_wood", "glass": "glass", "ground": "gravel", "win": "tall"},
    "industrie": {"wall": "pub_clad", "wall2": "zinc", "base": "concrete2", "trim": "steel_dark", "roof": "flat", "hall": "saw",
                  "tile": "zinc", "tile2": "steel", "frame": "frame_dark", "glass": "glass_dark", "ground": "asphalt2",
                  "win": "band"},
}


RIB = {"pub_red": "pub_red2", "pub_door_w": "pub_white", "pub_orange": "pub_orange2", "pub_yellow": "pub_yellow2", "pub_green": "pub_green2"}


def init():
    mat("pub_red", "#c0392f", noise=0.04)
    mat("pub_red2", "#a32e26", noise=0.04)
    mat("pub_orange", "#e07a2a", noise=0.04)
    mat("pub_orange2", "#c4661f", noise=0.04)
    mat("pub_yellow2", "#c99c2c", noise=0.04)
    mat("pub_green2", "#3f8550", noise=0.04)
    mat("pub_yellow", "#e3b53c", noise=0.04)
    mat("pub_green", "#4c9a5a", noise=0.04)
    mat("pub_white", "#f3f1ec", noise=0.02)
    mat("pub_larch", "#b9844f", noise=0.07)
    mat("pub_larch2", "#a37244", noise=0.07)
    mat("pub_clad", "#9aa3ab", noise=0.03)
    mat("pub_salt", "#e9e6df", noise=0.05)
    mat("pub_blue", "#4a8cff", noise=0.0, emit="#5aa0ff")
    mat("pub_door_w", "#d8d5ce", noise=0.02)
    mat("pub_heli", "#3d4a3f", noise=0.03)


# ------------------------------------------------------------------ Bausteine
def _win(st):
    k = ST[st]
    if k["win"] == "band":
        return Win(7, 6, frame=k["frame"], glass=k["glass"], cross=False, sill=False, lit=0.4, lit_mat="glass_office")
    if k["win"] == "tall":
        return Win(4, 9, frame=k["frame"], glass=k["glass"], cross=False, lit=0.45)
    return Win(4, 7, frame=k["frame"], glass=k["glass"], cross=True, lit=0.45)


def roof(m, st, x0, y0, x1, y1, z, kind, rng, ridge=None):
    """Dach nach Stil: gable (Satteldach), flat (Flachdach), green (begruent mit Solarfeld), saw (Sheddach)."""
    k = ST[st]
    if kind == "gable":
        ridge = ridge or ("x" if x1 - x0 >= y1 - y0 else "y")
        return gable_roof(m, x0, y0, x1, y1, z, ridge=ridge, tile=k["tile"], tile2=k["tile2"], pitch=0.6, overhang=1)
    if kind == "green":
        top = flat_roof(m, x0, y0, x1, y1, z, parapet="timber", fill="lawn", tech=False)
        for sx in range(x0 + 4, x1 - 8, 12):
            m.box(sx, y0 + 3, z + 1, sx + 7, y0 + 7, z + 2, M("glass_dark"))
        return top
    if kind == "saw":
        m.box(x0, y0, z, x1, y1, z + 1, M("zinc"))
        step = 10
        for sy in range(y0, y1 - 2, step):
            for i in range(step):
                if sy + i >= y1:
                    break
                h = (i * 6) // step
                m.box(x0, sy + i, z + 1, x1, sy + i + 1, z + 1 + h, M("zinc" if i < step - 1 else "steel"))
            m.box(x0, min(y1, sy + step) - 1, z + 1, x1, min(y1, sy + step), z + 7, M("glass_dark"))
        return z + 7
    return flat_roof(m, x0, y0, x1, y1, z, parapet=k["trim"], rng=rng, tech=True)


def house(m, st, x0, y0, x1, y1, floors, rng, roof_kind=None, fh=11, entrance=True, z0=1):
    """Mehrgeschossiger Bau (Verwaltung, Station, Klassen). Fenster auf Sued-/Ostseite, Eingang mittig Sued; z0 > 1 = Aufbau."""
    k = ST[st]
    z1 = z0 + floors * fh
    block(m, x0, y0, z0, x1, y1, z1, k["wall"], base=k["base"] if z0 == 1 else None, base_h=3)
    w = _win(st)
    entrance = entrance and z0 == 1
    facade_windows(m, x0, y0, x1, y1, z0, floors, fh, w, rng, spacing=w.w + 4, margin=3,
                   skip=(lambda f, u, fl: entrance and f == "s" and fl == 0 and abs(u - (x0 + x1) // 2) < 6))
    if k["win"] == "classic":
        for fl in range(1, floors):
            m.box(x0, y1 - 1, z0 + fl * fh, x1, y1, z0 + 1 + fl * fh, M(k["trim"]))
    if entrance:
        door(m, "s", (x0 + x1) // 2 - 3, 2, y1, w=6, h=9, mat_door=k["frame"])
    return roof(m, st, x0, y0, x1, y1, z1, roof_kind or k["roof"], rng)


def hall(m, st, x0, y0, x1, y1, h, doors, door_mat, rng, roof_kind=None, band=None, door_w=14):
    """Fahrzeughalle mit Sektionaltoren auf der Suedseite; band = Kennfarbe als Streifen unter der Traufe."""
    k = ST[st]
    block(m, x0, y0, 1, x1, y1, h, k["wall2"] if st == "industrie" else k["wall"], base=k["base"], base_h=2)
    if doors > 0:
        gap = (x1 - x0 - doors * door_w) // (doors + 1)
        for i in range(doors):
            u = x0 + gap + i * (door_w + gap)
            m.box(u, y1 - 2, 1, u + door_w, y1, h - 4, 0)
            m.box(u, y1 - 2, 1, u + door_w, y1 - 1, h - 4, M(door_mat))
            rib = RIB.get(door_mat, "steel")
            for z in range(4, h - 4, 4):
                m.box(u, y1 - 2, z, u + door_w, y1 - 1, z + 1, M(rib))
            m.box(u - 1, y1 - 1, h - 4, u + door_w + 1, y1, h - 3, M(k["trim"]))
    if band:
        m.box(x0, y1 - 1, h - 3, x1, y1, h - 1, M(band))
        m.box(x1 - 1, y0, h - 3, x1, y1, h - 1, M(band))
    for u in range(y0 + 4, y1 - 6, 10):
        window(m, "e", u, h - 10, x1, Win(5, 4, frame=k["frame"], glass=k["glass"], cross=False, sill=False, lit=0.3), rng)
    return roof(m, st, x0, y0, x1, y1, h, roof_kind or k["hall"], rng)


def tower(m, st, x, y, s, h, rng, cap="pub_red"):
    """Schlauch-/Uebungsturm oder Treppenturm: schlank, Fensterschlitze, Abschluss in Kennfarbe."""
    k = ST[st]
    block(m, x, y, 1, x + s, y + s, h, k["wall"], base=k["base"], base_h=3)
    for z in range(10, h - 6, 9):
        window(m, "s", x + s // 2 - 1, z, y + s, Win(2, 5, frame=k["frame"], glass=k["glass"], cross=False, sill=False, lit=0.2), rng)
        window(m, "e", y + s // 2 - 1, z, x + s, Win(2, 5, frame=k["frame"], glass=k["glass"], cross=False, sill=False, lit=0.2), rng)
    m.box(x - 1, y - 1, h, x + s + 1, y + s + 1, h + 2, M(cap))
    if ST[st]["roof"] == "gable":
        return gable_roof(m, x, y, x + s, y + s, h + 2, ridge="x", tile=k["tile"], tile2=k["tile2"], pitch=1.2, overhang=1)
    return h + 2


def canopy(m, x0, y0, x1, y1, h, roof_mat="steel", post="steel_dark"):
    for (px, py) in ((x0, y0), (x1 - 2, y0), (x0, y1 - 2), (x1 - 2, y1 - 2)):
        m.box(px, py, 1, px + 2, py + 2, h, M(post))
    m.box(x0 - 1, y0 - 1, h, x1 + 1, y1 + 1, h + 2, M(roof_mat))


def beacon(m, x, y, z):
    m.box(x, y, z, x + 3, y + 2, z + 2, M("pub_blue"))


def cross_sign(m, x, y_face, z, size=9):
    """Weisses Schild mit rotem Kreuz auf der Suedfassade."""
    m.box(x, y_face, z, x + size, y_face + 1, z + size, M("pub_white"))
    c = size // 2
    m.box(x + c - 1, y_face, z + 1, x + c + 2, y_face + 1, z + size - 1, M("pub_red"))
    m.box(x + 1, y_face, z + c - 1, x + size - 1, y_face + 1, z + c + 2, M("pub_red"))


def heap(m, x0, y0, x1, y1, h, mat_name):
    for i in range(h):
        m.box(x0 + i, y0 + i, 1 + i, x1 - i, y1 - i, 2 + i, M(mat_name))


def dome(m, cx, cy, r, mat_name="pub_salt"):
    """Streugutlager (Salzkuppel)."""
    for z in range(r):
        rr = int((r * r - z * z) ** 0.5)
        m.box(cx - rr, cy - rr, 1 + z, cx + rr, cy + rr, 2 + z, M(mat_name if z < r - 2 else "timber"))
    m.box(cx - 3, cy + r - 2, 1, cx + 3, cy + r + 1, 9, 0)


def ground(m, st, W, H, seed):
    k = ST[st]
    if k["ground"] == "paving":
        slab(m, 0, 0, W, H, paving_fn(4, "paving", "paving2"))
    elif k["ground"] == "gravel":
        slab(m, 0, 0, W, H, grass_fn(seed))
        slab(m, 0, H // 3, W, H, paving_fn(6, "gravel", "paving2"))
    else:
        slab(m, 0, 0, W, H, paving_fn(8, k["ground"], "concrete2" if k["ground"] != "concrete2" else "concrete"))


def greenery(m, st, spots, rng):
    """Baeume/Hecken je Stil: gruen viel, Backstein Hecken, modern wenig, Industrie Zaun statt Gruen."""
    for i, (x, y) in enumerate(spots):
        if st == "gruen" or (st == "backstein" and i % 2 == 0) or (st == "modern" and i == 0):
            tree(m, x, y, 1, kind=rng.choice(["round", "conifer"]) if st == "gruen" else "round", size=0.8, rng=rng)
        elif st == "backstein":
            bush(m, x, y, 1, r=3, rng=rng)


# ------------------------------------------------------------------ Feuerwache 4x3
def fire_station(v, st, seed):
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 90)
    ground(m, st, W, H, seed)
    door_m = "pub_red"
    if v == 0:      # Hallenzeile mit 3 Toren, Verwaltung rechts, Schlauchturm hinten links
        hall(m, st, 8, 20, 84, 72, 26, 3, door_m, rng, band="pub_red")
        house(m, st, 86, 30, 122, 72, 2, rng)
        tower(m, st, 10, 4, 12, 56, rng)
    elif v == 1:    # L-Form: Halle vorne links, Verwaltungsfluegel hinten quer, Turm an der Ecke
        hall(m, st, 6, 40, 70, 84, 24, 2, door_m, rng, band="pub_red")
        house(m, st, 6, 6, 118, 36, 2, rng, entrance=False)
        house(m, st, 76, 40, 118, 76, 1, rng)
        tower(m, st, 104, 10, 12, 60, rng)
    elif v == 2:    # Zentralturm zwischen zwei Hallenteilen
        hall(m, st, 4, 28, 54, 76, 24, 2, door_m, rng, band="pub_red")
        tower(m, st, 56, 34, 16, 66, rng)
        hall(m, st, 74, 28, 124, 76, 24, 2, door_m, rng, band="pub_red")
    elif v == 3:    # kompakt: Tore unten, zwei Buerogeschosse darueber
        hall(m, st, 14, 18, 112, 70, 24, 4, door_m, rng, roof_kind="flat", band="pub_red", door_w=16)
        house(m, st, 14, 18, 112, 52, 2, rng, z0=27)
        beacon(m, 60, 70, 22)
    elif v == 4:    # Halle hinten, freistehender Uebungsturm im Hof, flache Wache vorne rechts
        hall(m, st, 4, 6, 76, 50, 26, 3, door_m, rng, band="pub_red")
        tower(m, st, 14, 64, 14, 48, rng)
        house(m, st, 82, 46, 124, 82, 1, rng)
    else:           # lange Halle quer, Verwaltung als Kopfbau mit Turmaufsatz
        hall(m, st, 4, 34, 92, 78, 22, 4, door_m, rng, band="pub_red", door_w=12)
        house(m, st, 94, 20, 124, 78, 3, rng)
        tower(m, st, 102, 4, 12, 58, rng)
    beacon(m, W // 2 - 1, H - 3, 1) if v != 3 else None
    greenery(m, st, [(118, 90), (6, 90)], rng)
    lamp_post(m, 2, H - 3, 1, h=14)
    return m, {"w": 4, "h": 3, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 70, "blink": [W // 2, H - 4]}


# ------------------------------------------------------------------ Rettungswache 3x2
def rescue_station(v, st, seed):
    rng = random.Random(seed)
    W, H = 3 * T, 2 * T
    m = Model(W, H, 60)
    ground(m, st, W, H, seed)
    d = "pub_door_w"
    if v == 0:
        hall(m, st, 4, 16, 54, 52, 20, 2, d, rng, band="pub_orange", door_w=16)
        house(m, st, 56, 20, 92, 52, 2, rng)
    elif v == 1:
        house(m, st, 4, 4, 92, 26, 2, rng, entrance=False)
        hall(m, st, 4, 28, 60, 56, 18, 2, d, rng, band="pub_orange", door_w=18)
        house(m, st, 62, 28, 92, 56, 1, rng)
    elif v == 2:
        canopy(m, 4, 26, 52, 58, 18, roof_mat="pub_orange")
        house(m, st, 56, 12, 92, 52, 2, rng)
    elif v == 3:
        hall(m, st, 30, 14, 92, 52, 20, 3, d, rng, band="pub_orange", door_w=14)
        tower(m, st, 6, 18, 14, 40, rng, cap="pub_orange")
    elif v == 4:
        house(m, st, 4, 6, 40, 52, 3, rng)
        hall(m, st, 44, 20, 92, 54, 18, 2, d, rng, band="pub_orange", roof_kind="flat", door_w=16)
    else:
        hall(m, st, 6, 8, 64, 44, 20, 2, d, rng, band="pub_orange", door_w=18)
        house(m, st, 66, 8, 92, 44, 2, rng, roof_kind="flat")
        m.box(10, 48, 1, 60, 60, 2, M("asphalt"))
    cross_sign(m, W - 18, H - 13, 14, size=7) if v in (0, 2) else None
    beacon(m, 30, H - 3, 1)
    greenery(m, st, [(90, 58)], rng)
    return m, {"w": 3, "h": 2, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 46, "blink": [30, H - 4]}


# ------------------------------------------------------------------ Krankenhaus 5x4
def hospital(v, st, seed):
    rng = random.Random(seed)
    W, H = 5 * T, 4 * T
    m = Model(W, H, 120)
    ground(m, st, W, H, seed)
    flat = "flat" if st != "gruen" else "green"

    def helipad(x0, y0, x1, y1, z):
        m.box(x0 + 3, y0 + 3, z, x1 - 3, y1 - 3, z + 1, M("pub_heli"))
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        m.box(cx - 4, cy - 5, z + 1, cx - 2, cy + 5, z + 2, M("white"))
        m.box(cx + 2, cy - 5, z + 1, cx + 4, cy + 5, z + 2, M("white"))
        m.box(cx - 2, cy - 1, z + 1, cx + 2, cy + 1, z + 2, M("white"))

    if v == 0:      # Bettenhaus quer, Flachbau vorne mit Notaufnahme
        top = house(m, st, 10, 8, 150, 50, 6, rng, roof_kind=flat, entrance=False)
        house(m, st, 30, 54, 130, 100, 2, rng, roof_kind="flat")
        helipad(110, 10, 148, 48, top)
    elif v == 1:    # Kreuzform/T-Form
        house(m, st, 10, 40, 150, 80, 5, rng, roof_kind=flat)
        top = house(m, st, 60, 6, 100, 120, 6, rng, roof_kind="flat", entrance=False)
        helipad(60, 8, 100, 40, top)
    elif v == 2:    # zwei Tuerme mit Verbindungsbau
        top = house(m, st, 10, 10, 60, 70, 7, rng, roof_kind="flat", entrance=False)
        house(m, st, 60, 30, 100, 70, 3, rng, roof_kind=flat)
        house(m, st, 100, 10, 150, 70, 6, rng, roof_kind=flat, entrance=False)
        helipad(12, 12, 58, 58, top)
        house(m, st, 40, 76, 120, 104, 1, rng, roof_kind="flat")
    elif v == 3:    # Pavillonklinik: drei niedrige Haeuser im Park
        for i, (x0, y0) in enumerate(((8, 8), (58, 8), (108, 8))):
            house(m, st, x0, y0, x0 + 44, y0 + 44, 3, rng)
        house(m, st, 40, 64, 120, 100, 2, rng, roof_kind="flat")
        for p in ((20, 70), (140, 70), (20, 112), (140, 112)):
            tree(m, p[0], p[1], 1, kind="round", size=1.0, rng=rng)
    elif v == 4:    # Hofanlage (U-Form)
        house(m, st, 8, 8, 152, 40, 4, rng, roof_kind=flat, entrance=False)
        house(m, st, 8, 40, 40, 104, 4, rng, roof_kind=flat, entrance=False)
        top = house(m, st, 120, 40, 152, 104, 5, rng, roof_kind="flat")
        helipad(120, 60, 152, 100, top)
        tree(m, 80, 70, 1, kind="round", size=1.1, rng=rng)
    else:           # Hochhausklinik mit breitem Sockel
        house(m, st, 8, 30, 152, 100, 2, rng, roof_kind="flat")
        top = house(m, st, 40, 6, 120, 60, 9, rng, roof_kind="flat", entrance=False, fh=10)
        helipad(44, 10, 116, 56, top)
    canopy(m, 4, 104, 34, 124, 14, roof_mat="pub_red")
    cross_sign(m, 6, H - 1, 18, size=9) if v != 3 else cross_sign(m, 140, 100, 12, size=9)
    lamp_post(m, 40, H - 3, 1, h=16)
    return m, {"w": 5, "h": 4, "entrance": [W // 2, H], "delivery": [20, H], "height": 110, "blink": [20, H - 6]}


# ------------------------------------------------------------------ Bauhof 4x3
def municipal_yard(v, st, seed):
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 60)
    ground(m, st, W, H, seed)
    d = "pub_orange"
    if v == 0:
        hall(m, st, 6, 8, 80, 48, 22, 3, d, rng, band="pub_orange")
        dome(m, 104, 30, 18)
        heap(m, 70, 62, 100, 88, 7, "gravel")
    elif v == 1:
        hall(m, st, 40, 6, 124, 46, 20, 4, d, rng, band="pub_orange", door_w=14)
        house(m, st, 6, 6, 36, 46, 2, rng)
        heap(m, 8, 58, 40, 90, 8, "sand")
        heap(m, 48, 60, 78, 90, 7, "gravel")
    elif v == 2:
        canopy(m, 6, 10, 70, 50, 18, roof_mat="pub_orange")
        house(m, st, 76, 10, 122, 48, 2, rng)
        dome(m, 30, 74, 16)
    elif v == 3:
        hall(m, st, 6, 6, 122, 40, 18, 5, d, rng, band="pub_orange", door_w=14)
        dome(m, 26, 70, 15)
        heap(m, 60, 58, 94, 88, 8, "gravel")
    elif v == 4:
        house(m, st, 6, 6, 50, 38, 2, rng)
        hall(m, st, 56, 6, 122, 56, 24, 3, d, rng, band="pub_orange")
        canopy(m, 6, 50, 46, 86, 14, roof_mat="steel")
        heap(m, 70, 66, 110, 90, 6, "sand")
    else:
        hall(m, st, 6, 24, 70, 70, 22, 2, d, rng, band="pub_orange", door_w=18)
        tower(m, st, 80, 10, 14, 44, rng, cap="pub_orange")   # Streugutsilo
        heap(m, 96, 40, 124, 70, 8, "gravel")
    fence(m, 0, H - 2, 50, H, 1, h=6, mat_f="steel")
    fence(m, 78, H - 2, W, H, 1, h=6, mat_f="steel")
    greenery(m, st, [(122, 90)], rng)
    return m, {"w": 4, "h": 3, "entrance": [64, H], "delivery": [64, H], "height": 50}


# ------------------------------------------------------------------ Busbetriebshof 5x3
def bus_depot(v, st, seed):
    rng = random.Random(seed)
    W, H = 5 * T, 3 * T
    m = Model(W, H, 60)
    ground(m, st, W, H, seed)
    d = "pub_yellow"
    if v == 0:
        hall(m, st, 6, 8, 120, 56, 24, 5, d, rng, band="pub_yellow", door_w=16)
        house(m, st, 124, 16, 156, 56, 2, rng)
    elif v == 1:
        hall(m, st, 40, 6, 156, 52, 22, 5, d, rng, band="pub_yellow", door_w=16)
        house(m, st, 6, 6, 36, 52, 3, rng)
        canopy(m, 60, 62, 120, 86, 16, roof_mat="pub_yellow")
    elif v == 2:
        canopy(m, 6, 10, 100, 54, 18, roof_mat="steel")
        house(m, st, 106, 10, 154, 54, 2, rng)
    elif v == 3:
        hall(m, st, 6, 6, 156, 44, 22, 6, d, rng, band="pub_yellow", door_w=16)
        canopy(m, 100, 56, 150, 84, 14, roof_mat="pub_yellow")
    elif v == 4:
        hall(m, st, 6, 8, 80, 56, 24, 3, d, rng, band="pub_yellow", door_w=18)
        hall(m, st, 84, 8, 130, 56, 20, 2, "frame_dark", rng, roof_kind="flat", door_w=16)   # Werkstatt
        house(m, st, 134, 20, 156, 56, 2, rng, entrance=False)
    else:
        house(m, st, 6, 6, 50, 44, 3, rng)
        canopy(m, 56, 6, 154, 50, 18, roof_mat="pub_yellow" if st != "industrie" else "zinc")
        hall(m, st, 6, 52, 50, 84, 16, 1, "frame_dark", rng, roof_kind="flat", door_w=18)  # Waschhalle
    greenery(m, st, [(4, 90), (156, 90)], rng)
    return m, {"w": 5, "h": 3, "entrance": [80, H], "delivery": [80, H], "height": 50}


# ------------------------------------------------------------------ Schule 6x4
def public_school(v, st, seed):
    rng = random.Random(seed)
    W, H = 6 * T, 4 * T
    m = Model(W, H, 100)
    ground(m, st, W, H, seed)

    def field(x0, y0, x1, y1):
        slab(m, x0, y0, x1, y1, "asphalt")
        for x in range(x0 + 2, x1 - 2):
            m.put(x, y0 + 2, 0, M("white"))
            m.put(x, y1 - 3, 0, M("white"))
        for y in range(y0 + 2, y1 - 2):
            m.put(x0 + 2, y, 0, M("white"))
            m.put((x0 + x1) // 2, y, 0, M("white"))
            m.put(x1 - 3, y, 0, M("white"))

    if v == 0:      # Riegel hinten, Hof mit Spielfeld vorne
        house(m, st, 8, 8, 184, 46, 3, rng)
        field(10, 60, 110, 120)
    elif v == 1:    # L-Form
        house(m, st, 8, 8, 120, 44, 3, rng)
        house(m, st, 124, 8, 184, 100, 3, rng, entrance=False)
        field(10, 56, 110, 116)
    elif v == 2:    # U-Form um den Hof
        house(m, st, 8, 8, 184, 40, 2, rng, entrance=False)
        house(m, st, 8, 40, 44, 110, 2, rng, entrance=False)
        house(m, st, 148, 40, 184, 110, 2, rng)
        field(54, 50, 138, 104)
    elif v == 3:    # Pavillons
        for x0 in (8, 70, 132):
            house(m, st, x0, 10, x0 + 52, 50, 2, rng)
        field(40, 64, 150, 120)
    elif v == 4:    # Kompakter Block mit Turnhalle
        house(m, st, 8, 8, 100, 70, 4, rng)
        hall(m, st, 108, 8, 184, 60, 26, 0, "frame_dark", rng, band="pub_green")
        field(108, 70, 184, 120)
    else:           # Zwei versetzte Riegel
        house(m, st, 8, 8, 110, 40, 3, rng, entrance=False)
        house(m, st, 80, 46, 184, 80, 3, rng)
        field(10, 88, 76, 124)
    greenery(m, st, [(180, 120), (120, 120), (8, 50)], rng)
    for k in range(6):
        bike(m, 150 + k * 4, 118, 1, color=rng.choice(["red", "blue", "yellow", "black"]), face="y")
    return m, {"w": 6, "h": 4, "entrance": [96, H], "delivery": [W, 60], "height": 80}


# ------------------------------------------------------------------ Kita 4x3
def public_kita(v, st, seed):
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 50)
    slab(m, 0, 0, W, H, grass_fn(seed))
    accents = ["play_red", "play_yel", "play_blu", "play_grn"]

    def play(x, y):
        m.box(x, y, 0, x + 16, y + 12, 1, M("sand_pit"))
        m.box(x + 2, y + 2, 1, x + 5, y + 5, 10, M(rng.choice(accents)))
        for i in range(8):
            m.box(x + 5 + i, y + 2, 10 - i, x + 6 + i, y + 5, 11 - i, M("play_red"))

    layouts = {
        0: [(8, 8, 120, 40, 1)],
        1: [(8, 8, 60, 44, 2), (64, 20, 120, 44, 1)],
        2: [(8, 8, 40, 60, 1), (44, 8, 84, 40, 1), (88, 8, 120, 60, 1)],
        3: [(30, 8, 100, 48, 2)],
        4: [(8, 8, 120, 30, 1), (8, 30, 40, 60, 1)],
        5: [(8, 20, 56, 56, 1), (64, 8, 120, 44, 2)],
    }
    for i, (x0, y0, x1, y1, fl) in enumerate(layouts[v]):
        house(m, st, x0, y0, x1, y1, fl, rng, entrance=(i == 0), fh=11)
        m.box(x0, y1 - 1, 2, x1, y1, 4, M(accents[(v + i) % 4]))
    play(20, 66)
    play(80, 64)
    fence(m, 2, H - 2, W - 2, H, 1, h=6, mat_f=accents[v % 4])
    greenery(m, st, [(118, 84)], rng)
    return m, {"w": 4, "h": 3, "entrance": [W // 2, H], "delivery": [W, 24], "height": 40}


# ------------------------------------------------------------------ Recyclinghof 4x3
def recycling_yard(v, st, seed):
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 50)
    ground(m, st, W, H, seed)
    cols = ["pub_green", "pub_yellow", "blue", "red", "frame_dark"]

    def bins(x0, y, n):
        for i in range(n):
            x = x0 + i * 14
            m.box(x, y, 1, x + 12, y + 18, 9, M(cols[(i + v) % len(cols)]))
            m.box(x + 1, y + 1, 9, x + 11, y + 17, 10, M("steel_dark"))

    if v == 0:
        canopy(m, 6, 8, 90, 44, 16, roof_mat="pub_green")
        bins(10, 16, 5)
        house(m, st, 96, 8, 122, 40, 1, rng)
    elif v == 1:
        hall(m, st, 6, 6, 70, 44, 20, 2, "pub_green", rng, band="pub_green")
        bins(76, 10, 3)
        heap(m, 10, 56, 44, 88, 7, "gravel")
    elif v == 2:
        bins(8, 8, 8)
        house(m, st, 8, 54, 40, 84, 1, rng)
    elif v == 3:
        hall(m, st, 40, 6, 122, 46, 22, 3, "pub_green", rng, band="pub_green")
        bins(6, 60, 4)
        heap(m, 70, 58, 110, 90, 7, "soil")
    elif v == 4:
        canopy(m, 6, 6, 122, 36, 14, roof_mat="pub_green" if st != "industrie" else "zinc")
        bins(10, 12, 8)
        house(m, st, 90, 50, 122, 84, 1, rng)
    else:
        house(m, st, 6, 6, 36, 40, 2, rng)
        hall(m, st, 40, 6, 90, 40, 18, 1, "pub_green", rng, band="pub_green", door_w=20)
        bins(40, 52, 5)
    fence(m, 0, H - 2, 40, H, 1, h=6, mat_f="pub_green")
    fence(m, 80, H - 2, W, H, 1, h=6, mat_f="pub_green")
    greenery(m, st, [(124, 90)], rng)
    return m, {"w": 4, "h": 3, "entrance": [60, H], "delivery": [60, H], "height": 40}


BUILDERS = {"fire_station": fire_station, "rescue_station": rescue_station, "hospital": hospital, "municipal_yard": municipal_yard,
            "bus_depot": bus_depot, "public_school": public_school, "public_kita": public_kita, "recycling_yard": recycling_yard}


def sprite_name(btype, v, st):
    return "pub_%s_%d_%s" % (TYPES[btype][0], v, st)


def specs():
    """Alle Gebaeude: Name -> Erzeuger. Seed je Variante und Stil fest, damit das Bild reproduzierbar ist."""
    s = {}
    for bt in TYPES:
        for v in range(VARIANTS):
            for i, st in enumerate(STYLES):
                s[sprite_name(bt, v, st)] = (lambda bt=bt, v=v, st=st, sd=11 + 7 * v + 101 * i: BUILDERS[bt](v, st, sd))
    return s
