"""Flughafen-Gebaeude (Auftrag 16, Etappe E1): Terminal, Kontrollturm, Hangar, Feuerwehrwache.
Kompakt gebaut (passen in die kleinen Blöcke des Kuestenorts wie der Rasterstadt); Stil wie industrial.py
(Betonbasis, flache Daecher, Glasfronten, Metall). Alle Modelle liegen mittig in ihrem Grundriss, Boden z=1,
und blicken nach Sueden (+y). Die Startbahn und das Vorfeld sind Boden, keine Gebaeude (ground.py runway/apron)."""
import math
import random

from engine import Model, mat, M
from lib import (Win, window, door, block, facade_windows, flat_roof, slab, lamp_post, container, car,
                 tree, bush, fence, paving_fn, grass_fn)

T = 32


def init():
    mat("term_glass", "#6f95b3", noise=0.03, emit="#ffd98a", top=False)
    mat("term_white", "#e9e6de", noise=0.04)
    mat("term_band", "#2f6fa8", noise=0.04)
    mat("tower_glass", "#8fc4e6", noise=0.02, emit="#bfe4ff", top=False)
    mat("hangar_s", "#9aa2ac", noise=0.05)
    mat("hangar_d", "#5a626c", noise=0.05)
    mat("fire_red", "#c0392f", noise=0.05)
    mat("fire_body", "#f0ece2", noise=0.04)
    # Flugzeug (Etappe E2 Fluganimation): zentraler Anker = Mitte unten (z=0), Blickrichtung +x
    mat("plane_livery", "#2f6fa8", noise=0.04)
    mat("plane_red", "#c23b33", noise=0.0, emit="#ff4a3a", top=False)   # Positionslicht (Emission)
    mat("plane_white_lamp", "#ffffff", noise=0.0, emit="#fff2c8", top=False)


def plane(seed=1):
    """Kleines Propellerflugzeug, blickt nach +x, mittig in einem quadratischen Grundriss (26,26), Boden z=0.
    Fuer die Fluganimation (AirView): wird 90-Grad-gedreht je Fahrtrichtung; Pivot = Modellunterkante Mitte.
    Schlankes Profil (E2): sechspixelige Kabine, dreipixelige Fluegel, niedrige Flosse – wirkt zierlich neben Huetten."""
    S = 52
    m = Model(S, S, 20)
    W, GLASS, DARK, LIV = M("white"), M("glass_dark"), M("black"), M("plane_livery")
    # Rumpf (schmal, Mittellinie y=26)
    m.box(6, 23, 3, 46, 29, 9, W)
    m.box(6, 23, 5, 46, 29, 6, LIV)          # Farbband
    # Leitwerk (Heck, kleines x)
    m.box(2, 24, 8, 10, 28, 16, W)            # Flosse (schmal und niedrig)
    m.box(2, 24, 12, 10, 28, 16, LIV)         # Flossenfarbband
    m.put(3, 26, 15, M("plane_red"))          # Positionslicht am Heck (blinkt bei Nacht)
    m.box(2, 16, 8, 11, 26, 10, W)            # Seitenleitwerk West
    m.box(2, 26, 8, 11, 36, 10, W)            # Seitenleitwerk Ost
    m.put(3, 17, 9, M("plane_white_lamp"))
    m.put(3, 35, 9, M("plane_red"))
    # Nase und Propeller (vorne, grosses x)
    m.box(44, 24, 2, 49, 28, 8, W)
    m.box(47, 25, 4, 49, 27, 6, DARK)         # Propellerhub
    # Cockpit
    m.box(30, 23, 8, 39, 29, 12, GLASS)
    # Tragfluegel (drei Voxel dick, spannen symmetrisch ueber y)
    m.box(18, 8, 4, 29, 44, 6, W)
    m.box(18, 8, 4, 29, 12, 6, LIV)           # Fluegeltipp West
    m.box(18, 40, 4, 29, 44, 6, LIV)          # Fluegeltipp Ost
    m.put(20, 9, 5, M("plane_white_lamp"))    # Positionslichter an den Tips
    m.put(20, 43, 5, M("plane_red"))
    # Fahrwerk (bietet den Fusspunkt z=0)
    for gx in (14, 34):
        m.box(gx, 22, 0, gx + 2, 25, 3, DARK)
        m.box(gx, 27, 0, gx + 2, 30, 3, DARK)
    return m, {"height": 16}


