"""Fahrzeuge als Voxelmodelle. Alle Modelle blicken nach +x, stehen mittig in einem quadratischen Grundriss (S x S) und
haben ihren Boden bei z = 1. Firmenfarbe = Material "comp"/"comp_dark" (wird ueber die Maskenebene eingefaerbt).
Fahrtrichtungen entstehen durch Drehen um 90 Grad (engine.Model.rotated)."""
import random

from engine import Model, mat, M

SIZES = {"police": 40, "ambulance": 60, "firetruck": 60, "roadcrew": 60, "moving": 66, "car": 36, "cargobike": 26, "van": 56, "transporter": 66, "reefer": 66, "truck": 86, "semi": 126}
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
    mat("police_blue", "#2f5fb0", noise=0.03)
    mat("police_silver", "#e8eaee", noise=0.03)
    mat("beacon_blue", "#4a8cff", noise=0.0, emit="#5aa0ff", top=True)
    mat("beacon_red", "#ff4a3a", noise=0.0, emit="#ff3a2a", top=True)
    mat("beacon_amber", "#ffb030", noise=0.0, emit="#ffc040", top=True)
    mat("signal_red", "#d0302a", noise=0.02)
    mat("signal_orange", "#e8782a", noise=0.04)
    mat("hazard_white", "#f2f0ea", noise=0.02)
    mat("moving_blue", "#3a6fb8", noise=0.03)
    mat("box_brown", "#b88a58", noise=0.06)
    mat("bus_body", "#ece6d2", noise=0.03)
    mat("bus_stripe", "#c0392f", noise=0.03)
    mat("recycle_green", "#4c9a5a", noise=0.04)


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


def police():
    """Streifenwagen: silber-weiss mit blauen Tueren und Lichtbalken (Stadtdienst, Auftrag 12 Darstellung)."""
    S = SIZES["police"]
    m = _square(S)
    x0, y0 = (S - 30) // 2, (S - 14) // 2
    m.box(x0, y0, 2, x0 + 30, y0 + 14, 7, M("police_silver"))
    m.box(x0 + 8, y0, 3, x0 + 22, y0 + 1, 7, M("police_blue"))
    m.box(x0 + 8, y0 + 13, 3, x0 + 22, y0 + 14, 7, M("police_blue"))
    m.box(x0 + 7, y0 + 1, 7, x0 + 23, y0 + 13, 12, M("police_silver"))
    m.box(x0 + 8, y0 + 1, 7, x0 + 22, y0 + 13, 11, M("glass_dark"))
    m.box(x0 + 9, y0 + 2, 11, x0 + 21, y0 + 12, 12, M("police_silver"))
    m.box(x0 + 13, y0 + 2, 12, x0 + 17, y0 + 7, 14, M("beacon_blue"))
    m.box(x0 + 13, y0 + 7, 12, x0 + 17, y0 + 12, 14, M("beacon_blue"))
    m.box(x0 + 28, y0, 2, x0 + 30, y0 + 14, 4, M("black"))
    m.box(x0, y0, 2, x0 + 2, y0 + 14, 4, M("black"))
    for wx in (x0 + 6, x0 + 23):
        _wheel(m, wx, y0, 3, 1, 1)
        _wheel(m, wx, y0 + 13, 3, 1, 0)
    for yy in (y0 + 1, y0 + 11):
        m.box(x0 + 29, yy, 4, x0 + 30, yy + 2, 6, M("head_lamp"))
        m.box(x0, yy, 4, x0 + 1, yy + 2, 6, M("rear_lamp"))
    return m


def ambulance():
    """Rettungswagen: weisser Kofferaufbau, rote Bauchbinde, Blaulicht vorn und hinten."""
    S = SIZES["ambulance"]
    m = _square(S)
    L, W = 52, 20
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 3, x0 + 34, y0 + W, 26, M("cargo_white"))
    m.box(x0, y0, 3, x0 + 34, y0 + W, 5, M("black"))
    m.box(x0, y0 - 0, 12, x0 + 34, y0 + 1, 16, M("signal_red"))
    m.box(x0, y0 + W - 1, 12, x0 + 34, y0 + W, 16, M("signal_red"))
    m.box(x0 + 14, y0 - 0, 17, x0 + 20, y0 + 1, 23, M("signal_red"))
    m.box(x0 + 14, y0 + W - 1, 17, x0 + 20, y0 + W, 23, M("signal_red"))
    m.box(x0 + 1, y0 + 2, 26, x0 + 4, y0 + W - 2, 28, M("beacon_blue"))
    _cab(m, x0 + 34, y0, W, 19, 16)
    m.box(x0 + 34, y0 + 3, 19, x0 + 38, y0 + W - 3, 21, M("beacon_blue"))
    for wx in (x0 + 8, x0 + 40):
        _wheel(m, wx, y0, 4, 1, 1)
        _wheel(m, wx, y0 + W - 1, 4, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 5)
    return m


