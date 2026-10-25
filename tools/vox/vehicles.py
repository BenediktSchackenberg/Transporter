"""Fahrzeuge als Voxelmodelle. Alle Modelle blicken nach +x, stehen mittig in einem quadratischen Grundriss (S x S) und
haben ihren Boden bei z = 1. Firmenfarbe = Material "comp"/"comp_dark" (wird ueber die Maskenebene eingefaerbt).
Fahrtrichtungen entstehen durch Drehen um 90 Grad (engine.Model.rotated)."""
import random

from engine import Model, mat, M

SIZES = {"car": 36, "cargobike": 26, "van": 56, "transporter": 66, "reefer": 66, "truck": 86, "semi": 126}
CAR_COLORS = {"car_silver": "#c0c4cc", "car_black": "#2f3239", "car_red": "#b03a36", "car_blue": "#3a5fa0", "car_gold": "#cdb060",
              "car_white": "#e4e4e0", "car_green": "#4f8a55", "car_violet": "#74559c"}


def init():
    for k, v in CAR_COLORS.items():
        mat(k, v, noise=0.03)
    mat("tire", "#1d1f24", noise=0.02)
    mat("hub", "#a9afb7", noise=0.02)
    mat("rear_lamp", "#c0302a", noise=0.0, emit="#ff3a2a", top=False)
    mat("head_lamp", "#fff3c8", noise=0.0, emit="#ffe9a0", top=False)
    mat("cab_white", "#ecebe6", noise=0.03)
    mat("cargo_white", "#dcdbd6", noise=0.03)


def _wheel(m, cx, cy, r=4, z0=1, side=0):
    """Rad als Scheibe in der x-z-Ebene an der Seite y = cy."""
    for dx in range(-r, r + 1):
        for dz in range(-r, r + 1):
            d = dx * dx + dz * dz
            if d <= r * r:
                m.put(cx + dx, cy, z0 + r + dz - 1, M("tire") if d > (r - 2) ** 2 else M("hub"))
                m.put(cx + dx, cy + (1 if side == 0 else -1), z0 + r + dz - 1, M("tire"))


def _square(n):
    return Model(n, n, 60)


def _stripe(m, x0, x1, y_out, z, h, mname):
    for x in range(x0, x1):
        for zz in range(z, z + h):
            m.put(x, y_out, zz, M(mname))


def car(color="car_silver", seed=0):
    S = SIZES["car"]
    m = _square(S)
    x0, y0 = (S - 28) // 2, (S - 13) // 2
    m.box(x0, y0, 2, x0 + 28, y0 + 13, 7, M(color))
    m.box(x0 + 6, y0 + 1, 7, x0 + 22, y0 + 12, 12, M(color))
    m.box(x0 + 7, y0 + 1, 7, x0 + 21, y0 + 12, 11, M("glass_dark"))
    m.box(x0 + 8, y0 + 2, 11, x0 + 20, y0 + 11, 12, M(color))
    m.box(x0 + 26, y0, 2, x0 + 28, y0 + 13, 4, M("black"))
    m.box(x0, y0, 2, x0 + 2, y0 + 13, 4, M("black"))
    for wx in (x0 + 5, x0 + 21):
        _wheel(m, wx, y0, 3, 1, 1)
        _wheel(m, wx, y0 + 12, 3, 1, 0)
    for yy in (y0 + 1, y0 + 10):
        m.box(x0 + 27, yy, 4, x0 + 28, yy + 2, 6, M("head_lamp"))
        m.box(x0, yy, 4, x0 + 1, yy + 2, 6, M("rear_lamp"))
    return m


def cargobike(seed=0):
    S = SIZES["cargobike"]
    m = _square(S)
    cy = S // 2
    for wx, r in ((7, 4), (18, 4)):
        _wheel(m, wx, cy, r, 1, 1)
    m.box(7, cy - 1, 6, 19, cy + 1, 7, M("frame_dark"))
    m.box(18, cy - 1, 7, 20, cy + 1, 12, M("frame_dark"))      # Lenkstange
    m.box(17, cy - 3, 12, 21, cy + 3, 13, M("black"))
    m.box(2, cy - 4, 5, 12, cy + 4, 12, M("comp"))             # Transportkiste
    m.box(2, cy - 4, 12, 12, cy + 4, 13, M("comp_dark"))
    m.box(13, cy - 1, 7, 16, cy + 1, 10, M("black"))           # Sattel
    return m


def _cab(m, x, y0, w, h, front, mat_body="cab_white"):
    m.box(x, y0, 3, x + front, y0 + w, h, M(mat_body))
    m.box(x + front - 1, y0 + 1, h - 8, x + front, y0 + w - 1, h - 2, M("glass_dark"))      # Windschutzscheibe
    m.box(x + 2, y0, h - 8, x + front - 1, y0 + 1, h - 2, M("glass_dark"))
    m.box(x + 2, y0 + w - 1, h - 8, x + front - 1, y0 + w, h - 2, M("glass_dark"))
    m.box(x + front - 1, y0, 3, x + front, y0 + w, 6, M("black"))


def _lights(m, xf, xr, y0, w, z=4):
    for yy in (y0 + 1, y0 + w - 3):
        m.box(xf - 1, yy, z, xf, yy + 2, z + 2, M("head_lamp"))
        m.box(xr, yy, z, xr + 1, yy + 2, z + 2, M("rear_lamp"))


