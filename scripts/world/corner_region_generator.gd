class_name CornerRegionGenerator
extends RegionGenerator
## Neue Partien: eine Landmasse zwischen West- und Ostkueste, mit einem Ort je gewaehlter Eckregion.
## Der bisherige RegionGenerator bleibt fuer Spielstaende mit Generatorversion 2 erhalten.

const CORNERS := ["NW", "NO", "SW", "SO"]
var west_coast := PackedInt32Array()
## Zentrales Grosslager (Auftrag 19) in der Kartenmitte: Gelaende, Zufahrt je Himmelsrichtung, Strasse zu jeder Stadt.
const HUB_W := 44
const HUB_H := 30
const HUB_EXIT_OF := {"NW": "W", "NO": "N", "SO": "O", "SW": "S"}   # jede Stadt kommt aus ihrer Richtung an
var hub_rect := Rect2i()
var hub_out := {}


func generate(seed_value: int, map_size: int = Catalog.MAP_SIZE, reserve_share: float = 0.0) -> CityData:
	var cd := super.generate(seed_value, map_size, reserve_share)
	if report.ok:
		cd.gen_params["generator"] = maxi(3, version)
		cd.gen_params["landschaft"] = landschaft if version >= 6 else ""
		cd.gen_params["start_haeuser"] = start_houses   # Laden erzeugt die Karte neu: gleiche Zahl Startwohnhaeuser
		cd.gen_params["neubeginn"] = neubeginn
	return cd


static func selected_corners(seed_value: int, count: int) -> Array:
	if count >= 4:
		return CORNERS.duplicate()
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 43 + 29
	if count == 2:
		return ["NW", "SO"] if r.randi() % 2 == 0 else ["NO", "SW"]
	var omitted: int = r.randi() % 4
	var result: Array = []
	for k in 4:
		if k != omitted:
			result.append(CORNERS[k])
	return result


## Version 6 (15.11.2026, "die Karte sieht immer gleich aus"): Landschaftstyp je Seed und eigene, unabhaengige Kuesten.
const LANDSCHAFTEN := ["hochgebirge", "gebirge", "huegelland", "seenplatte", "waldland"]
var landschaft := "gebirge"


func _sea() -> void:
	if version >= 6:
		landschaft = LANDSCHAFTEN[rng.randi() % LANDSCHAFTEN.size()]
		forest_threshold = {"waldland": -0.05, "huegelland": 0.15, "seenplatte": 0.2}.get(landschaft, 0.25)
		forest_p = 0.8 if landschaft == "waldland" else 0.55
		_sea_v6()
		return
	super._sea()
	west_coast.resize(n)
	for y in n:
		west_coast[y] = n - 1 - coast[y]
		for x in range(west_coast[y] + 1):
			var i := c.idx(Vector2i(x, y))
			c.ground[i] = G.WATER if x < west_coast[y] else G.SAND
			c.blocked[i] = 1 if x < west_coast[y] else 0
		for x in range(west_coast[y] + 1, mini(n, west_coast[y] + 3)):
			c.ground[c.idx(Vector2i(x, y))] = G.SAND


