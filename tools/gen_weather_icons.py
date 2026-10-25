"""Erzeugt die Wettersymbole assets/gfx/i_w_*.png (32x32, Pixel-Art, dunkle 1-px-Kontur)."""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "gfx")
OUTLINE = (24, 22, 34, 255)
SUN = (255, 206, 70, 255)
SUN_L = (255, 238, 150, 255)
CLOUD = (226, 230, 240, 255)
CLOUD_D = (160, 168, 188, 255)
RAIN = (90, 170, 255, 255)
SNOW = (245, 250, 255, 255)
MOON = (240, 232, 190, 255)
BOLT = (255, 220, 60, 255)


def canvas():
    return Image.new("RGBA", (32, 32), (0, 0, 0, 0))


def outline(im):
    px = im.load()
    out = im.copy()
    op = out.load()
    for y in range(32):
        for x in range(32):
            if px[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 32 and 0 <= ny < 32 and px[nx, ny][3] > 0 and px[nx, ny] != OUTLINE:
                        op[x, y] = OUTLINE
                        break
    return out


def disc(d, cx, cy, r, col):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=col)


def cloud(d, ox=0, oy=0, dark=False):
    c = CLOUD_D if dark else CLOUD
    disc(d, 11 + ox, 17 + oy, 6, c)
    disc(d, 18 + ox, 13 + oy, 7, c)
    disc(d, 24 + ox, 18 + oy, 5, c)
    d.rectangle((11 + ox, 18 + oy, 24 + ox, 23 + oy), fill=c)
    d.line((10 + ox, 22 + oy, 25 + ox, 22 + oy), fill=(c[0] - 30, c[1] - 30, c[2] - 30, 255))


def sun(d, cx=16, cy=16, r=6):
    for a in range(8):
        import math
        x1 = cx + math.cos(a * math.pi / 4) * (r + 3)
        y1 = cy + math.sin(a * math.pi / 4) * (r + 3)
        x2 = cx + math.cos(a * math.pi / 4) * (r + 6)
        y2 = cy + math.sin(a * math.pi / 4) * (r + 6)
        d.line((x1, y1, x2, y2), fill=SUN, width=2)
    disc(d, cx, cy, r, SUN)
    disc(d, cx - 2, cy - 2, r // 2, SUN_L)


def make(name, fn):
    im = canvas()
    fn(ImageDraw.Draw(im))
    outline(im).save(os.path.join(OUT, f"i_w_{name}.png"))


def f_sonne(d):
    sun(d)


def f_mond(d):
    disc(d, 15, 16, 10, MOON)
    disc(d, 21, 12, 9, (0, 0, 0, 0))
    d.ellipse((12, 10, 30, 28), fill=(0, 0, 0, 0))
    disc(d, 13, 16, 9, MOON)
    d.ellipse((14, 6, 32, 24), fill=(0, 0, 0, 0))


def f_wolke(d):
    sun(d, 10, 10, 4)
    cloud(d, 0, 4)


def f_regen(d):
    cloud(d, 0, -3, dark=True)
    for x, y in ((10, 22), (16, 25), (22, 22), (13, 28), (19, 29)):
        d.line((x, y, x - 2, y + 3), fill=RAIN, width=2)


def f_schnee(d):
    cloud(d, 0, -3)
    for x, y in ((10, 24), (17, 27), (23, 24), (13, 29), (20, 30)):
        d.rectangle((x, y, x + 1, y + 1), fill=SNOW)
        d.point((x - 1, y), fill=SNOW)
        d.point((x + 2, y + 1), fill=SNOW)


def f_nebel(d):
    for y, x0, x1 in ((9, 6, 24), (14, 4, 27), (19, 7, 28), (24, 5, 22)):
        d.rectangle((x0, y, x1, y + 2), fill=CLOUD)


def f_gewitter(d):
    cloud(d, 0, -4, dark=True)
    d.polygon([(17, 17), (11, 26), (16, 26), (13, 31), (22, 21), (17, 21), (20, 17)], fill=BOLT)


for n, f in (("sonne", f_sonne), ("mond", f_mond), ("wolke", f_wolke), ("regen", f_regen), ("schnee", f_schnee),
             ("nebel", f_nebel), ("gewitter", f_gewitter)):
    make(n, f)
print("ok")
