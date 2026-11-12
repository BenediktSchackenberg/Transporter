"""Steinbauten und Stein-Kreationen der Unternehmer (Auftrag 23).

Die KI-Spieler planen aus dieser Bibliothek ein Motiv (Name, Form, Standort); die Engine prueft Platz,
Strasse und Material und baut es auf dem eigenen Grundstueck als Steinbau. Jede Stein-Kreation waermt
zwei unabhaengige Farbmasken mit:

  * "comp"   -> Grundton   (grosse Flaechen: Sockel, Baukoerper, Platten)
  * "accent" -> Akzent     (Details: Kopf, Muster, Kanten, Spitze, Fenster)

Beide liegen standardmaessig als Naturstein (grau) im Farbbild; der Maler faerbt sie spaeter in die
gewuenschten Farben (zwei Ebenen, frei kombinierbar -> viele unterscheidbare Werke). Kontrastmaterial
(Wasser, Laub, Glas, Bronze) bleibt naturfarben und gibt Kontur. Ein Feld = 32x32 Voxel, Boden z = 1.

Seriöse Motive (Denkmal, Obelisk, Brunnen, Tor, Säule, Mauer) und verspielte Motive (Katze, UFO,
Eis, Pilz, Riesenrad, Karussell, Igel, Ballon, Leuchtturm) stehen nebeneinander – die KI entscheidet,
was sie baut. Alle Funktionen liefern ein Model mit comp/accent-Maske.
"""
import math

from engine import Model, M, mat

T = 32


def init():
    # Kontrastmaterialien (bleiben naturfarben, nicht Teil der Farbmasken)
    mat("sw_marble", "#e8e4da", noise=0.03)
    mat("sw_stone", "#9a978f", noise=0.06)
    mat("sw_stone_dark", "#7d7a72", noise=0.06)
    mat("sw_water", "#4aa3c9", noise=0.02, top=False)
    mat("sw_leaf", "#4f9140", noise=0.10, top=False)
    mat("sw_leaf_dark", "#2f6330", noise=0.08, top=False)
    mat("sw_bronze", "#a8743a", noise=0.05)
    mat("sw_glass", "#5d86a8", noise=0.02, top=False)
    mat("sw_gold", "#e3b53c", noise=0.03)


def _m(h=70):
    return Model(T, T, h)


def _m2(h=70, w=2):
    return Model(w * T, w * T, h)


def _pedestal(m, x0, y0, x1, y1, h, mat="comp"):
    m.box(x0 - 1, y0 - 1, 1, x1 + 1, y1 + 1, 2, M("sw_stone"))          # Basisplatte
    m.box(x0, y0, 2, x1, y1, 2 + h, M(mat))


# ------------------------------------------------------------------ Seriöse Steinbauten
def statue():
    """Steinstatue auf Stufensockel: Figur im Grundton, Sockelkante im Akzent."""
    m = _m(70)
    for i, r in enumerate((12, 10, 8)):
        m.box(16 - r, 16 - r, 1 + i * 3, 16 + r, 16 + r, 4 + i * 3, M("comp"))
    m.box(12, 12, 10, 20, 20, 11, M("accent"))                            # Sockelkante (Akzent)
    m.box(13, 13, 11, 19, 19, 16, M("comp"))                              # Brust
    for x in (12, 17):
        m.box(x, 14, 12, x + 2, 16, 17, M("comp"))                        # Schultern/Arme
    m.box(13, 14, 17, 17, 18, 26, M("comp"))                              # Torso
    m.box(14, 15, 26, 18, 19, 34, M("comp"))                              # Kopf
    m.box(13, 15, 33, 19, 19, 35, M("accent"))                            # Stirnband (Akzent)
    return m


def obelisk():
    """Hohler Obelisk aus Quadern: Schaft Grundton, Spitze und Basis Akzent."""
    m = _m(120)
    m.box(10, 10, 1, 22, 22, 3, M("accent"))                              # Basissockel (Akzent)
    for i in range(80):
        r = 4 - i // 28
        m.box(16 - r, 16 - r, 3 + i, 16 + r, 16 + r, 4 + i, M("comp"))
    m.box(14, 14, 83, 18, 18, 88, M("accent"))                            # Pyramidenfuss (Akzent)
    m.box(15, 15, 88, 17, 17, 92, M("sw_gold"))                           # Spitze
    return m


