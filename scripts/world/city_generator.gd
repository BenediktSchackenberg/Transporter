class_name CityGenerator
extends RefCounted
## Erzeugt eine zusammenhaengende Stadt aus einem Seed:
## Strassenraster (enger in der Innenstadt), Kueste mit Hafen im Osten, sechs Viertel,
## Sonderbauten (Bank, Autohaeuser, Werkstaetten, Gueterbahnhof) und 12 Depotstandorte.
## Die 4 Startdepots liegen symmetrisch im gleichen Abstand zum Zentrum (faire Startbedingungen).

const G := CityData.G

## typ -> [Sprites, Breite, Hoehe, eingehende Waren, ausgehende Waren]
const TYPES := {
	"house": [["house0", "house1", "house2", "house3", "house0s1", "house1s1", "house2s1", "house3s1", "house0s2", "house1s2", "house2s2", "house3s2", "house0s3", "house1s3", "house2s3", "house3s3", "house0s4", "house1s4", "house2s4", "house3s4", "house0s5", "house1s5", "house2s5", "house3s5"], 2, 2, ["pakete", "moebel"], []],
	"apartment": [["apartment0", "apartment1", "apartment0s1", "apartment1s1", "apartment0s2", "apartment1s2", "apartment0s3", "apartment1s3"], 3, 3, ["pakete", "moebel", "getraenke"], ["pakete"]],
	"shop": [["shop0", "shop1", "shop2", "shop0s1", "shop1s1", "shop2s1", "shop0s2", "shop1s2", "shop2s2", "shop0s3", "shop1s3", "shop2s3"], 2, 2, ["pakete", "getraenke", "elektronik", "lebensmittel"], ["pakete"]],
	"pharmacy": [["pharmacy"], 2, 2, ["medikamente", "pakete"], []],
	"restaurant": [["restaurant"], 2, 2, ["lebensmittel", "getraenke"], []],
	"office": [["office0", "office1", "office0s1", "office1s1", "office0s2", "office1s2"], 3, 3, ["pakete", "elektronik", "moebel"], ["pakete", "elektronik"]],
	"bank": [["bank"], 3, 3, ["pakete"], []],
	"factory": [["factory"], 4, 4, ["baustoffe", "maschinenteile"], ["maschinenteile", "baustoffe", "elektronik", "moebel"]],
	"warehouse": [["warehouse"], 4, 3, ["pakete", "getraenke", "lebensmittel", "moebel", "elektronik", "container"],
		["pakete", "getraenke", "lebensmittel", "moebel", "elektronik", "medikamente"]],
	"farm": [["farm"], 3, 3, ["maschinenteile"], ["lebensmittel"]],
	"port_office": [["port_office"], 3, 2, ["container", "maschinenteile"], ["container", "elektronik", "lebensmittel", "getraenke", "medikamente"]],
	"freight_shed": [["freight_shed"], 5, 3, ["container", "moebel"], ["baustoffe", "container", "maschinenteile"]],
	"gas_station": [["gas_station"], 3, 2, ["getraenke", "pakete"], []],
	"workshop": [["workshop"], 3, 2, ["maschinenteile"], []],
	"dealer": [["dealer"], 4, 3, [], []],
	"depot": [["depot"], 3, 3, [], []],
	"containers": [["containers"], 2, 2, [], []],
	"crane": [["crane"], 2, 3, [], []],
	"fountain": [["fountain"], 2, 2, [], []],
	"clinic": [["clinic"], 3, 3, ["medikamente", "elektronik", "pakete"], []],
	"construction": [["construction"], 3, 3, ["baustoffe", "maschinenteile"], []],
	"shipyard": [["freight_shed"], 5, 3, ["maschinenteile"], ["maschinenteile"]],
	"semi": [["semi", "semis1", "semis2", "semis3"], 4, 2, ["pakete", "moebel"], []],
	"villa": [["villa", "villa1", "villa3", "villa4", "villa5", "villa6"], 4, 4, ["moebel", "pakete", "getraenke"], []],
	"highrise": [["highrise0", "highrise1"], 3, 3, ["pakete", "elektronik", "moebel"], ["pakete", "elektronik"]],
	"school": [["school"], 6, 4, ["moebel", "pakete", "lebensmittel"], []],
	"kindergarten": [["kindergarten"], 4, 3, ["lebensmittel", "getraenke"], []],
	"airport_cargo": [["airport_cargo"], 6, 4, ["container", "pakete", "elektronik"], ["container", "elektronik", "pakete"]],
	"job_board": [["job_board"], 3, 2, [], []],
	"staffing": [["staffing"], 2, 2, [], []],
	"office_site": [["office0", "office1"], 3, 3, [], []],
}