def van(seed=0):
    S = SIZES["van"]
    m = _square(S)
    L, W = 48, 20
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 3, x0 + 32, y0 + W, 24, M("comp"))
    m.box(x0, y0, 3, x0 + 32, y0 + W, 5, M("black"))
    m.box(x0 + 1, y0 + W - 1, 9, x0 + 31, y0 + W, 11, M("white"))
    m.box(x0 + 1, y0, 9, x0 + 31, y0 + 1, 11, M("white"))
    m.box(x0, y0, 22, x0 + 32, y0 + W, 24, M("comp_dark"))
    _cab(m, x0 + 32, y0, W, 17, 16)
    m.box(x0 + 32, y0, 17, x0 + 44, y0 + W, 18, M("cab_white"))
    for wx in (x0 + 8, x0 + 37):
        _wheel(m, wx, y0, 4, 1, 1)
        _wheel(m, wx, y0 + W - 1, 4, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 5)
    return m


def transporter(seed=0):
    S = SIZES["transporter"]
    m = _square(S)
    L, W = 60, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 4, x0 + 42, y0 + W, 31, M("comp"))
    m.box(x0, y0, 4, x0 + 42, y0 + W, 6, M("black"))
    m.box(x0 + 2, y0 + W - 1, 12, x0 + 40, y0 + W, 15, M("white"))
    m.box(x0 + 2, y0, 12, x0 + 40, y0 + 1, 15, M("white"))
    m.box(x0, y0, 29, x0 + 42, y0 + W, 31, M("comp_dark"))
    _cab(m, x0 + 42, y0, W, 22, 18)
    for wx in (x0 + 9, x0 + 47):
        _wheel(m, wx, y0, 5, 1, 1)
        _wheel(m, wx, y0 + W - 1, 5, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def reefer(seed=0):
    S = SIZES["reefer"]
    m = _square(S)
    L, W = 60, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 4, x0 + 42, y0 + W, 31, M("cargo_white"))
    m.box(x0, y0, 4, x0 + 42, y0 + W, 6, M("black"))
    m.box(x0 + 1, y0 + W - 1, 14, x0 + 41, y0 + W, 18, M("comp"))
    m.box(x0 + 1, y0, 14, x0 + 41, y0 + 1, 18, M("comp"))
    m.box(x0 + 1, y0 + W - 1, 18, x0 + 41, y0 + W, 19, M("blue"))
    m.box(x0 + 1, y0, 18, x0 + 41, y0 + 1, 19, M("blue"))
    m.box(x0 + 36, y0 + 3, 31, x0 + 42, y0 + W - 3, 35, M("steel"))     # Kuehlaggregat
    for yy in range(y0 + 5, y0 + W - 4, 4):
        m.box(x0 + 37, yy, 32, x0 + 41, yy + 1, 35, M("steel_dark"))
    _cab(m, x0 + 42, y0, W, 22, 18)
    for wx in (x0 + 9, x0 + 47):
        _wheel(m, wx, y0, 5, 1, 1)
        _wheel(m, wx, y0 + W - 1, 5, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def truck(seed=0):
    S = SIZES["truck"]
    m = _square(S)
    L, W = 80, 24
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 5, x0 + 58, y0 + W, 38, M("comp"))
    m.box(x0, y0, 5, x0 + 58, y0 + W, 8, M("black"))
    m.box(x0, y0, 36, x0 + 58, y0 + W, 38, M("comp_dark"))
    m.box(x0 + 2, y0 + W - 1, 14, x0 + 56, y0 + W, 19, M("white"))
    m.box(x0 + 2, y0, 14, x0 + 56, y0 + 1, 19, M("white"))
    _cab(m, x0 + 58, y0, W, 28, 22)
    m.box(x0 + 58, y0, 28, x0 + 76, y0 + W, 30, M("cab_white"))
    for wx in (x0 + 10, x0 + 24, x0 + 64):
        _wheel(m, wx, y0, 5, 1, 1)
        _wheel(m, wx, y0 + W - 1, 5, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 7)
    return m


def semi(seed=0):
    S = SIZES["semi"]
    m = _square(S)
    L, W = 120, 24
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 6, x0 + 88, y0 + W, 40, M("cargo_white"))
    m.box(x0, y0, 6, x0 + 88, y0 + W, 9, M("black"))
    m.box(x0 + 2, y0 + W - 1, 18, x0 + 86, y0 + W, 28, M("comp"))
    m.box(x0 + 2, y0, 18, x0 + 86, y0 + 1, 28, M("comp"))
    m.box(x0 + 2, y0 + W - 1, 28, x0 + 86, y0 + W, 30, M("comp_dark"))
    m.box(x0 + 2, y0, 28, x0 + 86, y0 + 1, 30, M("comp_dark"))
    m.box(x0 + 88, y0 + 4, 5, x0 + 92, y0 + W - 4, 8, M("steel_dark"))      # Kupplung
    _cab(m, x0 + 92, y0, W, 32, 24, "comp")
    m.box(x0 + 92, y0, 32, x0 + 114, y0 + W, 34, M("comp_dark"))
    m.box(x0 + 90, y0 + 2, 34, x0 + 92, y0 + W - 2, 44, M("comp"))          # Spoiler
    for wx in (x0 + 6, x0 + 15, x0 + 24, x0 + 98):
        _wheel(m, wx, y0, 5, 1, 1)
        _wheel(m, wx, y0 + W - 1, 5, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 8)
    return m