def fountain():
    """Springbrunnen: Becken Grundton, Wasser naturfarben, Fontäne Akzent."""
    m = _m(50)
    c = 16
    for x in range(T):
        for y in range(T):
            d = math.hypot(x - c, y - c)
            if d < 15:
                m.put(x, y, 1, M("comp"))
                if d > 12:
                    m.box(x, y, 2, x + 1, y + 1, 6, M("comp"))
                else:
                    m.put(x, y, 2, M("sw_water"))
    m.box(12, 12, 6, 20, 20, 8, M("accent"))                              # Mittelsockel (Akzent)
    m.box(14, 14, 8, 18, 18, 16, M("comp"))                               # Stumpf
    m.box(15, 15, 16, 17, 17, 22, M("accent"))                            # Fontänenkopf (Akzent)
    m.box(15, 15, 22, 17, 17, 24, M("sw_gold"))                           # Wassertropfen
    return m


def gate():
    """Triumph-/Stadttor: zwei Pfeiler + Sturz im Grundton, Schriftband Akzent."""
    m = _m(80)
    m.box(4, 12, 1, 12, 20, 44, M("comp"))                                # linker Pfeiler
    m.box(20, 12, 1, 28, 20, 44, M("comp"))                               # rechter Pfeiler
    m.box(4, 12, 44, 28, 20, 56, M("comp"))                               # Sturz
    m.box(4, 12, 56, 28, 20, 60, M("accent"))                             # Attika (Akzent)
    m.box(13, 13, 44, 19, 19, 56, M("accent"))                            # Schriftband (Akzent)
    for x in (5, 10, 21, 26):
        m.box(x, 11, 1, x + 2, 21, 44, M("comp"))                         # Kapitelle
    return m


def column():
    """Klassische Säule: Schaft Grundton, Kapitell und Plinthe Akzent."""
    m = _m(80)
    m.box(10, 10, 1, 22, 22, 4, M("accent"))                              # Plinthe (Akzent)
    for i in range(4):
        r = 5 - i // 12
        m.box(16 - r, 16 - r, 4 + i * 14, 16 + r, 16 + r, 18 + i * 14, M("comp"))
    m.box(11, 11, 56, 21, 21, 60, M("accent"))                            # Kapitell (Akzent)
    m.box(10, 10, 60, 22, 22, 62, M("sw_marble"))                         # Abakus
    return m


def monument_wall():
    """Niedrige Ehren-/Gedächtniswand mit eingelassener Platte: Wand Grundton, Platte Akzent."""
    m = _m(40)
    m.box(3, 12, 1, 29, 20, 20, M("comp"))                                # Wand
    m.box(2, 12, 20, 30, 20, 22, M("comp"))                               # Gesims
    m.box(2, 12, 22, 30, 20, 24, M("accent"))                             # Kante (Akzent)
    m.box(10, 12, 8, 22, 14, 18, M("accent"))                             # Gedenktafel (Akzent)
    for x in (6, 14, 22):
        m.box(x, 11, 1, x + 2, 21, 24, M("sw_stone_dark"))                # Pfeiler
    return m


# ------------------------------------------------------------------ Verspielte Stein-Kreationen
def cat_statue():
    """Steinkatze im Sitzen: Körper Grundton, Gesicht, Pfoten und Ohren Akzent."""
    m = _m(60)
    m.box(10, 14, 1, 22, 24, 18, M("comp"))                               # Hinterkörper
    m.box(11, 13, 14, 21, 23, 30, M("comp"))                              # Rücken
    m.box(12, 12, 30, 20, 20, 42, M("comp"))                              # Hals
    m.box(11, 11, 40, 21, 21, 52, M("comp"))                              # Kopf
    m.box(10, 12, 50, 13, 15, 56, M("accent"))                            # Ohr links (Akzent)
    m.box(19, 12, 50, 22, 15, 56, M("accent"))                            # Ohr rechts (Akzent)
    m.box(12, 11, 44, 20, 14, 48, M("accent"))                            # Gesicht (Akzent)
    for x in (13, 18):
        m.box(x, 12, 45, x + 2, 13, 47, M("sw_stone_dark"))               # Augen
    m.box(15, 11, 45, 17, 12, 47, M("sw_gold"))                           # Nase
    m.box(8, 18, 1, 24, 20, 4, M("accent"))                               # Pfoten (Akzent)
    m.box(20, 12, 1, 28, 14, 8, M("comp"))                                # Schwanz
    m.box(26, 10, 8, 29, 12, 14, M("comp"))
    return m