def firetruck():
    """Flugplatzfeuerwehrauto: roter Aufbau mit roemischer Ziffer Fuenf (weiss), Lichtbalken und Schlauchbalken."""
    S = SIZES["firetruck"]
    m = _square(S)
    L, W = 52, 20
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 3, x0 + L, y0 + W, 24, M("signal_red"))
    m.box(x0, y0, 3, x0 + L, y0 + W, 5, M("black"))
    m.box(x0, y0 + W - 1, 6, x0 + L, y0 + W, 9, M("hazard_white"))      # weisse Zierleiste an der Seite
    m.box(x0, y0, 6, x0 + L, y0 + 1, 9, M("hazard_white"))
    # Romanische Fuenf (V) als weisses Feld auf der Seite
    m.box(x0 + 16, y0, 10, x0 + 26, y0 + 1, 15, M("hazard_white"))
    m.box(x0 + 19, y0 + 1, 12, x0 + 23, y0 + 1, 15, M("hazard_white"))
    m.box(x0 + 2, y0 + 8, 24, x0 + 10, y0 + W - 8, 24, M("hazard_white"))   # waagerechter Balken
    m.box(x0 + 12, y0 + 8, 22, x0 + 16, y0 + 13, 24, M("hazard_white"))
    m.box(x0 + 34, y0, 6, x0 + 40, y0 + W - 1, 10, M("steel_dark"))         # Schlauchbalken hinten
    m.box(x0 + 36, y0 + 6, 24, x0 + 38, y0 + W - 6, 26, M("steel"))
    m.box(x0 + 1, y0 + 2, 24, x0 + 4, y0 + W - 2, 26, M("beacon_blue"))     # Lichtbalken vorn
    _cab(m, x0 + L - 16, y0, W, 24, 15, "signal_red")
    for wx in (x0 + 8, x0 + L - 10):
        _wheel(m, wx, y0, 4, 1, 1)
        _wheel(m, wx, y0 + W - 1, 4, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 5)
    return m


def roadcrew():
    """Fahrzeug der Strassenmeisterei: orange Pritsche mit Warnstreifen, Leitkegeln und Rundumleuchte."""
    S = SIZES["roadcrew"]
    m = _square(S)
    L, W = 50, 20
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 3, x0 + 32, y0 + W, 8, M("signal_orange"))
    m.box(x0, y0, 8, x0 + 32, y0 + 1, 12, M("signal_orange"))
    m.box(x0, y0 + W - 1, 8, x0 + 32, y0 + W, 12, M("signal_orange"))
    m.box(x0, y0, 8, x0 + 1, y0 + W, 12, M("signal_orange"))
    for k, xx in enumerate(range(x0, x0 + 32, 4)):
        m.box(xx, y0, 4, xx + 2, y0 + 1, 7, M("hazard_white" if k % 2 else "signal_red"))
        m.box(xx, y0 + W - 1, 4, xx + 2, y0 + W, 7, M("hazard_white" if k % 2 else "signal_red"))
    for cx, cy in ((x0 + 5, y0 + 5), (x0 + 12, y0 + 12), (x0 + 19, y0 + 5), (x0 + 26, y0 + 12)):
        m.box(cx - 1, cy - 1, 8, cx + 2, cy + 2, 12, M("signal_orange"))
        m.box(cx, cy, 12, cx + 1, cy + 1, 15, M("signal_orange"))
        m.box(cx - 1, cy - 1, 10, cx + 2, cy + 2, 11, M("hazard_white"))
    _cab(m, x0 + 32, y0, W, 19, 16, "signal_orange")
    m.box(x0 + 37, y0 + 8, 19, x0 + 41, y0 + 12, 22, M("beacon_amber"))
    for wx in (x0 + 8, x0 + 39):
        _wheel(m, wx, y0, 4, 1, 1)
        _wheel(m, wx, y0 + W - 1, 4, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 5)
    return m


def moving():
    """Umzugswagen: weisser Koffer mit blauem Streifen, hinten offen mit Umzugskartons."""
    S = SIZES["moving"]
    m = _square(S)
    L, W = 60, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 4, x0 + 42, y0 + W, 31, M("cargo_white"))
    m.box(x0, y0, 4, x0 + 42, y0 + W, 6, M("black"))
    m.box(x0 + 2, y0, 16, x0 + 40, y0 + 1, 21, M("moving_blue"))
    m.box(x0 + 2, y0 + W - 1, 16, x0 + 40, y0 + W, 21, M("moving_blue"))
    m.box(x0, y0 + 2, 6, x0 + 1, y0 + W - 2, 29, M("box_brown"))
    m.box(x0 - 3, y0 + 4, 4, x0, y0 + 10, 10, M("box_brown"))
    _cab(m, x0 + 42, y0, W, 22, 18)
    for wx in (x0 + 9, x0 + 47):
        _wheel(m, wx, y0, 5, 1, 1)
        _wheel(m, wx, y0 + W - 1, 5, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 6)
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


# ------------------------------------------------------------------ Kommunale Fahrzeuge (Auftrag 20, Etappe 3)
# Sprite-Namen = Municipal.VEHICLES[...].sprite: fw_hlf, fw_dlk, rd_rtw, rd_nef, bh_kipper, bh_streu, bus, rc_wagen.
SIZES.update({"fw_hlf": 66, "fw_dlk": 76, "rd_rtw": 60, "rd_nef": 44, "bh_kipper": 66, "bh_streu": 70, "bus": 80, "rc_wagen": 70})


def _axles(m, xs, y0, W, r=5):
    for wx in xs:
        _wheel(m, wx, y0, r, 1, 1)
        _wheel(m, wx, y0 + W - 1, r, 1, 0)


