"""Schwerer Tandemrotor-Materialhubschrauber im bestehenden Voxelstil.

Der Rumpf wird in vier Richtungen gebacken. Beide Rotoren bleiben getrennte,
im Spiel animierte Ebenen, damit sie beim Flug und Laden sichtbar drehen.
"""
from engine import Model, mat, M


def init():
    mat("heli_body", "#4f737a", noise=0.035)
    mat("heli_dark", "#29454f", noise=0.025)
    mat("heli_light", "#91aeb3", noise=0.02)
    mat("heli_stripe", "#eab552", noise=0.015)
    mat("heli_glass", "#6dabc1", noise=0.015, top=False)
    mat("heli_rotor", "#1e2c34", noise=0.01)
    mat("heli_lamp", "#ed5141", noise=0.0, emit="#ff5a4c", top=False)


def chinook():
    s = 100
    m = Model(s, s, 52)
    B, D, L, G, Y, R = (M(x) for x in ("heli_body", "heli_dark", "heli_light", "heli_glass", "heli_stripe", "heli_rotor"))
    # Langer, kantiger Transport-Rumpf; Nase zeigt nach +x.
    m.box(15, 37, 10, 81, 63, 27, B)
    m.box(20, 39, 8, 76, 61, 11, D)
    m.box(17, 38, 22, 79, 62, 28, D)
    m.box(23, 39, 27, 73, 61, 29, B)
    # Hoher Heckaufbau und angeschraegte Cockpitstirn.
    m.box(15, 40, 12, 29, 60, 32, B)
    m.box(18, 39, 28, 36, 61, 32, D)
    m.box(74, 40, 12, 82, 60, 25, B)
    m.box(80, 42, 14, 87, 58, 22, G)
    m.box(83, 44, 11, 88, 56, 15, D)
    # Panorama-Cockpit mit geteilter Scheibe, zwei seitliche Fenster.
    for y in (38, 61):
        m.box(70, y, 17, 81, y + 1, 25, G)
        m.box(75, y, 17, 76, y + 1, 25, D)
        for x in (50, 60):
            m.box(x, y, 18, x + 6, y + 1, 23, G)
    # Seitliches Frachttor, Schiebeprofil und Warnstreifen.
    m.box(31, 36, 13, 47, 38, 24, D)
    m.box(31, 62, 13, 47, 64, 24, D)
    for x in (31, 35, 39, 43):
        m.box(x, 36, 11, x + 2, 38, 14, Y)
        m.box(x, 62, 11, x + 2, 64, 14, Y)
    m.box(17, 36, 15, 72, 38, 17, Y)
    m.box(17, 62, 15, 72, 64, 17, Y)
    # Heckklappe als sichtbare Ladekante.
    m.box(11, 40, 8, 17, 60, 18, D)
    m.box(10, 42, 7, 15, 58, 9, L)
    for y in (39, 59):
        m.put(13, y, 17, M("heli_lamp"))
    # Vier Fahrwerksbeine mit groben Reifen.
    for x in (26, 71):
        for y in (36, 62):
            m.box(x, y, 2, x + 3, y + 2, 12, R)
            m.box(x - 3, y - 2, 1, x + 5, y + 4, 6, R)
            m.box(x - 1, y - 2, 2, x + 3, y + 4, 5, L)
    # Die beiden Rotortriebwerke und Masten; Rotorblaetter werden animiert.
    for x in (31, 68):
        m.box(x - 6, 44, 28, x + 7, 56, 33, D)
        m.box(x - 2, 47, 33, x + 3, 53, 40, R)
        m.box(x - 5, 47, 39, x + 6, 53, 41, L)
    # Unterflurhaken, Antennen und Positionslichter.
    m.box(47, 48, 5, 52, 53, 10, R)
    m.box(84, 49, 24, 86, 51, 28, R)
    m.put(85, 50, 28, M("heli_lamp"))
    m.put(26, 37, 30, M("heli_lamp"))
    return m