const LOTS := [
	{"shop": 4, "pharmacy": 1, "restaurant": 2, "office": 3, "highrise": 1, "apartment": 2},     # Innenstadt
	{"house": 6, "semi": 2, "villa": 1, "apartment": 2, "shop": 1},                # Wohnviertel
	{"factory": 3, "warehouse": 3, "containers": 1},                               # Industrie
	{"warehouse": 3, "port_office": 1, "containers": 3},                           # Hafen
	{"warehouse": 3, "shop": 1, "office": 1, "gas_station": 1},                    # Gewerbe
	{"house": 2, "farm": 2},                                                       # Randbezirk
]

const SURNAMES := ["Krause", "Hansen", "Weber", "Schulz", "Becker", "Wagner", "Hoffmann", "Koch", "Richter",
	"Klein", "Wolf", "Neumann", "Schwarz", "Braun", "Zimmermann", "Hartmann", "Lange", "Werner", "Krüger",
	"Meier", "Lehmann", "Schmitt", "Fischer", "Vogel", "Jung", "Otto", "Kaiser", "Fuchs", "Peters", "Lorenz"]
const NAMES := {
	"shop": ["Bäckerei", "Elektro", "Getränkemarkt", "Buchhandlung", "Supermarkt", "Möbelhaus", "Blumen", "Kiosk", "Modehaus", "Technik"],
	"pharmacy": ["Apotheke"],
	"restaurant": ["Restaurant Adler", "Pizzeria Roma", "Café Hafenblick", "Bistro Ecke", "Wirtshaus Linde",
		"Imbiss Bahnhof", "Trattoria Sole", "Gasthof Krone"],
	"office": ["Versicherung", "Kanzlei", "Agentur", "Software", "Verlag", "Ingenieurbüro"],
	"factory": ["Stahlwerk", "Maschinenbau", "Möbelfabrik", "Elektronikwerk", "Zementwerk", "Brauerei"],
	"warehouse": ["Lager", "Großhandel", "Druckerei", "Recyclinghof", "Kühlhaus"],
	"port_office": ["Hafenkontor", "Reederei"],
}

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var c: CityData
var n: int
var center: Vector2
var coast: PackedInt32Array
var xs: Array = []
var ys: Array = []


func generate(seed_value: int, map_size: int = Catalog.MAP_SIZE) -> CityData:
	rng.seed = seed_value
	noise.seed = seed_value
	noise.frequency = 0.035
	n = map_size
	c = CityData.new()
	c.setup(n, seed_value)
	center = Vector2(n * 0.45, n * 0.5)
	_coast_and_districts()
	_roads()
	_blocks_ground()
	_specials()
	_fill_lots()
	_finish()
	return c


func _coast_and_districts() -> void:
	coast = PackedInt32Array()
	coast.resize(n)
	for y in n:
		coast[y] = n - 10 + int(round(3.0 * sin(y * 0.07) + noise.get_noise_2d(0, y * 3) * 2.0))
	for y in n:
		for x in n:
			var cell := Vector2i(x, y)
			var i := c.idx(cell)
			if x >= coast[y]:
				c.ground[i] = G.WATER
				c.blocked[i] = 1
			else:
				c.ground[i] = G.GRASS
			c.district[i] = _district_for(x, y)


func _district_for(x: int, y: int) -> int:
	var jx := x + noise.get_noise_2d(x, y) * 10.0
	var jy := y + noise.get_noise_2d(y + 500, x) * 10.0
	var d := Vector2(jx, jy).distance_to(center) / n
	if d < 0.17:
		return 0
	if jx > n * 0.72 and absf(jy - n * 0.42) < n * 0.17:
		return 3
	if jx > n * 0.5 and jy > n * 0.64:
		return 2
	if (jx < n * 0.33 and jy > n * 0.3 and jy < n * 0.62) or (jy < n * 0.27 and jx > n * 0.52):
		return 4
	if d > 0.43:
		return 5
	return 1


