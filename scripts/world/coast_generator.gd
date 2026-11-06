class_name CoastGenerator
extends CityGenerator
## Weltart "kueste" (Auftrag 15, docs/COASTAL_TOWN.md): kleiner Kuestenort in einer weiten, unerschlossenen Landschaft.
##
## Gelaende: Meer im Osten bis zum Kartenrand (unruhige Kuestenlinie), Hoehenfeld mit 3-4 Berggebieten im Hinterland
## (CityData.height, nicht begehbar, unbebaut), ein Fluss vom hoechsten Berg bis ins Meer, zwei Seen im Flachland, Waelder,
## Wiesen und Felder. Ort: kompakter Kern an der Kueste mit Schotterstrassen, Hafen (Anleger, Hafenlager), den oeffentlichen
## Rollen, die die Spielsysteme brauchen, vier Startgrundstuecken und Huetten - hoechstens MAX_BUILDINGS fertige Gebaeude.
## Der Generator prueft seine Bedingungen (validate); eine fehlerhafte Welt wird mit dem naechsten Samen neu erzeugt.

const MAX_BUILDINGS := 40
const NAME_A := ["Silber", "Auen", "Morgen", "Sonnen", "Wind", "Möwen", "Bernstein", "Linden", "Falken", "Kiesel", "Nebel", "Salz", "Lior", "Seerosen", "Birken", "Muschel"]
const NAME_B := ["bucht", "hafen", "fels", "wiek", "holm", "strand", "haven", "sund", "ufer", "ort", "furt", "klippe"]

var heights := PackedByteArray()
var town := Vector2i.ZERO          # Hafenkreuzung (Ortsmitte)
var town_rect := Rect2i()          # Ortsbereich (freigehalten von Bergen, Fluss, Seen)
var report := {}                   # Ergebnis der Pruefung (fuer Tests und Fehlersuche)


func generate(seed_value: int, map_size: int = Catalog.MAP_SIZE, reserve_share: float = 0.0) -> CityData:
	var s := seed_value
	for attempt in 8:
		var cd := _generate_once(s, map_size)
		report = validate(cd)
		report["versuch"] = attempt + 1
		if report.ok:
			cd.gen_params = {"welt": "kueste", "seed": seed_value, "erzeugt_mit_seed": s, "versuch": attempt + 1, "groesse": map_size}
			return cd
		s = seed_value + 7919 * (attempt + 1)
	push_warning("CoastGenerator: keine gueltige Welt in 8 Versuchen (%s)" % str(report.get("fehler", [])))
	return c


func _generate_once(seed_value: int, map_size: int) -> CityData:
	reserve = 0.0
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.035
	n = map_size
	c = CityData.new()
	c.setup(n, seed_value)
	c.world = "kueste"
	c.town_name = town_name(seed_value)
	heights = PackedByteArray()
	heights.resize(n * n)
	_sea()
	town = Vector2i(coast[int(n * 0.5)] - 6, int(n * rng.randf_range(0.4, 0.6)))
	town.x = coast[town.y] - 6
	town_rect = Rect2i(town.x - 40, town.y - 24, 46, 48)
	_mountains()
	_lakes()
	_river()
	_town()
	_land_cover()
	c.height = heights
	_finish()
	center = Vector2(town)
	return c


## Kuratierter Fantasiename (zwei Silben aus Listen, keine Dopplung wie "Auenau").
static func town_name(seed_value: int) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 31 + 17
	for k in 10:
		var a: String = NAME_A[r.randi() % NAME_A.size()]
		var b: String = NAME_B[r.randi() % NAME_B.size()]
		if not a.to_lower().ends_with(b.left(2)):
			return a + b
	return "Silberbucht"


# ------------------------------------------------------------------ Gelaende
func _sea() -> void:
	coast = PackedInt32Array()
	coast.resize(n)
	var width := int(n * 0.14)
	for y in n:
		coast[y] = n - width + int(round(6.0 * sin(y * 0.03) + noise.get_noise_2d(0, y * 2) * 10.0))
	for y in n:
		for x in n:
			var i := c.idx(Vector2i(x, y))
			c.district[i] = 5
			if x >= coast[y]:
				c.ground[i] = G.WATER
				c.blocked[i] = 1
			elif x >= coast[y] - 2:
				c.ground[i] = G.SAND
			else:
				c.ground[i] = G.GRASS


