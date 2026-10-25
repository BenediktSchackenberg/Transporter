"""Voxel-Renderer fuer die isometrische Miniaturstadt (siehe ART_DIRECTION.md).

Projektion (Dimetrie 2:1): sx = 2*(x - y), sy = (x + y) - 2*z. Blick aus (+x, +y, +z).
Jeder sichtbare Voxel belegt 12 Pixel: Oberseite (4), linke Seite = +y-Flaeche (4), rechte Seite = +x-Flaeche (4).
Ausgabe je Modell: Farbbild, Emissionsbild (Nachtlicht), Oberseitenmaske (Schnee/Naesse), Firmenfarbmaske,
Aussenschatten und der Ankerpunkt (Bildposition des Weltursprungs).
"""
import numpy as np
from PIL import Image, ImageFilter

# ------------------------------------------------------------------ Materialien
MATS = [None]           # Index 0 = leer
MAT_ID = {}


def mat(name, rgb, noise=0.06, emit=None, comp=False, top=True, glow=0.0):
    """Material registrieren. emit: Leuchtfarbe (Nacht), comp: Firmenfarbe, top: Teil der Schnee/Naesse-Maske."""
    if name in MAT_ID:
        return MAT_ID[name]
    if isinstance(rgb, str):
        rgb = tuple(int(rgb.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    if isinstance(emit, str):
        emit = tuple(int(emit.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    MATS.append({"name": name, "rgb": np.array(rgb, dtype=np.float32), "noise": noise, "emit": emit, "comp": comp,
                 "top": top, "glow": glow})
    MAT_ID[name] = len(MATS) - 1
    return MAT_ID[name]


def M(name):
    return MAT_ID[name]


FACE_SHADE = {"top": 1.0, "left": 0.80, "right": 0.62}
# Pixelversatz relativ zur oberen Rautenspitze A = (2(x-y), x+y-2z-2)
STAMPS = {
    "top": [(-1, 0), (0, 0), (-1, 1), (0, 1)],
    "left": [(-2, 1), (-2, 2), (-1, 2), (-1, 3)],
    "right": [(1, 1), (1, 2), (0, 2), (0, 3)],
}
SUN_STEP = (-1, 0, 2)    # Richtung zur Sonne je Schritt: -x, +2z (Schattenlaenge = Hoehe / 2)


class Model:
    def __init__(self, sx, sy, sz):
        self.g = np.zeros((sx, sy, sz), dtype=np.uint8)
        self.size = (sx, sy, sz)

    # --- Grundformen (halboffene Intervalle, werden auf das Gitter beschnitten)
    def box(self, x0, y0, z0, x1, y1, z1, m):
        sx, sy, sz = self.size
        x0, y0, z0 = max(0, int(x0)), max(0, int(y0)), max(0, int(z0))
        x1, y1, z1 = min(sx, int(x1)), min(sy, int(y1)), min(sz, int(z1))
        if x0 < x1 and y0 < y1 and z0 < z1:
            self.g[x0:x1, y0:y1, z0:z1] = m

    def clear(self, x0, y0, z0, x1, y1, z1):
        self.box(x0, y0, z0, x1, y1, z1, 0)

    def put(self, x, y, z, m):
        sx, sy, sz = self.size
        if 0 <= x < sx and 0 <= y < sy and 0 <= z < sz:
            self.g[int(x), int(y), int(z)] = m

    def get(self, x, y, z):
        sx, sy, sz = self.size
        if 0 <= x < sx and 0 <= y < sy and 0 <= z < sz:
            return int(self.g[int(x), int(y), int(z)])
        return 0

    def fill(self, x0, y0, z0, x1, y1, z1, fn):
        """Bereich mit fn(x, y, z) -> Material (0 = leer lassen) fuellen."""
        for x in range(max(0, x0), min(self.size[0], x1)):
            for y in range(max(0, y0), min(self.size[1], y1)):
                for z in range(max(0, z0), min(self.size[2], z1)):
                    m = fn(x, y, z)
                    if m:
                        self.g[x, y, z] = m

    def rotated(self, k):
        """Um die z-Achse in 90-Grad-Schritten drehen (k = 0..3); bei ungeradem k werden x- und y-Ausdehnung vertauscht."""
        g = np.rot90(self.g, k % 4, axes=(0, 1)).copy()
        out = Model(g.shape[0], g.shape[1], g.shape[2])
        out.g = g
        return out

    def blit(self, other, ox, oy, oz):
        """Anderes Modell einsetzen (leere Voxel ueberschreiben nichts)."""
        sx, sy, sz = other.size
        for x in range(sx):
            tx = ox + x
            if not 0 <= tx < self.size[0]:
                continue
            for y in range(sy):
                ty = oy + y
                if not 0 <= ty < self.size[1]:
                    continue
                col = other.g[x, y]
                nz = np.nonzero(col)[0]
                for z in nz:
                    tz = oz + z
                    if 0 <= tz < self.size[2]:
                        self.g[tx, ty, tz] = col[z]


def _hash(x, y, z):
    h = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def render(model, shadow_len=64, outline=True, ground_shadow=True, ao=True):
    g = model.g
    sx, sy, sz = g.shape
    occ = g > 0
    pad = np.zeros((sx + 1, sy + 1, sz + 1), dtype=bool)
    pad[:sx, :sy, :sz] = occ
    # Schatten: S[x,y,z] = True, wenn auf dem Weg zur Sonne ein Voxel liegt
    S = np.zeros((sx + 1, sy + 1, sz + 1), dtype=bool)
    if shadow_len > 0:
        for k in range(1, shadow_len + 1):
            dx, dz = SUN_STEP[0] * k, SUN_STEP[2] * k
            if dz >= sz:
                break
            # S[x, y, z] |= occ[x + dx, y, z + dz]
            xs0, xs1 = max(0, -dx), sx            # Ziel-x mit x + dx >= 0
            zs1 = sz - dz
            if xs0 >= xs1 or zs1 <= 0:
                continue
            S[xs0:xs1, :sy, :zs1] |= occ[xs0 + dx:xs1 + dx, :, dz:dz + zs1]
    faces = {
        "top": occ & ~pad[:sx, :sy, 1:sz + 1],
        "left": occ & ~pad[:sx, 1:sy + 1, :sz],
        "right": occ & ~pad[1:sx + 1, :sy, :sz],
    }
    shadow_probe = {"top": (0, 0, 1), "left": (0, 1, 0), "right": (1, 0, 0)}
    px_x, px_y, px_d, px_c, px_e, px_t, px_m = [], [], [], [], [], [], []
    mat_rgb = np.array([[0, 0, 0]] + [m["rgb"] for m in MATS[1:]], dtype=np.float32)
    mat_noise = np.array([0] + [m["noise"] for m in MATS[1:]], dtype=np.float32)
    mat_emit = np.array([[0, 0, 0]] + [m["emit"] if m["emit"] else (0, 0, 0) for m in MATS[1:]], dtype=np.float32)
    mat_has_emit = np.array([False] + [m["emit"] is not None for m in MATS[1:]])
    mat_comp = np.array([False] + [m["comp"] for m in MATS[1:]])
    mat_top = np.array([False] + [m["top"] for m in MATS[1:]])
    for face, mask in faces.items():
        xs, ys, zs = np.nonzero(mask)
        if xs.size == 0:
            continue
        mids = g[xs, ys, zs]
        h = ((xs * 73856093) ^ (ys * 19349663) ^ (zs * 83492791)) & 0xFFFFFF
        h = ((h * 2654435761) >> 8) & 0xFFFF
        jitter = 1.0 + (h / 65535.0 - 0.5) * 2.0 * mat_noise[mids]
        shade = np.full(xs.shape, FACE_SHADE[face], dtype=np.float32)
        ox, oy, oz = shadow_probe[face]
        shadowed = S[np.minimum(xs + ox, sx), np.minimum(ys + oy, sy), np.minimum(zs + oz, sz)]
        shade = np.where(shadowed, shade * (0.70 if face != "right" else 0.88), shade)
        if ao and face == "top":
            cnt = np.zeros(xs.shape, dtype=np.float32)
            for ddx, ddy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)):
                nx, ny = np.clip(xs + ddx, 0, sx - 1), np.clip(ys + ddy, 0, sy - 1)
                nz = np.minimum(zs + 1, sz - 1)
                cnt += occ[nx, ny, nz] & (zs + 1 < sz)
            shade *= 1.0 - np.minimum(cnt, 5) * 0.045
        if ao and face != "top":
            # Kontaktschatten am Fuss von Waenden (Voxel darunter vorhanden, davor Boden)
            below_front = np.zeros(xs.shape, dtype=bool)
            if face == "left":
                below_front = occ[xs, np.minimum(ys + 1, sy - 1), np.maximum(zs - 1, 0)] & (ys + 1 < sy) & (zs > 0)
            else:
                below_front = occ[np.minimum(xs + 1, sx - 1), ys, np.maximum(zs - 1, 0)] & (xs + 1 < sx) & (zs > 0)
            shade = np.where(below_front, shade * 0.86, shade)
        col = mat_rgb[mids] * (shade * jitter)[:, None]
        ax = 2 * (xs - ys)
        ay = xs + ys - 2 * zs - 2
        depth = xs + ys + zs
        for (dx, dy) in STAMPS[face]:
            px_x.append(ax + dx)
            px_y.append(ay + dy)
            px_d.append(depth)
            px_c.append(col)
            px_e.append(mids)
            px_t.append(np.full(xs.shape, face == "top"))
            px_m.append(shade * jitter)
    if not px_x:
        return None
    X = np.concatenate(px_x)
    Y = np.concatenate(px_y)
    D = np.concatenate(px_d)
    C = np.concatenate(px_c)
    E = np.concatenate(px_e)
    T = np.concatenate(px_t)
    SH = np.concatenate(px_m)
    # Aussenschatten auf dem Boden (Ebene z = 0) ausserhalb der Bodenplatte
    gs_x, gs_y = np.array([], dtype=np.int64), np.array([], dtype=np.int64)
    if ground_shadow and shadow_len > 0:
        ground_free = ~occ[:, :, 0]
        sh = S[:sx, :sy, 1] & ground_free
        gx, gy = np.nonzero(sh)
        if gx.size:
            ax = 2 * (gx - gy)
            ay = gx + gy - 2 * 0 - 2 + 2   # Oberseite der Bodenebene liegt bei z = 1 (wie Bodenplatten)
            sx_list, sy_list = [], []
            for (dx, dy) in STAMPS["top"]:
                sx_list.append(ax + dx)
                sy_list.append(ay + dy - 2)
            gs_x = np.concatenate(sx_list)
            gs_y = np.concatenate(sy_list)
    minx = min(X.min(), gs_x.min() if gs_x.size else X.min()) - 2
    miny = min(Y.min(), gs_y.min() if gs_y.size else Y.min()) - 2
    maxx = max(X.max(), gs_x.max() if gs_x.size else X.max()) + 2
    maxy = max(Y.max(), gs_y.max() if gs_y.size else Y.max()) + 2
    W, H = int(maxx - minx + 1), int(maxy - miny + 1)
    Xi, Yi = (X - minx).astype(np.int64), (Y - miny).astype(np.int64)
    flat = Yi * W + Xi
    # naechster Voxel je Pixel gewinnt
    order = np.lexsort((D, flat))
    flat_s = flat[order]
    last = np.ones(flat_s.size, dtype=bool)
    last[:-1] = flat_s[1:] != flat_s[:-1]
    sel = order[last]
    img = np.zeros((H * W, 4), dtype=np.float32)
    depth = np.full(H * W, -10 ** 9, dtype=np.int64)
    img[flat[sel], :3] = C[sel]
    img[flat[sel], 3] = 255
    depth[flat[sel]] = D[sel]
    mids = np.zeros(H * W, dtype=np.int64)
    mids[flat[sel]] = E[sel]
    topm = np.zeros(H * W, dtype=bool)
    topm[flat[sel]] = T[sel]
    shades = np.zeros(H * W, dtype=np.float32)
    shades[flat[sel]] = SH[sel]
    img = img.reshape(H, W, 4)
    depth = depth.reshape(H, W)
    mids = mids.reshape(H, W)
    alpha = img[:, :, 3] > 0
    if outline:
        # Silhouette dunkel, Tiefenspruenge (Vorderkante ueber Hintergrund) leicht dunkel
        edge = np.zeros_like(alpha)
        inner = np.zeros_like(alpha)
        for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nb_a = np.roll(np.roll(alpha, ddy, axis=0), ddx, axis=1)
            nb_d = np.roll(np.roll(depth, ddy, axis=0), ddx, axis=1)
            edge |= alpha & ~nb_a
            inner |= alpha & nb_a & (depth > nb_d + 5)
        img[edge, :3] *= 0.52
        img[inner & ~edge, :3] *= 0.80
    img[:, :, :3] = np.clip(img[:, :, :3], 0, 255)
    color = Image.fromarray(img.astype(np.uint8), "RGBA")
    # Emission
    em = np.zeros((H, W, 4), dtype=np.float32)
    has_e = mat_has_emit[mids] & alpha
    em[has_e, :3] = mat_emit[mids[has_e]]
    em[has_e, 3] = 255
    lit = Image.fromarray(em.astype(np.uint8), "RGBA")
    if has_e.any():
        glow = lit.filter(ImageFilter.GaussianBlur(3))
        ga = np.array(glow).astype(np.float32)
        ga[:, :, 3] *= 0.55
        base = np.array(lit).astype(np.float32)
        out = np.where(base[:, :, 3:4] > 0, base, ga)
        lit = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    # Oberseitenmaske (Schnee/Naesse) und Firmenfarbmaske (schattiert)
    tm = np.zeros((H, W, 4), dtype=np.uint8)
    t_ok = topm.reshape(H, W) & mat_top[mids] & alpha & ~mat_has_emit[mids]
    tm[t_ok] = (255, 255, 255, 255)
    cm = np.zeros((H, W, 4), dtype=np.float32)
    c_ok = mat_comp[mids] & alpha
    sh2 = shades.reshape(H, W)
    cm[c_ok, :3] = (255.0 * np.clip(sh2[c_ok], 0, 1.2))[:, None]
    cm[c_ok, 3] = 255
    out = {"color": color, "lit": lit, "top": Image.fromarray(tm, "RGBA"),
           "anchor": (int(-minx), int(-miny)), "size": (W, H)}
    if c_ok.any():
        out["mask"] = Image.fromarray(np.clip(cm, 0, 255).astype(np.uint8), "RGBA")
    if gs_x.size:
        shimg = np.zeros((H, W, 4), dtype=np.uint8)
        shimg[(gs_y - miny).astype(np.int64), (gs_x - minx).astype(np.int64)] = (12, 10, 30, 95)
        out["shadow"] = Image.fromarray(shimg, "RGBA")
    return out


def save(result, folder, name, crop_to=None):
    import os
    os.makedirs(folder, exist_ok=True)
    result["color"].save(os.path.join(folder, name + ".png"))
    result["lit"].save(os.path.join(folder, name + "_lit.png"))
    result["top"].save(os.path.join(folder, name + "_top.png"))
    files = ["color", "lit", "top"]
    if "mask" in result:
        result["mask"].save(os.path.join(folder, name + "_mask.png"))
        files.append("mask")
    if "shadow" in result:
        result["shadow"].save(os.path.join(folder, name + "_shadow.png"))
        files.append("shadow")
    return files
