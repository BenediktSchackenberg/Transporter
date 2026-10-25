"""Erzeugt alle isometrischen Grafiken nach assets/iso/ und schreibt manifest.json.
Aufruf (aus dem Projektordner):  python tools/build_iso.py [ground buildings facilities vehicles figures props]
Ohne Argumente wird alles gebaut. Beschreibung der Projektion und Konventionen: ART_DIRECTION.md."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "vox"))

import numpy as np
from PIL import Image

import engine
import lib
import ground as G
import vehicles as V
import figures as F
import props as PR
import facilities as FA
import residential as R
import buildings as B
import commercial as C
import industrial as I

OUT = os.path.join(HERE, "..", "assets", "iso")
os.makedirs(OUT, exist_ok=True)
MANIFEST_PATH = os.path.join(OUT, "manifest.json")
manifest = json.load(open(MANIFEST_PATH, encoding="utf8")) if os.path.exists(MANIFEST_PATH) else {}

DEFAULT_TINT = (96, 118, 150)     # Firmenfarbe fuer neutrale Gebaeude (Maske wird eingebacken)
GROUND_CELL = (128, 72)
GROUND_ORIGIN = (64, 6)


def init():
    lib.init_materials()
    G.init()
    V.init()
    F.init()
    PR.init()


def bake(im, mask, tint):
    """Firmenfarbmaske in das Farbbild einbacken (fuer neutrale Gebaeude)."""
    c = np.array(im).astype(float)
    a = np.array(mask).astype(float) / 255.0
    sel = a[:, :, 3] > 0.5
    c[sel, :3] = np.array(tint, dtype=float)[None, :] * a[sel, :3]
    return Image.fromarray(np.clip(c, 0, 255).astype("uint8"), "RGBA")


def save_result(name, r, keep_mask=False, tint=DEFAULT_TINT, lit=True, top=True):
    """Schreibt <name>.png (+ _lit, _top, _mask) und gibt die Manifest-Daten zurueck."""
    color = r["color"]
    if "mask" in r and not keep_mask:
        color = bake(color, r["mask"], tint)
    color.save(os.path.join(OUT, name + ".png"))
    if lit and r["lit"].getbbox():
        r["lit"].save(os.path.join(OUT, name + "_lit.png"))
    if top:
        r["top"].save(os.path.join(OUT, name + "_top.png"))
    if keep_mask and "mask" in r:
        r["mask"].save(os.path.join(OUT, name + "_mask.png"))
    return {"anchor": list(r["anchor"]), "size": list(r["size"]), "lit": bool(r["lit"].getbbox()), "mask": bool(keep_mask and "mask" in r)}


def render(m, **kw):
    if isinstance(m, tuple):
        m = m[0]
    return engine.render(m, **kw)


# ------------------------------------------------------------------ Boden
def build_ground():
    names = ["grass0", "grass1", "grass2", "park0", "park1", "gravel", "sidewalk", "plaza", "concrete", "quay", "sand", "field", "crop"]
    models = [G.grass(0, 1), G.grass(1, 2), G.grass(2, 3), G.park(0, 1), G.park(1, 2), G.gravel(), G.sidewalk(), G.plaza(), G.concrete(),
              G.quay(), G.sand(), G.field(), G.crop()]
    for f in range(4):
        names.append("water%d" % f)
        models.append(G.water(f))
    names += ["rail_h", "rail_v", "parking"]
    models += [G.rail(True), G.rail(False), G.parking()]
    for mask in range(16):
        names.append("road%d" % mask)
        models.append(G.road(mask))
    cols = 12
    rows = (len(names) + cols - 1) // cols
    atlas = Image.new("RGBA", (cols * GROUND_CELL[0], rows * GROUND_CELL[1]), (0, 0, 0, 0))
    tiles = {}
    for i, (n, m) in enumerate(zip(names, models)):
        r = engine.render(m, outline=False, ground_shadow=False, ao=False, shadow_len=0)
        ax, ay = r["anchor"]
        cell = Image.new("RGBA", GROUND_CELL, (0, 0, 0, 0))
        cell.paste(r["color"], (GROUND_ORIGIN[0] - ax, GROUND_ORIGIN[1] - ay), r["color"])
        c, rr = i % cols, i // cols
        atlas.paste(cell, (c * GROUND_CELL[0], rr * GROUND_CELL[1]))
        tiles[n] = [c, rr]
    atlas.save(os.path.join(OUT, "ground.png"))
    manifest["ground"] = {"cell": list(GROUND_CELL), "origin": list(GROUND_ORIGIN), "tiles": tiles, "cols": cols}
    print("Boden:", len(names), "Kacheln")


# ------------------------------------------------------------------ Gebaeude
# Anzahl Ausfuehrungen je Bauart (Seed-Varianten): mehr Individualitaet in der Stadt
VARIANTS = {"house": 6, "apartment": 4, "office": 3, "semi": 4, "villa": 4, "shop": 4}


def building_specs():
    """Spritename -> Funktion. Namen entsprechen CityGenerator.TYPES."""
    s = {}
    for v in range(8):
        s["house%d" % v] = (lambda v=v: R.house(v, 1 + v))
        for k in range(1, VARIANTS["house"]):   # weitere Haeuser derselben Bauart: andere Farben, Dachfarben, Gaerten
            s["house%ds%d" % (v, k)] = (lambda v=v, k=k: R.house(v, 1 + v + 7 * k))
    for v in range(2):
        s["apartment%d" % v] = (lambda v=v: R.apartment(v, 1 + v))
        s["office%d" % v] = (lambda v=v: R.office(v, 1 + v))
        for k in range(1, VARIANTS["apartment"]):
            s["apartment%ds%d" % (v, k)] = (lambda v=v, k=k: R.apartment(v, 1 + v + 5 * k))
        for k in range(1, VARIANTS["office"]):
            s["office%ds%d" % (v, k)] = (lambda v=v, k=k: R.office(v, 1 + v + 5 * k))
    s["semi"] = lambda: R.semi(1)
    for k in range(1, VARIANTS["semi"]):
        s["semis%d" % k] = (lambda k=k: R.semi(1 + 3 * k))
    for k in range(3, 3 + VARIANTS["villa"]):
        s["villa%d" % k] = (lambda k=k: B.villa(k))
    s["highrise0"] = lambda: R.highrise(0)
    s["highrise1"] = lambda: R.highrise(1)
    s["school"] = lambda: R.school(1)
    s["kindergarten"] = lambda: R.kindergarten(1)
    s["villa"] = lambda: B.villa(1)
    s["villa1"] = lambda: B.villa(2)
    for v in range(3):
        s["shop%d" % v] = (lambda v=v: C.shop(v, 1 + v))
        for k in range(1, VARIANTS["shop"]):
            s["shop%ds%d" % (v, k)] = (lambda v=v, k=k: C.shop(v, 1 + v + 4 * k))
    s["pharmacy"] = lambda: C.pharmacy(1)
    s["restaurant"] = lambda: C.restaurant(1)
    s["bank"] = lambda: C.bank(1)
    s["clinic"] = lambda: C.clinic(1)
    s["job_board"] = lambda: C.job_board(1)
    s["staffing"] = lambda: C.staffing(1)
    s["gas_station"] = lambda: C.gas_station(1)
    s["dealer"] = lambda: C.dealer(1)
    s["factory"] = lambda: I.factory(1)
    s["warehouse"] = lambda: I.warehouse(1)
    s["farm"] = lambda: I.farm(1)
    s["port_office"] = lambda: I.port_office(1)
    s["freight_shed"] = lambda: I.freight_shed(1)
    s["depot"] = lambda: I.depot(1)
    s["containers"] = lambda: I.containers(1)
    s["crane"] = lambda: I.crane(1)
    s["fountain"] = lambda: I.fountain(1)
    s["construction"] = lambda: I.construction(1)
    s["airport_cargo"] = lambda: I.airport_cargo(1)
    s["workshop"] = lambda: FA.make("werkstatt", 4)
    return s


def build_buildings(only=None):
    out = manifest.setdefault("buildings", {})
    for name, fn in building_specs().items():
        if only and name not in only:
            continue
        res = fn()
        meta = res[1] if isinstance(res, tuple) else {}
        model = res[0] if isinstance(res, tuple) else res
        r = engine.render(model)
        keep = name == "depot"
        info = save_result("b_" + name, r, keep_mask=keep)
        info["w"] = model.size[0] // 32
        info["h"] = model.size[1] // 32
        info["height"] = meta.get("height", model.size[2])
        if "smoke" in meta:
            info["smoke"] = meta["smoke"]
        if name in ("crane",):
            info["blink"] = True
        out[name] = info
    print("Gebaeude:", len(out))


# ------------------------------------------------------------------ Einrichtungen
def build_facilities():
    out = manifest.setdefault("facilities", {})
    for typ, (w, h) in FA.SIZES.items():
        m = FA.make(typ, 3)
        for rot in ((0, 1) if w != h else (0,)):
            mm = m if rot == 0 else m.rotated(1)
            r = engine.render(mm)
            name = "fac_%s%s" % (typ, "" if rot == 0 else "_r")
            info = save_result(name, r, keep_mask=True)
            info["w"] = mm.size[0] // 32
            info["h"] = mm.size[1] // 32
            out[name] = info
    print("Einrichtungen:", len(out))


# ------------------------------------------------------------------ Fahrzeuge
def build_vehicles():
    out = manifest.setdefault("vehicles", {})
    for name in ("cargobike", "van", "transporter", "reefer", "truck", "semi"):
        base = getattr(V, name)()
        n = base.size[0]
        for k in range(4):
            r = engine.render(base.rotated(k), shadow_len=0, ground_shadow=False)
            info = save_result("v_%s_%d" % (name, k), r, keep_mask=True, top=False)
            info["pivot"] = [r["anchor"][0], r["anchor"][1] + n]   # (cx, cy, z=0) mit cx = cy = n / 2 -> y-Versatz = n
            out["%s_%d" % (name, k)] = info
    for cname in V.CAR_COLORS:
        base = V.car(cname)
        n = base.size[0]
        for k in range(4):
            r = engine.render(base.rotated(k), shadow_len=0, ground_shadow=False)
            info = save_result("v_car_%s_%d" % (cname.split("_")[1], k), r, top=False)
            info["pivot"] = [r["anchor"][0], r["anchor"][1] + n]
            out["car_%s_%d" % (cname.split("_")[1], k)] = info
    print("Fahrzeuge:", len(out))


# ------------------------------------------------------------------ Figuren
def build_figures():
    out = manifest.setdefault("figures", {})
    n = F.S
    for style in range(len(F.STYLES)):
        items = []
        for k in range(4):
            for f in range(F.FRAMES):
                r = engine.render(F.figure(style, f).rotated(k), shadow_len=0, ground_shadow=False, ao=False)
                items.append((k, f, r))
        sheet = _sheet(items, n, "fig_%d" % style, F.FRAMES, 4, keep_mask=True)
        out["fig_%d" % style] = sheet
    items = []
    for k in range(4):
        r = engine.render(F.figure(0, 0, umbrella=True, only_umbrella=True).rotated(k), shadow_len=0, ground_shadow=False, ao=False)
        items.append((k, 0, r))
    out["fig_umbrella"] = _sheet(items, n, "fig_umbrella", 1, 4, keep_mask=True)
    print("Figuren:", len(out))


def _sheet(items, n, name, cols, rows, keep_mask):
    """Packt Einzelbilder (Zeile = Richtung, Spalte = Bild) in ein Blatt mit gemeinsamem Pivot."""
    piv = [(r["anchor"][0], r["anchor"][1] + n) for _, _, r in items]
    left = max(p[0] for p in piv)
    up = max(p[1] for p in piv)
    right = max(r["size"][0] - p[0] for (_, _, r), p in zip(items, piv))
    down = max(r["size"][1] - p[1] for (_, _, r), p in zip(items, piv))
    cw, ch = left + right, up + down
    color = Image.new("RGBA", (cw * cols, ch * rows), (0, 0, 0, 0))
    mask = Image.new("RGBA", (cw * cols, ch * rows), (0, 0, 0, 0))
    for (k, f, r), p in zip(items, piv):
        pos = (f * cw + left - p[0], k * ch + up - p[1])
        color.paste(r["color"], pos, r["color"])
        if "mask" in r:
            mask.paste(r["mask"], pos, r["mask"])
    color.save(os.path.join(OUT, name + ".png"))
    mask.save(os.path.join(OUT, name + "_mask.png"))
    return {"cell": [cw, ch], "pivot": [left, up], "hframes": cols, "vframes": rows}


# ------------------------------------------------------------------ Requisiten
def build_props():
    out = manifest.setdefault("props", {})

    def prop(name, model, pivot_xy=(16, 16), keep_mask=False, lit=True):
        r = engine.render(model, shadow_len=40, ground_shadow=False)
        info = save_result(name, r, keep_mask=keep_mask, lit=lit)
        info["pivot"] = [r["anchor"][0], r["anchor"][1] + pivot_xy[0] + pivot_xy[1]]
        info["pivot"][0] += 2 * (pivot_xy[0] - pivot_xy[1])
        out[name] = info

    prop("d_tree0", PR.tree_round(1))
    prop("d_tree1", PR.tree_conifer(2))
    prop("d_tree2", PR.tree_blossom(3))
    prop("d_lamp", PR.lamp())
    prop("d_bench", PR.bench())
    prop("d_bush", PR.hedge_bush())
    prop("d_light_red", PR.traffic_light("red"))
    prop("d_light_green", PR.traffic_light("green"))
    prop("roadwork", PR.roadwork())
    prop("flag", PR.flag(), (8, 8), keep_mask=True)
    prop("fac_site", PR.site_fence())
    for c in ("pakete", "lebensmittel", "medikamente", "getraenke", "elektronik", "moebel", "baustoffe", "maschinenteile", "container"):
        r = engine.render(PR.crate(c), shadow_len=0, ground_shadow=False)
        info = save_result("c_" + c, r, lit=False, top=False)
        info["pivot"] = [r["anchor"][0], r["anchor"][1] + 14]
        out["c_" + c] = info
    print("Requisiten:", len(out))


def main():
    what = sys.argv[1:] or ["ground", "buildings", "facilities", "vehicles", "figures", "props"]
    init()
    if "ground" in what:
        build_ground()
    if "buildings" in what:
        build_buildings()
    if "facilities" in what:
        build_facilities()
    if "vehicles" in what:
        build_vehicles()
    if "figures" in what:
        build_figures()
    if "props" in what:
        build_props()
    manifest["projection"] = {"tile_px": [128, 64], "voxels_per_tile": 32}
    json.dump(manifest, open(MANIFEST_PATH, "w", encoding="utf8"), indent=1)
    print("manifest:", MANIFEST_PATH)


main()