## 3-4 Berggebiete im Hinterland: Hoehe aus Kegeln mit Rauschen (Stufen 1..11); Berge sind nicht begehbar.
func _mountains() -> void:
	var count := 3 + (1 if rng.randf() < 0.5 else 0)
	var centers: Array = []
	var tries := 0
	while centers.size() < count and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(n * 0.08, coast[int(n * 0.5)] - n * 0.3), rng.randf_range(n * 0.1, n * 0.9))
		if p.distance_to(Vector2(town)) < n * 0.3:
			continue
		if centers.any(func(q): return q.distance_to(p) < n * 0.24):
			continue
		centers.append(p)
	for ci in centers.size():
		var ctr: Vector2 = centers[ci]
		var rad := n * rng.randf_range(0.07, 0.11)
		var peak := rng.randf_range(8.0, 11.0)
		for y in range(maxi(1, int(ctr.y - rad - 4)), mini(n - 1, int(ctr.y + rad + 4))):
			for x in range(maxi(1, int(ctr.x - rad - 4)), mini(n - 1, int(ctr.x + rad + 4))):
				var p := Vector2i(x, y)
				var d := Vector2(p).distance_to(ctr) / rad + noise.get_noise_2d(x * 3, y * 3) * 0.35
				if d >= 1.0:
					continue
				var h := int(round(pow(1.0 - d, 1.1) * peak + noise.get_noise_2d(x * 7 + 99, y * 7) * 1.5))
				if h < 1 or c.ground[c.idx(p)] == G.WATER or town_rect.grow(6).has_point(p):
					continue
				var i := c.idx(p)
				heights[i] = maxi(heights[i], clampi(h, 1, 11))
				c.blocked[i] = 1
				c.district[i] = 5
	_prune_specks()


## Felssplitter am Bergfuss (Rauschen) entfernen: nur zusammenhaengende Massive ab MIN_MASSIF Feldern bleiben Berg.
const MIN_MASSIF := 30
func _prune_specks() -> void:
	var seen := PackedByteArray()
	seen.resize(n * n)
	for i in n * n:
		if heights[i] == 0 or seen[i] != 0:
			continue
		var comp: Array[int] = []
		var stack: Array[int] = [i]
		seen[i] = 1
		while not stack.is_empty():
			var q: int = stack.pop_back()
			comp.append(q)
			var x := q % n
			for nb in [q - n, q + n, q - 1 if x > 0 else -1, q + 1 if x < n - 1 else -1]:
				if nb >= 0 and nb < n * n and seen[nb] == 0 and heights[nb] > 0:
					seen[nb] = 1
					stack.append(nb)
		if comp.size() < MIN_MASSIF:
			for q in comp:
				heights[q] = 0
				c.blocked[q] = 0


func _is_mountain(p: Vector2i) -> bool:
	return c.inside(p) and heights[c.idx(p)] > 0


## Zwei Seen in Senken des Flachlands (nicht im Ort, nicht an Bergen).
func _lakes() -> void:
	var made := 0
	var tries := 0
	while made < 2 and tries < 500:
		tries += 1
		var ctr := Vector2i(rng.randi_range(int(n * 0.1), coast[int(n * 0.5)] - int(n * 0.12)), rng.randi_range(int(n * 0.1), int(n * 0.9)))
		var r := rng.randf_range(4.0, 8.0)
		var box := Rect2i(ctr - Vector2i(int(r) + 3, int(r) + 3), Vector2i(int(r) * 2 + 6, int(r) * 2 + 6))
		if box.intersects(town_rect.grow(8)):
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