def ufo():
    """Ufo-Stein: Scheibe Grundton, Kuppel und Landungspunkte Akzent."""
    m = _m(40)
    for x in range(T):
        for y in range(T):
            d = math.hypot(x - 16, y - 16)
            if d < 14:
                m.put(x, y, 1, M("comp"))
                if d > 8:
                    m.box(x, y, 2, x + 1, y + 1, 4, M("comp"))
    m.box(8, 8, 4, 24, 24, 7, M("comp"))                                  # Scheibenkörper
    m.box(11, 11, 7, 21, 21, 11, M("accent"))                             # Kuppel (Akzent)
    m.box(13, 13, 11, 19, 19, 14, M("accent"))
    for x, y in ((6, 12), (6, 20), (24, 12), (24, 20)):                   # Leuchten (Akzent)
        m.box(x, y, 4, x + 2, y + 2, 5, M("sw_gold"))
    for x, y in ((8, 8), (8, 22), (22, 8), (22, 22)):                     # Landbeine
        m.box(x, y, 1, x + 1, y + 1, 2, M("sw_stone_dark"))
    return m


def ice_cream():
    """Rieseneis: Waffelkegel Grundton, Kugel und Schleife Akzent."""
    m = _m(80)
    m.box(13, 13, 1, 19, 19, 20, M("comp"))                               # Kegel (Grundton)
    for z in range(4, 20, 4):                                             # Waffelmuster (Akzent)
        m.box(13, 13, z, 19, 19, z + 1, M("accent"))
    m.box(11, 11, 20, 21, 21, 34, M("accent"))                            # Kugel (Akzent)
    m.box(13, 13, 34, 19, 19, 42, M("accent"))
    for a in range(4):                                                    # Schmaeher
        for i in range(10):
            m.put(16 + int(math.cos(a * 1.57) * (10 - i * 0.6)),
                  16 + int(math.sin(a * 1.57) * (10 - i * 0.6)), 34 + i // 2, M("sw_gold"))
    m.box(14, 14, 42, 18, 18, 46, M("sw_leaf_dark"))                      # Kirsche
    m.box(15, 15, 46, 17, 17, 48, M("sw_gold"))
    return m


def mushroom():
    """Pilzhütte: Hut Grundton mit Punkten (Akzent), Hauswand + Tür Akzent."""
    m = _m(60)
    m.box(9, 9, 1, 23, 23, 22, M("comp"))                                 # Stiel/Wand
    m.box(13, 13, 22, 19, 19, 26, M("comp"))
    m.box(13, 13, 12, 19, 13, 22, M("accent"))                            # Tür (Akzent)
    m.put(16, 13, 15, M("sw_gold"))                                       # Klinke
    # Hut: umlaufend abfallend
    for x in range(T):
        for y in range(T):
            d = math.hypot(x - 16, y - 16)
            hz = 26 + int(8 - d * 0.5)
            if d < 15:
                m.box(x, y, 26, x + 1, y + 1, max(27, hz), M("comp"))
    for x, y in ((10, 12), (20, 12), (16, 20), (12, 20), (22, 18)):       # Punkte (Akzent)
        m.box(x, y, 26, x + 2, y + 2, 28, M("accent"))
    m.box(15, 12, 30, 17, 14, 33, M("accent"))                            # Frontfenster
    return m


def ferris_wheel():
    """Riesenrad: Ständer + Nabe Grundton, Speichen und Gondeln Akzent."""
    m = _m(90)
    m.box(14, 14, 1, 18, 18, 40, M("comp"))                               # Ständer
    m.box(12, 12, 1, 20, 20, 3, M("comp"))                                # Sockel
    m.box(13, 13, 40, 19, 19, 44, M("comp"))                              # Nabe
    m.box(14, 14, 44, 18, 18, 48, M("accent"))                            # Nabenkappe (Akzent)
    for a in range(8):                                                    # Speichen + Gondeln
        for i in range(12):
            m.put(16 + int(math.cos(a * 0.785) * i), 16 + int(math.sin(a * 0.785) * i),
                  46 + int(i), M("comp"))
        m.box(16 + int(math.cos(a * 0.785) * 12) - 1,
              16 + int(math.sin(a * 0.785) * 12) - 1, 44 + 11,
              16 + int(math.cos(a * 0.785) * 12) + 1,
              16 + int(math.sin(a * 0.785) * 12) + 1, 47 + 11, M("accent"))
    for x in (10, 22):                                                     # Beine
        m.box(x, 12, 1, x + 2, 20, 3, M("comp"))
    return m


def carousel():
    """Karussell: Drehbühne Grundton, Dachrand + Säulenköpfe Akzent."""
    m = _m(60)
    for x in range(T):
        for y in range(T):
            d = math.hypot(x - 16, y - 16)
            if d < 14:
                m.put(x, y, 1, M("comp"))
                if d > 11:
                    m.box(x, y, 2, x + 1, y + 1, 6, M("comp"))
    m.box(9, 9, 6, 23, 23, 9, M("comp"))                                  # Bühne
    for x, y in ((6, 6), (6, 24), (24, 6), (24, 24)):
        m.box(x, y, 6, x + 2, y + 2, 34, M("comp"))                       # Säulen
        m.box(x - 1, y - 1, 34, x + 3, y + 3, 36, M("accent"))            # Kapitell (Akzent)
    for x in range(T):
        for y in range(T):
            d = math.hypot(x - 16, y - 16)
            hz = 36 + int(10 - d)
            if d < 15:
                m.box(x, y, 36, x + 1, y + 1, max(37, hz), M("comp"))     # Kuppeldach
    m.box(7, 7, 36, 25, 25, 37, M("accent"))                              # Dachring (Akzent)
    m.box(15, 15, 45, 17, 17, 48, M("sw_gold"))                           # Spitze
    for x, y in ((10, 16), (22, 16), (16, 10)):                           # Pferde
        m.box(x, y, 6, x + 3, y + 2, 10, M("accent"))
        m.box(x, y - 1, 10, x + 2, y, 12, M("accent"))
    return m


def hedgehog():
    """Steinigel: Körper Grundton, Stacheln und Schnauze Akzent."""
    m = _m(40)
    m.box(8, 12, 1, 24, 22, 14, M("comp"))                                # Körper
    for x in range(8, 24):
        for y in range(12, 22):
            if (x + y) % 3 == 0 and 1 <= math.hypot(x - 16, y - 16) < 9:  # Stacheln
                m.box(x, y, 14, x + 1, y + 1, 17, M("accent"))
    m.box(22, 14, 8, 29, 18, 14, M("accent"))                             # Schnauze (Akzent)
    m.put(29, 15, 11, M("sw_stone_dark"))                                 # Nase
    m.box(24, 15, 11, 25, 16, 12, M("sw_stone_dark"))                     # Auge
    for x in (10, 20):
        m.box(x, 20, 1, x + 2, 22, 3, M("comp"))                          # Pfoten
    return m


def balloon():
    """Ballon-Stein: Korb Grundton, Ballonkappe und Streifen Akzent."""
    m = _m(90)
    m.box(11, 11, 1, 21, 21, 8, M("comp"))                                # Korb
    m.box(13, 13, 8, 19, 19, 14, M("comp"))                               # Zügel
    m.box(12, 12, 14, 20, 20, 16, M("comp"))
    m.box(8, 8, 16, 24, 24, 52, M("accent"))                              # Ballon (Akzent)
    for i in range(6):                                                     # Streifen (Grundton)
        m.box(8 + i * 3, 8, 16, 9 + i * 3, 24, 52, M("comp"))
    for x in range(8, 24, 3):                                             # Kegel unten
        m.box(x, 14, 12, x + 2, 18, 16, M("accent"))
    return m


def lighthouse():
    """Leuchtturm: Turm Grundton, Leuchtkammer und Streifen Akzent."""
    m = _m(100)
    for i in range(7):
        r = 6 - i // 2
        z0 = 4 + i * 12
        m.box(16 - r, 16 - r, z0, 16 + r, 16 + r, z0 + 12, M("comp" if i % 2 == 0 else "accent"))
    m.box(10, 10, 88, 22, 22, 92, M("sw_glass"))                          # Leuchtkammer
    m.box(11, 11, 92, 21, 21, 96, M("accent"))                            # Galerie (Akzent)
    m.box(12, 12, 96, 20, 20, 100, M("comp"))                             # Kuppel
    m.box(10, 10, 1, 22, 22, 4, M("sw_stone"))                            # Fundament
    for x, y in ((8, 8), (24, 8), (8, 24), (24, 24)):                     # Geländerpfosten
        m.box(x, y, 90, x + 1, y + 1, 96, M("accent"))
    return m


def turtle():
    """Stein-Schildkröte: Panzer Grundton, Kopf, Beine und Panzermuster Akzent."""
    m = _m(40)
    m.box(6, 11, 1, 26, 21, 12, M("comp"))                                # Panzer
    for x in range(6, 26):
        for y in range(11, 21):
            if (x // 4 + y // 4) % 2 == 0:
                m.box(x, y, 12, x + 1, y + 1, 14, M("accent"))            # Schuppen (Akzent)
    m.box(26, 13, 6, 30, 19, 12, M("accent"))                             # Kopf (Akzent)
    m.put(30, 15, 9, M("sw_stone_dark"))                                  # Auge
    for x, y in ((8, 8), (8, 22), (20, 8), (20, 22)):                     # Beine
        m.box(x, y, 1, x + 3, y + 3, 4, M("accent"))
    return m


def rocket():
    """Steinrakete: Rumpf Grundton, Fins und Fensterscheibe Akzent/Glas."""
    m = _m(110)
    for z in range(1, 70):
        r = 4 + z // 20
        m.box(16 - r, 16 - r, z, 16 + r, 16 + r, z + 1, M("comp"))
    for z in range(60):                                                    # Spitze
        r = 4 + (70 - z) // 12
        m.box(16 - r, 16 - r, 70 + z, 16 + r, 16 + r, 71 + z, M("comp"))
    m.box(13, 13, 70, 19, 19, 92, M("accent"))                            # Nasenkap (Akzent)
    m.box(9, 14, 1, 13, 18, 16, M("accent"))                              # Flosse links (Akzent)
    m.box(19, 14, 1, 23, 18, 16, M("accent"))                             # Flosse rechts (Akzent)
    m.box(14, 12, 1, 18, 16, 16, M("accent"))                             # Flosse vorn
    m.box(14, 14, 30, 18, 18, 36, M("sw_glass"))                          # Fenster
    m.box(14, 14, 36, 18, 18, 38, M("comp"))
    return m


## Alle Motive als Tabelle id -> (label, Funktion, w, h) — w/h in Feldern (1 oder 2).
MOTIFS = {
    "statue": ("Statue", statue, 1, 1),
    "obelisk": ("Obelisk", obelisk, 1, 1),
    "fountain": ("Springbrunnen", fountain, 1, 1),
    "gate": ("Triumphbogen", gate, 1, 1),
    "column": ("Säule", column, 1, 1),
    "monument_wall": ("Gedächtniswand", monument_wall, 1, 1),
    "cat_statue": ("Steinkatze", cat_statue, 1, 1),
    "ufo": ("Ufo-Stein", ufo, 1, 1),
    "ice_cream": ("Rieseneis", ice_cream, 1, 1),
    "mushroom": ("Pilzhütte", mushroom, 1, 1),
    "ferris_wheel": ("Riesenrad", ferris_wheel, 1, 1),
    "carousel": ("Karussell", carousel, 1, 1),
    "hedgehog": ("Steinigel", hedgehog, 1, 1),
    "balloon": ("Ballon-Stein", balloon, 1, 1),
    "lighthouse": ("Leuchtturm", lighthouse, 1, 1),
    "turtle": ("Stein-Schildkröte", turtle, 1, 1),
    "rocket": ("Steinrakete", rocket, 1, 1),
}


def names():
    return list(MOTIFS.keys())
