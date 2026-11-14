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
    "incineration_plant": ("iv", 5, 4),
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


RIB = {"pub_red": "pub_red2", "pub_door_w": "pub_white", "pub_orange": "pub_orange2", "pub_yellow": "pub_yellow2", "pub_green": "pub_green2",
       "pub_wblue": "pub_wblue2"}


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
    mat("pub_wblue", "#2f78b7", noise=0.03)       # Kennfarbe Wasserwerk (Auftrag 22 Phase 4)
    mat("pub_wblue2", "#26649a", noise=0.03)
    mat("pub_sludge", "#6b5a3a", noise=0.08)      # Klaeranlage: Belebungsbecken/Schlamm (Auftrag 22 Phase 4 Schritt 4)
    mat("pub_sludge2", "#7d6c48", noise=0.08)


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


# ------------------------------------------------------------------ Auftrag 20 Etappe 13: Feuerwehr-Ausbaustufen
def _yard_marks(m, x0, y0, x1, y1):
    """Aufstellflaeche vor den Toren: gelbe Sperrmarkierung (Ausfahrt freihalten)."""
    for x in range(x0, x1, 6):
        m.box(x, y0, 1, x + 3, y1, 2, M("pub_yellow"))


def _mast(m, x, y, h):
    """Funkmast der Leitstelle."""
    m.box(x, y, 1, x + 2, y + 2, h, M("steel"))
    m.box(x - 2, y - 2, h - 10, x + 4, y + 4, h - 9, M("steel"))
    m.box(x, y, h, x + 2, y + 2, h + 2, M("pub_red"))


def _burn_house(m, x0, y0, s, h):
    """Brandhaus der Ausbildung: dunkler Beton, verrusste Fensteroeffnungen."""
    m.box(x0, y0, 1, x0 + s, y0 + s, h, M("concrete2"))
    for z in range(6, h - 4, 9):
        m.box(x0 + 3, y0 + s - 1, z, x0 + 7, y0 + s, z + 5, M("black"))
        m.box(x0 + s - 1, y0 + 3, z, x0 + s, y0 + 7, z + 5, M("black"))
    m.box(x0, y0, h, x0 + s, y0 + s, h + 1, M("steel_dark"))


