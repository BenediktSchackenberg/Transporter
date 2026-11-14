class_name RegionGenerator
extends CoastGenerator
## Weltart "region" (Auftrag 17, docs/REGION.md): 2-4 Kuestenorte auf einer gemeinsamen Karte.
##
## Ablauf: Meer im Osten (wie Kueste) -> Ortsstandorte entlang der Kueste mit Mindestabstand -> Berge im Hinterland (Abstand zu
## allen Orten und zum Kuestenband) -> Seen ausserhalb der Orte -> Fluss mit Muendung jenseits der Orte (trennt keine Stadt ab)
## -> je Ort: Schotterstrassen, Hafen, Grundversorgung, genau ein Unternehmer-Startgrundstueck, Flughafen, Huetten bis zur
## Obergrenze von MAX_BUILDINGS je Ort -> Verbindungsstrassen (Schotter) von Ort zu Ort ueber Land -> Waelder/Felder.
## Gebaeude tragen "town"; CityData.towns beschreibt die Orte. validate() prueft alles und verwirft fehlerhafte Welten.

var town_count := 4
## Ortscharakter (je Ort aus dem Seed): praegt Strassennetz, Bebauung und Umland, damit die Staedte verschieden aussehen.
const CHARACTERS := ["Fischerdorf", "Marktflecken", "Bauerndorf", "Handwerkerort"]
var towns_out: Array = []          # [{id, name, center: [x, y], rect: [x, y, w, h], airport: {...}}]
var _rects: Array = []             # Rect2i je Ort
var _air_rects: Array = []
var failures: Array = []         # Fehler der verworfenen Versuche (Fehlersuche)
var _band := Rect2i()              # Kuestenband zwischen den Orten (Verbindungsstrassen, frei von Fluss/Seen/Bergen)


func _init(count: int = 4) -> void:
	town_count = clampi(count, 1, 4)


func generate(seed_value: int, map_size: int = Catalog.MAP_SIZE, reserve_share: float = 0.0) -> CityData:
	var s := seed_value
	for attempt in 8:
		var cd := _generate_once(s, map_size)
		report = validate(cd)
		report["versuch"] = attempt + 1
		failures.append(report.get("fehler", []))
		if report.ok:
			cd.gen_params = {"welt": "region", "seed": seed_value, "erzeugt_mit_seed": s, "versuch": attempt + 1, "groesse": map_size, "orte": town_count, "generator": 2}
			return cd
		s = seed_value + 7919 * (attempt + 1)
	push_error("RegionGenerator: keine gueltige Region in 8 Versuchen (Seed %d, %d Orte): %s" % [seed_value, town_count, str(report.get("fehler", []))])
	return c