func _roads() -> void:
	var limit_x := n - 16
	for y in n:
		limit_x = mini(limit_x, coast[y] - 7)
	xs = [2]
	while true:
		var last: int = xs[-1]
		var step := 9 + int(7.0 * absf(last - center.x) / (n * 0.5)) + rng.randi_range(0, 2)
		if last + step > limit_x:
			break
		xs.append(last + step)
	if limit_x - xs[-1] >= 8:
		xs.append(limit_x)   # Kuestenstrasse, damit der Streifen bis zum Wasser erschlossen ist
	ys = [2]
	while true:
		var last: int = ys[-1]
		var step := 9 + int(7.0 * absf(last - center.y) / (n * 0.5)) + rng.randi_range(0, 2)
		if last + step > n - 3:
			break
		ys.append(last + step)
	for x in xs:
		for y in range(ys[0], ys[-1] + 1):
			_set_ground(Vector2i(x, y), G.ROAD)
	for y in ys:
		for x in range(xs[0], xs[-1] + 1):
			_set_ground(Vector2i(x, y), G.ROAD)
	# Hafenstichstrassen bis zur Kaikante
	for y in ys:
		if c.district_of(Vector2i(xs[-1] + 2, y)) == 3:
			for x in range(xs[-1], coast[y] - 1):
				_set_ground(Vector2i(x, y), G.ROAD)
	# Randbezirke: einzelne Strassenabschnitte entfernen (groessere Bloecke), Zusammenhang bleibt erhalten
	var segments: Array = []
	for i in xs.size():
		for j in ys.size() - 1:
			segments.append([Vector2i(xs[i], ys[j] + 1), Vector2i(0, 1), ys[j + 1] - ys[j] - 1])
	for j in ys.size():
		for i in xs.size() - 1:
			segments.append([Vector2i(xs[i] + 1, ys[j]), Vector2i(1, 0), xs[i + 1] - xs[i] - 1])
	for seg in segments:
		var mid: Vector2i = seg[0] + seg[1] * (seg[2] / 2)
		if c.district_of(mid) != 5 or rng.randf() > 0.3:
			continue
		for k in seg[2]:
			_set_ground(seg[0] + seg[1] * k, G.GRASS)
		if not _roads_connected():
			for k in seg[2]:
				_set_ground(seg[0] + seg[1] * k, G.ROAD)


