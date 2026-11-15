class_name Terrain
extends RefCounted
## Gemeinsames Gelaenderelief (15.11.2026): bisher nur in MountainView berechnet, jetzt auch fuer die Spiellogik der freien Wesen
## (begehbare Haenge, Hochebenen, Bauen am Berg). Gleiche Rechnung wie zuvor in MountainView._build_relief, damit Darstellung und
## Logik exakt uebereinstimmen: Hoehenfeld des Generators geglaettet (5x5), mit Gratnetz (Ridged-Noise) auf 1..15 Stufen gestreckt.

const CLIMB_MAX := 9      # hoechste begehbare Reliefstufe (Grate und Gipfel darueber bleiben unpassierbar)
const STEEP_MAX := 2      # groesster Hoehenunterschied zu einem Nachbarn, der noch begehbar ist
const FLAT_MAX := 1       # zum Bauen: hoechstens so viel Unterschied zu den Nachbarn (Hochebene, sanfter Hang)


static func relief(city: CityData) -> PackedFloat32Array:
	var H: PackedByteArray = city.height
	var out := PackedFloat32Array()
	if H.is_empty():
		return out
	var n: int = city.size
	out.resize(H.size())
	out.fill(0.0)
	var a := PackedFloat32Array()
	a.resize(H.size())
	for i in H.size():
		a[i] = float(H[i])
	for pass_i in 2:
		var b := PackedFloat32Array()
		b.resize(a.size())
		for y in n:
			for x in n:
				var i := y * n + x
				if H[i] == 0:
					continue
				var sum := 0.0
				var cnt := 0.0
				for k in range(-2, 3):
					var xx := clampi(x + k, 0, n - 1)
					sum += a[y * n + xx]
					cnt += 1.0
				b[i] = sum / cnt
		for y in n:
			for x in n:
				var i := y * n + x
				if H[i] == 0:
					continue
				var sum := 0.0
				var cnt := 0.0
				for k in range(-2, 3):
					var yy := clampi(y + k, 0, n - 1)
					sum += b[yy * n + x]
					cnt += 1.0
				a[i] = sum / cnt
	var ridge := FastNoiseLite.new()
	ridge.seed = city.seed_value * 7 + 3
	ridge.frequency = 0.03
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 3
	var top := 0.0
	for i in H.size():
		if H[i] > 0:
			top = maxf(top, a[i])
	for i in H.size():
		if H[i] == 0:
			continue
		var x := i % n
		var y := i / n
		var k := clampf(a[i] / maxf(1.0, top), 0.0, 1.0)
		var crest := clampf(ridge.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 1.0)
		var h := 1.0 + 14.0 * pow(k, 1.35) * (0.45 + 0.75 * pow(crest, 1.6))
		out[i] = clampf(round(h), 1.0, 15.0)
	return out


## Groesster Hoehenunterschied einer Zelle zu ihren vier Nachbarn (Rand und Ebene zaehlen als 0).
static func steepness(city: CityData, rel: PackedFloat32Array, c: Vector2i) -> int:
	var h := at(city, rel, c)
	var m := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		m = maxi(m, absi(int(h) - int(at(city, rel, c + d))))
	return m


static func at(city: CityData, rel: PackedFloat32Array, c: Vector2i) -> float:
	if rel.is_empty() or not city.inside(c):
		return 0.0
	return rel[city.idx(c)]


## Bergzelle, die ein Wesen begehen kann (sanfter Hang oder Hochebene bis CLIMB_MAX).
static func climbable(city: CityData, rel: PackedFloat32Array, c: Vector2i) -> bool:
	return city.inside(c) and not city.height.is_empty() and city.height[city.idx(c)] > 0 and at(city, rel, c) <= CLIMB_MAX \
		and steepness(city, rel, c) <= STEEP_MAX