def fire_station_m(v, st, seed):
    """FW-02 Feuerwache 5x3: drei bis vier Stellplaetze, Einsatzleitung, Sozialraeume, Werkstatt."""
    rng = random.Random(seed)
    W, H = 5 * T, 3 * T
    m = Model(W, H, 90)
    ground(m, st, W, H, seed)
    d = "pub_red"
    if v == 0:      # vier Tore in einer Zeile, zweigeschossige Wache links
        house(m, st, 4, 26, 40, 76, 2, rng)
        hall(m, st, 42, 26, 154, 76, 26, 4, d, rng, band="pub_red", door_w=16)
        tower(m, st, 140, 4, 12, 56, rng)
    elif v == 1:    # Halle hinten, Werkstatt und Wache vorne versetzt
        hall(m, st, 4, 4, 110, 48, 26, 3, d, rng, band="pub_red")
        house(m, st, 112, 4, 156, 64, 2, rng)
        hall(m, st, 60, 54, 108, 90, 18, 1, "pub_door_w", rng, roof_kind="flat", door_w=12)
        _yard_marks(m, 8, 52, 56, 56)
    elif v == 2:    # zwei Hallenbloecke beidseits eines Wachgebaeudes mit Turm
        hall(m, st, 4, 30, 58, 80, 24, 2, d, rng, band="pub_red")
        house(m, st, 60, 20, 100, 80, 3, rng)
        hall(m, st, 102, 30, 156, 80, 24, 2, d, rng, band="pub_red")
        tower(m, st, 74, 4, 12, 66, rng)
    elif v == 3:    # Wache ueber der Halle, Werkstatt als Anbau rechts
        hall(m, st, 6, 22, 118, 74, 24, 3, d, rng, roof_kind="flat", band="pub_red", door_w=18)
        house(m, st, 6, 22, 80, 56, 2, rng, z0=25)
        hall(m, st, 120, 34, 156, 74, 16, 1, "pub_door_w", rng, door_w=10)
    elif v == 4:    # L-Form: Halle quer vorne, Wachfluegel hinten laengs, Uebungsturm im Winkel
        hall(m, st, 4, 46, 120, 90, 24, 4, d, rng, band="pub_red", door_w=14)
        house(m, st, 4, 4, 156, 40, 2, rng, entrance=False)
        house(m, st, 122, 46, 156, 86, 1, rng)
        tower(m, st, 130, 8, 14, 64, rng)
    else:           # Pultdach-Halle schraeg gestaffelt, Kopfbau mit drei Geschossen
        hall(m, st, 4, 36, 60, 84, 22, 2, d, rng, band="pub_red")
        hall(m, st, 62, 28, 118, 76, 26, 2, d, rng, band="pub_red")
        house(m, st, 120, 14, 156, 76, 3, rng)
    beacon(m, W // 2, H - 3, 1)
    greenery(m, st, [(150, 90), (4, 90)], rng)
    lamp_post(m, 2, H - 3, 1, h=14)
    return m, {"w": 5, "h": 3, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 70, "blink": [W // 2, H - 4]}


def fire_station_l(v, st, seed):
    """FW-03 Hauptfeuerwache 6x4: mehrere Hallen, Verwaltung, Leitstelle mit Funkmast, Ausbildungsflaeche, Uebungsturm."""
    rng = random.Random(seed)
    W, H = 6 * T, 4 * T
    m = Model(W, H, 110)
    ground(m, st, W, H, seed)
    d = "pub_red"
    if v == 0:      # Hallenkamm vorne, Verwaltungsriegel hinten, Turm im Hof
        hall(m, st, 6, 70, 186, 122, 26, 5, d, rng, band="pub_red", door_w=16)
        house(m, st, 6, 6, 140, 50, 3, rng, entrance=False)
        tower(m, st, 160, 10, 16, 80, rng)
        _mast(m, 120, 54, 70)
    elif v == 1:    # Winkelbau um einen Uebungshof
        hall(m, st, 6, 60, 110, 120, 26, 3, d, rng, band="pub_red", door_w=18)
        house(m, st, 112, 6, 186, 120, 4, rng)
        house(m, st, 6, 6, 110, 40, 2, rng, entrance=False)
        tower(m, st, 20, 42, 14, 70, rng)
        _mast(m, 170, 6, 96)
    elif v == 2:    # zwei Hallen mit Leitstellenturm (Glaskanzel) dazwischen
        hall(m, st, 4, 50, 80, 120, 28, 3, d, rng, band="pub_red")
        house(m, st, 82, 30, 112, 120, 6, rng, roof_kind="flat", fh=10)
        hall(m, st, 114, 50, 188, 120, 28, 3, d, rng, band="pub_red")
        house(m, st, 4, 4, 188, 40, 2, rng, entrance=False)
        _mast(m, 94, 34, 100)
    elif v == 3:    # gestaffelte Hallen, Verwaltung als Hochbau rechts vorne
        hall(m, st, 4, 10, 120, 58, 28, 4, d, rng, band="pub_red", door_w=14)
        hall(m, st, 4, 66, 120, 118, 24, 4, d, rng, band="pub_red", door_w=14)
        house(m, st, 124, 50, 188, 120, 5, rng)
        tower(m, st, 150, 8, 16, 78, rng)
    elif v == 4:    # Wache ueber der Halle (zwei Geschosse), seitlicher Werkstatthof
        hall(m, st, 6, 40, 140, 110, 26, 5, d, rng, roof_kind="flat", band="pub_red", door_w=16)
        house(m, st, 6, 40, 140, 84, 2, rng, z0=27)
        hall(m, st, 144, 56, 188, 110, 18, 1, "pub_door_w", rng, door_w=14)
        tower(m, st, 160, 8, 14, 74, rng)
        _mast(m, 20, 10, 80)
    else:           # Halbrund aus drei Hallen um den Turm (Ausbildungsflaeche)
        hall(m, st, 4, 70, 70, 122, 24, 3, d, rng, band="pub_red", door_w=14)
        hall(m, st, 120, 70, 188, 122, 24, 3, d, rng, band="pub_red", door_w=14)
        house(m, st, 40, 6, 150, 46, 3, rng, entrance=False)
        tower(m, st, 88, 60, 16, 84, rng)
    beacon(m, W // 2, H - 3, 1)
    greenery(m, st, [(184, 124), (4, 124), (96, 4)], rng)
    lamp_post(m, 2, H - 3, 1, h=16)
    return m, {"w": 6, "h": 4, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 96, "blink": [W // 2, H - 4]}


def fire_hq(v, st, seed):
    """FW-04 Berufsfeuerwehr-Zentrale 7x5: Einsatzleitung, Werkstaetten, mehrere Fahrzeughallen, Personalgebaeude."""
    rng = random.Random(seed)
    W, H = 7 * T, 5 * T
    m = Model(W, H, 130)
    ground(m, st, W, H, seed)
    d = "pub_red"
    if v == 0:      # Campus: Hallenreihe vorn, Hochhaus der Verwaltung hinten, Werkstatt rechts
        hall(m, st, 6, 100, 160, 154, 28, 6, d, rng, band="pub_red", door_w=16)
        house(m, st, 30, 8, 120, 60, 7, rng, roof_kind="flat", entrance=False, fh=10)
        hall(m, st, 164, 60, 220, 154, 20, 2, "pub_door_w", rng, door_w=16)
        tower(m, st, 180, 8, 18, 96, rng)
        _mast(m, 130, 20, 110)
    elif v == 1:    # Doppelhalle mit Personalhaus dazwischen, Leitstelle als Kubus vorne rechts
        hall(m, st, 4, 70, 96, 150, 30, 4, d, rng, band="pub_red", door_w=16)
        house(m, st, 98, 10, 130, 150, 4, rng)
        hall(m, st, 132, 70, 220, 150, 30, 4, d, rng, band="pub_red", door_w=16)
        house(m, st, 4, 8, 96, 60, 3, rng, entrance=False)
        house(m, st, 140, 8, 220, 60, 5, rng, roof_kind="flat", entrance=False)
        _mast(m, 210, 12, 120)
    elif v == 2:    # Hofanlage (geschlossen) mit Uebungsturm in der Mitte
        hall(m, st, 6, 110, 220, 156, 28, 7, d, rng, band="pub_red", door_w=14)
        house(m, st, 6, 6, 220, 40, 3, rng, entrance=False)
        house(m, st, 6, 40, 40, 108, 3, rng, entrance=False)
        hall(m, st, 186, 40, 220, 108, 22, 0, d, rng)
        tower(m, st, 104, 60, 18, 100, rng)
    elif v == 3:    # gestaffelter Komplex: drei Hallen nach hinten versetzt, Hochhaus vorne rechts
        hall(m, st, 4, 10, 80, 60, 26, 3, d, rng, band="pub_red")
        hall(m, st, 4, 64, 110, 112, 26, 4, d, rng, band="pub_red")
        hall(m, st, 4, 116, 140, 156, 22, 5, d, rng, band="pub_red", door_w=14)
        house(m, st, 150, 80, 220, 156, 8, rng, roof_kind="flat", fh=10)
        tower(m, st, 120, 10, 16, 90, rng)
        _mast(m, 200, 10, 110)
    elif v == 4:    # Wache ueber Hallen auf ganzer Laenge, Werkstatthof hinten
        hall(m, st, 6, 80, 220, 150, 28, 7, d, rng, roof_kind="flat", band="pub_red", door_w=16)
        house(m, st, 6, 80, 220, 120, 3, rng, z0=29)
        hall(m, st, 40, 6, 150, 60, 22, 0, d, rng)
        tower(m, st, 180, 10, 18, 96, rng)
    else:           # Ringbau mit Glaskanzel, freistehende Hallen links und rechts vorn
        hall(m, st, 4, 96, 90, 156, 26, 3, d, rng, band="pub_red", door_w=18)
        hall(m, st, 136, 96, 222, 156, 26, 3, d, rng, band="pub_red", door_w=18)
        house(m, st, 50, 10, 180, 80, 4, rng)
        house(m, st, 96, 96, 130, 150, 2, rng)
        tower(m, st, 10, 10, 16, 92, rng)
        _mast(m, 200, 20, 116)
    beacon(m, W // 2, H - 3, 1)
    greenery(m, st, [(218, 4), (4, 90), (120, 90)], rng)
    lamp_post(m, 2, H - 3, 1, h=18)
    lamp_post(m, W - 4, H - 3, 1, h=18)
    return m, {"w": 7, "h": 5, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 110, "blink": [W // 2, H - 4]}


def fire_airport(v, st, seed):
    """FW-05 Flughafenfeuerwehr 3x2 (Grundflaeche der Flughafenwache): hohe, breite Tore fuer Flugfeldloeschfahrzeuge, Beobachtungskanzel."""
    rng = random.Random(seed)
    W, H = 3 * T, 2 * T
    m = Model(W, H, 90)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete2", "concrete"))
    d = "pub_yellow"
    if v == 0:      # zwei Riesentore, Kanzel auf Stelzen rechts
        hall(m, st, 2, 10, 70, 54, 30, 2, d, rng, roof_kind="flat", band="pub_red", door_w=26)
        m.box(80, 30, 1, 84, 34, 44, M("steel"))
        house(m, st, 72, 20, 94, 42, 1, rng, roof_kind="flat", z0=44, entrance=False)
    elif v == 1:    # Halle mit Kanzel als Kopfbau links
        house(m, st, 2, 14, 22, 56, 4, rng, roof_kind="flat", fh=11)
        hall(m, st, 24, 14, 94, 56, 30, 2, d, rng, roof_kind="flat", band="pub_red", door_w=26)
    elif v == 2:    # Halle mit Hallendach (Sheds), Sozialtrakt hinten
        house(m, st, 2, 2, 94, 18, 1, rng, entrance=False)
        hall(m, st, 2, 20, 94, 60, 28, 2, d, rng, roof_kind="saw", band="pub_red", door_w=30)
    elif v == 3:    # ein Tor, Kanzelturm und Schaummitteltank
        hall(m, st, 2, 8, 56, 58, 30, 1, d, rng, roof_kind="flat", band="pub_red", door_w=34)
        tower(m, st, 62, 34, 14, 62, rng, cap="pub_yellow")
        m.box(78, 6, 1, 92, 20, 24, M("pub_white"))
    elif v == 4:    # versetzte Doppelhalle
        hall(m, st, 2, 4, 48, 46, 28, 1, d, rng, roof_kind="flat", band="pub_red", door_w=30)
        hall(m, st, 50, 16, 94, 60, 28, 1, d, rng, roof_kind="flat", band="pub_red", door_w=30)
    else:           # drei Tore, Kanzel auf dem Dach
        hall(m, st, 2, 12, 94, 58, 28, 3, d, rng, roof_kind="flat", band="pub_red", door_w=22)
        house(m, st, 34, 18, 62, 40, 1, rng, roof_kind="flat", z0=29, entrance=False)
    _yard_marks(m, 4, H - 4, W - 4, H - 2)
    beacon(m, W // 2, H - 3, 1)
    return m, {"w": 3, "h": 2, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 70, "blink": [W // 2, H - 4]}


def fire_school(v, st, seed):
    """FW-06 Feuerwehrausbildungszentrum 5x4: Lehrgebaeude, Uebungsturm, Brandhaus, Uebungsgelaende mit Wrack und Gefahrgutcontainer."""
    rng = random.Random(seed)
    W, H = 5 * T, 4 * T
    m = Model(W, H, 100)
    ground(m, st, W, H, seed)
    slab(m, 70, 60, 156, 124, paving_fn(6, "concrete2", "concrete"))   # Uebungsgelaende
    if v == 0:      # Lehrgebaeude quer hinten, Turm und Brandhaus auf dem Gelaende
        house(m, st, 6, 6, 120, 50, 3, rng)
        tower(m, st, 130, 10, 16, 84, rng)
        _burn_house(m, 80, 70, 26, 30)
        car(m, 120, 100, 1, color="black")
    elif v == 1:    # Winkelbau Lehrsaele, Uebungshalle, Turm vorne
        house(m, st, 6, 6, 60, 120, 2, rng)
        hall(m, st, 64, 6, 156, 54, 22, 2, "pub_red", rng, band="pub_red")
        tower(m, st, 100, 80, 14, 76, rng)
        _burn_house(m, 126, 70, 24, 26)
    elif v == 2:    # Campus: zwei Lehrhaeuser, Atemschutzstrecke, Brandhaus gross
        house(m, st, 6, 6, 70, 46, 2, rng)
        house(m, st, 6, 60, 60, 120, 3, rng)
        _burn_house(m, 90, 10, 40, 44)
        m.box(80, 86, 1, 150, 100, 12, M("steel_dark"))   # Atemschutzuebungsstrecke
    elif v == 3:    # Hochbau mit Turm angebaut, Wrack- und Containerplatz
        house(m, st, 10, 10, 70, 60, 5, rng, roof_kind="flat", fh=10)
        tower(m, st, 72, 10, 16, 92, rng)
        m.box(96, 70, 1, 140, 84, 14, M("pub_orange"))     # Gefahrgutcontainer
        car(m, 90, 100, 1, color="black")
        car(m, 120, 104, 1, color="blue")
    elif v == 4:    # Halle mit Lehrtrakt obenauf, Brandhaus und Turm getrennt
        hall(m, st, 6, 6, 100, 56, 22, 3, "pub_red", rng, roof_kind="flat", band="pub_red")
        house(m, st, 6, 6, 100, 36, 1, rng, z0=23, entrance=False)
        house(m, st, 104, 6, 156, 56, 2, rng)
        _burn_house(m, 76, 72, 30, 34)
        tower(m, st, 130, 72, 14, 70, rng)
    else:           # Pavillons um den Platz, Turm in der Mitte
        for (x0, y0) in ((6, 6), (56, 6), (106, 6)):
            house(m, st, x0, y0, x0 + 44, y0 + 40, 2, rng)
        tower(m, st, 100, 76, 18, 96, rng)
        _burn_house(m, 20, 70, 30, 28)
    greenery(m, st, [(4, 124), (60, 124)], rng)
    lamp_post(m, 2, H - 3, 1, h=16)
    return m, {"w": 5, "h": 4, "entrance": [30, H], "delivery": [30, H], "height": 90, "blink": [30, H - 4]}


TYPES.update({"fire_station_m": ("fw2", 5, 3), "fire_station_l": ("fw3", 6, 4), "fire_hq": ("fw4", 7, 5), "fire_airport": ("fw5", 3, 2),
              "fire_school": ("fw6", 5, 4)})
BUILDERS.update({"fire_station_m": fire_station_m, "fire_station_l": fire_station_l, "fire_hq": fire_hq, "fire_airport": fire_airport,
                 "fire_school": fire_school})


# ------------------------------------------------------------------ Auftrag 20 Etappe 14: Rettungsdienst und Kliniken
def _ramp(m, x0, y0, x1, y1):
    """Liegendanfahrt der Notaufnahme: rotes Vordach ueber einer Zufahrt."""
    canopy(m, x0, y0, x1, y1, 14, roof_mat="pub_red")


def rescue_center(v, st, seed):
    """RD-02 Zentrale Rettungswache 4x3: mehrere Fahrzeughallen, Aufenthalt, Materiallager, Desinfektion."""
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 70)
    ground(m, st, W, H, seed)
    d = "pub_door_w"
    if v == 0:      # vier Tore in einer Zeile, Wache zweigeschossig rechts
        hall(m, st, 4, 30, 90, 76, 20, 4, d, rng, band="pub_orange", door_w=16)
        house(m, st, 92, 22, 124, 76, 2, rng)
    elif v == 1:    # Winkel: Halle vorn, Lagertrakt hinten quer
        house(m, st, 4, 4, 124, 28, 1, rng, entrance=False)
        hall(m, st, 4, 32, 80, 78, 20, 3, d, rng, band="pub_orange", door_w=18)
        house(m, st, 84, 32, 124, 78, 2, rng)
    elif v == 2:    # offener Unterstand fuer RTW, Wache mit Turm
        canopy(m, 4, 40, 70, 82, 18, roof_mat="pub_orange")
        house(m, st, 74, 20, 124, 80, 3, rng)
        tower(m, st, 8, 6, 12, 48, rng, cap="pub_orange")
    elif v == 3:    # Wache ueber der Halle
        hall(m, st, 6, 24, 122, 76, 20, 5, d, rng, roof_kind="flat", band="pub_orange", door_w=14)
        house(m, st, 6, 24, 90, 52, 2, rng, z0=21)
    elif v == 4:    # zwei Hallen beidseits des Sozialbaus
        hall(m, st, 4, 34, 48, 80, 20, 2, d, rng, band="pub_orange", door_w=14)
        house(m, st, 50, 20, 78, 80, 3, rng)
        hall(m, st, 80, 34, 124, 80, 20, 2, d, rng, band="pub_orange", door_w=14)
    else:           # Halle hinten, Waschhalle und Buero vorne versetzt
        hall(m, st, 4, 4, 100, 46, 22, 4, d, rng, band="pub_orange", door_w=16)
        house(m, st, 4, 52, 50, 88, 1, rng)
        hall(m, st, 60, 52, 124, 88, 16, 1, "pub_white", rng, roof_kind="flat", door_w=20)
    cross_sign(m, W - 14, H - 1, 16, size=8) if v in (0, 4) else None
    beacon(m, 40, H - 3, 1)
    greenery(m, st, [(124, 92), (2, 92)], rng)
    return m, {"w": 4, "h": 3, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 52, "blink": [40, H - 4]}


def general_hospital(v, st, seed):
    """KH-02 Allgemeinkrankenhaus 6x4: mehrere Stationen, Diagnostik, Rettungswagenzufahrt."""
    rng = random.Random(seed)
    W, H = 6 * T, 4 * T
    m = Model(W, H, 120)
    ground(m, st, W, H, seed)
    fl = "flat" if st != "gruen" else "green"
    if v == 0:      # Bettenriegel hinten, Behandlungsbau vorn, Notaufnahme rechts
        house(m, st, 8, 6, 184, 46, 6, rng, roof_kind=fl, entrance=False)
        house(m, st, 30, 54, 140, 100, 2, rng, roof_kind="flat")
        _ramp(m, 148, 96, 184, 120)
    elif v == 1:    # Doppel-T: zwei Bettenhaeuser mit Magistrale
        house(m, st, 10, 6, 70, 110, 5, rng, roof_kind=fl, entrance=False)
        house(m, st, 70, 46, 120, 80, 2, rng, roof_kind="flat")
        house(m, st, 120, 6, 180, 110, 5, rng, roof_kind=fl)
        _ramp(m, 76, 90, 112, 120)
    elif v == 2:    # Kamm: Sockel mit drei Pflegefluegeln
        house(m, st, 6, 70, 186, 110, 2, rng, roof_kind="flat")
        for x0 in (10, 76, 142):
            house(m, st, x0, 6, x0 + 40, 66, 5, rng, roof_kind=fl, entrance=False)
        _ramp(m, 150, 112, 186, 126)
    elif v == 3:    # Hochhaus mit Hubschrauberlandeplatz und Flachbau
        top = house(m, st, 60, 10, 130, 70, 9, rng, roof_kind="flat", entrance=False, fh=10)
        m.box(64, 14, top, 126, 66, top + 1, M("pub_heli"))
        house(m, st, 6, 70, 186, 112, 2, rng, roof_kind="flat")
        _ramp(m, 6, 112, 40, 126)
    elif v == 4:    # Hofanlage mit Garten
        house(m, st, 6, 6, 186, 36, 4, rng, roof_kind=fl, entrance=False)
        house(m, st, 6, 36, 36, 110, 4, rng, roof_kind=fl, entrance=False)
        house(m, st, 156, 36, 186, 110, 4, rng, roof_kind=fl)
        tree(m, 96, 70, 1, kind="round", size=1.2, rng=rng)
        _ramp(m, 60, 100, 100, 124)
    else:           # Pavillons: Altbau mit Satteldach plus moderner Anbau
        house(m, st, 6, 10, 90, 60, 4, rng, roof_kind="gable", entrance=False)
        house(m, st, 96, 10, 186, 80, 5, rng, roof_kind="flat")
        house(m, st, 6, 70, 90, 110, 2, rng, roof_kind="flat")
        _ramp(m, 120, 96, 160, 122)
    cross_sign(m, 8, H - 1, 18, size=9)
    lamp_post(m, 44, H - 3, 1, h=16)
    return m, {"w": 6, "h": 4, "entrance": [W // 2, H], "delivery": [30, H], "height": 110, "blink": [30, H - 6]}


def central_clinic(v, st, seed):
    """KH-03 Zentralklinikum 7x5: mehrere Gebaeudefluegel, grosse Notaufnahme, Hubschrauberlandeplatz."""
    rng = random.Random(seed)
    W, H = 7 * T, 5 * T
    m = Model(W, H, 140)
    ground(m, st, W, H, seed)
    fl = "flat" if st != "gruen" else "green"

    def heli(x0, y0, x1, y1, z):
        m.box(x0 + 2, y0 + 2, z, x1 - 2, y1 - 2, z + 1, M("pub_heli"))
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        m.box(cx - 4, cy - 6, z + 1, cx - 2, cy + 6, z + 2, M("white"))
        m.box(cx + 2, cy - 6, z + 1, cx + 4, cy + 6, z + 2, M("white"))
        m.box(cx - 2, cy - 1, z + 1, cx + 2, cy + 1, z + 2, M("white"))

    if v == 0:      # Turm + breiter Sockel + Seitenfluegel
        house(m, st, 6, 90, 218, 150, 2, rng, roof_kind="flat")
        top = house(m, st, 70, 10, 150, 86, 10, rng, roof_kind="flat", entrance=False, fh=10)
        heli(74, 14, 146, 82, top)
        house(m, st, 6, 10, 66, 86, 5, rng, roof_kind=fl, entrance=False)
        house(m, st, 156, 10, 218, 86, 5, rng, roof_kind=fl, entrance=False)
    elif v == 1:    # Stern: drei Fluegel um einen Kern
        house(m, st, 80, 40, 140, 110, 7, rng, roof_kind="flat")
        house(m, st, 6, 56, 80, 96, 5, rng, roof_kind=fl, entrance=False)
        house(m, st, 140, 56, 218, 96, 5, rng, roof_kind=fl, entrance=False)
        top = house(m, st, 90, 4, 130, 40, 8, rng, roof_kind="flat", entrance=False)
        heli(90, 4, 130, 40, top)
    elif v == 2:    # Campus: vier Haeuser, Magistrale
        for (x0, y0, f) in ((6, 6, 6), (116, 6, 7), (6, 84, 4), (116, 84, 5)):
            house(m, st, x0, y0, x0 + 100, y0 + 60, f, rng, roof_kind=fl, entrance=False)
        house(m, st, 100, 66, 122, 84, 2, rng, roof_kind="flat")
    elif v == 3:    # Scheibe quer mit Hubschrauberplattform, flache Funktionsbauten
        top = house(m, st, 6, 6, 218, 50, 8, rng, roof_kind="flat", entrance=False, fh=10)
        heli(170, 8, 216, 48, top)
        house(m, st, 6, 60, 110, 120, 2, rng, roof_kind="flat")
        house(m, st, 120, 60, 218, 120, 3, rng, roof_kind=fl)
    elif v == 4:    # Doppelhof
        house(m, st, 6, 6, 218, 34, 5, rng, roof_kind=fl, entrance=False)
        house(m, st, 6, 34, 34, 120, 5, rng, roof_kind=fl, entrance=False)
        house(m, st, 96, 34, 124, 120, 5, rng, roof_kind=fl, entrance=False)
        house(m, st, 190, 34, 218, 120, 5, rng, roof_kind=fl)
        tree(m, 64, 76, 1, kind="round", size=1.2, rng=rng)
        tree(m, 156, 76, 1, kind="round", size=1.2, rng=rng)
    else:           # Terrassen: gestaffelte Bettenhaeuser
        house(m, st, 6, 6, 218, 40, 7, rng, roof_kind="flat", entrance=False)
        house(m, st, 6, 40, 218, 76, 5, rng, roof_kind=fl, entrance=False)
        top = house(m, st, 6, 76, 160, 112, 3, rng, roof_kind="flat")
        heli(170, 80, 216, 120, 1)
    _ramp(m, 6, 128, 50, 154)
    cross_sign(m, 60, H - 1, 18, size=10)
    lamp_post(m, 100, H - 3, 1, h=18)
    return m, {"w": 7, "h": 5, "entrance": [W // 2, H], "delivery": [30, H], "height": 130, "blink": [30, H - 6]}


def mvz(v, st, seed):
    """KH-04 Medizinisches Versorgungszentrum 3x3: Praxisgebaeude, Apotheke, Parkplaetze."""
    rng = random.Random(seed)
    W, H = 3 * T, 3 * T
    m = Model(W, H, 70)
    ground(m, st, W, H, seed)
    fl = "flat" if st != "gruen" else "green"
    if v == 0:
        house(m, st, 6, 6, 90, 50, 3, rng)
        car(m, 20, 70, 1, color="blue")
    elif v == 1:
        house(m, st, 6, 6, 50, 90, 2, rng, roof_kind=fl)
        house(m, st, 52, 30, 90, 70, 1, rng)
    elif v == 2:
        house(m, st, 20, 10, 76, 66, 4, rng, roof_kind="flat")
        canopy(m, 20, 70, 76, 86, 12, roof_mat="pub_green")
    elif v == 3:
        house(m, st, 6, 6, 90, 36, 2, rng, roof_kind=fl, entrance=False)
        house(m, st, 6, 36, 46, 80, 2, rng)
        tree(m, 70, 64, 1, kind="round", size=0.9, rng=rng)
    elif v == 4:
        house(m, st, 30, 6, 90, 60, 3, rng, roof_kind="gable")
        house(m, st, 6, 30, 30, 60, 1, rng, roof_kind="flat", entrance=False)
        car(m, 50, 76, 1, color="red")
    else:
        house(m, st, 6, 20, 70, 70, 2, rng, roof_kind="flat")
        house(m, st, 70, 6, 90, 70, 3, rng, roof_kind="flat", entrance=False)
    cross_sign(m, 8, H - 1 - 20, 12, size=7) if v in (1, 3) else cross_sign(m, 60, H - 1 - 20, 12, size=7)
    return m, {"w": 3, "h": 3, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 60}


TYPES.update({"rescue_center": ("rd2", 4, 3), "general_hospital": ("kh2", 6, 4), "central_clinic": ("kh3", 7, 5), "mvz": ("kh4", 3, 3)})
BUILDERS.update({"rescue_center": rescue_center, "general_hospital": general_hospital, "central_clinic": central_clinic, "mvz": mvz})


# ------------------------------------------------------------------ Auftrag 22 Phase 2: Betriebshof der Abfallwirtschaft 4x3
def _parked_truck(m, x0, y0, along_x=True):
    """Abgestellter Muellwagen von oben: orange Pressaufbau, weisse Kabine."""
    if along_x:
        m.box(x0, y0, 1, x0 + 30, y0 + 12, 14, M("pub_orange"))
        m.box(x0 + 30, y0, 1, x0 + 38, y0 + 12, 12, M("pub_white"))
        m.box(x0 + 33, y0 + 4, 12, x0 + 35, y0 + 8, 14, M("pub_yellow"))
    else:
        m.box(x0, y0, 1, x0 + 12, y0 + 30, 14, M("pub_orange"))
        m.box(x0, y0 + 30, 1, x0 + 12, y0 + 38, 12, M("pub_white"))
        m.box(x0 + 4, y0 + 33, 12, x0 + 8, y0 + 35, 14, M("pub_yellow"))


def _bin_row(m, x0, y, n, cols=("frame_dark", "pub_green", "pub_yellow", "blue")):
    """Reihe Ersatztonnen (240-l-Tonnen) im Hof."""
    for i in range(n):
        x = x0 + i * 7
        m.box(x, y, 1, x + 5, y + 6, 8, M(cols[i % len(cols)]))


def waste_depot(v, st, seed):
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 50)
    ground(m, st, W, H, seed)
    d = "pub_orange"
    if v == 0:
        hall(m, st, 6, 6, 84, 46, 22, 3, d, rng, band="pub_orange")
        house(m, st, 92, 8, 122, 40, 2, rng)
        _parked_truck(m, 10, 58)
        _parked_truck(m, 54, 58)
    elif v == 1:
        house(m, st, 6, 6, 38, 40, 2, rng)
        canopy(m, 44, 6, 122, 46, 18, roof_mat="pub_orange" if st != "industrie" else "zinc")
        _parked_truck(m, 50, 12)
        _parked_truck(m, 50, 30)
        _bin_row(m, 8, 54, 10)
    elif v == 2:
        hall(m, st, 40, 8, 122, 52, 24, 4, d, rng, band="pub_orange", door_w=16)
        house(m, st, 6, 8, 34, 44, 1, rng)
        _parked_truck(m, 10, 60, along_x=True)
        _bin_row(m, 60, 66, 8)
    elif v == 3:
        hall(m, st, 6, 6, 70, 52, 20, 2, d, rng, band="pub_orange", door_w=18)
        canopy(m, 76, 6, 122, 40, 14, roof_mat="steel")      # Waschplatz
        _parked_truck(m, 80, 12)
        house(m, st, 80, 52, 122, 84, 1, rng)
    elif v == 4:
        canopy(m, 6, 6, 80, 40, 16, roof_mat="pub_orange" if st != "gruen" else "pub_green")
        _parked_truck(m, 10, 14)
        _parked_truck(m, 40, 14)
        house(m, st, 88, 6, 122, 44, 2, rng)
        _bin_row(m, 10, 58, 12)
    else:
        house(m, st, 6, 50, 44, 86, 2, rng)
        hall(m, st, 6, 6, 122, 42, 20, 5, d, rng, band="pub_orange", door_w=14)
        _parked_truck(m, 56, 54, along_x=False)
        _parked_truck(m, 74, 54, along_x=False)
    fence(m, 0, H - 2, 44, H, 1, h=6, mat_f="steel")
    fence(m, 84, H - 2, W, H, 1, h=6, mat_f="steel")
    greenery(m, st, [(124, 90)], rng)
    return m, {"w": 4, "h": 3, "entrance": [64, H], "delivery": [64, H], "height": 45}


TYPES.update({"waste_depot": ("aw", 4, 3)})
BUILDERS.update({"waste_depot": waste_depot})


# ------------------------------------------------------------------ Auftrag 22 Phase 2 Schritt 4: Muellverbrennungsanlage 5x4 (gemeinsam, neben der Deponie)
def incineration_plant(v, st, seed):
    """Brennhaus mit Schornstein (Rauch), Waermeverwaltung und Aschenhof; sechs Grundformen, vier Stile."""
    rng = random.Random(seed)
    W, H = 5 * T, 4 * T
    m = Model(W, H, 110)
    ground(m, st, W, H, seed)
    d = "pub_orange"

    def chim(x, y, s=12, h=66):
        """Schornstein: schlanker Schlauchturm mit orangem Kennband; gibt die Rauchposition in der Bildebene zurueck
        (Konvention wie Factory, industrial.py: [2(cx-cy), cx+cy-2h])."""
        tower(m, st, x, y, s, h, rng, cap="zinc")
        m.box(x, y + s - 2, h - 10, x + s, y + s, h - 6, M("pub_orange"))
        cx, cy = x + s // 2, y + s // 2
        return [2 * (cx - cy), cx + cy - 2 * h]

    sm = []
    if v == 0:      # Brennhaus quer, Schornstein hinten links, Verwaltung rechts, Aschenlager vorne
        hall(m, st, 6, 18, 120, 66, 24, 4, d, rng, band="pub_orange", door_w=16)
        house(m, st, 126, 18, 156, 60, 2, rng)
        sm = chim(20, 74, 12, 70)
        heap(m, 70, 76, 104, 100, 6, "zinc")
        _parked_truck(m, 6, 74)
    elif v == 1:    # L-Anlage: Halle vorne, Ofenfluegel rechts, zwei Schornsteine
        hall(m, st, 6, 60, 110, 108, 24, 4, d, rng, band="pub_orange")
        hall(m, st, 112, 60, 156, 108, 20, 2, d, rng, roof_kind="flat", door_w=16)
        house(m, st, 6, 18, 60, 54, 2, rng)
        sm = chim(66, 20, 12, 72)
        chim(96, 20, 10, 60)
        heap(m, 18, 30, 54, 50, 5, "zinc")
    elif v == 2:    # Zwei Hallenteile um einen mittigen Schornstein, Waermoelhaus vorne
        hall(m, st, 6, 44, 64, 108, 24, 3, d, rng, band="pub_orange")
        hall(m, st, 96, 44, 156, 108, 24, 3, d, rng, band="pub_orange")
        sm = chim(70, 60, 14, 78)
        house(m, st, 44, 6, 120, 36, 1, rng)
        _parked_truck(m, 126, 10)
    elif v == 3:    # Kompakt: Halle unten, zwei Geschosse drueber, Schornstein seitlich
        hall(m, st, 6, 52, 150, 108, 22, 5, d, rng, band="pub_orange", door_w=14)
        house(m, st, 30, 12, 124, 44, 2, rng, z0=25, entrance=False)
        sm = chim(132, 60, 12, 74)
        heap(m, 10, 16, 26, 40, 5, "zinc")
    elif v == 4:    # Halle hinten, freistehender Schornstein im Hof, Verwaltung rechts vorne
        hall(m, st, 6, 60, 156, 108, 26, 4, d, rng, band="pub_orange")
        sm = chim(24, 16, 12, 70)
        house(m, st, 92, 8, 156, 48, 2, rng)
        _parked_truck(m, 116, 56)
        heap(m, 58, 14, 88, 40, 5, "zinc")
    else:           # Lange Brennhauszeile, Schornstuenturm am Kopf, Aschenhof
        hall(m, st, 6, 30, 120, 80, 22, 5, d, rng, band="pub_orange", door_w=14)
        sm = chim(126, 34, 14, 80)
        house(m, st, 6, 8, 60, 26, 1, rng)
        heap(m, 70, 86, 110, 112, 6, "zinc")
        heap(m, 118, 84, 150, 112, 5, "sand")
    fence(m, 0, H - 2, 40, H, 1, h=6, mat_f="steel")
    fence(m, 110, H - 2, W, H, 1, h=6, mat_f="steel")
    greenery(m, st, [(152, 116)], rng)
    lamp_post(m, 4, H - 3, 1, h=16)
    return m, {"w": 5, "h": 4, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 96, "smoke": sm}


BUILDERS.update({"incineration_plant": incineration_plant})


# ------------------------------------------------------------------ Auftrag 22 Phase 4 Schritt 1: Wasserwerk 4x3 (je Stadt)
def _basin(m, x0, y0, x1, y1, h=4, rim="concrete"):
    """Offenes Filter-/Absetzbecken: Betonrand, Wasserflaeche mit leichtem Muster."""
    m.box(x0, y0, 1, x1, y1, 1 + h, M(rim))
    for x in range(x0 + 2, x1 - 2):
        for y in range(y0 + 2, y1 - 2):
            m.put(x, y, h, M("water" if (x + 2 * y) % 9 else "water2"))
    m.clear(x0 + 2, y0 + 2, h + 1, x1 - 2, y1 - 2, h + 2)


def _tank(m, cx, cy, r, h, mat_name="concrete"):
    """Runder Reinwasserbehaelter mit flachem Deckel und blauem Kennband."""
    for z in range(1, h + 1):
        for x in range(cx - r, cx + r + 1):
            for y in range(cy - r, cy + r + 1):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if d <= r * r:
                    m.put(x, y, z, M("pub_wblue" if h - 6 <= z <= h - 4 and d >= (r - 1) ** 2 else mat_name))
    m.box(cx - 1, cy - 1, h + 1, cx + 2, cy + 2, h + 3, M("steel_dark"))


def _mound(m, x0, y0, x1, y1, h):
    """Erdueberdeckter Hochbehaelter: Grashuegel mit Betontuer zur Hofseite."""
    for i in range(h):
        m.box(x0 + i, y0 + i, 1 + i, x1 - i, y1 - i, 2 + i, M("grass" if i else "grass3"))
    mx = (x0 + x1) // 2
    m.box(mx - 5, y1 - 2, 1, mx + 5, y1, 9, M("concrete"))
    m.box(mx - 2, y1 - 1, 1, mx + 2, y1, 7, M("pub_wblue"))


def waterworks(v, st, seed):
    """Wasserwerk: Filterhalle (Pumpen), Becken, Reinwasserbehaelter oder Huegel-Hochbehaelter, Brunnenhaeuschen; sechs Grundformen."""
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 60)
    ground(m, st, W, H, seed)
    d = "pub_wblue"
    if v == 0:      # Filterhalle hinten, zwei Becken vorne, Verwaltung rechts
        hall(m, st, 6, 6, 82, 44, 20, 2, d, rng, band="pub_wblue")
        house(m, st, 90, 8, 122, 40, 2, rng)
        _basin(m, 8, 54, 56, 86)
        _basin(m, 62, 54, 110, 86)
    elif v == 1:    # Rundbehaelter links, Halle rechts, Brunnenhaus vorne
        _tank(m, 26, 28, 18, 26)
        hall(m, st, 52, 6, 122, 50, 20, 2, d, rng, band="pub_wblue", door_w=12)
        house(m, st, 56, 60, 84, 86, 1, rng)
        _basin(m, 90, 58, 122, 88)
    elif v == 2:    # Grashuegel-Hochbehaelter hinten, Pumpenhaus vorne links
        _mound(m, 6, 4, 84, 48, 10)
        house(m, st, 90, 6, 122, 44, 2, rng)
        hall(m, st, 8, 56, 70, 88, 16, 1, d, rng, band="pub_wblue")
        _basin(m, 78, 56, 120, 88)
    elif v == 3:    # Zwei Rundbehaelter, flache Pumpenhalle dazwischen
        _tank(m, 20, 24, 14, 24)
        _tank(m, 108, 24, 14, 24)
        hall(m, st, 38, 6, 90, 46, 18, 2, d, rng, roof_kind="flat", band="pub_wblue")
        house(m, st, 8, 58, 50, 88, 1, rng)
        _basin(m, 60, 56, 120, 88)
    elif v == 4:    # Lange Filterhalle quer, Huegel rechts vorne
        hall(m, st, 6, 6, 122, 40, 22, 3, d, rng, band="pub_wblue", door_w=12)
        house(m, st, 6, 50, 40, 86, 2, rng)
        _mound(m, 60, 50, 122, 90, 8)
    else:           # Wasserturm-Variante: schlanker Turm mit Behaelterkopf, Halle, Becken
        tower(m, st, 12, 14, 12, 40, rng, cap="pub_wblue")
        _tank(m, 18, 20, 11, 50, "pub_white")
        hall(m, st, 44, 6, 122, 46, 20, 2, d, rng, band="pub_wblue")
        _basin(m, 44, 56, 122, 88)
    fence(m, 0, H - 2, 44, H, 1, h=6, mat_f="steel")
    fence(m, 84, H - 2, W, H, 1, h=6, mat_f="steel")
    greenery(m, st, [(124, 90), (4, 50)], rng)
    return m, {"w": 4, "h": 3, "entrance": [64, H], "delivery": [64, H], "height": 56}


TYPES.update({"waterworks": ("ww", 4, 3)})
BUILDERS.update({"waterworks": waterworks})


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


# ------------------------------------------------------------------ Auftrag 22 Phase 6 Schritt 1: Bahnhof (Empfangsgebaeude)
def _clock(m, x, y_face, z):
    """Bahnhofsuhr: weisses Zifferblatt mit dunklem Rand auf der Suedfassade."""
    m.box(x - 3, y_face, z - 3, x + 4, y_face + 1, z + 4, M("frame_dark"))
    m.box(x - 2, y_face, z - 2, x + 3, y_face + 1, z + 3, M("pub_white"))
    m.box(x, y_face, z, x + 1, y_face + 1, z + 2, M("frame_dark"))


def _station_sign(m, x0, x1, y_face, z):
    """Blaues Bahnhofsschild mit weissem Rand ueber dem Eingang."""
    m.box(x0, y_face, z, x1, y_face + 1, z + 5, M("pub_white"))
    m.box(x0 + 1, y_face, z + 1, x1 - 1, y_face + 1, z + 4, M("pub_wblue"))


def _station_body(m, st, v, rng, L, D):
    """Empfangsgebaeude in einem L x D-Rahmen (lange Seite x). Rueckgabe: Hoehe."""
    k = ST[st]
    mid = L // 2
    if v == 0:      # klassisches Empfangsgebaeude mit Mittelrisalit und Uhr
        house(m, st, 6, 8, L - 6, D - 6, 2, rng, roof_kind="gable" if st != "modern" else None)
        house(m, st, mid - 14, 4, mid + 14, D - 4, 3, rng, roof_kind="gable" if st != "modern" else None, entrance=False)
        _clock(m, mid, D - 4, 30)
        _station_sign(m, mid - 10, mid + 10, D - 4, 22)
        return 50
    if v == 1:      # langer Flachbau mit Vordach (Kleinstadtbahnhof)
        house(m, st, 4, 10, L - 4, D - 10, 1, rng)
        canopy(m, 8, D - 12, L - 8, D - 2, 12, roof_mat="steel" if st != "backstein" else "tile_terra")
        _station_sign(m, mid - 12, mid + 12, D - 10, 14)
        return 30
    if v == 2:      # Turmbahnhof: Uhrturm an der Ecke
        house(m, st, 4, 10, L - 20, D - 6, 2, rng)
        tower(m, st, L - 18, 8, 12, 46, rng, cap="pub_wblue")
        _clock(m, L - 12, 20, 36)
        _station_sign(m, 12, 40, D - 6, 22)
        return 60
    if v == 3:      # Glaskubus modern mit Kragdach
        block(m, 10, 8, 1, L - 10, D - 8, 22, k["glass"] if st == "modern" else k["wall"], base=k["base"], base_h=2)
        m.box(6, 4, 22, L - 6, D - 4, 24, M("concrete" if st != "gruen" else "pub_larch"))
        door(m, "s", mid - 4, 2, D - 8, w=8, h=10, mat_door=k["frame"])
        _station_sign(m, mid - 10, mid + 10, D - 4, 16)
        return 32
    if v == 4:      # Fachwerk-/Holzbahnhof mit Gueterschuppen
        house(m, st, 4, 8, mid + 6, D - 6, 2, rng, roof_kind="gable")
        hall(m, st, mid + 8, 10, L - 4, D - 8, 14, 1, "timber", rng, roof_kind="gable", door_w=12)
        _station_sign(m, 10, 34, D - 6, 22)
        return 44
    # v == 5: Haltepunkt mit Wartehalle und Fahrkartenautomat
    house(m, st, 4, 12, 40, D - 10, 1, rng)
    canopy(m, 46, 10, L - 6, D - 8, 13, roof_mat="glass_dark")
    for x in range(50, L - 10, 14):
        bench(m, x, D - 12, 1)
    m.box(L - 14, D - 14, 1, L - 11, D - 11, 9, M("pub_wblue"))
    _station_sign(m, 8, 34, D - 10, 14)
    return 28


def train_station(v, st, seed):
    """Empfangsgebaeude 4x2 (Gleis laeuft laengs der langen Seite)."""
    rng = random.Random(seed)
    W, H = 4 * T, 2 * T
    m = Model(W, H, 80)
    ground(m, st, W, H, seed)
    h = _station_body(m, st, v, rng, W, H)
    lamp_post(m, 2, H - 3, 1, h=16)
    lamp_post(m, W - 3, H - 3, 1, h=16)
    return m, {"w": 4, "h": 2, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": h}


def train_station_v(v, st, seed):
    """Dasselbe Empfangsgebaeude gedreht (2x4): Modell in x-Richtung bauen, dann x und y tauschen."""
    m0, meta = train_station(v, st, seed)
    W, H = 2 * T, 4 * T
    m = Model(W, H, 80)
    m.g = m0.g.transpose(1, 0, 2).copy()   # Suedfassade wird Ostfassade (beide sichtbar)
    return m, {"w": 2, "h": 4, "entrance": [W, H // 2], "delivery": [W, H // 2], "height": meta["height"]}


TYPES.update({"train_station": ("bf", 4, 2), "train_station_v": ("bfv", 2, 4)})
BUILDERS.update({"train_station": train_station, "train_station_v": train_station_v})


# ------------------------------------------------------------------ Auftrag 22 Phase 7 Schritt 1: Gueterbahnhof am Grosslager
def _containers(m, x0, y0, n, along_x=True):
    cols = ["pub_wblue", "pub_orange", "pub_green", "pub_red"]
    for i in range(n):
        c = cols[i % len(cols)]
        if along_x:
            m.box(x0 + i * 22, y0, 1, x0 + i * 22 + 20, y0 + 9, 10, M(c))
        else:
            m.box(x0, y0 + i * 22, 1, x0 + 9, y0 + i * 22 + 20, 10, M(c))


def freight_depot(v, st, seed):
    """Gueterhalle 4x2 am Ladegleis: Halle mit Rolltoren, Laderampe vorne, Container oder Paletten im Hof; sechs Grundformen."""
    rng = random.Random(seed)
    W, H = 4 * T, 2 * T
    m = Model(W, H, 60)
    ground(m, st, W, H, seed)
    if v in (0, 3):
        hall(m, st, 4, 6, 92, 52, 20, 3, "steel", rng, band="pub_yellow", door_w=14)
        house(m, st, 96, 8, 124, 40, 2, rng)
    elif v in (1, 4):
        hall(m, st, 4, 4, 124, 44, 22, 4, "steel", rng, band="pub_yellow", door_w=12, roof_kind="saw" if v == 1 else None)
        _containers(m, 8, 50, 4)
    else:
        canopy(m, 4, 6, 80, 50, 16, roof_mat="steel")
        _containers(m, 10, 14, 3)
        house(m, st, 86, 6, 124, 44, 1, rng)
    m.box(0, H - 6, 1, W, H, 4, M("concrete"))   # Laderampe zur Gleisseite
    return m, {"w": 4, "h": 2, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": 44}


def freight_depot_v(v, st, seed):
    m0, meta = freight_depot(v, st, seed)
    m = Model(2 * T, 4 * T, 60)
    m.g = m0.g.transpose(1, 0, 2).copy()
    return m, {"w": 2, "h": 4, "entrance": [2 * T, 2 * T], "delivery": [2 * T, 2 * T], "height": meta["height"]}


TYPES.update({"freight_depot": ("gb", 4, 2), "freight_depot_v": ("gbv", 2, 4)})
BUILDERS.update({"freight_depot": freight_depot, "freight_depot_v": freight_depot_v})


# ------------------------------------------------------------------ Auftrag 22 Phase 4 Schritt 2/4: Hochbehaelter und Klaeranlage
def water_tank(v, st, seed):
    """Hochbehaelter 2x2 (Druckzone): Grashuegel, Wasserturm, Rundbehaelter, Pilzturm; sechs Grundformen."""
    rng = random.Random(seed)
    W, H = 2 * T, 2 * T
    m = Model(W, H, 90)
    ground(m, st, W, H, seed)
    top = 30
    if v == 0:      # erdueberdeckter Behaelter mit Tuerbau
        _mound(m, 4, 4, 60, 56, 9)
        top = 12
    elif v == 1:    # klassischer Wasserturm: Schaft und breiter Kopf
        tower(m, st, 26, 26, 12, 46, rng, cap="pub_wblue")
        _tank(m, 32, 32, 14, 62, "pub_white")
        for z in range(1, 47):   # Kopf erst ab Schafthoehe: unten freiraeumen
            for x in range(18, 47):
                for y in range(18, 47):
                    if not (26 <= x < 38 and 26 <= y < 38):
                        m.put(x, y, z, 0)
        top = 66
    elif v == 2:    # niedriger Rundbehaelter mit Kennband
        _tank(m, 32, 30, 22, 22)
        top = 26
    elif v == 3:    # zwei Kammern nebeneinander
        _tank(m, 18, 30, 13, 20)
        _tank(m, 46, 30, 13, 20)
        top = 24
    elif v == 4:    # Pilz-Wasserturm aus Beton
        m.box(28, 28, 1, 36, 36, 44, M("concrete"))
        for z in range(44, 58):
            r = min(18, 4 + (z - 44) * 2)
            for x in range(32 - r, 32 + r):
                for y in range(32 - r, 32 + r):
                    if (x - 32) ** 2 + (y - 32) ** 2 <= r * r:
                        m.put(x, y, z, M("pub_wblue" if z in (52, 53) else "concrete"))
        top = 60
    else:           # Huegel mit kleinem Schieberhaus
        _mound(m, 2, 2, 46, 46, 8)
        house(m, st, 40, 40, 62, 62, 1, rng)
        top = 20
    fence(m, 0, H - 2, W, H, 1, h=5, mat_f="steel")
    return m, {"w": 2, "h": 2, "entrance": [W // 2, H], "delivery": [W // 2, H], "height": top}


def _clarifier(m, cx, cy, r):
    """Rundes Nachklaerbecken mit Raeumerbruecke."""
    for x in range(cx - r, cx + r + 1):
        for y in range(cy - r, cy + r + 1):
            d = (x - cx) ** 2 + (y - cy) ** 2
            if d <= r * r:
                m.box(x, y, 1, x + 1, y + 1, 5, M("concrete"))
                if d <= (r - 2) ** 2:
                    m.put(x, y, 4, M("water" if (x + y) % 7 else "water2"))
    m.box(cx - r, cy - 1, 5, cx + r, cy + 1, 7, M("steel"))
    m.box(cx - 1, cy - 1, 1, cx + 2, cy + 2, 8, M("steel_dark"))


def _digester(m, cx, cy, r, h):
    """Faulturm (Ei-Form angenaehert)."""
    for z in range(1, h):
        rr = int(r * (1.0 - abs(z - h * 0.45) / (h * 0.75)))
        rr = max(3, rr)
        for x in range(cx - rr, cx + rr + 1):
            for y in range(cy - rr, cy + rr + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= rr * rr:
                    m.put(x, y, z, M("pub_clad" if z % 12 else "steel_dark"))


def sewage_plant(v, st, seed):
    """Klaeranlage 4x3: Belebungsbecken, Nachklaerbecken, Faultuerme, Betriebsgebaeude; sechs Grundformen."""
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 60)
    ground(m, st, W, H, seed)
    d = "pub_wblue"
    def aeration(x0, y0, x1, y1):
        _basin(m, x0, y0, x1, y1)
        for x in range(x0 + 2, x1 - 2):
            for y in range(y0 + 2, y1 - 2):
                m.put(x, y, 4, M("pub_sludge" if (x * 3 + y) % 5 else "pub_sludge2"))
    if v == 0:      # zwei Belebungsbecken hinten, zwei Rundbecken vorne, Betriebshaus rechts
        aeration(6, 6, 56, 44)
        aeration(60, 6, 98, 44)
        _clarifier(m, 26, 70, 16)
        _clarifier(m, 64, 70, 16)
        house(m, st, 100, 8, 124, 40, 2, rng)
    elif v == 1:    # Faultuerme links, Becken rechts
        _digester(m, 16, 24, 11, 40)
        _digester(m, 16, 66, 11, 40)
        aeration(36, 6, 122, 44)
        _clarifier(m, 56, 70, 16)
        hall(m, st, 80, 54, 122, 88, 14, 1, d, rng, band="pub_wblue")
    elif v == 2:    # langes Becken quer, drei kleine Rundbecken
        aeration(6, 6, 122, 36)
        for i, cx in enumerate((22, 60, 98)):
            _clarifier(m, cx, 64, 13)
    elif v == 3:    # Halle hinten (Rechen/Sandfang), Becken vorne, Faulturm rechts
        hall(m, st, 6, 6, 88, 40, 18, 2, d, rng, band="pub_wblue")
        _digester(m, 108, 24, 12, 44)
        aeration(6, 50, 70, 88)
        _clarifier(m, 98, 70, 16)
    elif v == 4:    # kompakt: ein grosses Rundbecken, Becken und Haus
        _clarifier(m, 30, 30, 24)
        aeration(62, 6, 122, 52)
        house(m, st, 8, 60, 44, 88, 2, rng)
        _basin(m, 62, 58, 122, 88)
    else:           # Pflanzenklaeranlage: Schilfbeete und Haus
        for i in range(3):
            x0 = 6 + i * 40
            m.box(x0, 6, 1, x0 + 36, 60, 3, M("concrete"))
            for x in range(x0 + 2, x0 + 34):
                for y in range(8, 58):
                    m.put(x, y, 3, M("grass3" if (x + y) % 3 else "grass"))
        house(m, st, 8, 64, 48, 88, 1, rng)
        _basin(m, 56, 64, 122, 88)
    fence(m, 0, H - 2, 44, H, 1, h=6, mat_f="steel")
    fence(m, 84, H - 2, W, H, 1, h=6, mat_f="steel")
    greenery(m, st, [(124, 90), (4, 50)], rng)
    return m, {"w": 4, "h": 3, "entrance": [64, H], "delivery": [64, H], "height": 46}


TYPES.update({"water_tank": ("ht", 2, 2), "sewage_plant": ("ka", 4, 3)})
BUILDERS.update({"water_tank": water_tank, "sewage_plant": sewage_plant})
