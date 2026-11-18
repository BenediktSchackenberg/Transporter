"""Gelaende-LKW (Wildnis-Start). Benedikt 18.11.2026: die Animation der KI und wie sie mit dem Fahrzeug faehrt sei sehr
schlecht und muesse wesentlich besser und detaillierter werden.

Allrad-Pritschenwagen: grosse Stollenreifen mit gelben Felgen, Bodenfreiheit mit sichtbarem Rahmen und Achsen, Kotfluegel,
Kabine in Firmenfarbe mit grossen Scheiben (der Fahrer wird zur Laufzeit hineingezeichnet, Sitz siehe SEAT), Lichtleiste,
Dachtraeger, Schnorchel, Rammschutz mit Seilwinde, Pritsche mit Plane, Reserverad, Kanister, Schlammspritzer.
Blickt nach +x wie alle Fahrzeuge (vehicles.py); Boden bei z = 1."""
from engine import Model, mat, M

SIZE = 90
L, W = 76, 26
R = 8                         # Radius der Stollenreifen
SEAT = (57, 19, 27)           # Kopf des Fahrers relativ zu (x0, y0, z): links in Fahrtrichtung, auf Hoehe der Seitenscheibe
HEIGHT = 38                   # hoechster Punkt (Rundumleuchte) fuer Ladung/Warnzeichen


def _mats():
    mat("gl_knob", "#3a3d44", noise=0.05)
    mat("gl_rim", "#c9a640", noise=0.03)
    mat("gl_tarp", "#6d7352", noise=0.07)
    mat("gl_tarp2", "#5c6245", noise=0.07)
    mat("gl_mud", "#6b5034", noise=0.12, top=False)
    mat("gl_bar", "#1f2125", noise=0.02)
    mat("gl_lamp", "#fff6d8", noise=0.0, emit="#fff0b0", top=False)
    mat("gl_amber", "#ffb030", noise=0.0, emit="#ffb840", top=False)
    mat("gl_can", "#3f6a3a", noise=0.04)


def _hash3(x, y, z):
    h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def origin():
    return (SIZE - L) // 2, (SIZE - W) // 2


