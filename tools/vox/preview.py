"""Vorschau: rendert Modelle nebeneinander in ein Bild (Entwicklungswerkzeug). Aufruf: python preview.py ausgabe.png name1 name2 ..."""
import sys

sys.path.insert(0, ".")
import engine, lib, residential, buildings
from PIL import Image

lib.init_materials()


def build(name):
    mod, _, arg = name.partition(":")
    a = int(arg) if arg else 0
    fn = {"house": lambda: residential.house(a), "semi": lambda: residential.semi(a + 1), "apartment": lambda: residential.apartment(a),
          "office": lambda: residential.office(a), "highrise": lambda: residential.highrise(a), "school": lambda: residential.school(a + 1),
          "kindergarten": lambda: residential.kindergarten(a + 1), "villa": lambda: buildings.villa(a + 1)}
    if mod in fn:
        return fn[mod]()
    import importlib
    for modname in ("commercial", "industrial", "vehicles", "figures", "props", "ground", "facilities"):
        try:
            mm = importlib.import_module(modname)
        except ImportError:
            continue
        if hasattr(mm, mod):
            return getattr(mm, mod)(a) if arg else getattr(mm, mod)()
    raise SystemExit("unbekannt: " + name)


def main():
    out = sys.argv[1]
    imgs = []
    for n in sys.argv[2:]:
        m = build(n)
        if isinstance(m, tuple):
            m = m[0]
        r = engine.render(m)
        imgs.append(r["color"])
    W = sum(i.size[0] for i in imgs) + 10 * len(imgs)
    H = max(i.size[1] for i in imgs)
    sheet = Image.new("RGBA", (W, H), (96, 124, 92, 255))
    x = 0
    for im in imgs:
        sheet.paste(im, (x, H - im.size[1]), im)
        x += im.size[0] + 10
    sheet.save(out)
    print(sheet.size)


main()
