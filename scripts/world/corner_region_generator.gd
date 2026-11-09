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
		cd.gen_params["generator"] = 3
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


func _sea() -> void:
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
		y = clampi(y, 62, n - 63)
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
	var chars: Array = CHARACTERS.duplicate()
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


func _mountains_corners() -> void:
	var centers: Array = []
	var tries := 0
	while centers.size() < 4 and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(n * 0.36, n * 0.64), rng.randf_range(n * 0.13, n * 0.87))
		if centers.any(func(q): return q.distance_to(p) < n * 0.16):
			continue
		centers.append(p)
	for ctr in centers:
		var rad := n * rng.randf_range(0.045, 0.07)
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


func _lakes_corners() -> void:
	var made := 0
	var tries := 0
	while made < 2 and tries < 200:
		tries += 1
		var ctr := Vector2i(rng.randi_range(int(n * 0.34), int(n * 0.66)), rng.randi_range(int(n * 0.28), int(n * 0.72)))
		var clear := true
		for y in range(ctr.y - 8, ctr.y + 9):
			for x in range(ctr.x - 8, ctr.x + 9):
				if heights[c.idx(Vector2i(x, y))] > 0 or c.ground[c.idx(Vector2i(x, y))] == G.WATER:
					clear = false
		if not clear or c.lakes.any(func(q): return q.distance_to(ctr) < 30):
			continue
		for y in range(ctr.y - 7, ctr.y + 8):
			for x in range(ctr.x - 7, ctr.x + 8):
				var d := Vector2(Vector2i(x, y)).distance_to(Vector2(ctr)) + noise.get_noise_2d(x * 5, y * 5) * 2.0
				if d < 6.0:
					var i := c.idx(Vector2i(x, y))
					c.ground[i] = G.WATER
					c.blocked[i] = 1
		c.lakes.append(ctr)
		made += 1


func _river_corners() -> void:
	# Die Muendung liegt zwischen den Nord- und Suedorten; die Landstrassen koennen sie umrunden.
	var y0 := int(n * 0.5)
	for x in range(int(n * 0.58), n):
		var y := y0 + int(round(9.0 * sin(float(x) * 0.045)))
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
	var plaza := _hub_area(q_sw, Vector2i(7, 5), q_sw.position + Vector2i(3, 8), G.PLAZA)
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
		var path := astar.get_id_path(a, b)
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