func _generate_once(seed_value: int, map_size: int) -> CityData:
	reserve = 0.0
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.035
	n = map_size
	c = CityData.new()
	c.setup(n, seed_value)
	c.world = "region"
	heights = PackedByteArray()
	heights.resize(n * n)
	towns_out = []
	_rects = []
	_air_rects = []
	_sea()
	var chosen := selected_corners(seed_value, town_count)
	var names := town_names(seed_value, town_count)
	for k in chosen.size():
		var corner: String = chosen[k]
		var top := corner.begins_with("N")
		var left := corner.ends_with("W")
		var y := int(n * (0.18 if top else 0.82) + rng.randf_range(-0.025, 0.025) * n)
		if version >= 4:   # Orte liegen mal weit aussen, mal naeher an der Kartenmitte
			y = int(n * (rng.randf_range(0.13, 0.30) if top else rng.randf_range(0.70, 0.87)))
		y = clampi(y, 62, n - 63)
		if left and version >= 6:
			_fit_west_coast(y)   # Westorte entstehen gespiegelt: dort Kuestenform der Ostkueste uebernehmen (weich angeglichen)
		var east_x: int = coast[y] - 6
		var x := n - 1 - east_x if left else east_x
		var r := Rect2i(x - 5 if left else x - 40, y - 24, 46, 48)
		_rects.append(r)
		towns_out.append({"id": k, "name": names[k], "center": [x, y], "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "ecke": corner})
	town = Vector2i(int(towns_out[0].center[0]), int(towns_out[0].center[1]))
	town_rect = _rects[0]
	_mountains_corners()
	_lakes_corners()
	_river_corners()
	hub_rect = _find_hub_site()   # nach Bergen/Seen/Fluss: die Zufallsfolge (und damit die Staedte) bleibt unveraendert
	_clear_hub_site()
	var chars: Array = (CHARACTERS if version < 4 else CHARACTERS_V4).duplicate()
	for i in range(chars.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = chars[i]
		chars[i] = chars[j]
		chars[j] = tmp
	for k in town_count:
		towns_out[k]["charakter"] = chars[k]
		if str(towns_out[k].ecke).ends_with("W"):
			_build_mirrored_town(k)
		else:
			_build_town(k)
	_build_hub()
	_connect_towns()
	_connect_hub()
	_land_cover_region()
	c.height = heights
	_finish()
	c.hub = hub_out
	c.towns = towns_out
	c.town_name = str(towns_out[0].name)
	c.airport = towns_out[0].get("airport", {})
	center = Vector2(town)
	return c


## Ost- und Westkueste unabhaengig: eigene Breite, Wellen (Buchten, Halbinseln) und Phase je Seed.
func _sea_v6() -> void:
	coast = PackedInt32Array()
	coast.resize(n)
	west_coast = PackedInt32Array()
	west_coast.resize(n)
	var ew := n * rng.randf_range(0.08, 0.18)
	var ww := n * rng.randf_range(0.08, 0.18)
	var ea := rng.randf_range(4.0, 26.0)
	var wa := rng.randf_range(4.0, 26.0)
	var ef := rng.randf_range(0.008, 0.04)
	var wf := rng.randf_range(0.008, 0.04)
	var ep := rng.randf_range(0.0, TAU)
	var wp := rng.randf_range(0.0, TAU)
	for y in n:
		coast[y] = clampi(n - int(ew) + int(round(ea * sin(y * ef + ep) + noise.get_noise_2d(0, y * 2) * 10.0)), int(n * 0.72), n - 8)
		west_coast[y] = clampi(int(ww) + int(round(wa * sin(y * wf + wp) + noise.get_noise_2d(500, y * 2) * 10.0)), 8, int(n * 0.28))
	for y in n:
		for x in n:
			var i := c.idx(Vector2i(x, y))
			c.district[i] = 5
			if x >= coast[y] or x < west_coast[y]:
				c.ground[i] = G.WATER
				c.blocked[i] = 1
			elif x >= coast[y] - 2 or x <= west_coast[y] + 2:
				c.ground[i] = G.SAND
			else:
				c.ground[i] = G.GRASS


## Westkueste um einen Westort (y +-60) weich an das Spiegelbild der Ostkueste angleichen und den Boden dort neu setzen.
func _fit_west_coast(ty: int) -> void:
	for y in range(maxi(0, ty - 70), mini(n, ty + 71)):
		var d := absi(y - ty)
		var wgt := 1.0 if d <= 50 else 1.0 - float(d - 50) / 20.0
		west_coast[y] = int(round(lerpf(float(west_coast[y]), float(n - 1 - coast[y]), wgt)))
		for x in range(0, int(n * 0.32)):
			var i := c.idx(Vector2i(x, y))
			if x < west_coast[y]:
				c.ground[i] = G.WATER
				c.blocked[i] = 1
			elif x <= west_coast[y] + 2:
				c.ground[i] = G.SAND
				c.blocked[i] = 0
			else:
				c.ground[i] = G.GRASS
				c.blocked[i] = 0


func _mountains_corners() -> void:
	if version >= 6:
		match landschaft:
			"hochgebirge":
				_mountains_v5(10, 14, 0.06, 0.13, 3, 4)
			"gebirge":
				_mountains_v5(6, 9, 0.05, 0.1, 1, 2)
			"huegelland":
				_mountains_v5(14, 20, 0.025, 0.05, 0, 1, 3.0, 6.0)
			"seenplatte":
				_mountains_v5(2, 4, 0.04, 0.07, 0, 1)
			"waldland":
				_mountains_v5(4, 6, 0.04, 0.08, 1, 1)
		return
	if version >= 5:
		_mountains_v5()
		return
	var centers: Array = []
	var tries := 0
	var want := 4
	var x_lo := 0.36
	var x_hi := 0.64
	var r_lo := 0.045
	var r_hi := 0.07
	if version >= 4:   # 3-5 Gebirge, breiter gestreut, mal Huegel, mal Massiv
		want = rng.randi_range(3, 5)
		x_lo = 0.28
		x_hi = 0.72
		r_lo = 0.035
		r_hi = 0.085
	while centers.size() < want and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(n * x_lo, n * x_hi), rng.randf_range(n * 0.13, n * 0.87))
		if centers.any(func(q): return q.distance_to(p) < n * 0.16):
			continue
		if version >= 4 and not _far_from_towns(p, n * 0.2):
			continue
		centers.append(p)
	for ctr in centers:
		var rad := n * rng.randf_range(r_lo, r_hi)
		for y in range(maxi(1, int(ctr.y - rad)), mini(n - 1, int(ctr.y + rad))):
			for x in range(maxi(1, int(ctr.x - rad)), mini(n - 1, int(ctr.x + rad))):
				var p := Vector2i(x, y)
				var d := Vector2(p).distance_to(ctr) / rad + noise.get_noise_2d(x * 3, y * 3) * 0.2
				if d >= 1.0:
					continue
				var i := c.idx(p)
				heights[i] = maxi(heights[i], clampi(int((1.0 - d) * 11.0), 1, 11))
				c.blocked[i] = 1
	_prune_specks()


## Version 5 (Welt 2, 15.11.2026): richtige Gebirgslandschaft – 6-9 grosse Massive und 1-2 lange Gebirgszuege ueber das ganze
## Land (Abstand zu den Orten und zum Meer); hohe Gipfel, Hochebenen am Rand. Das Grosslager sucht sich danach eine flache Stelle.
func _mountains_v5(lo := 6, hi := 9, r_lo := 0.05, r_hi := 0.1, ridge_lo := 1, ridge_hi := 2, peak_lo := 8.0, peak_hi := 11.0) -> void:
	var want := rng.randi_range(lo, hi)
	var centers: Array = []
	var tries := 0
	while centers.size() < want and tries < 1200:
		tries += 1
		var p := Vector2(rng.randf_range(n * 0.12, n * 0.88), rng.randf_range(n * 0.08, n * 0.92))
		if not _far_from_towns(p, n * 0.17) or centers.any(func(q): return q.distance_to(p) < n * minf(0.13, 0.5 / sqrt(float(want)))) or not _inland(p, n * 0.07):
			continue
		centers.append(p)
	for ctr in centers:
		_corner_blob(ctr, n * rng.randf_range(r_lo, r_hi), rng.randf_range(peak_lo, peak_hi))
	for r in rng.randi_range(ridge_lo, ridge_hi):   # Gebirgszug
		var start := Vector2(rng.randf_range(n * 0.2, n * 0.8), rng.randf_range(n * 0.15, n * 0.85))
		var dir := Vector2.from_angle(rng.randf_range(0.0, TAU))
		for i in rng.randi_range(6, 10):
			var p := start + dir * (n * 0.045) * i + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			if p.x < n * 0.08 or p.x > n * 0.92 or p.y < n * 0.06 or p.y > n * 0.94:
				break
			if _far_from_towns(p, n * 0.15) and _inland(p, n * 0.06):
				_corner_blob(p, n * rng.randf_range(0.04, 0.065), rng.randf_range(9.0, 11.0))
	_prune_specks()


## Punkt liegt mindestens `margin` Felder vom Meer (Ost- und Westkueste) entfernt.
func _inland(p: Vector2, margin: float) -> bool:
	var y := clampi(int(p.y), 0, n - 1)
	return p.x > float(west_coast[y]) + margin and p.x < float(coast[y]) - margin


func _corner_blob(ctr: Vector2, rad: float, peak: float) -> void:
	for y in range(maxi(1, int(ctr.y - rad - 4)), mini(n - 1, int(ctr.y + rad + 4))):
		for x in range(maxi(1, int(ctr.x - rad - 4)), mini(n - 1, int(ctr.x + rad + 4))):
			var p := Vector2i(x, y)
			if not _inland(Vector2(p), 6.0) or _rects.any(func(r): return r.grow(6).has_point(p)):
				continue
			var d := Vector2(p).distance_to(ctr) / rad + noise.get_noise_2d(x * 3, y * 3) * 0.35
			if d >= 1.0:
				continue
			var h := int(round(pow(1.0 - d, 1.1) * peak + noise.get_noise_2d(x * 7 + 99, y * 7) * 1.5))
			var i := c.idx(p)
			if h < 1 or c.ground[i] == G.WATER:
				continue
			heights[i] = maxi(heights[i], clampi(h, 1, 11))
			c.blocked[i] = 1


func _lakes_corners() -> void:
	var made := 0
	var tries := 0
	var want := 2 if version < 4 else rng.randi_range(2, 4)
	if version >= 6:
		want = rng.randi_range(6, 9) if landschaft == "seenplatte" else rng.randi_range(2, 4)
	while made < want and tries < 200:
		tries += 1
		var ctr := Vector2i(rng.randi_range(int(n * 0.34), int(n * 0.66)), rng.randi_range(int(n * 0.28), int(n * 0.72)))
		var clear := true
		for y in range(ctr.y - 8, ctr.y + 9):
			for x in range(ctr.x - 8, ctr.x + 9):
				if heights[c.idx(Vector2i(x, y))] > 0 or c.ground[c.idx(Vector2i(x, y))] == G.WATER:
					clear = false
		if not clear or c.lakes.any(func(q): return q.distance_to(ctr) < 30):
			continue
		var lr := 6.0 if version < 4 else rng.randf_range(3.5, 7.5)
		for y in range(ctr.y - 7, ctr.y + 8):
			for x in range(ctr.x - 7, ctr.x + 8):
				var d := Vector2(Vector2i(x, y)).distance_to(Vector2(ctr)) + noise.get_noise_2d(x * 5, y * 5) * 2.0
				if d < lr:
					var i := c.idx(Vector2i(x, y))
					c.ground[i] = G.WATER
					c.blocked[i] = 1
		c.lakes.append(ctr)
		made += 1


func _river_corners() -> void:
	# Die Muendung liegt zwischen den Nord- und Suedorten; die Landstrassen koennen sie umrunden.
	var y0 := int(n * 0.5)
	var x_from := int(n * 0.58)
	var amp := 9.0
	var freq := 0.045
	var phase := 0.0
	var west := false
	if version >= 4:   # Fluss muendet mal im Osten, mal im Westen, mit eigenem Lauf
		west = rng.randf() < 0.5
		y0 = int(n * rng.randf_range(0.44, 0.56))
		x_from = int(n * rng.randf_range(0.52, 0.66))
		amp = rng.randf_range(5.0, 13.0)
		freq = rng.randf_range(0.03, 0.06)
		phase = rng.randf_range(0.0, TAU)
	for x0 in range(x_from, n):
		var x := n - 1 - x0 if west else x0
		var y := y0 + int(round(amp * sin(float(x0) * freq + phase)))
		for dy in 2:
			var p := Vector2i(x, y + dy)
			if c.inside(p) and heights[c.idx(p)] == 0:
				c.ground[c.idx(p)] = G.WATER
				c.blocked[c.idx(p)] = 1
				c.river.append(p)


func _build_mirrored_town(k: int) -> void:
	# Die bewaehrte Orts- und Flughafenplanung wird auf einer leeren Ostkueste ausgefuehrt.
	# Anschliessend werden ihre befahrbaren Zellen und Objekte geometrisch nach Westen gespiegelt.
	var actual := c
	var actual_rect: Rect2i = _rects[k]
	var actual_t: Dictionary = towns_out[k]
	var actual_x: int = int(actual_t.center[0])
	var east_x := n - 1 - actual_x
	var virtual_rect := Rect2i(east_x - 40, int(actual_t.center[1]) - 24, 46, 48)
	var temp := CityData.new()
	temp.setup(n, int(actual.seed_value))
	for y in n:
		for x in range(coast[y] - 2, n):
			var i := temp.idx(Vector2i(x, y))
			temp.ground[i] = G.WATER if x >= coast[y] else G.SAND
			temp.blocked[i] = 1 if x >= coast[y] else 0
	c = temp
	_rects[k] = virtual_rect
	towns_out[k]["center"] = [east_x, int(actual_t.center[1])]
	towns_out[k]["rect"] = [virtual_rect.position.x, virtual_rect.position.y, 46, 48]
	_build_town(k)
	var offset := actual.buildings.size()
	for b0 in temp.buildings:
		var b: Dictionary = b0.duplicate(true)
		b["id"] = offset + int(b.id)
		b["x"] = n - int(b.x) - int(b.w)
		if b.has("parent") and int(b.parent) >= 0:
			b["parent"] = offset + int(b.parent)
		actual.buildings.append(b)
	for y in range(maxi(0, int(actual_t.center[1]) - 56), mini(n, int(actual_t.center[1]) + 57)):
		for x in range(int(n * 0.65), n):
			var src := temp.idx(Vector2i(x, y))
			var dst := actual.idx(Vector2i(n - 1 - x, y))
			actual.ground[dst] = temp.ground[src]
			actual.district[dst] = temp.district[src]
			actual.blocked[dst] = temp.blocked[src]
			actual.building_at[dst] = offset + temp.building_at[src] if temp.building_at[src] >= 0 else temp.building_at[src]
	for sid in temp.start_depots:
		actual.start_depots.append(offset + sid)
	if not temp.start_depots.is_empty():
		towns_out[k]["start_plot"] = offset + int(temp.start_depots[0])
	for key in ["town_hall", "bauhof", "harbor", "port_office"]:
		if int(towns_out[k].get(key, -1)) >= 0:
			towns_out[k][key] = offset + int(towns_out[k][key])
	var air: Dictionary = towns_out[k].get("airport", {}).duplicate(true)
	if not air.is_empty():
		for key in ["terminal", "tower", "hangar", "fire", "cargo"]:
			if air.has(key):
				air[key] = offset + int(air[key])
		air.rect[0] = n - int(air.rect[0]) - int(air.rect[2])
		var lo := int(air.run_x0)
		air.run_x0 = n - 1 - int(air.run_x1)
		air.run_x1 = n - 1 - lo
		air.dir = -1
		for apron in air.apron:
			apron[0] = n - 1 - int(apron[0])
		towns_out[k]["airport"] = air
		actual.airport = air
		_air_rects[-1] = Rect2i(n - airport_rect.end.x, airport_rect.position.y, airport_rect.size.x, airport_rect.size.y)
	c = actual
	_rects[k] = actual_rect
	towns_out[k]["center"] = [actual_x, int(actual_t.center[1])]
	towns_out[k]["rect"] = [actual_rect.position.x, actual_rect.position.y, 46, 48]
	town = Vector2i(actual_x, int(actual_t.center[1]))
	town_rect = actual_rect


# ------------------------------------------------------------------ Grosslager (Auftrag 19)
## Standort nahe der Kartenmitte ohne Wasser (Seen, Fluss) und mit moeglichst wenig Berg; Berge werden danach eingeebnet.
func _find_hub_site() -> Rect2i:
	var best := Rect2i()
	var best_s := INF
	var mid := Vector2(n * 0.5, n * 0.5)
	for y in range(int(n * 0.36), int(n * 0.64) - HUB_H, 4):
		for x in range(int(n * 0.30), int(n * 0.62) - HUB_W, 4):
			var r := Rect2i(x, y, HUB_W, HUB_H)
			var g := r.grow(10)
			var score := 0.0
			for yy in range(g.position.y, g.end.y, 2):
				for xx in range(g.position.x, g.end.x, 2):
					var i := c.idx(Vector2i(xx, yy))
					if c.ground[i] == G.WATER:
						score += 1000.0
					elif heights[i] > 0:
						score += 1.0
			score += Vector2(r.get_center()).distance_to(mid) * 0.5
			if score < best_s:
				best_s = score
				best = r
	return best


## Gelaende freiraeumen: Berge werden eingeebnet (Wasser meidet schon die Standortwahl).
func _clear_hub_site() -> void:
	var area := hub_rect.grow(10)
	var river := {}
	for p in c.river:
		river[p] = true
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := Vector2i(x, y)
			if not c.inside(p) or river.has(p):
				continue
			var i := c.idx(p)
			if c.ground[i] == G.WATER:
				continue
			heights[i] = 0
			c.blocked[i] = 0


## Lagergelaende: Ringstrasse, Achsen mit Zufahrten aus allen vier Himmelsrichtungen, vier Bereiche (Lager, Hallen, Handel, Fahrzeuge).
func _build_hub() -> void:
	var R := hub_rect
	var cx := R.position.x + R.size.x / 2
	var cy := R.position.y + R.size.y / 2
	for y in range(R.position.y, R.end.y):
		for x in range(R.position.x, R.end.x):
			c.ground[c.idx(Vector2i(x, y))] = G.CONCRETE   # befestigter Hof
	var x0 := R.position.x + 1
	var x1 := R.end.x - 2
	var y0 := R.position.y + 1
	var y1 := R.end.y - 2
	_road(Vector2i(x0, y0), Vector2i(x1, y0))
	_road(Vector2i(x0, y1), Vector2i(x1, y1))
	_road(Vector2i(x0, y0), Vector2i(x0, y1))
	_road(Vector2i(x1, y0), Vector2i(x1, y1))
	_road(Vector2i(cx, R.position.y - 4), Vector2i(cx, R.end.y + 3))   # Nord-Sued-Achse mit Zufahrten
	_road(Vector2i(R.position.x - 4, cy), Vector2i(R.end.x + 3, cy))   # West-Ost-Achse mit Zufahrten
	var exits := {"N": [cx, R.position.y - 4], "S": [cx, R.end.y + 3], "W": [R.position.x - 4, cy], "O": [R.end.x + 3, cy]}
	var keep_town := town
	var keep_rect := town_rect
	town = Vector2i(n * 2, cy)   # _district_at: kein Hafenbezirk im Lager
	var q_nw := Rect2i(x0 + 1, y0 + 1, cx - x0 - 1, cy - y0 - 1)
	var q_ne := Rect2i(cx + 1, y0 + 1, x1 - cx - 1, cy - y0 - 1)
	var q_sw := Rect2i(x0 + 1, cy + 1, cx - x0 - 1, y1 - cy - 1)
	var q_se := Rect2i(cx + 1, cy + 1, x1 - cx - 1, y1 - cy - 1)
	var B := {}
	# Nordwest: Hauptlager mit Warenannahme und Hochregallager
	town_rect = q_nw
	B["hauptlager"] = _put("freight_shed", q_nw.position + Vector2i(3, 2), "hub_main", "Großlager – Hauptlager")
	B["hochregal"] = _put("warehouse", q_nw.position + Vector2i(12, 2), "hub_rack", "Großlager – Hochregallager")
	B["annahme"] = _put("freight_shed", q_nw.position + Vector2i(4, 9), "hub_in", "Großlager – Warenannahme")
	B["container0"] = _put("containers", q_nw.position + Vector2i(14, 9), "decor", "Containerlager")
	# Nordost: Warenhallen und Warenausgang
	town_rect = q_ne
	for i in 3:
		B["halle%d" % (i + 1)] = _put("warehouse", q_ne.position + Vector2i(2 + i * 6, 2), "hub_hall", "Großlager – Warenhalle %d" % (i + 1))
	B["ausgang"] = _put("freight_shed", q_ne.position + Vector2i(10, 9), "hub_out", "Großlager – Warenausgang")
	# Suedwest: Baustoffhandel, Grosshandelsmarkt, Verwaltung, Haendler-Marktplatz
	town_rect = q_sw
	B["baustoffe"] = _put("freight_shed", q_sw.position + Vector2i(3, 2), "hub_materials", "Großlager – Baustoffhandel")
	B["grosshandel"] = _put("warehouse", q_sw.position + Vector2i(12, 2), "hub_wholesale", "Großlager – Großhandelsmarkt")
	B["verwaltung"] = _put("office", q_sw.position + Vector2i(16, 9), "hub_admin", "Großlager – Verwaltung")
	if neubeginn:   # Neubeginn: die Dienste der Orte stehen hier (Arbeitsamt, Personalbuero, Bank; Werkstatt und Tankstelle im Suedosten)
		B["arbeitsamt"] = _put("job_board", q_sw.position + Vector2i(2, 8), "job_board", "Arbeitsamt am Großlager")
		B["personal"] = _put("staffing", q_sw.position + Vector2i(7, 8), "staffing", "Personalbüro am Großlager")
	var plaza := _hub_area(q_sw, Vector2i(7, 5), q_sw.position + Vector2i(3, 8), G.PLAZA) if not neubeginn else Rect2i()
	if plaza.size.x > 0:
		B["brunnen"] = _put_in("fountain", Rect2i(plaza.position + Vector2i(2, 1), Vector2i(2, 2)), "decor", "Brunnen am Händlermarkt")
		c.benches.append(plaza.position + Vector2i(1, 4))
		c.benches.append(plaza.position + Vector2i(5, 4))
		c.lamps.append(plaza.position)
		c.lamps.append(plaza.position + Vector2i(6, 0))
	# Suedost: Fahrzeug- und Maschinenhandel, Lkw-Parkplatz, Dienstwagen-Stellplaetze, Containerlager
	town_rect = q_se
	B["fahrzeughandel"] = _put("dealer", q_se.position + Vector2i(3, 2), "dealer", "Großlager – Fahrzeug- und Maschinenhandel")
	var trucks := _hub_area(q_se, Vector2i(9, 4), q_se.position + Vector2i(11, 2), G.PARKING)
	var officials := _hub_area(q_se, Vector2i(6, 2), q_se.position + Vector2i(3, 10), G.PARKING)
	if neubeginn:
		B["werkstatt"] = _put("workshop", q_se.position + Vector2i(11, 8), "workshop", "Werkstatt am Großlager")
		B["tankstelle"] = _put("gas_station", q_se.position + Vector2i(16, 8), "", "Tankstelle am Großlager")
		B["bank"] = _put("bank", q_se.position + Vector2i(13, 10), "bank", "Sparkasse am Großlager")
	else:
		B["container1"] = _put("containers", q_se.position + Vector2i(13, 10), "decor", "Containerlager")
		B["container2"] = _put("containers", q_se.position + Vector2i(16, 10), "decor", "Containerlager")
	town = keep_town
	town_rect = keep_rect
	for y in range(R.position.y - 4, R.end.y + 4):
		for x in range(R.position.x - 4, R.end.x + 4):
			var p := Vector2i(x, y)
			if c.inside(p):
				c.district[c.idx(p)] = 2   # Industriegebiet
	for k in B.keys():
		if int(B[k]) < 0:
			B.erase(k)
		else:
			c.buildings[int(B[k])]["hub"] = true
	hub_out = {"rect": [R.position.x, R.position.y, R.size.x, R.size.y], "center": [cx, cy], "exits": exits, "buildings": B,
		"parking": [trucks.position.x, trucks.position.y, trucks.size.x, trucks.size.y],
		"official_parking": [officials.position.x, officials.position.y, officials.size.x, officials.size.y],
		"plaza": [plaza.position.x, plaza.position.y, plaza.size.x, plaza.size.y], "links": []}


## Freie Flaeche (Parkplatz, Pflaster) mit Strassenanschluss nahe `near` im Bereich `area`; Zellen bekommen `gtype`, bleiben unbebaut.
func _hub_area(area: Rect2i, size: Vector2i, near: Vector2i, gtype: int) -> Rect2i:
	var best := Rect2i()
	var best_d := INF
	for y in range(area.position.y, area.end.y - size.y + 1):
		for x in range(area.position.x, area.end.x - size.x + 1):
			var r := Rect2i(Vector2i(x, y), size)
			if not _free(r) or not _touches_road(r):
				continue
			var d := Vector2(r.position).distance_to(Vector2(near))
			if d < best_d:
				best_d = d
				best = r
	if best_d == INF:
		return Rect2i()
	for y in range(best.position.y, best.end.y):
		for x in range(best.position.x, best.end.x):
			var i := c.idx(Vector2i(x, y))
			c.ground[i] = gtype
			c.building_at[i] = -2   # nicht bebauen (_finish gibt die Zellen frei, der Boden bleibt)
	return best


func _put_in(type: String, r: Rect2i, role: String, name: String) -> int:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			c.building_at[c.idx(Vector2i(x, y))] = -1
	return _place(type, r, role, name)


## Strasse von jeder Zufahrt zur naechstgelegenen Ortsstrasse der zugehoerigen Stadt (A* wie die Landstrassen).
func _connect_hub() -> void:
	if hub_out.is_empty():
		return
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	var R := hub_rect
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			var i := c.idx(p)
			if c.ground[i] in [G.WATER, G.QUAY, G.RUNWAY, G.APRON] or heights[i] > 0 or c.building_at[i] >= 0 or (R.has_point(p) and c.ground[i] != G.ROAD):
				astar.set_point_solid(p, true)
			elif c.ground[i] == G.ROAD:
				astar.set_point_weight_scale(p, 0.5)
			else:
				astar.set_point_weight_scale(p, 1.0 + 0.6 * (noise.get_noise_2d(x * 2 + 900, y * 2) + 1.0))
	for k in towns_out.size():
		var corner := str(towns_out[k].get("ecke", ""))
		var ex: Array = hub_out.exits[HUB_EXIT_OF.get(corner, "N")]
		var a := Vector2i(int(ex[0]), int(ex[1]))
		var b := _hub_target(k, a)
		var path := _road_path(astar, a, b)
		var cells := 0
		for p in path:
			if c.ground[c.idx(p)] != G.ROAD:
				c.ground[c.idx(p)] = G.ROAD
				c.district[c.idx(p)] = 4
				cells += 1
		hub_out.links.append({"stadt": k, "zufahrt": HUB_EXIT_OF.get(corner, "N"), "zellen": cells, "laenge": path.size(), "verbunden": not path.is_empty()})


## Ziel der Zufahrt: naechstgelegene Ortsstrasse, die nachweislich mit der Ortsmitte verbunden ist (sonst endete die Zufahrt
## neben dem Ortsnetz und Gebaeude am Ortsrand galten als unerreichbar).
func _hub_target(k: int, from: Vector2i) -> Vector2i:
	var ctr := Vector2i(int(towns_out[k].center[0]), int(towns_out[k].center[1]))
	var cands: Array = []
	var r: Rect2i = _rects[k].grow(4)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			if c.inside(p) and c.ground[c.idx(p)] == G.ROAD:
				cands.append(p)
	cands.sort_custom(func(p, q): return absi(p.x - from.x) + absi(p.y - from.y) < absi(q.x - from.x) + absi(q.y - from.y))
	for p in cands.slice(0, 40):
		if _road_path_exists(p, ctr):
			return p
	return _edge_road(k, from.y > ctr.y)


func validate(cd: CityData) -> Dictionary:
	var out := super.validate(cd)
	var errs: Array = out.fehler
	if version >= 4:   # Fluss darf auch an der Westkueste muenden
		errs.erase("Fluss erreicht das Meer nicht")
		if cd.river.is_empty() or not cd.river.any(func(p): return p.x >= coast[p.y] - 2 or p.x <= west_coast[p.y] + 2):
			errs.append("Fluss erreicht das Meer nicht")
	if cd.hub.is_empty():
		errs.append("Großlager fehlt")
	else:
		for l in cd.hub.links:
			if not bool(l.verbunden):
				errs.append("Großlager ohne Straße zu Ort %d" % int(l.stadt))
		for key in ["hauptlager", "baustoffe", "fahrzeughandel", "verwaltung"]:
			if not cd.hub.buildings.has(key):
				errs.append("Großlager ohne %s" % key)
	for t in cd.towns:
		var corner: String = str(t.get("ecke", ""))
		var x := int(t.center[0])
		var y := int(t.center[1])
		if (corner.begins_with("N") != (y < cd.size / 2)) or (corner.ends_with("W") != (x < cd.size / 2)):
			errs.append("%s liegt nicht in %s" % [t.name, corner])
		var shore := west_coast[y] if corner.ends_with("W") else coast[y]
		if absi(x - shore) > 10:
			errs.append("%s hat keinen Kuestenzugang" % t.name)
	out.ok = errs.is_empty()
	return out