## Fluss vom hoechsten Bergrand bis ins Meer (Wegsuche ueber das Flachland mit Rausch-Kosten fuer Maeander), zwei Felder breit.
func _river() -> void:
	var src := Vector2i(-1, -1)
	var best := -1
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			if heights[c.idx(p)] != 0 or c.ground[c.idx(p)] == G.WATER:
				continue
			var hn := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _is_mountain(p + d):
					hn = maxi(hn, heights[c.idx(p + d)])
			if hn > best and (x + y + int(rng.randi() % 3)) % 5 == 0:
				best = hn
				src = p
	if src.x < 0:
		return
	var mouth_y := clampi(town.y + (int(n * 0.22) if town.y < n / 2 else -int(n * 0.22)), 4, n - 5)
	var mouth := Vector2i(coast[mouth_y], mouth_y)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			if _is_mountain(p) or town_rect.grow(4).has_point(p):
				astar.set_point_solid(p, true)
			else:
				astar.set_point_weight_scale(p, 1.0 + 3.0 * (noise.get_noise_2d(x * 2 + 300, y * 2) + 1.0))
	var path := astar.get_id_path(src, mouth)
	for p in path:
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var q: Vector2i = p + d
			if c.inside(q) and not _is_mountain(q) and not town_rect.has_point(q):
				c.ground[c.idx(q)] = G.WATER
				c.blocked[c.idx(q)] = 1
				c.river.append(q)


# ------------------------------------------------------------------ Ort
func _road(a: Vector2i, b: Vector2i) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var p := a
	while true:
		if c.inside(p) and c.ground[c.idx(p)] != G.WATER:
			c.ground[c.idx(p)] = G.ROAD
			c.district[c.idx(p)] = _district_at(p)
		if p == b:
			break
		p += step


func _district_at(p: Vector2i) -> int:
	if p.x >= town.x - 2:
		return 3          # Hafen
	if town_rect.grow(-6).has_point(p):
		return 0          # Ortskern
	return 1


## Freie Flaeche w x h nahe `near` im Ort, an einer Strasse (Abstand 1), nicht auf Strasse/Wasser/Sand.
func _put(type: String, near: Vector2i, role: String = "", name: String = "") -> int:
	var info: Array = TYPES[type]
	var w: int = info[1]
	var h: int = info[2]
	var best := Rect2i()
	var best_d := INF
	for y in range(town_rect.position.y, town_rect.end.y - h):
		for x in range(town_rect.position.x, town_rect.end.x - w):
			var r := Rect2i(x, y, w, h)
			if not _free(r) or not _touches_road(r):
				continue
			var d := Vector2(r.position + r.size / 2).distance_to(Vector2(near))
			if d < best_d:
				best_d = d
				best = r
	if best_d == INF:
		return -1
	var id := _place(type, best, role, name)
	for y in range(best.position.y, best.end.y):
		for x in range(best.position.x, best.end.x):
			c.district[c.idx(Vector2i(x, y))] = _district_at(Vector2i(x, y))
	_reserve_ring(best)
	return id


func _touches_road(r: Rect2i) -> bool:
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var p := Vector2i(x, y)
			if c.inside(p) and c.is_road(p):
				return true
	return false


## Ein Feld Abstand um Gebaeude (Gaerten, Wege): als Sperrmarkierung -2 fuer weitere Gebaeude, wird in _finish frei.
func _reserve_ring(r: Rect2i) -> void:
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var p := Vector2i(x, y)
			if c.inside(p) and c.building_at[c.idx(p)] == -1 and not c.is_road(p):
				c.building_at[c.idx(p)] = -2


