class_name Iso
extends RefCounted
## Feste orthografische Dimetrie 2:1 (siehe ART_DIRECTION.md). Simulationskoordinaten (1 Feld = 32 Einheiten) werden
## auf Bildschirmkoordinaten abgebildet: sx = 2 (x - y), sy = x + y. Ein Feld erscheint als Raute 128 x 64 px.

const TILE_W := 128.0
const TILE_H := 64.0


static func to_screen(p: Vector2) -> Vector2:
	return Vector2(2.0 * (p.x - p.y), p.x + p.y)


static func to_world(s: Vector2) -> Vector2:
	return Vector2(s.y * 0.5 + s.x * 0.25, s.y * 0.5 - s.x * 0.25)


## Bildschirmposition der hinteren (Nord-)Ecke einer Karten-Zelle (Ursprung aller Gebaeude-/Boden-Grafiken).
static func tile_origin(t: Vector2i) -> Vector2:
	return to_screen(Vector2(t.x * 32.0, t.y * 32.0))


## y-Koordinate (relativ zur Ursprungsecke) der Vorderkante einer w x h Grundflaeche an der Bildschirm-x-Position sx.
## Dient der Tiefensortierung in senkrechten Streifen: dahinter liegende Figuren werden verdeckt, davor stehende nicht.
static func front_edge_y(w: int, h: int, sx: float) -> float:
	var x := clampf(sx, -64.0 * h, 64.0 * w)
	if x <= 64.0 * (w - h):
		return 32.0 * h + 0.5 * (x + 64.0 * h)
	return 32.0 * (w + h) - 0.5 * (x - 64.0 * (w - h))