def terminal(seed=1):
    """Flughafenterminal 4x3: niedrige Empfangshalle mit groesser Glasfront, blauem Band und Rolltreppe."""
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 70)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    slab(m, 0, 0, W, 6, grass_fn(4))
    x0, y0, x1, y1 = 10, 8, 118, 60
    block(m, x0, y0, 1, x1, y1, 26, "plaster_grey", base="concrete", base_h=3)
    m.box(x0, y1 - 2, 26, x1, y1, 30, M("concrete2"))
    # breites Glasband im Erdgeschoss (Sued) mit Pfosten
    for u in range(x0 + 2, x1 - 14, 16):
        m.box(u, y1 - 1, 4, u + 14, y1, 20, M("term_glass"))
        m.box(u + 14, y1 - 1, 4, u + 15, y1, 20, M("frame_dark"))
    m.box(x0, y1 - 1, 20, x1, y1, 26, M("term_band"))
    flat_roof(m, x0, y0, x1, y1, 26, rng=rng, tech=True)
    # Eingang mit Vordach (Mitte Sued)
    door(m, "s", 64, 2, y1, w=6, h=12, canopy=True)
    # Rolltreppe/Glasaufgang rechts
    m.box(100, y1, 1, 118, y1 + 14, 4, M("concrete2"))
    for a in range(100, 118):
        for z in range(4, 22):
            if (a - 100) >= (z - 4):
                m.put(a, y1 + (z - 4) // 2, z, M("term_glass"))
    # Schild / Uhr
    m.box(52, y1 - 1, 28, 76, y1, 30, M("term_white"))
    lamp_post(m, 14, 70, 1, h=16)
    lamp_post(m, 114, 70, 1, h=16)
    for tx in (20, 108):
        tree(m, tx, 74, 1, kind="round", size=0.7, rng=rng)
    return m, {"w": 4, "h": 3, "entrance": [64, H], "delivery": [32, H], "height": 60, "lit": True}


def tower(seed=2):
    """Kontrollturm 2x2: schlanker Schaft, auskragende Kabine mit Glaskranz, Antenne mit Blinklicht."""
    rng = random.Random(seed)
    W, H = 2 * T, 2 * T
    m = Model(W, H, 96)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    cx, cy = W // 2, H // 2
    m.box(cx - 7, cy - 7, 1, cx + 7, cy + 7, 48, M("term_white"))
    m.box(cx - 6, cy - 6, 48, cx + 6, cy + 6, 52, M("steel_dark"))
    m.box(cx - 11, cy - 11, 52, cx + 11, cy + 11, 68, M("tower_glass"))
    m.box(cx - 13, cy - 13, 68, cx + 13, cy + 13, 72, M("steel"))
    m.box(cx - 1, cy - 1, 72, cx + 1, cy + 1, 84, M("steel_dark"))
    m.box(cx - 1, cy - 1, 84, cx + 1, cy + 1, 86, M("lamp_red"))
    m.box(cx - 13, cy - 13, 50, cx + 13, cy + 13, 52, M("term_band"))
    return m, {"w": 2, "h": 2, "entrance": [cx, H], "delivery": [cx, H], "height": 86, "blink": [32, 84]}


def hangar(seed=3):
    """Hangar 4x3: niedrige Schallungshalle mit groesserem Schindeltor nach Sued und Flachdach."""
    rng = random.Random(seed)
    W, H = 4 * T, 3 * T
    m = Model(W, H, 50)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    slab(m, 0, 0, W, 6, grass_fn(8))
    x0, y0, x1, y1 = 8, 8, 120, 64
    block(m, x0, y0, 1, x1, y1, 24, "steel", base="concrete", base_h=3)
    # Schindeltor (vertikale Profile)
    for u in range(x0 + 6, x1 - 6, 10):
        m.box(u, y1 - 1, 2, u + 9, y1, 24, M("hangar_s") if (u // 10) % 2 == 0 else M("hangar_d"))
    m.box(x0 + 6, y1 - 1, 24, x1 - 6, y1, 27, M("steel_dark"))
    flat_roof(m, x0, y0, x1, y1, 24, rng=rng, tech=True)
    # kleines Nebenbuero
    m.box(x0 + 6, y1, 1, x0 + 34, y1 + 18, 14, M("plaster_white"))
    window(m, "s", x0 + 12, 4, y1 + 18, Win(10, 8, frame="frame_dark", lit=0.4, lit_mat="glass_lit"), rng)
    container(m, 100, 70, 1, "red", "x")
    lamp_post(m, 8, 70, 1, h=14)
    return m, {"w": 4, "h": 3, "entrance": [64, H], "delivery": [32, H], "height": 40}


def fire(seed=4):
    """Flughafenfeuerwache 3x2: rot-weiße Halle mit doppeltuerigem Tor und Blaulicht. Laeuft im Ausbau auf mehrere Fahrzeuge auf."""
    rng = random.Random(seed)
    W, H = 3 * T, 2 * T
    m = Model(W, H, 44)
    slab(m, 0, 0, W, H, paving_fn(8, "concrete", "concrete2"))
    x0, y0, x1, y1 = 8, 6, 88, 52
    block(m, x0, y0, 1, x1, y1, 22, "fire_body", base="concrete", base_h=3)
    m.box(x0, y1 - 1, 22, x1, y1, 25, M("fire_red"))
    # groesse Doppel-Tor (Sued)
    for u in range(x0 + 8, x1 - 8, 8):
        m.box(u, y1 - 1, 2, u + 7, y1, 22, M("fire_red"))
    m.box(x0 + 8, y1 - 1, 22, x1 - 8, y1, 24, M("steel_dark"))
    flat_roof(m, x0, y0, x1, y1, 22, rng=rng, tech=True)
    m.box(50, y1 - 1, 26, 62, y1, 30, M("fire_body"))
    m.box(54, y1, 27, 58, y1 + 4, 31, M("beacon_blue"))
    lamp_post(m, 88, 52, 1, h=12)
    return m, {"w": 3, "h": 2, "entrance": [48, H], "delivery": [48, H], "height": 34, "blink": [56, 30]}