func _town() -> void:
	var t := town
	# Schotterstrassen: Uferstrasse, Hafenzufahrt, drei Querstrassen, Hinterstrasse zu den Startgrundstuecken
	_road(Vector2i(t.x, t.y - 20), Vector2i(t.x, t.y + 20))
	for x in range(t.x, coast[t.y] - 1):
		c.ground[c.idx(Vector2i(x, t.y))] = G.ROAD
	for x in range(t.x, coast[t.y]):
		c.ground[c.idx(Vector2i(x, t.y + 1))] = G.QUAY
	for dy in [-12, 0, 12]:
		_road(Vector2i(t.x, t.y + dy), Vector2i(t.x - 30, t.y + dy))
	_road(Vector2i(t.x - 30, t.y - 20), Vector2i(t.x - 30, t.y + 20))
	_road(Vector2i(t.x - 30, t.y - 20), Vector2i(t.x, t.y - 20))
	_road(Vector2i(t.x - 30, t.y + 20), Vector2i(t.x, t.y + 20))
	for y in range(town_rect.position.y, town_rect.end.y):
		for x in range(town_rect.position.x, mini(town_rect.end.x, coast[clampi(y, 0, n - 1)] - 2)):
			var p := Vector2i(x, y)
			if c.inside(p) and c.ground[c.idx(p)] == G.GRASS and c.road_mask(p) != 0:
				c.ground[c.idx(p)] = G.GRAVEL
	# Hafen: Anleger und Hafenlager direkt am Wasser
	_put("port_office", Vector2i(t.x + 3, t.y - 3), "", "Hafen %s" % c.town_name)
	_put("warehouse", Vector2i(t.x + 3, t.y + 4), "", "Hafenlager")
	# Gemeinschaftsgebaeude der Grundversorgung (je Rolle ein kleines Gebaeude)
	var core := Vector2i(t.x - 8, t.y - 4)
	_put("townhall", core, "town_hall", "Rathaus %s" % c.town_name)
	_put("job_board", core + Vector2i(-6, 2), "job_board", "Arbeitsamt")
	_put("staffing", core + Vector2i(-6, -4), "staffing", "Personalbüro")
	_put("police", core + Vector2i(2, 8), "police", "Dorfwache")
	_put("doctor", core + Vector2i(-2, 8), "doctor", "Dorfarzt")
	_put("bank", core + Vector2i(4, -6), "bank", "Sparkasse %s" % c.town_name)
	_put("shop", core + Vector2i(-2, -8), "", "Dorfladen am Markt")
	_put("shop", core + Vector2i(2, 4), "", "Bäckerei %s" % SURNAMES[rng.randi() % SURNAMES.size()])
	_put("restaurant", core + Vector2i(6, 2), "", "Gasthaus zum Anker")
	_put("freight_shed", Vector2i(t.x - 22, t.y + 16), "", "Städtischer Bauhof")
	_put("factory", Vector2i(t.x - 22, t.y - 17), "", "Kraftwerk")
	_put("dealer", Vector2i(t.x - 14, t.y + 16), "dealer", "Fahrzeughandel")
	_put("workshop", Vector2i(t.x - 8, t.y + 16), "workshop", "Werkstatt " + SURNAMES[rng.randi() % SURNAMES.size()])
	_put("gas_station", Vector2i(t.x - 3, t.y + 15), "", "Tankstelle am Hafen")
	# Vier Startgrundstuecke an der Hinterstrasse (gleiche Groesse, alle ueber den Ort erreichbar)
	for k in 4:
		var y0 := t.y - 19 + k * 10
		var r := Rect2i(t.x - 38, y0, PLOT_W, PLOT_H)
		var r2 := Rect2i(t.x - 38 - EXT_W, y0, EXT_W, PLOT_H)
		if _free(r) and _free(r2):
			var id := _plot_building(r, "Firmengrundstück %d" % (k + 1), -1)
			_plot_building(r2, "Erweiterungsfläche %d" % (k + 1), id)
			c.start_depots.append(id)
			_road(Vector2i(t.x - 31, y0 + 2), Vector2i(t.x - 30, y0 + 2))
	# Huetten und kleine Haeuser bis zur Obergrenze
	var budget := MAX_BUILDINGS - _counted()
	var k2 := 0
	var tries := 0
	while budget > 0 and tries < 200:
		tries += 1
		var p := Vector2i(t.x - rng.randi_range(4, 28), t.y + rng.randi_range(-19, 19))
		var id2 := _put("semi" if k2 % 3 == 2 else "house", p)
		if id2 >= 0:
			budget -= 1
			k2 += 1


