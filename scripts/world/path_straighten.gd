class_name PathStraighten
extends RefCounted
## Begradigt Wege der Rasterwegsuche (AStarGrid2D ohne Diagonalen). Schraege Verbindungen kommen dort als Treppe aus
## Einzelschritten heraus, in der Schraegansicht ein Zickzack. Ersetzt wird jedes Stueck durch ein L (erst die eine, dann die andere
## Achse), solange alle Felder frei sind: lange Geraden mit rechtwinkligen Kurven. Anfang und Ende bleiben erhalten.

const WINDOW := 24   # so viele Wegpunkte hintereinander darf ein L nicht passen, bevor die Suche nach einem weiteren Ziel endet
const SPAN := 48     # ein L ersetzt hoechstens so viele Wegpunkte: es bleibt nahe am gesuchten Weg (sonst weite Umwege und Parallelstrassen)


## path: Wegpunkte (Vector2i oder Vector2) mit Schritten der Laenge 1. free(Vector2i) -> bool: Feld darf Weg werden.
## Ergebnis: lueckenloser Weg (Array von Vector2i) mit Schritten der Laenge 1.
static func straighten(path, free: Callable) -> Array:
	var pts: Array = []
	for p in path:
		pts.append(Vector2i(p))
	if pts.size() < 3:
		return pts
	var out: Array = [pts[0]]
	var heading := Vector2i.ZERO
	var i := 0
	while i < pts.size() - 1:
		var best_j := i + 1
		var best_leg: Array = [pts[i + 1]]
		var misses := 0
		for j in range(i + 2, mini(pts.size(), i + SPAN + 1)):
			var leg := _l_leg(pts[i], pts[j], heading, free)
			if leg.is_empty():
				misses += 1
				if misses > WINDOW:
					break
				continue
			misses = 0
			best_j = j
			best_leg = leg
		out.append_array(best_leg)
		if out.size() >= 2:
			heading = out[-1] - out[-2]
		i = best_j
	return out


## L von a nach b ohne a selbst; zuerst die Achse der bisherigen Richtung (weniger Kurven). Leer, wenn beide Varianten blockiert sind.
static func _l_leg(a: Vector2i, b: Vector2i, heading: Vector2i, free: Callable) -> Array:
	var x_first := heading.y == 0
	for variant in [x_first, not x_first]:
		var leg := _walk(a, b, variant, free)
		if not leg.is_empty():
			return leg
	return []


static func _walk(a: Vector2i, b: Vector2i, x_first: bool, free: Callable) -> Array:
	var leg: Array = []
	var q := a
	var corner := Vector2i(b.x, a.y) if x_first else Vector2i(a.x, b.y)
	for target in [corner, b]:
		var d := Vector2i(signi(target.x - q.x), signi(target.y - q.y))
		while q != target:
			q += d
			if q != b and not free.call(q):
				return []
			leg.append(q)
	return leg
