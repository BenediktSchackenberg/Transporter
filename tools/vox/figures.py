"""Figuren als Voxelmodelle (Erwachsene, ca. 1,8 m). Blick nach +x, mittig in einem 14x14-Grundriss, Boden z = 1.
Hemd = "comp" (wird je Firma/Beruf eingefaerbt), Hose und Haut/Haare je Stil. Bildfolgen:
0 stehen, 1-4 gehen, 5-6 arbeiten (Werkzeug). Blickrichtungen ueber Model.rotated (0:+x, 1:+y, 2:-x, 3:-y)."""
from engine import Model, mat, M

S = 14
FRAMES = 7
STYLES = [  # Haut, Haar, Frisur, Hose
    ("skin_a", "hair_brown", "short", "trou_blue"),
    ("skin_d", "hair_black", "short", "trou_grey"),
    ("skin_b", "hair_blond", "long", "trou_dark"),
    ("skin_a", "hair_red", "cap", "trou_blue"),
    ("skin_c", "hair_grey", "short", "trou_dark"),
    ("skin_a", "hair_black", "bun", "trou_grey"),
]


def init():
    mat("skin_a", "#f0c8a0", noise=0.03, top=False)
    mat("skin_b", "#e0aa7c", noise=0.03, top=False)
    mat("skin_c", "#c98a5e", noise=0.03, top=False)
    mat("skin_d", "#7a4c32", noise=0.03, top=False)
    mat("hair_brown", "#5a3a22", noise=0.04, top=False)
    mat("hair_black", "#23201f", noise=0.04, top=False)
    mat("hair_blond", "#d8b45a", noise=0.04, top=False)
    mat("hair_red", "#a8472a", noise=0.04, top=False)
    mat("hair_grey", "#a9a7a3", noise=0.04, top=False)
    mat("trou_blue", "#3c5a8c", noise=0.04, top=False)
    mat("trou_grey", "#5b5f68", noise=0.04, top=False)
    mat("trou_dark", "#2e3139", noise=0.04, top=False)
    mat("shoe", "#25221f", noise=0.02, top=False)
    mat("eye", "#1a1a1e", noise=0.0, top=False)
    mat("tool", "#b8bec6", noise=0.03, top=False)
    mat("hat_cap", "#a33a33", noise=0.04, top=False)


def figure(style=0, frame=0, umbrella=False, only_umbrella=False):
    skin, hair, cut, trou = STYLES[style % len(STYLES)]
    m = Model(S, S, 40)
    cx, cy = S // 2, S // 2          # Mitte
    swing = [0, 2, 0, -2, 0, 0, 0][frame] if 1 <= frame <= 4 else 0
    if frame == 1:
        swing = 2
    elif frame == 3:
        swing = -2
    bob = 1 if frame in (2, 4) else 0
    work = frame in (5, 6)
    z0 = 1
    if not only_umbrella:
        # Beine (links y-, rechts y+), Schritt entlang x
        for side, sg in ((-1, 1), (1, -1)):
            ly = cy + (0 if side > 0 else -2)
            lx = cx - 1 + (swing * sg) // 1
            lift = 1 if (frame in (1, 3) and ((sg > 0) == (swing > 0))) else 0
            m.box(lx, ly, z0 + lift, lx + 2, ly + 2, z0 + lift + 1, M("shoe"))
            m.box(lx, ly, z0 + lift + 1, lx + 2, ly + 2, z0 + lift + 9, M(trou))
        zt = z0 + 9 + bob
        # Torso (Hemd = Firmenfarbe)
        m.box(cx - 1, cy - 3, zt, cx + 2, cy + 3, zt + 7, M("comp"))
        m.box(cx - 1, cy - 3, zt, cx + 2, cy + 3, zt + 1, M("comp_dark"))
        # Arme
        for side, sg in ((-1, 1), (1, -1)):
            ay = cy - 4 if side < 0 else cy + 3
            ax = cx + (swing * sg) // 2
            if work:
                reach = 3 if frame == 5 else -1
                m.box(cx + 1, ay, zt + 3, cx + 2 + reach + 1, ay + 1, zt + 7, M("comp"))
                m.box(cx + 1 + reach, ay, zt + 2, cx + 3 + reach, ay + 1, zt + 4, M(skin))
                if side > 0:
                    m.box(cx + 3 + reach, ay, zt + 3, cx + 7 + reach, ay + 1, zt + 4, M("tool"))
            else:
                m.box(ax, ay, zt + 3, ax + 2, ay + 1, zt + 7, M("comp"))
                m.box(ax, ay, zt + 1, ax + 2, ay + 1, zt + 3, M(skin))
        # Kopf
        zh = zt + 7
        m.box(cx - 1, cy - 2, zh, cx + 3, cy + 2, zh + 4, M(skin))
        m.put(cx + 2, cy - 1, zh + 2, M("eye"))
        m.put(cx + 2, cy, zh + 2, M("eye"))
        # Haare
        m.box(cx - 1, cy - 2, zh + 4, cx + 3, cy + 2, zh + 5, M(hair))
        m.box(cx - 2, cy - 2, zh + 1, cx - 1, cy + 2, zh + 4, M(hair))
        m.box(cx - 1, cy - 3, zh + 3, cx + 3, cy - 2, zh + 5, M(hair))
        m.box(cx - 1, cy + 2, zh + 3, cx + 3, cy + 3, zh + 5, M(hair))
        if cut == "long":
            m.box(cx - 2, cy - 2, zh - 4, cx - 1, cy + 2, zh + 1, M(hair))
        elif cut == "cap":
            m.box(cx - 1, cy - 2, zh + 4, cx + 4, cy + 2, zh + 5, M("hat_cap"))
        elif cut == "bun":
            m.box(cx - 2, cy - 1, zh + 5, cx, cy + 1, zh + 7, M(hair))
    if umbrella:
        zu = z0 + 25
        m.box(cx + 1, cy + 3, z0 + 12, cx + 2, cy + 4, zu, M("steel_dark"))
        import math
        for dx in range(-6, 8):
            for dy in range(-6, 7):
                d = math.hypot(dx - 0.5, dy)
                if d <= 6.5:
                    m.put(cx + 1 + dx, cy + 3 + dy, zu + (0 if d > 3.5 else 1), M("comp"))
    return m