func _roads_connected() -> bool:
	var total := 0
	var start := Vector2i(-1, -1)
	for i in c.ground.size():
		if c.ground[i] == G.ROAD:
			total += 1
			if start.x < 0:
				start = Vector2i(i % n, i / n)
	var seen := {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var q: Vector2i = p + d
			if c.is_road(q) and not seen.has(q):
				seen[q] = true
				stack.append(q)
	c.road_count = total
	return seen.size() == total


func _set_ground(cell: Vector2i, ground_type: int) -> void:
	if c.inside(cell) and c.ground[c.idx(cell)] != G.WATER:
		c.ground[c.idx(cell)] = ground_type


func _blocks_ground() -> void:
	for y in n:
		for x in n:
			var cell := Vector2i(x, y)
			var i := c.idx(cell)
			var gt := c.ground[i]
			if gt == G.WATER or gt == G.ROAD:
				continue
			var dist := c.district[i]
			if x == coast[y] - 1 and dist == 3:
				c.ground[i] = G.QUAY
			elif x >= coast[y] - 2:
				c.ground[i] = G.SAND
			elif c.road_mask(cell) != 0 or _diag_road(cell):
				c.ground[i] = G.GRASS if dist == 5 else G.SIDEWALK
			else:
				c.ground[i] = [G.PLAZA, G.GRASS, G.CONCRETE, G.CONCRETE, G.CONCRETE, G.GRASS][dist]


func _diag_road(cell: Vector2i) -> bool:
	for d in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if c.is_road(cell + d):
			return true
	return false


## Innenflaeche (ohne Gehwegring) des Blocks, in dem die Zelle liegt.
func _block_at(p: Vector2) -> Rect2i:
	var bx := 0
	var by := 0
	for i in xs.size() - 1:
		if p.x > xs[i] and p.x < xs[i + 1]:
			bx = i
	for j in ys.size() - 1:
		if p.y > ys[j] and p.y < ys[j + 1]:
			by = j
	return Rect2i(xs[bx] + 2, ys[by] + 2, xs[bx + 1] - xs[bx] - 3, ys[by + 1] - ys[by] - 3)


func _free(r: Rect2i) -> bool:
	if r.position.x < 1 or r.position.y < 1 or r.end.x >= n - 1 or r.end.y >= n - 1:
		return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := c.idx(Vector2i(x, y))
			var gt := c.ground[i]
			if c.building_at[i] != -1 or gt in [G.ROAD, G.WATER, G.SIDEWALK, G.SAND, G.QUAY]:
				return false
	return true


func _place(type: String, r: Rect2i, role: String = "", name: String = "") -> int:
	var info: Array = TYPES[type]
	var id := c.buildings.size()
	var sprites: Array = info[0]
	var b := {"id": id, "type": type, "sprite": sprites[rng.randi() % sprites.size()],
		"x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y,
		"district": c.district_of(r.position), "in": info[3], "out": info[4],
		"role": role if role != "" else ("customer" if not (info[3].is_empty() and info[4].is_empty()) else "decor"),
		"name": name if name != "" else _name_for(type, id)}
	c.buildings.append(b)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := c.idx(Vector2i(x, y))
			c.building_at[i] = id
			c.blocked[i] = 1
	return id


func _name_for(type: String, id: int) -> String:
	var sur: String = SURNAMES[(id * 7 + rng.randi()) % SURNAMES.size()]
	match type:
		"house":
			return "Familie " + sur
		"apartment":
			return "Wohnblock " + sur + "straße"
		"farm":
			return "Hof " + sur
		"restaurant":
			var r: Array = NAMES.restaurant
			return r[rng.randi() % r.size()]
		"gas_station":
			return "Tankstelle " + sur
		"freight_shed":
			return "Güterbahnhof"
		"semi":
			return "Doppelhaus " + sur
		"villa":
			return "Villa " + sur
		"highrise":
			return "Hochhaus " + ["Rheinblick", "Zentrum", "Altstadt", "Domviertel"][rng.randi() % 4]
		"school":
			return "Grundschule " + sur + "straße"
		"kindergarten":
			return "Kita " + ["Sonnenschein", "Regenbogen", "Pusteblume", "Kleine Strolche"][rng.randi() % 4]
		"airport_cargo":
			return "Frachtterminal Flughafen"
		"containers", "crane", "fountain":
			return {"containers": "Containerlager", "crane": "Hafenkran", "fountain": "Brunnen"}[type]
	var pre: Array = NAMES.get(type, ["Firma"])
	return "%s %s" % [pre[rng.randi() % pre.size()], sur]


const PLOT_W := 7
const PLOT_H := 6
const EXT_W := 5


func _specials() -> void:
	# 4 gleich grosse, leere Startgrundstuecke (7x6) im gleichen Abstand zum Zentrum, je mit Erweiterungsflaeche (5x6).
	# Weitere 8 Standorte: mietbare Gewerbehallen (Depots).
	var angles := [45, 135, 225, 315, 0, 90, 180, 270, 20, 110, 200, 290]
	var radius := n * 0.29
	for k in angles.size():
		var a := deg_to_rad(float(angles[k]))
		var target := center + Vector2(cos(a), sin(a)) * radius
		if k < 4:
			var id := _place_plot(target, k)
			if id >= 0:
				c.start_depots.append(id)
			continue
		var hall := _place_in_block("depot", target, "depot_site", "Gewerbehalle %d" % (k + 1))
		if hall >= 0:
			c.depot_sites.append(hall)
	_place_in_block("bank", center + Vector2(4, -6), "bank", "Stadtsparkasse")
	_place_in_block("dealer", Vector2(n * 0.22, n * 0.45), "dealer", "Autohaus West")
	_place_in_block("dealer", Vector2(n * 0.68, n * 0.18), "dealer", "Autohaus Nord")
	for p in [Vector2(n * 0.18, n * 0.58), Vector2(n * 0.62, n * 0.78), Vector2(n * 0.5, n * 0.2)]:
		_place_in_block("workshop", p, "workshop", "Werkstatt " + SURNAMES[rng.randi() % SURNAMES.size()])
	_place_in_block("freight_shed", Vector2(n * 0.62, n * 0.88))
	# Orte fuer persoenliche Besuche: Jobboerse, Personalbuero, Buerostandorte
	_place_in_block("job_board", center + Vector2(-6, 6), "job_board", "Jobbörse")
	_place_in_block("staffing", center + Vector2(10, 8), "staffing", "Personalbüro")
	for spec in [["Bürohaus (Zentrum)", Vector2(2, -2)], ["Nordbüro", Vector2(0, -n * 0.3)], ["Westbüro", Vector2(-n * 0.3, 0)],
			["Südbüro", Vector2(0, n * 0.32)], ["Hafenbüro", Vector2(n * 0.33, -n * 0.06)]]:
		_place_in_block("office_site", center + spec[1], "office_site", spec[0])
	# Ziele der Lieferketten
	for spec in [["Stadtklinik", Vector2(n * 0.4, n * 0.36)], ["Klinik am Park", Vector2(n * 0.3, n * 0.68)]]:
		_place_in_block("clinic", spec[1], "customer", spec[0])
	for spec in [["Baustelle Nord", Vector2(n * 0.45, n * 0.15)], ["Baustelle West", Vector2(n * 0.12, n * 0.4)],
			["Baustelle Süd", Vector2(n * 0.5, n * 0.8)]]:
		_place_in_block("construction", spec[1], "customer", spec[0])
	_place_in_block("shipyard", Vector2(n * 0.8, n * 0.5), "customer", "Werft")
	for spec in [["Grundschule Am Rhein", Vector2(n * 0.3, n * 0.52)], ["Grundschule Nord", Vector2(n * 0.55, n * 0.3)]]:
		_place_in_block("school", spec[1], "customer", spec[0])
	for spec in [["Kita Sonnenschein", Vector2(n * 0.36, n * 0.58)], ["Kita Regenbogen", Vector2(n * 0.6, n * 0.42)]]:
		_place_in_block("kindergarten", spec[1], "customer", spec[0])
	_place_in_block("airport_cargo", Vector2(n * 0.82, n * 0.82), "customer", "Frachtterminal Flughafen")
	for k in 3:
		_place_in_block("gas_station", Vector2(rng.randf_range(0.2, 0.7) * n, rng.randf_range(0.2, 0.8) * n))
	# Brunnen-Park in der Innenstadt
	var park := _block_at(center + Vector2(-12, 10))
	_make_park(park)


## Leeres Firmengrundstueck (Betonhof, begehbar) plus angrenzende Erweiterungsflaeche in einem Block.
func _place_plot(target: Vector2, k: int) -> int:
	var candidates: Array = []
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var cb := Vector2((xs[i] + xs[i + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5)
			candidates.append([cb.distance_squared_to(target), cb])
	candidates.sort_custom(func(p, q): return p[0] < q[0])
	for cand in candidates:
		var blk := _block_at(cand[1])
		if blk.size.x < PLOT_W + EXT_W or blk.size.y < PLOT_H:
			continue
		var r := Rect2i(blk.position, Vector2i(PLOT_W, PLOT_H))
		var r2 := Rect2i(blk.position + Vector2i(PLOT_W, 0), Vector2i(EXT_W, PLOT_H))
		if not _free(r) or not _free(r2):
			continue
		var id := _plot_building(r, "Firmengrundstück %d" % (k + 1), -1)
		_plot_building(r2, "Erweiterungsfläche %d" % (k + 1), id)
		return id
	return -1


func _plot_building(r: Rect2i, name: String, parent: int) -> int:
	var id := c.buildings.size()
	c.buildings.append({"id": id, "type": "plot", "sprite": "", "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y,
		"district": c.district_of(r.position), "in": ["moebel", "pakete", "elektronik", "baustoffe"], "out": [], "role": "plot",
		"name": name, "parent": parent})
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := c.idx(Vector2i(x, y))
			c.building_at[i] = id
			c.ground[i] = G.CONCRETE
	return id


func _place_in_block(type: String, target: Vector2, role: String = "", name: String = "") -> int:
	var info: Array = TYPES[type]
	var size := Vector2i(info[1], info[2])
	# Bloecke nach Abstand zum Ziel durchsuchen, erste freie Ecke nehmen
	var candidates: Array = []
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var center_b := Vector2((xs[i] + xs[i + 1]) * 0.5, (ys[j] + ys[j + 1]) * 0.5)
			candidates.append([center_b.distance_squared_to(target), center_b])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for cand in candidates:
		var blk := _block_at(cand[1])
		if blk.size.x < size.x or blk.size.y < size.y:
			continue
		var r := Rect2i(blk.position, size)
		if _free(r):
			return _place(type, r, role, name)
	return -1


func _make_park(blk: Rect2i) -> bool:
	for y in range(blk.position.y, blk.end.y):
		for x in range(blk.position.x, blk.end.x):
			var cell := Vector2i(x, y)
			if c.building_at[c.idx(cell)] != -1:
				return false
	var mid := blk.position + blk.size / 2
	for y in range(blk.position.y, blk.end.y):
		for x in range(blk.position.x, blk.end.x):
			var i := c.idx(Vector2i(x, y))
			c.ground[i] = G.GRAVEL if (x == mid.x or y == mid.y) else (G.PARK if rng.randf() < 0.7 else G.GRASS)
			c.building_at[i] = -2   # reserviert
	_place("fountain", Rect2i(mid - Vector2i(1, 1), Vector2i(2, 2)))
	for k in 10:
		var p := Vector2i(rng.randi_range(blk.position.x, blk.end.x - 1), rng.randi_range(blk.position.y, blk.end.y - 1))
		if c.ground[c.idx(p)] != G.GRAVEL and c.building_at[c.idx(p)] == -2:
			_tree(p)
	for k in 3:
		c.benches.append(Vector2i(mid.x + rng.randi_range(-3, 3), mid.y + 1))
	return true


func _tree(p: Vector2i) -> void:
	c.trees.append([p, rng.randi() % 3])
	c.blocked[c.idx(p)] = 1


func _pick(weights: Dictionary) -> String:
	var total := 0
	for k in weights:
		total += weights[k]
	var r := rng.randi() % total
	for k in weights:
		r -= weights[k]
		if r < 0:
			return k
	return weights.keys()[0]


func _fill_lots() -> void:
	for i in xs.size():
		for j in ys.size() - 1:
			var x1: int = (xs[i + 1] if i + 1 < xs.size() else coast[ys[j] + 1] - 1)
			var blk := Rect2i(xs[i] + 2, ys[j] + 2, x1 - xs[i] - 3, ys[j + 1] - ys[j] - 3)
			if blk.size.x < 2 or blk.size.y < 2:
				continue
			var dist := c.district_of(blk.position + blk.size / 2)
			if dist in [0, 1] and rng.randf() < 0.1 and _make_park(blk):
				continue
			if dist == 5 and rng.randf() < 0.45:
				_make_fields(blk)
			_fill_block(blk, dist)
	# Hafen: Kraene an der Kaikante
	for y in range(4, n - 4, 9):
		if c.district_of(Vector2i(coast[y] - 3, y)) == 3:
			var r := Rect2i(coast[y] - 4, y, 2, 3)
			if _free(r):
				_place("crane", r)


func _make_fields(blk: Rect2i) -> void:
	for y in range(blk.position.y, blk.end.y):
		for x in range(blk.position.x, blk.end.x):
			c.ground[c.idx(Vector2i(x, y))] = G.CROP if (y / 3) % 2 == 0 else G.FIELD


func _fill_block(blk: Rect2i, dist: int) -> void:
	var weights: Dictionary = LOTS[dist]
	for y in range(blk.position.y, blk.end.y):
		var x := blk.position.x
		while x < blk.end.x:
			var placed := false
			for attempt in 3:
				var t := _pick(weights)
				var info: Array = TYPES[t]
				var r := Rect2i(x, y, info[1], info[2])
				if r.end.x <= blk.end.x and r.end.y <= blk.end.y and _free(r):
					_place(t, r)
					x += info[1] + (1 if dist in [1, 5] else 0)
					placed = true
					break
			if not placed:
				x += 1
	# Restflaechen begruenen bzw. als Parkplatz nutzen
	for y in range(blk.position.y, blk.end.y):
		for x in range(blk.position.x, blk.end.x):
			var p := Vector2i(x, y)
			var i := c.idx(p)
			if c.building_at[i] != -1:
				continue
			if dist in [1, 5] and rng.randf() < 0.22:
				_tree(p)
			elif dist in [2, 3, 4] and rng.randf() < 0.25:
				c.ground[i] = G.PARKING
			elif dist == 0 and rng.randf() < 0.06:
				_tree(p)


func _finish() -> void:
	for i in c.building_at.size():
		if c.building_at[i] == -2:
			c.building_at[i] = -1
	# Kreuzungen, Laternen, Strassenbaeume
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			if c.is_road(p):
				var m := c.road_mask(p)
				var cnt := 0
				for bit in [1, 2, 4, 8]:
					if m & bit:
						cnt += 1
				if cnt >= 3:
					c.intersections.append(p)
			elif c.g(p) == G.SIDEWALK and c.building_at[c.idx(p)] == -1 and c.blocked[c.idx(p)] == 0:
				if (x * 7 + y * 13) % 11 == 0 and c.road_mask(p) != 0:
					c.lamps.append(p)
			elif c.g(p) == G.GRASS and c.blocked[c.idx(p)] == 0 and rng.randf() < 0.012 and c.district_of(p) != 0:
				_tree(p)
	_roads_connected()
	# Zugaenge erst nach Baeumen/Laternen bestimmen, damit sie im Fussnetz liegen
	# Gebaeudezugaenge: naechste Strassenzelle (Fahrzeuge) und Gehwegzelle (Figuren) im zusammenhaengenden Fussnetz
	var main := _main_walk_area()
	for b in c.buildings:
		var r := Rect2i(b.x, b.y, b.w, b.h)
		b["road"] = _nearest(r, func(p): return c.is_road(p))
		b["walk"] = _nearest(r, func(p): return main.has(p) and c.g(p) != G.ROAD)
		if b.type == "plot":
			# Einfahrt: Grundstueckszelle, die der Strasse am naechsten liegt
			var best := Vector2i(b.x, b.y)
			for y in range(b.y, b.y + b.h):
				for x in range(b.x, b.x + b.w):
					if Vector2(Vector2i(x, y) - b.road).length() < Vector2(best - b.road).length():
						best = Vector2i(x, y)
			b["entrance"] = best


## Groesste zusammenhaengende begehbare Flaeche (4er-Nachbarschaft); abgeschlossene Taschen zwischen Gebaeuden zaehlen nicht.
func _main_walk_area() -> Dictionary:
	var label := PackedInt32Array()
	label.resize(n * n)
	label.fill(-1)
	var best_id := -1
	var best_size := 0
	var comp := 0
	for i in n * n:
		var start := Vector2i(i % n, i / n)
		if label[i] >= 0 or not c.walkable(start):
			continue
		var stack: Array[Vector2i] = [start]
		label[i] = comp
		var size := 0
		while not stack.is_empty():
			var q: Vector2i = stack.pop_back()
			size += 1
			for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var nb: Vector2i = q + d
				if c.inside(nb) and label[c.idx(nb)] < 0 and c.walkable(nb):
					label[c.idx(nb)] = comp
					stack.append(nb)
		if size > best_size:
			best_size = size
			best_id = comp
		comp += 1
	var out := {}
	for i in n * n:
		if label[i] == best_id:
			out[Vector2i(i % n, i / n)] = true
	return out


func _nearest(r: Rect2i, pred: Callable) -> Vector2i:
	var bottom := Vector2(r.position.x + r.size.x * 0.5, r.end.y)
	for rad in range(1, 14):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for y in range(r.position.y - rad, r.end.y + rad):
			for x in range(r.position.x - rad, r.end.x + rad):
				if x > r.position.x - rad and x < r.end.x + rad - 1 and y > r.position.y - rad and y < r.end.y + rad - 1:
					continue
				var p := Vector2i(x, y)
				if c.inside(p) and pred.call(p):
					var d := Vector2(p).distance_squared_to(bottom)
					if d < best_d:
						best_d = d
						best = p
		if best.x >= 0:
			return best
	return Vector2i(r.position.x, r.end.y)