## Ortsnamen: je Ort ein eigener Fantasiename aus dem Welt-Seed, ohne Dopplung.
static func town_names(seed_value: int, count: int) -> Array:
	var out: Array = []
	var k := 0
	while out.size() < count and k < 200:
		var nm := CoastGenerator.town_name(seed_value * 13 + k * 101 + 7)
		if nm not in out:
			out.append(nm)
		k += 1
	return out


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
	var names := town_names(seed_value, town_count)
	# Ortsstandorte: gleichmaessig entlang der Kueste mit Zufallsversatz (Mindestabstand ergibt sich aus der Teilung)
	var span := 0.76 / float(town_count)
	for k in town_count:
		var y := int(n * (0.12 + span * (float(k) + 0.5)) + rng.randf_range(-0.2, 0.2) * span * n)
		y = clampi(y, 30, n - 31)
		var t := Vector2i(coast[y] - 6, y)
		_rects.append(Rect2i(t.x - 40, t.y - 24, 46, 48))
		towns_out.append({"id": k, "name": names[k], "center": [t.x, t.y], "rect": [t.x - 40, t.y - 24, 46, 48]})
	var x0: int = _rects.map(func(r): return r.position.x).min() - 30
	var x1: int = coast[int(n / 2)]
	_band = Rect2i(x0, _rects[0].position.y - 6, n - x0, _rects[-1].end.y - _rects[0].position.y + 12)
	town = Vector2i(towns_out[0].center[0], towns_out[0].center[1])
	town_rect = _rects[0]
	_mountains_region()
	_lakes_region()
	_river_region()
	# je Ort ein anderer Charakter (gemischt nach Seed), damit die Staedte verschieden aussehen
	var chars: Array = CHARACTERS.duplicate()
	for i in range(chars.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = chars[i]
		chars[i] = chars[j]
		chars[j] = tmp
	for k in town_count:
		towns_out[k]["charakter"] = chars[k % chars.size()]
	for k in town_count:
		_build_town(k)
	_connect_towns()
	_land_cover_region()
	c.height = heights
	_finish()
	c.towns = towns_out
	c.town_name = towns_out[0].name
	c.airport = towns_out[0].get("airport", {})
	center = Vector2(town)
	return c


# ------------------------------------------------------------------ Gelaende
func _far_from_towns(p: Vector2, dist: float) -> bool:
	for r in _rects:
		if p.distance_to(Vector2(r.get_center())) < dist:
			return false
	return true


func _mountains_region() -> void:
	var count := 3 + (1 if rng.randf() < 0.5 else 0)
	var centers: Array = []
	var tries := 0
	while centers.size() < count and tries < 600:
		tries += 1
		var p := Vector2(rng.randf_range(n * 0.08, _band.position.x - n * 0.12), rng.randf_range(n * 0.08, n * 0.92))
		if p.x < n * 0.06 or not _far_from_towns(p, n * 0.26):
			continue
		if centers.any(func(q): return q.distance_to(p) < n * 0.22):
			continue
		centers.append(p)
	for ctr in centers:
		var rad := n * rng.randf_range(0.06, 0.1)
		var peak := rng.randf_range(8.0, 11.0)
		for y in range(maxi(1, int(ctr.y - rad - 4)), mini(n - 1, int(ctr.y + rad + 4))):
			for x in range(maxi(1, int(ctr.x - rad - 4)), mini(n - 1, int(ctr.x + rad + 4))):
				var p := Vector2i(x, y)
				var d := Vector2(p).distance_to(ctr) / rad + noise.get_noise_2d(x * 3, y * 3) * 0.35
				if d >= 1.0 or p.x >= _band.position.x - 14:   # Streifen westlich des Kuestenbands bleibt frei (Fluss, Wege)
					continue
				var h := int(round(pow(1.0 - d, 1.1) * peak + noise.get_noise_2d(x * 7 + 99, y * 7) * 1.5))
				if h < 1 or c.ground[c.idx(p)] == G.WATER:
					continue
				var i := c.idx(p)
				heights[i] = maxi(heights[i], clampi(h, 1, 11))
				c.blocked[i] = 1
				c.district[i] = 5
	_prune_specks()


func _lakes_region() -> void:
	var made := 0
	var tries := 0
	while made < 2 and tries < 800:
		tries += 1
		var ctr := Vector2i(rng.randi_range(int(n * 0.08), _band.position.x - 12), rng.randi_range(int(n * 0.08), int(n * 0.92)))
		var r := rng.randf_range(4.0, 8.0)
		var box := Rect2i(ctr - Vector2i(int(r) + 3, int(r) + 3), Vector2i(int(r) * 2 + 6, int(r) * 2 + 6))
		if box.intersects(_band.grow(6)):
			continue
		var clear := true
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				var p := Vector2i(x, y)
				if not c.inside(p) or _is_mountain(p) or c.ground[c.idx(p)] in [G.WATER, G.SAND]:
					clear = false
		if not clear:
			continue
		for y in range(box.position.y, box.end.y):
			for x in range(box.position.x, box.end.x):
				var p := Vector2i(x, y)
				var d := Vector2(p).distance_to(Vector2(ctr)) / r + noise.get_noise_2d(x * 5, y * 5) * 0.3
				if d < 1.0:
					c.ground[c.idx(p)] = G.WATER
					c.blocked[c.idx(p)] = 1
				elif d < 1.25:
					c.ground[c.idx(p)] = G.SAND
		c.lakes.append(ctr)
		made += 1


## Fluss vom hoechsten Bergrand ins Meer; die Muendung liegt noerdlich bzw. suedlich aller Orte, das Kuestenband zwischen den Orten
## bleibt frei (die Startverbindung braucht keine Bruecke).
func _river_region() -> void:
	# Quellen: Flachlandzellen am Bergrand, nach Hoehe des Nachbarbergs (hoechste zuerst); eine Quelle in einer abgeschlossenen
	# Mulde findet keinen Weg zum Meer, dann die naechste.
	var cands: Array = []
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			if heights[c.idx(p)] != 0 or c.ground[c.idx(p)] == G.WATER:
				continue
			var hn := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _is_mountain(p + d):
					hn = maxi(hn, heights[c.idx(p + d)])
			if hn > 0 and (x + y + int(rng.randi() % 3)) % 5 == 0:
				cands.append([hn, p])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var north := clampi(_band.position.y - 10, 4, n - 5)
	var south := clampi(_band.end.y + 10, 4, n - 5)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			if _is_mountain(p) or _band.grow(3).has_point(p):
				astar.set_point_solid(p, true)
			else:
				astar.set_point_weight_scale(p, 1.0 + 3.0 * (noise.get_noise_2d(x * 2 + 300, y * 2) + 1.0))
	# Muendung auf der Seite mit mehr Platz zuerst, sonst die andere (nie zwischen den Orten)
	var order := [south, north] if (n - 5 - south) >= (north - 4) else [north, south]
	var path: Array = []
	for cand in cands.slice(0, 8):
		for my in order:
			path = astar.get_id_path(cand[1], Vector2i(coast[my], my))
			if not path.is_empty():
				break
		if not path.is_empty():
			break
	if path.is_empty():
		failures.append(["Fluss: kein Weg zum Meer (Band %s)" % str(_band)])
	for p in path:
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var q: Vector2i = p + d
			if c.inside(q) and not _is_mountain(q) and not _band.has_point(q):
				c.ground[c.idx(q)] = G.WATER
				c.blocked[c.idx(q)] = 1
				c.river.append(q)


# ------------------------------------------------------------------ Orte
func _build_town(k: int) -> void:
	var t: Dictionary = towns_out[k]
	town = Vector2i(int(t.center[0]), int(t.center[1]))
	town_rect = _rects[k]
	c.town_name = str(t.name)
	_pick_palette()
	t["palette"] = palette.duplicate()
	var first := c.buildings.size()
	_town_core(k)
	for b in c.buildings.slice(first):
		b["town"] = k
	t["town_hall"] = _first_id(first, func(b): return b.role == "town_hall")
	t["bauhof"] = _first_id(first, func(b): return b.name == "Städtischer Bauhof")
	t["harbor"] = _first_id(first, func(b): return b.type == "warehouse" and b.name == "Hafenlager")
	t["port_office"] = _first_id(first, func(b): return b.type == "port_office")
	t["start_plot"] = c.start_depots[k] if c.start_depots.size() > k else -1


func _first_id(from: int, pred: Callable) -> int:
	for b in c.buildings.slice(from):
		if pred.call(b):
			return int(b.id)
	return -1


## Ortskern wie CoastGenerator._town(), aber genau ein Unternehmer-Startgrundstueck und Gebaeudelimit je Ort.
func _town_core(k: int) -> void:
	var t := town
	var ch: String = str(towns_out[k].charakter)
	_streets(t, ch)
	for x in range(t.x, coast[t.y] - 1):
		c.ground[c.idx(Vector2i(x, t.y))] = G.ROAD
	for x in range(t.x + 1, coast[t.y]):   # Kai beginnt hinter der Hauptstrasse (sonst trennt er deren Suedteil ab)
		c.ground[c.idx(Vector2i(x, t.y + 1))] = G.QUAY
	for y in range(town_rect.position.y, town_rect.end.y):
		for x in range(town_rect.position.x, mini(town_rect.end.x, coast[clampi(y, 0, n - 1)] - 2)):
			var p := Vector2i(x, y)
			if c.inside(p) and c.ground[c.idx(p)] == G.GRASS and c.road_mask(p) != 0:
				c.ground[c.idx(p)] = G.GRAVEL
	var first := c.buildings.size()
	var nm := c.town_name
	_put("port_office", Vector2i(t.x + 3, t.y - 3), "", "Hafen %s" % nm)
	_put("warehouse", Vector2i(t.x + 3, t.y + 4), "", "Hafenlager")
	var core := Vector2i(t.x - 8, t.y - 4)
	_put("townhall", core, "town_hall", "Rathaus %s" % nm)
	_market_square(core + Vector2i(2, 2))
	_put("job_board", core + Vector2i(-6, 2), "job_board", "Arbeitsamt %s" % nm)
	_put("staffing", core + Vector2i(-6, -4), "staffing", "Personalbüro %s" % nm)
	_put("police", core + Vector2i(2, 8), "police", "Dorfwache %s" % nm)
	_put("doctor", core + Vector2i(-2, 8), "doctor", "Dorfarzt %s" % nm)
	_put("bank", core + Vector2i(4, -6), "bank", "Sparkasse %s" % nm)
	_put("shop", core + Vector2i(-2, -8), "", "Dorfladen %s" % nm)
	_put("shop", core + Vector2i(2, 4), "", "Bäckerei %s" % SURNAMES[rng.randi() % SURNAMES.size()])
	_put("restaurant", core + Vector2i(6, 2), "", "Gasthaus %s" % nm)
	_put("freight_shed", Vector2i(t.x - 22, t.y + 16), "", "Städtischer Bauhof")
	if k == 0:
		_put("factory", Vector2i(t.x - 22, t.y - 17), "", "Kraftwerk")   # ein regionales Kraftwerk (Stadtwerke), nicht je Ort
	_put("dealer", Vector2i(t.x - 14, t.y + 16), "dealer", "Fahrzeughandel %s" % nm)
	_put("workshop", Vector2i(t.x - 8, t.y + 16), "workshop", "Werkstatt " + SURNAMES[rng.randi() % SURNAMES.size()])
	_put("gas_station", Vector2i(t.x - 3, t.y + 15), "", "Tankstelle %s" % nm)
	match ch:
		"Marktflecken":
			_put("shop", core + Vector2i(-10, 6), "", "Markthalle %s" % nm)
		"Handwerkerort":
			_put("workshop", Vector2i(t.x - 18, t.y + 8), "", "Schmiede " + SURNAMES[rng.randi() % SURNAMES.size()])
		"Fischerdorf":
			_put("containers", Vector2i(t.x + 2, t.y + 10), "", "Fischhalle %s" % nm)
	# genau ein Unternehmer-Startgrundstueck je Ort (Abschnitt 5)
	var y0 := t.y - 9
	var r := Rect2i(t.x - 38, y0, PLOT_W, PLOT_H)
	var r2 := Rect2i(t.x - 38 - EXT_W, y0, EXT_W, PLOT_H)
	if _free(r) and _free(r2):
		var id := _plot_building(r, "Firmengrundstück %s" % nm, -1)
		_plot_building(r2, "Erweiterungsfläche %s" % nm, id)
		c.start_depots.append(id)
		_road(Vector2i(t.x - 31, y0 + 2), Vector2i(t.x - 30, y0 + 2))
	_farm_lane()
	c.airport = {}
	airport_rect = Rect2i()
	_airport()
	if not c.airport.is_empty():
		c.airport.name = "Flughafen %s" % nm
		towns_out[k]["airport"] = c.airport
		_air_rects.append(airport_rect)
	var budget := MAX_BUILDINGS - _counted_from(first)
	var k2 := 0
	var tries := 0
	# Bebauung nach Charakter: Fischerdorf dicht am Wasser, Bauerndorf weit verstreut mit Hoefen, Marktflecken mit Doppelhaeusern
	var span: Array = {"Fischerdorf": [1, 14], "Marktflecken": [4, 22], "Bauerndorf": [10, 30], "Handwerkerort": [4, 28]}[ch]
	# kompakt: von der Ortsmitte nach aussen fuellen (Radius waechst mit jedem Haus), Freiflaechen bleiben am Rand
	while budget > 0 and tries < 260:
		tries += 1
		var reach := mini(int(span[1]), int(span[0]) + 4 + k2 + tries / 12)
		var p := Vector2i(t.x - rng.randi_range(int(span[0]), reach), t.y + rng.randi_range(-mini(19, 5 + k2), mini(19, 5 + k2)))
		var kind := "house"
		match ch:
			"Marktflecken":
				kind = "semi" if k2 % 2 == 1 else "house"
			"Bauerndorf":
				kind = "farm" if k2 % 5 == 4 else "house"
			"Handwerkerort":
				kind = "workshop" if k2 % 6 == 5 else ("semi" if k2 % 3 == 2 else "house")
			_:
				kind = "semi" if k2 % 4 == 3 else "house"
		var id2 := _put(kind, p)
		if id2 >= 0:
			budget -= 1
			k2 += 1


## Strassennetz des Orts nach Charakter. Allen gemeinsam: Hauptstrasse an der Kueste (x = Ortsmitte), Querstrasse auf Hoehe der
## Ortsmitte bis zur Hinterstrasse (x - 30, dort beginnen Feldweg und Startgrundstueck).
func _streets(t: Vector2i, ch: String) -> void:
	match ch:
		"Fischerdorf":   # lange Uferstrasse, kurze Stichstrassen, kurze Hinterstrasse
			_road(Vector2i(t.x, t.y - 22), Vector2i(t.x, t.y + 22))
			for dy in [-18, -9, 9, 18]:
				_road(Vector2i(t.x, t.y + dy), Vector2i(t.x - 12, t.y + dy))
			_road(Vector2i(t.x, t.y), Vector2i(t.x - 30, t.y))
			_road(Vector2i(t.x - 30, t.y - 10), Vector2i(t.x - 30, t.y + 6))
		"Marktflecken":  # dichtes Raster um den Markt
			_road(Vector2i(t.x, t.y - 18), Vector2i(t.x, t.y + 18))
			for dy in [-12, -6, 0, 6, 12]:
				_road(Vector2i(t.x, t.y + dy), Vector2i(t.x - 30, t.y + dy))
			_road(Vector2i(t.x - 15, t.y - 12), Vector2i(t.x - 15, t.y + 12))
			_road(Vector2i(t.x - 30, t.y - 18), Vector2i(t.x - 30, t.y + 18))
			_road(Vector2i(t.x - 30, t.y - 18), Vector2i(t.x, t.y - 18))
		"Bauerndorf":    # lockeres Netz, lange Hofwege nach Westen
			_road(Vector2i(t.x, t.y - 16), Vector2i(t.x, t.y + 16))
			for dy in [-14, 0, 14]:
				_road(Vector2i(t.x, t.y + dy), Vector2i(t.x - 30, t.y + dy))
			_road(Vector2i(t.x - 30, t.y - 14), Vector2i(t.x - 30, t.y + 14))
			_road(Vector2i(t.x - 30, t.y + 8), Vector2i(t.x - 38, t.y + 8))
		_:               # Handwerkerort: zwei Achsen, Werkstattgasse
			_road(Vector2i(t.x, t.y - 20), Vector2i(t.x, t.y + 20))
			for dy in [-14, 0, 10]:
				_road(Vector2i(t.x, t.y + dy), Vector2i(t.x - 30, t.y + dy))
			_road(Vector2i(t.x - 18, t.y - 14), Vector2i(t.x - 18, t.y + 18))
			_road(Vector2i(t.x - 30, t.y - 20), Vector2i(t.x - 30, t.y + 20))
			_road(Vector2i(t.x - 18, t.y + 18), Vector2i(t.x, t.y + 18))


func _counted_from(first: int) -> int:
	return c.buildings.slice(first).filter(func(b): return b.type != "plot" or int(b.get("parent", -1)) < 0).size()


## Verbindungsstrassen (Schotter) von Ort k zu Ort k+1: Wegsuche ueber Land (kein Wasser, kein Berg, keine Gebaeude), danach Strasse.
func _connect_towns() -> void:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			var i := c.idx(p)
			if c.ground[i] in [G.WATER, G.QUAY, G.RUNWAY, G.APRON] or heights[i] > 0 or c.building_at[i] >= 0:
				astar.set_point_solid(p, true)
			elif c.ground[i] == G.ROAD:
				astar.set_point_weight_scale(p, 0.5)
			elif c.building_at[i] == -2:
				astar.set_point_weight_scale(p, 6.0)
			else:
				astar.set_point_weight_scale(p, 1.0 + 0.6 * (noise.get_noise_2d(x * 2 + 700, y * 2) + 1.0))
	c.region_roads = []
	for k in towns_out.size() - 1:
		var a := _edge_road(k, true)        # suedlichste Strasse des Orts k ...
		var b := _edge_road(k + 1, false)   # ... zur noerdlichsten des Nachbarorts
		var path: Array = PathStraighten.straighten(astar.get_id_path(a, b), func(q: Vector2i) -> bool: return c.inside(q) and not astar.is_point_solid(q))
		var cells: Array = []
		for p in path:
			if c.ground[c.idx(p)] != G.ROAD:
				c.ground[c.idx(p)] = G.ROAD
				c.district[c.idx(p)] = 4
				cells.append([p.x, p.y])
		c.region_roads.append({"id": "L%d" % (k + 1), "von": k, "nach": k + 1, "zellen": cells.size(), "laenge": path.size(), "verbunden": not path.is_empty(),
			"eigentum": "region", "wartung": "anliegende Städte je Verwaltungsgebiet"})


## Strassenzelle eines Orts, die dem Nachbarort am naechsten liegt (south: groesstes y), nur Zellen, die mit der Ortsmitte verbunden sind.
func _edge_road(k: int, south: bool) -> Vector2i:
	var r: Rect2i = _rects[k]
	var ctr := Vector2i(int(towns_out[k].center[0]), int(towns_out[k].center[1]))
	var best := ctr
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			if not c.inside(p) or not c.is_road(p) or x >= ctr.x:
				continue   # nicht die Uferstrasse/Hafenzufahrt
			if (south and p.y > best.y) or (not south and p.y < best.y):
				if _road_path_exists(p, ctr):
					best = p
	return best


func _land_cover_region() -> void:
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var p := Vector2i(x, y)
			var i := c.idx(p)
			if c.ground[i] != G.GRASS or heights[i] > 0 or c.building_at[i] != -1:
				continue
			if _rects.any(func(r): return r.has_point(p)) or _air_rects.any(func(r): return r.has_point(p)):
				continue
			var f := noise.get_noise_2d(x * 1.5 + 1000, y * 1.5)
			if f > 0.25 and rng.randf() < 0.55:
				_tree(p)
			elif f < _field_threshold(p) and _rects.any(func(r): return r.grow(30).has_point(p)):
				c.ground[i] = G.CROP if (y / 3) % 2 == 0 else G.FIELD


## Felder: Bauerndorf haeufiger (Schwelle hoeher), Fischerdorf seltener.
func _field_threshold(p: Vector2i) -> float:
	for i in _rects.size():
		if _rects[i].grow(30).has_point(p):
			match str(towns_out[i].get("charakter", "")):
				"Bauerndorf":
					return -0.1
				"Fischerdorf":
					return -0.5
	return -0.35


# ------------------------------------------------------------------ Pruefung
## Abschnitte 5/6/17: je Ort <= 40 Gebaeude, genau ein Rathaus, ein Bauhof, ein Hafen, ein Flughafen, ein Startgrundstueck, alles
## ueber das Strassennetz vom Ortszentrum erreichbar; alle Orte untereinander verbunden; Berge unbebaut; >= 60 % unerschlossen;
## Meer am Rand, >= 3 Berggebiete, Fluss bis zum Meer, >= 2 Seen; eindeutige Namen.
func validate(cd: CityData) -> Dictionary:
	var errs: Array = []
	var nn := cd.size
	var mountains := _components(cd)
	if mountains < 3:
		errs.append("nur %d Berggebiete" % mountains)
	if cd.river.is_empty() or not cd.river.any(func(p): return p.x >= coast[p.y] - 2):
		errs.append("Fluss erreicht das Meer nicht")
	if cd.lakes.size() < 2:
		errs.append("nur %d Seen" % cd.lakes.size())
	var names: Array = towns_out.map(func(t): return t.name)
	for nm in names:
		if names.count(nm) > 1:
			errs.append("Name %s doppelt" % nm)
	var per := []
	for k in towns_out.size():
		var t: Dictionary = towns_out[k]
		var own: Array = cd.buildings.filter(func(b): return int(b.get("town", -1)) == k)
		var counted := own.filter(func(b): return b.type != "plot" or int(b.get("parent", -1)) < 0).size()
		per.append(counted)
		if counted > MAX_BUILDINGS:
			errs.append("%s: %d Startgebaeude (> %d)" % [t.name, counted, MAX_BUILDINGS])
		if own.filter(func(b): return b.role == "town_hall").size() != 1:
			errs.append("%s: nicht genau ein Rathaus" % t.name)
		if own.filter(func(b): return b.name == "Städtischer Bauhof").size() != 1:
			errs.append("%s: nicht genau ein Bauhof" % t.name)
		if own.filter(func(b): return b.type == "port_office").size() != 1:
			errs.append("%s: kein Hafen" % t.name)
		if not t.has("airport") or t.airport.is_empty():
			errs.append("%s: kein Flughafen" % t.name)
		if int(t.get("start_plot", -1)) < 0:
			errs.append("%s: kein Startgrundstück" % t.name)
		var ctr := Vector2i(int(t.center[0]), int(t.center[1]))
		for b in own:
			if b.type == "plot" or not b.has("road"):
				continue
			if not _road_path_exists(b.road, ctr):
				errs.append("%s: %s nicht erreichbar" % [t.name, b.name])
				break
		if k > 0 and not _road_path_exists(Vector2i(int(towns_out[0].center[0]), int(towns_out[0].center[1])), ctr):
			errs.append("%s: keine Straßenverbindung zu %s" % [t.name, towns_out[0].name])
	if cd.start_depots.size() != towns_out.size():
		errs.append("%d Startgrundstücke statt %d" % [cd.start_depots.size(), towns_out.size()])
	for b in cd.buildings:
		for y in range(b.y, b.y + b.h):
			for x in range(b.x, b.x + b.w):
				if cd.height[cd.idx(Vector2i(x, y))] > 0:
					errs.append("Gebaeude %s im Berg" % b.name)
	var land := 0
	var used := 0
	for i in nn * nn:
		if cd.ground[i] == G.WATER or cd.height[i] > 0:
			continue
		land += 1
		if cd.building_at[i] >= 0 or cd.ground[i] == G.ROAD:
			used += 1
	var free_share := 1.0 - float(used) / maxf(1.0, float(land))
	if free_share < 0.6:
		errs.append("nur %.0f %% unerschlossen" % (free_share * 100.0))
	return {"ok": errs.is_empty(), "fehler": errs, "berggebiete": mountains, "seen": cd.lakes.size(), "gebaeude_je_ort": per, "unerschlossen": snappedf(free_share, 0.01),
		"namen": names}


## Wie CityGenerator._free, zusaetzlich frei von Startbahn/Vorfeld/Parkplatz anderer Flughaefen.
func _free(r: Rect2i) -> bool:
	if not super._free(r):
		return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if c.ground[c.idx(Vector2i(x, y))] in [G.RUNWAY, G.APRON, G.PARKING]:
				return false
	return true