def _knobby(m, cx, y_out, inward):
    """Stollenreifen als Scheibe in der x-z-Ebene; y_out = Aussenseite, inward = +1/-1 Richtung Fahrzeugmitte."""
    for dx in range(-R, R + 1):
        for dz in range(-R, R + 1):
            d = dx * dx + dz * dz
            if d > R * R:
                continue
            for k in range(4):                       # 4 Voxel breit: breite Gelaendereifen
                y = y_out + k * inward
                if d > (R - 2) ** 2:                 # Lauffläche mit Stollen (abwechselnd erhaben)
                    knob = (int((dx + 20) * 1.3 + (dz + 20) * 0.7) // 2) % 2 == 0
                    mm = "gl_knob" if knob and k in (0, 3) else "tire"
                elif k == 0 and d > (R - 4) ** 2:
                    mm = "black"                      # Flanke
                elif k == 0 and d > 2:
                    mm = "gl_rim"
                elif k == 0:
                    mm = "hub"
                else:
                    mm = "tire"
                m.put(cx + dx, y, R + dz, M(mm))


def gelaende_lkw():
    _mats()
    m = Model(SIZE, SIZE, 60)
    x0, y0 = origin()
    axles = (x0 + 14, x0 + 56)
    # Rahmen und Achsen (Bodenfreiheit: Aufbau beginnt erst bei z = 11)
    m.box(x0 + 4, y0 + 7, 8, x0 + 70, y0 + W - 7, 11, M("steel_dark"))
    for ax in axles:
        m.box(ax - 2, y0 + 3, 6, ax + 3, y0 + W - 3, 9, M("gl_bar"))
        m.box(ax - 2, y0 + W // 2 - 3, 4, ax + 3, y0 + W // 2 + 3, 9, M("steel_dark"))
        _knobby(m, ax, y0, 1)
        _knobby(m, ax, y0 + W - 1, -1)
    # Pritsche: Boden, Bordwaende in Firmenfarbe, Plane auf dem hinteren Teil
    bx0, bx1 = x0 + 2, x0 + 44
    m.box(bx0, y0 + 1, 11, bx1, y0 + W - 1, 13, M("deck"))
    for yy in (y0, y0 + W - 1):
        m.box(bx0, yy, 11, bx1, yy + 1, 20, M("comp"))
        for bx in range(bx0 + 5, bx1, 8):
            m.box(bx, yy, 11, bx + 1, yy + 1, 20, M("comp_dark"))
    m.box(bx0, y0, 11, bx0 + 1, y0 + W, 20, M("comp_dark"))
    m.box(bx1 - 1, y0, 11, bx1, y0 + W, 22, M("comp_dark"))               # Stirnwand
    m.box(bx0, y0, 19, bx1, y0 + 1, 20, M("comp_dark"))
    m.box(bx0, y0 + W - 1, 19, bx1, y0 + W, 20, M("comp_dark"))
    tx1 = bx0 + 27
    for x in range(bx0, tx1):
        rib = (x - bx0) % 7 == 0
        mm = M("gl_tarp2" if rib else "gl_tarp")
        for y in range(y0, y0 + W):
            off = min(y - y0, y0 + W - 1 - y)        # gewoelbte Plane: Rand tiefer als Mitte
            top = 26 + min(off, 3)
            if off == 0:
                m.box(x, y, 20, x + 1, y + 1, top + 1, mm)
            else:
                m.put(x, y, top, mm)
    m.box(bx0, y0, 20, bx0 + 1, y0 + W, 28, M("gl_tarp2"))
    for y in range(y0 + 3, y0 + W - 2, 5):                                  # Spanngurte am Heck
        m.box(bx0 - 1, y, 14, bx0, y + 1, 28, M("gl_bar"))
    # Reserverad stehend vor der Stirnwand
    for dy in range(-6, 7):
        for dz in range(-6, 7):
            d = dy * dy + dz * dz
            if d <= 36:
                mm = "tire" if d > 12 else ("gl_rim" if d > 2 else "hub")
                m.put(bx1 - 3, y0 + W // 2 + dy, 27 + dz, M(mm))
                m.put(bx1 - 2, y0 + W // 2 + dy, 27 + dz, M("tire"))
    # Kanister an der Bordwand (rechte Seite = Seite y0)
    for cx in (bx0 + 31, bx0 + 35):
        m.box(cx, y0 - 1, 12, cx + 3, y0, 18, M("gl_can"))
        m.box(cx + 1, y0 - 1, 18, cx + 2, y0, 19, M("gl_bar"))
    # Kabine
    cx0, cx1 = x0 + 46, x0 + 64
    m.box(cx0, y0, 11, cx1, y0 + W, 33, M("comp"))
    m.box(cx0, y0, 11, cx1, y0 + W, 14, M("gl_bar"))
    m.box(cx0, y0, 14, cx1, y0 + W, 16, M("comp_dark"))
    m.box(cx1 - 1, y0 + 1, 21, cx1, y0 + W - 1, 32, M("glass_dark"))
    m.box(cx1 - 1, y0 + W // 2, 21, cx1, y0 + W // 2 + 1, 32, M("comp_dark"))
    for yy in (y0, y0 + W - 1):
        m.box(cx0 + 3, yy, 21, cx1 - 2, yy + 1, 32, M("glass_dark"))
        m.box(cx0 + 10, yy, 21, cx0 + 11, yy + 1, 32, M("comp_dark"))
        m.box(cx0 + 12, yy, 18, cx0 + 15, yy + 1, 19, M("gl_bar"))
    m.box(cx0, y0 + 2, 22, cx0 + 1, y0 + W - 2, 31, M("glass_dark"))
    m.box(cx0, y0, 32, cx1, y0 + W, 34, M("comp_dark"))
    for x in range(cx0 + 1, cx1 - 3, 3):                                    # Dachtraeger
        m.box(x, y0 + 1, 34, x + 1, y0 + W - 1, 35, M("gl_bar"))
    m.box(cx0 + 1, y0 + 1, 35, cx1 - 3, y0 + 2, 36, M("gl_bar"))
    m.box(cx0 + 1, y0 + W - 2, 35, cx1 - 3, y0 + W - 1, 36, M("gl_bar"))
    m.box(cx1 - 3, y0 + 3, 34, cx1 - 1, y0 + W - 3, 37, M("gl_bar"))      # Lichtleiste
    for yy in range(y0 + 4, y0 + W - 5, 3):
        m.box(cx1 - 1, yy, 35, cx1, yy + 2, 37, M("gl_lamp"))
    m.box(cx0 + 2, y0 + W - 4, 34, cx0 + 4, y0 + W - 2, 37, M("gl_amber"))  # Rundumleuchte
    for yy in (y0 - 2, y0 + W):                                             # Spiegel
        m.box(cx1 - 3, yy, 25, cx1 - 2, yy + 2, 30, M("gl_bar"))
    # Motorhaube, Grill, Scheinwerfer, Stossstange, Seilwinde, Rammschutz
    hx1 = x0 + 72
    m.box(cx1, y0 + 1, 11, hx1, y0 + W - 1, 24, M("comp"))
    m.box(cx1, y0 + 1, 23, hx1, y0 + W - 1, 24, M("comp_dark"))
    m.box(hx1 - 1, y0 + 5, 13, hx1, y0 + W - 5, 22, M("gl_bar"))
    for z in range(14, 22, 2):
        m.box(hx1 - 1, y0 + 6, z, hx1, y0 + W - 6, z + 1, M("steel"))
    for yy in (y0 + 1, y0 + W - 4):
        m.box(hx1 - 1, yy, 17, hx1, yy + 3, 20, M("gl_lamp"))
    m.box(hx1, y0, 9, hx1 + 2, y0 + W, 13, M("gl_bar"))
    m.box(hx1 + 1, y0 + 9, 10, hx1 + 3, y0 + W - 9, 13, M("steel"))
    m.box(hx1 + 3, y0 + W // 2, 11, hx1 + 4, y0 + W // 2 + 1, 12, M("gl_amber"))
    for yy in (y0 + 1, y0 + W - 3):
        m.box(hx1 + 1, yy, 13, hx1 + 3, yy + 2, 22, M("gl_bar"))
    m.box(hx1 + 1, y0 + 1, 21, hx1 + 3, y0 + W - 1, 22, M("gl_bar"))
    # Schnorchel an der rechten A-Saeule, Auspuff hinter der Kabine
    m.box(cx1 - 1, y0 - 2, 13, cx1 + 1, y0, 36, M("gl_bar"))
    m.box(cx1 - 1, y0 - 2, 36, cx1 + 2, y0 + 1, 38, M("gl_bar"))
    m.box(cx0 - 2, y0 + W - 3, 13, cx0, y0 + W - 1, 37, M("steel_dark"))
    # Kotfluegel ueber den Raedern
    for ax in axles:
        for yy in (y0 - 1, y0 + W):
            for dx in range(-R - 1, R + 2):
                z = 18 if abs(dx) < R - 2 else 18 - (abs(dx) - (R - 3))
                m.box(ax + dx, yy, z, ax + dx + 1, yy + 1, z + 1, M("gl_bar"))
    for yy in (y0 + 1, y0 + W - 3):                                         # Ruecklichter
        m.box(x0 + 1, yy, 14, x0 + 2, yy + 2, 17, M("rear_lamp"))
    # Schlammspritzer am unteren Aufbau (fest aus der Position)
    for x in range(x0, hx1 + 3):
        for y in range(y0 - 2, y0 + W + 2):
            for z in range(4, 18):
                if m.get(x, y, z) and _hash3(x, y, z) < 0.22 - 0.012 * z:
                    m.put(x, y, z, M("gl_mud"))
    return m