## Gezaehlte Gebaeude (Startgrundstuecke als je ein Gruendungsbuero, Erweiterungsflaechen nicht).
func _counted() -> int:
	return c.buildings.filter(func(b): return b.type != "plot" or int(b.get("parent", -1)) < 0).size()


## Waelder, Wiesen und Felder ausserhalb des Ortes.
func _land_cover() -> void:
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var p := Vector2i(x, y)
			var i := c.idx(p)
			if c.ground[i] != G.GRASS or heights[i] > 0 or town_rect.has_point(p) or c.building_at[i] != -1:
				continue
			var f := noise.get_noise_2d(x * 1.5 + 1000, y * 1.5)
			if f > 0.25 and rng.randf() < 0.55:
				_tree(p)
			elif f < -0.35 and town_rect.grow(30).has_point(p):
				c.ground[i] = G.CROP if (y / 3) % 2 == 0 else G.FIELD


# ------------------------------------------------------------------ Pruefung
## Bedingungen des Auftrags (Abschnitt 13): Meer am Rand, Hafen am Wasser, >=3 Berggebiete, Fluss bis zum Meer, >=2 Seen,
## hoechstens 40 Gebaeude, genau ein Rathaus und ein Bauhof, Startgrundstuecke erreichbar, Berge unbebaut, >=60 % unerschlossen.
func validate(cd: CityData) -> Dictionary:
	var errs: Array = []
	var nn := cd.size
	var sea_edge := false
	for y in nn:
		if cd.ground[cd.idx(Vector2i(nn - 1, y))] == G.WATER:
			sea_edge = true
	if not sea_edge:
		errs.append("kein Meer am Kartenrand")
	var mountains := _components(cd)
	if mountains < 3:
		errs.append("nur %d Berggebiete" % mountains)
	if cd.river.is_empty() or not cd.river.any(func(p): return p.x >= coast[p.y] - 2):
		errs.append("Fluss erreicht das Meer nicht")
	if cd.lakes.size() < 2:
		errs.append("nur %d Seen" % cd.lakes.size())
	var counted := cd.buildings.filter(func(b): return b.type != "plot" or int(b.get("parent", -1)) < 0).size()
	if counted > MAX_BUILDINGS:
		errs.append("%d Startgebaeude (> %d)" % [counted, MAX_BUILDINGS])
	if cd.buildings.filter(func(b): return b.role == "town_hall").size() != 1:
		errs.append("nicht genau ein Rathaus")
	if cd.buildings.filter(func(b): return b.name == "Städtischer Bauhof").size() != 1:
		errs.append("nicht genau ein Bauhof")
	var port: Array = cd.buildings.filter(func(b): return b.type == "port_office")
	if port.is_empty():
		errs.append("kein Hafen")
	if cd.start_depots.size() < 4:
		errs.append("nur %d Startgrundstuecke" % cd.start_depots.size())
	for sid in cd.start_depots:
		if not _road_path_exists(cd.building(sid).road, town):
			errs.append("Startgrundstueck %d nicht erreichbar" % sid)
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
	return {"ok": errs.is_empty(), "fehler": errs, "berggebiete": mountains, "seen": cd.lakes.size(), "gebaeude": counted, "unerschlossen": snappedf(free_share, 0.01), "name": cd.town_name}


## Zusammenhaengende Berggebiete (4er-Nachbarschaft).
func _components(cd: CityData) -> int:
	var seen := PackedByteArray()
	seen.resize(cd.size * cd.size)
	var comps := 0
	for i in cd.size * cd.size:
		if cd.height[i] == 0 or seen[i] != 0:
			continue
		comps += 1
		var stack: Array[int] = [i]
		seen[i] = 1
		while not stack.is_empty():
			var q: int = stack.pop_back()
			var x := q % cd.size
			for nb in [q - cd.size, q + cd.size, q - 1 if x > 0 else -1, q + 1 if x < cd.size - 1 else -1]:
				if nb >= 0 and nb < cd.size * cd.size and seen[nb] == 0 and cd.height[nb] > 0:
					seen[nb] = 1
					stack.append(nb)
	return comps
