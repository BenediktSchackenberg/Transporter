"""Voxel models for the 240 buildable residential and commercial designs.

Each design has a stable silhouette/facade/yard combination. The six material worlds
match TownPlan's city forms; detail level changes landscaping, signage and roof use.
"""
import json
import random
from pathlib import Path

import numpy as np

from engine import M
from lib import tree, flowerbed, bike, bench, lamp_post
import residential as R
import buildings as B
import commercial as C
import industrial as I

DATA = Path(__file__).resolve().parents[2] / "config" / "building_designs.json"
STYLES = {
    "hafenort": ("brick", "brick2", "slate", "slate2", "blue"),
    "buchtenstadt": ("plaster_white", "plaster_cream", "zinc", "slate2", "blue"),
    "gartenstadt": ("plaster_sage", "plaster_cream", "tile_terra", "tile_terra2", "green_acc"),
    "hangstadt": ("sandstone", "plaster_grey", "slate", "slate2", "orange"),
    "flussstadt": ("plaster_cream", "plaster_sage", "tile_red", "tile_red2", "blue"),
    "marktort": ("plaster_ochre", "brick", "tile_red", "tile_red2", "red"),
}


def _base(d, seed):
    family = d["base"]
    v = d["variant"]
    if family == "einfamilienhaus":
        result = R.house((seed + v) % 8, seed)
    elif family == "doppelhaus":
        result = R.semi(seed)
    elif family == "mehrfamilienhaus":
        result = R.apartment(v % 2, seed)
    elif family == "stadtvilla":
        result = B.villa(1 + seed % 5)
    elif family == "hochhaus":
        result = R.highrise(v % 2)
    elif family in ("supermarkt", "baeckerei_laden", "getraenkemarkt", "moebelhaus", "technik_fachmarkt"):
        result = C.shop((seed + v) % 3, seed)
    elif family == "drogerie_laden":
        result = C.pharmacy(seed)
    elif family == "restaurant_neu":
        result = C.restaurant(seed)
    elif family == "buerogebaeude":
        result = R.office(v % 2, seed)
    elif family == "lager_werkstatt":
        result = I.warehouse(seed)
    else:
        result = R.apartment(v % 2, seed)  # Wohn- und Geschaeftshaus
    return result[0] if isinstance(result, tuple) else result


def _replace(m, original, names, target):
    replacement = M(target)
    for name in names:
        m.g[original == M(name)] = replacement


def make(d):
    seed = int(d["id"].split("_")[-1])
    rng = random.Random(seed * 997)
    m = _base(d, seed)
    wall, wall2, roof, roof2, accent = STYLES[d["style"]]
    original = m.g.copy()
    # A material world is visible from both street-facing facades and the roof.
    _replace(m, original, ["plaster_cream", "plaster_white", "plaster_rose", "plaster_sage", "plaster_ochre"], wall)
    _replace(m, original, ["brick", "brick2", "sandstone", "sandstone2", "concrete", "concrete2"], wall2)
    _replace(m, original, ["tile_red", "tile_terra", "slate", "zinc"], roof)
    _replace(m, original, ["tile_red2", "tile_terra2", "slate2"], roof2)
    w, h, _ = m.size
    v = d["variant"]
    # Street furniture and gardens are real voxels, not a recolored copy.
    if d["category"] == "wohnen":
        if v in (1, 3):
            flowerbed(m, 3, h - 7, min(w - 3, 17 + v * 5), h - 2, 1, rng=rng)
        if v in (2, 3):
            bike(m, min(w - 12, 13), h - 9, 1, color="red", face="y")
        if w >= 80 and v == 3:
            bench(m, w - 26, h - 10, 1, along="x")
        if v == 1 and w >= 80:
            tree(m, w - 10, h - 12, 1, kind="round", size=0.65, rng=rng)
    else:
        # A consistent city's accent is repeated in signs and entrance canopies.
        x0 = max(4, w // 3)
        x1 = min(w - 4, x0 + 15 + (seed % 4) * 3)
        z = 16 + seed % 5
        m.box(x0, h - 4, z, x1, h - 2, z + 4, M("accent"))
        m.box(x0, h - 3, z + 4, x1, h - 2, z + 5, M("frame_white"))
        if v:
            lamp_post(m, w - 8, h - 8, 1)
            flowerbed(m, 3, h - 7, min(w - 3, 19), h - 2, 1, rng=rng)
        m.box(w - 12, h - 12, 1, w - 10, h - 10, 23, M("steel"))
        m.box(w - 17, h - 13, 15, w - 6, h - 12, 23, M("accent"))
    # Individual entrance mosaic. Its eight stones encode the stable design ID;
    # this also keeps two similar massing variants distinguishable on the map.
    marker = seed + (128 if d["category"] == "gewerbe" else 0)
    for i in range(8):
        x = 3 + i * 5
        m.box(x, h - 1, 2, x + 3, h, 3, M("accent" if marker & (1 << i) else "paving"))
    return m, {"height": m.size[2]}


def specs():
    designs = json.loads(DATA.read_text(encoding="utf8"))["designs"]
    return {d["sprite"]: (lambda d=d: make(d)) for d in designs}