def fw_hlf():
    """Hilfeleistungsloeschfahrzeug: rote Mannschaftskabine, Geraeteraeume mit Rollladen, weisse Bauchbinde, Blaulicht."""
    S = SIZES["fw_hlf"]
    m = _square(S)
    L, W = 58, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 4, x0 + 38, y0 + W, 30, M("signal_red"))
    m.box(x0, y0, 4, x0 + 38, y0 + W, 7, M("black"))
    for xx in range(x0 + 2, x0 + 36, 8):            # Rolllaeden der Geraeteraeume
        for yy in (y0, y0 + W - 1):
            m.box(xx, yy, 9, xx + 7, yy + 1, 26, M("steel"))
            for z in range(10, 26, 3):
                m.box(xx, yy, z, xx + 7, yy + 1, z + 1, M("steel_dark"))
    m.box(x0, y0, 27, x0 + 38, y0 + 1, 29, M("hazard_white"))
    m.box(x0, y0 + W - 1, 27, x0 + 38, y0 + W, 29, M("hazard_white"))
    m.box(x0 + 2, y0 + 3, 30, x0 + 34, y0 + W - 3, 32, M("steel_dark"))     # Dachkasten mit Steckleiter
    m.box(x0 + 4, y0 + 8, 32, x0 + 30, y0 + 10, 33, M("steel"))
    m.box(x0 + 4, y0 + 12, 32, x0 + 30, y0 + 14, 33, M("steel"))
    _cab(m, x0 + 38, y0, W, 24, 20, "signal_red")
    m.box(x0 + 38, y0, 13, x0 + 58, y0 + 1, 15, M("hazard_white"))
    m.box(x0 + 38, y0 + W - 1, 13, x0 + 58, y0 + W, 15, M("hazard_white"))
    m.box(x0 + 48, y0 + 3, 24, x0 + 52, y0 + W - 3, 26, M("beacon_blue"))
    m.box(x0 + 1, y0 + 2, 30, x0 + 3, y0 + 5, 32, M("beacon_blue"))
    _axles(m, (x0 + 10, x0 + 46), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def fw_dlk():
    """Drehleiter: rotes Fahrgestell, Drehkranz hinten, Leiterpark ueber der Kabine nach vorn ausgelegt, Rettungskorb."""
    S = SIZES["fw_dlk"]
    m = _square(S)
    L, W = 66, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 4, x0 + 46, y0 + W, 18, M("signal_red"))
    m.box(x0, y0, 4, x0 + 46, y0 + W, 7, M("black"))
    m.box(x0, y0, 15, x0 + 46, y0 + 1, 17, M("hazard_white"))
    m.box(x0, y0 + W - 1, 15, x0 + 46, y0 + W, 17, M("hazard_white"))
    m.box(x0 + 4, y0 + 5, 18, x0 + 16, y0 + W - 5, 24, M("steel_dark"))     # Drehkranz
    a, b = x0 + 6, x0 + 62
    m.box(a, y0 + 6, 25, b, y0 + 8, 28, M("steel"))                          # Leiterholme
    m.box(a, y0 + W - 8, 25, b, y0 + W - 6, 28, M("steel"))
    for xx in range(a, b, 4):
        m.box(xx, y0 + 8, 26, xx + 1, y0 + W - 8, 27, M("hazard_white"))
    m.box(x0 + 60, y0 + 5, 22, x0 + 66, y0 + W - 5, 28, M("signal_red"))     # Rettungskorb
    _cab(m, x0 + 46, y0, W, 22, 18, "signal_red")
    m.box(x0 + 52, y0 + 3, 22, x0 + 56, y0 + W - 3, 24, M("beacon_blue"))
    _axles(m, (x0 + 8, x0 + 22, x0 + 54), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def rd_rtw():
    """Rettungswagen der Rettungswache (Modell wie der Krankenwagen, eigener Name fuer die Leitstelle)."""
    return ambulance()


def rd_nef():
    """Notarzteinsatzfahrzeug: weisser Kombi mit roter Bauchbinde und Lichtbalken."""
    S = SIZES["rd_nef"]
    m = _square(S)
    x0, y0 = (S - 34) // 2, (S - 15) // 2
    m.box(x0, y0, 2, x0 + 34, y0 + 15, 8, M("cargo_white"))
    m.box(x0 + 2, y0 + 1, 8, x0 + 24, y0 + 14, 14, M("cargo_white"))
    m.box(x0 + 3, y0 + 1, 8, x0 + 24, y0 + 14, 13, M("glass_dark"))
    m.box(x0 + 4, y0 + 2, 13, x0 + 23, y0 + 13, 14, M("cargo_white"))
    m.box(x0, y0, 5, x0 + 34, y0 + 1, 7, M("signal_red"))
    m.box(x0, y0 + 14, 5, x0 + 34, y0 + 15, 7, M("signal_red"))
    m.box(x0 + 14, y0 + 3, 14, x0 + 19, y0 + 12, 16, M("beacon_blue"))
    m.box(x0 + 32, y0, 2, x0 + 34, y0 + 15, 4, M("black"))
    for wx in (x0 + 6, x0 + 27):
        _wheel(m, wx, y0, 3, 1, 1)
        _wheel(m, wx, y0 + 14, 3, 1, 0)
    _lights(m, x0 + 34, x0, y0, 15, 4)
    return m


def bh_kipper():
    """Bauhof-Kipper: orange Kabine, Kippmulde mit Schotter, Rundumleuchte."""
    S = SIZES["bh_kipper"]
    m = _square(S)
    L, W = 58, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 5, x0 + 38, y0 + W, 8, M("steel_dark"))
    m.box(x0, y0, 8, x0 + 38, y0 + W, 20, M("signal_orange"))
    m.box(x0 + 2, y0 + 2, 10, x0 + 36, y0 + W - 2, 20, 0)
    m.box(x0 + 2, y0 + 2, 10, x0 + 36, y0 + W - 2, 17, M("gravel"))
    for xx in range(x0 + 4, x0 + 34, 6):
        m.box(xx, y0 + 4, 17, xx + 4, y0 + W - 4, 19, M("gravel"))
    _cab(m, x0 + 40, y0, W, 24, 18, "signal_orange")
    m.box(x0 + 46, y0 + 9, 24, x0 + 50, y0 + 13, 27, M("beacon_amber"))
    _axles(m, (x0 + 8, x0 + 20, x0 + 48), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def bh_streu():
    """Streu- und Raeumfahrzeug: orange, Salztrichter auf der Ladeflaeche, Raeumschild vorn, Streuteller hinten."""
    S = SIZES["bh_streu"]
    m = _square(S)
    L, W = 56, 22
    x0, y0 = (S - L) // 2 - 2, (S - W) // 2
    m.box(x0, y0, 5, x0 + 36, y0 + W, 8, M("steel_dark"))
    for k in range(10):                                  # Trichter, nach unten schmaler
        m.box(x0 + 2 + k // 2, y0 + 2 + k // 2, 8 + k, x0 + 34 - k // 2, y0 + W - 2 - k // 2, 9 + k, M("signal_orange"))
    m.box(x0 + 2, y0 + 2, 18, x0 + 34, y0 + W - 2, 20, M("signal_orange"))
    m.box(x0 + 5, y0 + 5, 19, x0 + 31, y0 + W - 5, 20, M("white"))   # Streusalz
    m.box(x0 - 3, y0 + 7, 3, x0, y0 + W - 7, 5, M("steel"))          # Streuteller
    _cab(m, x0 + 38, y0, W, 24, 18, "signal_orange")
    m.box(x0 + 44, y0 + 9, 24, x0 + 48, y0 + 13, 27, M("beacon_amber"))
    m.box(x0 + 57, y0 - 4, 2, x0 + 60, y0 + W + 4, 10, M("signal_orange"))   # Raeumschild
    for yy in range(y0 - 4, y0 + W + 4, 4):
        m.box(x0 + 59, yy, 3, x0 + 60, yy + 2, 9, M("hazard_white"))
    _axles(m, (x0 + 8, x0 + 46), y0, W)
    _lights(m, x0 + 56, x0, y0, W, 6)
    return m


def bus():
    """Linienbus: cremeweiss mit Fensterband und roter Zierlinie, Tueren rechts, Klimaanlage, Zielanzeige."""
    S = SIZES["bus"]
    m = _square(S)
    L, W = 72, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 3, x0 + L, y0 + W, 28, M("bus_body"))
    m.box(x0, y0, 3, x0 + L, y0 + W, 6, M("black"))
    for yy in (y0, y0 + W - 1):
        m.box(x0 + 2, yy, 13, x0 + L - 2, yy + 1, 24, M("glass_dark"))
        m.box(x0 + 2, yy, 7, x0 + L - 2, yy + 1, 10, M("bus_stripe"))
    for dx in (x0 + 14, x0 + 44, x0 + 62):              # Tueren (rechte Seite = +y)
        m.box(dx, y0 + W - 1, 6, dx + 6, y0 + W, 24, M("glass_lit"))
    m.box(x0 + L - 1, y0 + 1, 12, x0 + L, y0 + W - 1, 25, M("glass_dark"))
    m.box(x0 + L - 1, y0 + 4, 25, x0 + L, y0 + W - 4, 27, M("beacon_amber"))   # Zielanzeige
    m.box(x0 + 10, y0 + 4, 28, x0 + 30, y0 + W - 4, 31, M("steel"))             # Klimaanlage
    _axles(m, (x0 + 12, x0 + L - 14), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def rc_wagen():
    """Wertstoffsammelfahrzeug: weisse Kabine, gruener Pressaufbau mit Schuettung hinten, Rundumleuchte."""
    S = SIZES["rc_wagen"]
    m = _square(S)
    L, W = 60, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0 + 4, y0, 5, x0 + 42, y0 + W, 30, M("recycle_green"))
    m.box(x0 + 4, y0, 5, x0 + 42, y0 + W, 8, M("black"))
    for yy in (y0, y0 + W - 1):
        m.box(x0 + 6, yy, 18, x0 + 40, yy + 1, 21, M("hazard_white"))
    m.box(x0, y0 + 1, 5, x0 + 6, y0 + W - 1, 26, M("steel_dark"))     # Pressheck
    m.box(x0, y0 + 4, 6, x0 + 2, y0 + W - 4, 12, M("steel"))           # Schuettung
    _cab(m, x0 + 42, y0, W, 24, 18)
    m.box(x0 + 48, y0 + 9, 24, x0 + 52, y0 + 13, 27, M("beacon_amber"))
    _axles(m, (x0 + 12, x0 + 26, x0 + 50), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


MUNICIPAL = ["fw_hlf", "fw_dlk", "rd_rtw", "rd_nef", "bh_kipper", "bh_streu", "bus", "rc_wagen"]


# ------------------------------------------------------------------ Auftrag 20 Etappe 13: weitere Feuerwehrfahrzeuge
SIZES.update({"fw_kdow": 40, "fw_elw": 50, "fw_klf": 54, "fw_lf10": 62, "fw_tlf": 66, "fw_gwl": 70, "fw_rw": 66, "fw_flf": 90})


def _red_body(m, x0, y0, L, W, h, shutters=True, band=True):
    """Roter Geraeteaufbau mit Fahrgestell; Rolllaeden der Geraeteraeume und weisse Bauchbinde."""
    m.box(x0, y0, 4, x0 + L, y0 + W, h, M("signal_red"))
    m.box(x0, y0, 4, x0 + L, y0 + W, 7, M("black"))
    if shutters:
        for xx in range(x0 + 2, x0 + L - 2, 8):
            for yy in (y0, y0 + W - 1):
                m.box(xx, yy, 9, xx + 7, yy + 1, h - 4, M("steel"))
                for z in range(10, h - 4, 3):
                    m.box(xx, yy, z, xx + 7, yy + 1, z + 1, M("steel_dark"))
    if band:
        m.box(x0, y0, h - 3, x0 + L, y0 + 1, h - 1, M("hazard_white"))
        m.box(x0, y0 + W - 1, h - 3, x0 + L, y0 + W, h - 1, M("hazard_white"))


def fw_kdow():
    """Kommandowagen: roter Kombi (Pkw), Lichtbalken, weisse Seitenstreifen."""
    S = SIZES["fw_kdow"]
    m = _square(S)
    x0, y0 = (S - 30) // 2, (S - 14) // 2
    m.box(x0, y0, 2, x0 + 30, y0 + 14, 8, M("signal_red"))
    m.box(x0 + 3, y0 + 1, 8, x0 + 22, y0 + 13, 13, M("glass_dark"))
    m.box(x0 + 4, y0 + 2, 12, x0 + 21, y0 + 12, 13, M("signal_red"))
    m.box(x0, y0, 5, x0 + 30, y0 + 1, 6, M("hazard_white"))
    m.box(x0, y0 + 13, 5, x0 + 30, y0 + 14, 6, M("hazard_white"))
    m.box(x0 + 11, y0 + 3, 13, x0 + 16, y0 + 11, 15, M("beacon_blue"))
    for wx in (x0 + 6, x0 + 24):
        _wheel(m, wx, y0, 3, 1, 1)
        _wheel(m, wx, y0 + 13, 3, 1, 0)
    _lights(m, x0 + 30, x0, y0, 14, 4)
    return m


def fw_elw():
    """Einsatzleitwagen 1: Kastenwagen mit Hochdach, Antennenmast und Lichtbalken, Fenster im Fuehrungsraum."""
    S = SIZES["fw_elw"]
    m = _square(S)
    L, W = 40, 18
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 3, x0 + 28, y0 + W, 24, M("signal_red"))
    m.box(x0, y0, 3, x0 + 28, y0 + W, 5, M("black"))
    for yy in (y0, y0 + W - 1):
        m.box(x0 + 6, yy, 14, x0 + 22, yy + 1, 19, M("glass_dark"))
        m.box(x0, yy, 9, x0 + 28, yy + 1, 11, M("hazard_white"))
    m.box(x0 + 3, y0 + 3, 24, x0 + 5, y0 + 5, 40, M("steel"))      # Antennenmast
    _cab(m, x0 + 28, y0, W, 17, 12, "signal_red")
    m.box(x0 + 30, y0 + 3, 17, x0 + 34, y0 + W - 3, 19, M("beacon_blue"))
    for wx in (x0 + 7, x0 + 33):
        _wheel(m, wx, y0, 4, 1, 1)
        _wheel(m, wx, y0 + W - 1, 4, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 5)
    return m


def fw_klf():
    """Kleinloeschfahrzeug: Transporter-Fahrgestell, kurzer Geraeteaufbau, Steckleiter auf dem Dach."""
    S = SIZES["fw_klf"]
    m = _square(S)
    L, W = 44, 18
    x0, y0 = (S - L) // 2, (S - W) // 2
    _red_body(m, x0, y0, 30, W, 22)
    m.box(x0 + 3, y0 + 7, 22, x0 + 28, y0 + 9, 23, M("steel"))
    m.box(x0 + 3, y0 + 10, 22, x0 + 28, y0 + 12, 23, M("steel"))
    _cab(m, x0 + 30, y0, W, 17, 14, "signal_red")
    m.box(x0 + 34, y0 + 3, 17, x0 + 38, y0 + W - 3, 19, M("beacon_blue"))
    _axles(m, (x0 + 8, x0 + 36), y0, W, 4)
    _lights(m, x0 + L, x0, y0, W, 5)
    return m


def fw_lf10():
    """Loeschgruppenfahrzeug LF 10: mittlerer Aufbau, Saugschlauch seitlich, Leiter quer auf dem Dach."""
    S = SIZES["fw_lf10"]
    m = _square(S)
    L, W = 52, 20
    x0, y0 = (S - L) // 2, (S - W) // 2
    _red_body(m, x0, y0, 34, W, 27)
    m.box(x0 + 2, y0 - 1, 10, x0 + 30, y0, 12, M("black"))          # Saugschlauch
    m.box(x0 + 2, y0 + 4, 27, x0 + 30, y0 + 16, 28, M("steel_dark"))
    m.box(x0 + 4, y0 + 7, 28, x0 + 28, y0 + 9, 29, M("steel"))
    m.box(x0 + 4, y0 + 11, 28, x0 + 28, y0 + 13, 29, M("steel"))
    _cab(m, x0 + 34, y0, W, 22, 18, "signal_red")
    m.box(x0 + 42, y0 + 3, 22, x0 + 46, y0 + W - 3, 24, M("beacon_blue"))
    _axles(m, (x0 + 9, x0 + 42), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def fw_tlf():
    """Tankloeschfahrzeug TLF 3000: runder Wassertank hinten, Wasserwerfer (Monitor) auf dem Dach, kurze Kabine."""
    S = SIZES["fw_tlf"]
    m = _square(S)
    L, W = 56, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 4, x0 + 38, y0 + W, 7, M("black"))
    for z in range(7, 27):                                           # Tank mit gerundeten Kanten
        inset = 2 if z in (7, 26) else (1 if z in (8, 25) else 0)
        m.box(x0 + 1, y0 + inset, z, x0 + 30, y0 + W - inset, z + 1, M("signal_red"))
    m.box(x0 + 30, y0, 7, x0 + 38, y0 + W, 26, M("steel"))           # Pumpenraum
    m.box(x0 + 1, y0, 17, x0 + 30, y0 + 1, 19, M("hazard_white"))
    m.box(x0 + 1, y0 + W - 1, 17, x0 + 30, y0 + W, 19, M("hazard_white"))
    m.box(x0 + 33, y0 + 8, 26, x0 + 37, y0 + 14, 29, M("steel_dark"))   # Monitor
    m.box(x0 + 37, y0 + 10, 28, x0 + 43, y0 + 12, 29, M("steel"))
    _cab(m, x0 + 38, y0, W, 22, 18, "signal_red")
    m.box(x0 + 46, y0 + 3, 22, x0 + 50, y0 + W - 3, 24, M("beacon_blue"))
    _axles(m, (x0 + 8, x0 + 20, x0 + 48), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def fw_gwl():
    """Geraetewagen Logistik: Lkw mit Ladebordwand und Rollcontainern, Plane in Signalrot, Kennstreifen."""
    S = SIZES["fw_gwl"]
    m = _square(S)
    L, W = 60, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 4, x0 + 40, y0 + W, 7, M("black"))
    m.box(x0, y0, 7, x0 + 40, y0 + W, 30, M("signal_red"))
    m.box(x0, y0 + 2, 9, x0 + 1, y0 + W - 2, 28, M("steel_dark"))     # Heckklappe
    m.box(x0 - 3, y0 + 2, 5, x0, y0 + W - 2, 6, M("steel"))           # Ladebordwand
    for xx in range(x0 + 4, x0 + 38, 9):
        m.box(xx, y0, 12, xx + 1, y0 + W, 28, M("signal_red"))
    m.box(x0, y0, 22, x0 + 40, y0 + 1, 25, M("hazard_white"))
    m.box(x0, y0 + W - 1, 22, x0 + 40, y0 + W, 25, M("hazard_white"))
    _cab(m, x0 + 40, y0, W, 22, 18, "signal_red")
    m.box(x0 + 48, y0 + 3, 22, x0 + 52, y0 + W - 3, 24, M("beacon_blue"))
    _axles(m, (x0 + 10, x0 + 50), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def fw_rw():
    """Ruestwagen: kantiger Kofferaufbau, Lichtmast und Seilwinde vorne, Ladekran hinten."""
    S = SIZES["fw_rw"]
    m = _square(S)
    L, W = 56, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    _red_body(m, x0 + 6, y0, 32, W, 30)
    m.box(x0, y0 + 3, 4, x0 + 6, y0 + W - 3, 7, M("black"))
    m.box(x0, y0 + 6, 7, x0 + 6, y0 + W - 6, 18, M("steel_dark"))     # Kransaeule
    m.box(x0 + 1, y0 + 9, 18, x0 + 26, y0 + 13, 21, M("hazard_white"))   # Kranausleger, abgelegt
    m.box(x0 + 26, y0 + 9, 30, x0 + 28, y0 + 11, 40, M("steel"))      # Lichtmast
    m.box(x0 + 24, y0 + 7, 40, x0 + 30, y0 + 13, 42, M("head_lamp"))
    _cab(m, x0 + 38, y0, W, 22, 16, "signal_red")
    m.box(x0 + 54, y0 + 6, 4, x0 + 56, y0 + W - 6, 9, M("steel_dark"))  # Seilwinde
    m.box(x0 + 44, y0 + 3, 22, x0 + 48, y0 + W - 3, 24, M("beacon_blue"))
    _axles(m, (x0 + 14, x0 + 46), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


def fw_flf():
    """Flugfeldloeschfahrzeug: sehr grosser Allrad-Aufbau, Panoramakabine vorn, Dach- und Frontwerfer, drei Achsen mit grossen Raedern."""
    S = SIZES["fw_flf"]
    m = _square(S)
    L, W = 78, 28
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 6, x0 + 60, y0 + W, 10, M("black"))
    m.box(x0, y0, 10, x0 + 60, y0 + W, 34, M("signal_red"))
    for xx in range(x0 + 3, x0 + 56, 10):
        for yy in (y0, y0 + W - 1):
            m.box(xx, yy, 13, xx + 8, yy + 1, 30, M("steel"))
    m.box(x0, y0, 30, x0 + 60, y0 + 1, 33, M("hazard_white"))
    m.box(x0, y0 + W - 1, 30, x0 + 60, y0 + W, 33, M("hazard_white"))
    m.box(x0 + 40, y0 + 10, 34, x0 + 48, y0 + 18, 38, M("steel_dark"))   # Dachwerfer
    m.box(x0 + 48, y0 + 12, 37, x0 + 58, y0 + 16, 39, M("steel"))
    m.box(x0 + 60, y0, 6, x0 + 78, y0 + W, 10, M("black"))
    m.box(x0 + 60, y0, 10, x0 + 76, y0 + W, 28, M("signal_red"))
    m.box(x0 + 66, y0 + 1, 18, x0 + 76, y0 + W - 1, 27, M("glass_dark"))  # Panoramascheibe
    m.box(x0 + 62, y0, 18, x0 + 66, y0 + 1, 27, M("glass_dark"))
    m.box(x0 + 62, y0 + W - 1, 18, x0 + 66, y0 + W, 27, M("glass_dark"))
    m.box(x0 + 76, y0 + 11, 6, x0 + 80, y0 + 17, 9, M("steel_dark"))      # Frontwerfer
    m.box(x0 + 64, y0 + 3, 28, x0 + 70, y0 + W - 3, 30, M("beacon_blue"))
    _axles(m, (x0 + 12, x0 + 30, x0 + 66), y0, W, 7)
    _lights(m, x0 + L, x0, y0, W, 8)
    return m


MUNICIPAL += ["fw_kdow", "fw_elw", "fw_klf", "fw_lf10", "fw_tlf", "fw_gwl", "fw_rw", "fw_flf"]


# ------------------------------------------------------------------ Auftrag 22 Phase 2: Muellwagen der Abfallwirtschaft
SIZES.update({"aw_muell": 72})


def aw_muell():
    """Muellwagen: weisse Kabine, orange Pressaufbau mit Schuettung und Tonnenlifter hinten, zwei Trittbretter, Rundumleuchten."""
    S = SIZES["aw_muell"]
    m = _square(S)
    L, W = 62, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0 + 4, y0, 5, x0 + 44, y0 + W, 32, M("pub_orange"))
    m.box(x0 + 4, y0, 5, x0 + 44, y0 + W, 8, M("black"))
    for yy in (y0, y0 + W - 1):
        m.box(x0 + 6, yy, 20, x0 + 42, yy + 1, 23, M("hazard_white"))
    m.box(x0, y0 + 1, 5, x0 + 6, y0 + W - 1, 28, M("steel_dark"))     # Pressheck
    m.box(x0 - 2, y0 + 5, 6, x0, y0 + W - 5, 14, M("steel"))          # Tonnenlifter
    m.box(x0 - 3, y0 + 1, 4, x0, y0 + 5, 5, M("steel_dark"))          # Trittbretter der Lader
    m.box(x0 - 3, y0 + W - 5, 4, x0, y0 + W - 1, 5, M("steel_dark"))
    _cab(m, x0 + 44, y0, W, 24, 18)
    m.box(x0 + 50, y0 + 3, 24, x0 + 53, y0 + 6, 27, M("beacon_amber"))
    m.box(x0 + 50, y0 + W - 6, 24, x0 + 53, y0 + W - 3, 27, M("beacon_amber"))
    _axles(m, (x0 + 12, x0 + 28, x0 + 52), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


MUNICIPAL += ["aw_muell"]

SIZES.update({"aw_kehr": 72})


def aw_kehr():
    """Kehrmaschine der Stadtreinigung: weisse Kabine, orangem Aufbau mit Schuettung und seitlicher Kehrbuerste, Rundumleuchte.
    Auftrag 22 Phase 2 Schritt 3: raumt den Abfall, der aus ueberquellenden Tonnen ueberquillt, von den Strassen der Viertele."""
    S = SIZES["aw_kehr"]
    m = _square(S)
    L, W = 62, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0 + 4, y0, 5, x0 + 44, y0 + W, 30, M("pub_orange"))
    m.box(x0 + 4, y0, 5, x0 + 44, y0 + W, 8, M("black"))
    for yy in (y0, y0 + W - 1):
        m.box(x0 + 6, yy, 18, x0 + 42, yy + 1, 21, M("hazard_white"))
    m.box(x0, y0 + 3, 5, x0 + 6, y0 + W - 3, 26, M("steel_dark"))     # Heckkiste
    m.box(x0 + 46, y0 + W - 6, 3, x0 + 56, y0 + W - 2, 9, M("steel"))         # seitliche Kehrbuerste
    for zz in range(3, 9, 2):
        m.box(x0 + 56, y0 + W - 6, zz, x0 + 58, y0 + W - 2, zz + 1, M("hazard_white"))
    m.box(x0 + 54, y0 - 4, 2, x0 + 60, y0 + W + 4, 6, M("steel_dark"))       # Kehrschild vorn
    _cab(m, x0 + 44, y0, W, 24, 18)
    m.box(x0 + 50, y0 + 3, 22, x0 + 53, y0 + 6, 25, M("beacon_amber"))
    m.box(x0 + 50, y0 + W - 6, 22, x0 + 53, y0 + W - 3, 25, M("beacon_amber"))
    _axles(m, (x0 + 12, x0 + 28, x0 + 52), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


MUNICIPAL += ["aw_kehr"]


# ------------------------------------------------------------------ Auftrag 20 Etappe 14: Rettungsdienst
SIZES.update({"rd_ktw": 50, "rd_elw": 46, "rd_itw": 80})


def rd_ktw():
    """Krankentransportwagen: kurzer Kastenwagen (Hochdach), weiss mit schmalem blauem Streifen, ohne Notfallkoffer-Aufbau."""
    S = SIZES["rd_ktw"]
    m = _square(S)
    L, W = 40, 17
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 3, x0 + 28, y0 + W, 22, M("cargo_white"))
    m.box(x0, y0, 3, x0 + 28, y0 + W, 5, M("black"))
    m.box(x0, y0, 11, x0 + 28, y0 + 1, 13, M("beacon_blue"))
    m.box(x0, y0 + W - 1, 11, x0 + 28, y0 + W, 13, M("beacon_blue"))
    m.box(x0 + 6, y0, 15, x0 + 20, y0 + 1, 20, M("glass_dark"))
    _cab(m, x0 + 28, y0, W, 16, 12)
    m.box(x0 + 30, y0 + 4, 16, x0 + 33, y0 + W - 4, 17, M("beacon_blue"))
    for wx in (x0 + 7, x0 + 33):
        _wheel(m, wx, y0, 4, 1, 1)
        _wheel(m, wx, y0 + W - 1, 4, 1, 0)
    _lights(m, x0 + L, x0, y0, W, 5)
    return m


def rd_elw():
    """Einsatzleitwagen Rettungsdienst: Gelaendewagen weiss-rot, Lichtbalken, Dachbox mit Antennen."""
    S = SIZES["rd_elw"]
    m = _square(S)
    x0, y0 = (S - 34) // 2, (S - 16) // 2
    m.box(x0, y0, 3, x0 + 34, y0 + 16, 10, M("cargo_white"))
    m.box(x0 + 2, y0 + 1, 10, x0 + 26, y0 + 15, 17, M("glass_dark"))
    m.box(x0 + 3, y0 + 2, 16, x0 + 25, y0 + 14, 17, M("cargo_white"))
    m.box(x0, y0, 6, x0 + 34, y0 + 1, 9, M("signal_red"))
    m.box(x0, y0 + 15, 6, x0 + 34, y0 + 16, 9, M("signal_red"))
    m.box(x0 + 4, y0 + 4, 17, x0 + 14, y0 + 12, 19, M("steel_dark"))
    m.box(x0 + 6, y0 + 6, 19, x0 + 7, y0 + 7, 27, M("steel"))
    m.box(x0 + 11, y0 + 9, 19, x0 + 12, y0 + 10, 25, M("steel"))
    m.box(x0 + 17, y0 + 3, 17, x0 + 22, y0 + 13, 19, M("beacon_blue"))
    for wx in (x0 + 7, x0 + 27):
        _wheel(m, wx, y0, 4, 1, 1)
        _wheel(m, wx, y0 + 15, 4, 1, 0)
    _lights(m, x0 + 34, x0, y0, 16, 5)
    return m


def rd_itw():
    """Intensivtransportwagen: langer Koffer auf Lkw-Fahrgestell mit drei Achsen, gelb-weisse Warnmarkierung, Klimageraet auf dem Dach."""
    S = SIZES["rd_itw"]
    m = _square(S)
    L, W = 66, 22
    x0, y0 = (S - L) // 2, (S - W) // 2
    m.box(x0, y0, 4, x0 + 46, y0 + W, 30, M("cargo_white"))
    m.box(x0, y0, 4, x0 + 46, y0 + W, 7, M("black"))
    for xx in range(x0, x0 + 46, 6):
        m.box(xx, y0, 12, xx + 3, y0 + 1, 15, M("signal_orange"))
        m.box(xx + 3, y0, 12, xx + 6, y0 + 1, 15, M("signal_red"))
        m.box(xx, y0 + W - 1, 12, xx + 3, y0 + W, 15, M("signal_orange"))
        m.box(xx + 3, y0 + W - 1, 12, xx + 6, y0 + W, 15, M("signal_red"))
    m.box(x0 + 8, y0 + 5, 30, x0 + 20, y0 + W - 5, 34, M("steel"))      # Klimageraet
    m.box(x0 + 1, y0 + 3, 30, x0 + 4, y0 + W - 3, 32, M("beacon_blue"))
    _cab(m, x0 + 46, y0, W, 22, 18)
    m.box(x0 + 52, y0 + 3, 22, x0 + 56, y0 + W - 3, 24, M("beacon_blue"))
    _axles(m, (x0 + 8, x0 + 20, x0 + 54), y0, W)
    _lights(m, x0 + L, x0, y0, W, 6)
    return m


MUNICIPAL += ["rd_ktw", "rd_elw", "rd_itw"]
