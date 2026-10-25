"""Requisiten: Baeume, Laternen, Baenke, Ampeln, Baustellenabsperrung, Fahne, Ladungskisten, Einrichtungs-Absperrung.
Alle Modelle: mittig im Grundriss (32x32 bzw. kleiner), Boden z = 1 (ohne Bodenplatte)."""
import random

from engine import Model, mat, M
from lib import tree, bush, bench as _bench, lamp_post as _lamp, _blob

T = 32


def init():
    mat("cone", "#e8742a", noise=0.03)
    mat("tl_red_on", "#ff4a3a", noise=0.0, emit="#ff3a2a", top=False)
    mat("tl_green_on", "#58ff8a", noise=0.0, emit="#44f07a", top=False)
    mat("tl_off", "#2a2c32", noise=0.0, top=False)
    mat("cardboard", "#b88a58", noise=0.06)
    mat("tape", "#d8c48a", noise=0.02)
    mat("crate_green", "#5f9a46", noise=0.06)
    mat("bottle_b", "#3a78b8", noise=0.04)
    mat("bottle_g", "#4f9a4a", noise=0.04)
    mat("screen", "#7ec8e8", noise=0.02, top=False)
    mat("brick_s", "#b0603f", noise=0.07)
    mat("orange_m", "#e0802a", noise=0.04)


def _base(h=70):
    return Model(T, T, h)


def tree_round(seed=1):
    m = _base(80)
    tree(m, 15, 15, 1, kind="round", size=1.4, rng=random.Random(seed))
    return m


def tree_conifer(seed=2):
    m = _base(90)
    tree(m, 15, 15, 1, kind="conifer", size=1.15, rng=random.Random(seed))
    return m


def tree_blossom(seed=3):
    m = _base(80)
    tree(m, 15, 15, 1, kind="blossom", size=1.35, rng=random.Random(seed))
    return m


def lamp():
    m = _base(40)
    _lamp(m, 15, 15, 1, h=26)
    return m


def bench():
    m = _base(12)
    _bench(m, 12, 15, 1, along="x", length=9)
    return m


def hedge_bush():
    m = _base(16)
    bush(m, 15, 15, 1, 6, flowers="flower_p", rng=random.Random(4))
    return m


def traffic_light(state="red"):
    m = _base(40)
    m.box(14, 14, 1, 16, 16, 30, M("frame_dark"))
    m.box(12, 12, 28, 18, 18, 36, M("frame_dark"))
    lamp_r = "tl_red_on" if state == "red" else "tl_off"
    lamp_g = "tl_green_on" if state == "green" else "tl_off"
    m.box(13, 18, 33, 17, 19, 35, M(lamp_r))
    m.box(13, 18, 29, 17, 19, 31, M(lamp_g))
    m.box(18, 13, 33, 19, 17, 35, M(lamp_r))
    m.box(18, 13, 29, 19, 17, 31, M(lamp_g))
    return m


def roadwork():
    m = _base(24)
    for x in range(2, 30, 8):
        m.box(x, 14, 4, x + 6, 16, 6, M("white"))
        m.box(x, 14, 6, x + 6, 16, 8, M("red"))
        m.box(x, 14, 1, x + 1, 16, 4, M("frame_dark"))
        m.box(x + 5, 14, 1, x + 6, 16, 4, M("frame_dark"))
    for cx, cy in ((6, 22), (24, 8), (16, 24)):
        m.box(cx - 2, cy - 2, 1, cx + 3, cy + 3, 2, M("black"))
        m.box(cx - 1, cy - 1, 2, cx + 2, cy + 2, 6, M("cone"))
        m.box(cx, cy, 6, cx + 1, cy + 1, 9, M("cone"))
        m.box(cx - 1, cy - 1, 4, cx + 2, cy + 2, 5, M("white"))
    return m


def flag():
    m = Model(16, 16, 50)
    m.box(7, 7, 1, 9, 9, 40, M("steel"))
    m.box(9, 7, 28, 22 if False else 15, 8, 38, M("comp"))
    m.box(9, 8, 28, 15, 9, 38, M("comp_dark"))
    m.box(6, 6, 40, 10, 10, 42, M("yellow"))
    return m


def site_fence():
    """Absperrung einer Baustelle (eine Zelle): Gitter-Elemente entlang der Zellkante."""
    m = _base(12)
    for x in range(0, T, 8):
        m.box(x, 0, 1, x + 7, 1, 2, M("steel"))
        m.box(x, 0, 6, x + 7, 1, 7, M("steel"))
        m.box(x, 0, 1, x + 1, 1, 8, M("steel_dark"))
        m.box(x + 2, 0, 2, x + 6, 1, 6, M("orange") if (x // 8) % 2 else M("white"))
    return m


def smoke_puff():
    m = Model(10, 10, 10)
    _blob(m, 5, 5, 5, 3.5, ["white", "plaster_grey", "plaster_white"], random.Random(1))
    return m


# ------------------------------------------------------------------ Ladungskisten (klein, 14x14x12)
def crate(cargo):
    m = Model(14, 14, 16)
    c = 3
    if cargo == "pakete":
        for k, (x, y, w, h) in enumerate(((1, 1, 6, 5), (7, 2, 6, 4), (3, 7, 7, 6))):
            m.box(x, y, 1, x + w, y + 6, 1 + h, M("cardboard"))
            m.box(x, y + 2, 1 + h - 1, x + w, y + 4, 1 + h, M("tape"))
    elif cargo == "lebensmittel":
        m.box(1, 1, 1, 13, 13, 6, M("crate_green"))
        for k in range(14):
            m.put(2 + (k * 5) % 10, 2 + (k * 3) % 10, 6, M(["flower_r", "leaf3", "flower_y", "orange"][k % 4]))
            m.put(3 + (k * 7) % 9, 3 + (k * 5) % 9, 7, M(["flower_r", "leaf3", "orange"][k % 3]))
    elif cargo == "medikamente":
        m.box(1, 2, 1, 13, 12, 9, M("white"))
        m.box(6, 1, 4, 8, 2, 8, M("red"))
        m.box(5, 1, 5, 9, 2, 7, M("red"))
    elif cargo == "getraenke":
        m.box(1, 1, 1, 13, 13, 4, M("blue"))
        for x in range(2, 13, 3):
            for y in range(2, 13, 3):
                m.box(x, y, 4, x + 2, y + 2, 9, M("bottle_b" if (x + y) % 2 else "bottle_g"))
                m.put(x, y, 9, M("white"))
    elif cargo == "elektronik":
        m.box(1, 2, 1, 13, 12, 10, M("steel"))
        m.box(2, 12, 3, 12, 13, 9, M("screen"))
    elif cargo == "moebel":
        m.box(1, 3, 1, 13, 11, 5, M("wood"))
        m.box(2, 4, 5, 6, 10, 12, M("timber"))
        m.box(8, 4, 5, 12, 10, 8, M("wood"))
    elif cargo == "baustoffe":
        for k in range(3):
            m.box(1, 1 + k * 4, 1, 13, 4 + k * 4, 5 + (k % 2), M("brick_s"))
    elif cargo == "maschinenteile":
        m.box(1, 1, 1, 13, 13, 5, M("steel_dark"))
        m.box(3, 3, 5, 11, 11, 11, M("orange_m"))
        m.box(6, 6, 11, 8, 8, 14, M("steel"))
    else:   # container
        m.box(0, 3, 1, 14, 11, 10, M("red"))
        for x in range(1, 14, 2):
            m.box(x, 3, 2, x + 1, 4, 9, M("black"))
    return m
