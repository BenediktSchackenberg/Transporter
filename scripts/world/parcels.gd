class_name Parcels
extends RefCounted
## Grundstuecke als eigenstaendige Wirtschaftsobjekte (Auftrag 7, Etappe 1).
##
## Die Grundstuecke werden deterministisch aus der Karte abgeleitet: jedes Gebaeude steht auf einem Grundstueck (Identitaet bleibt),
## alle freien Flaechen werden in Grundstuecke und Korridore zerlegt. Gespeichert werden nur die Aenderungen gegenueber dieser
## Ausgangslage (`touched`); aeltere Spielstaende bekommen die Grundstuecke daher beim Laden aus ihrer Karte.
## Eigentum (`owner`), Pacht und sonstige Rechte (`rights`) sind getrennt; die Stadt kann nur ueber Eigenes verfuegen.

const G := CityData.G
const STATES := ["frei", "reserviert", "privat_gehalten", "zur_entwicklung", "genehmigt", "in_erschliessung", "im_bau", "bebaut"]
const CITY := "stadt"
const MIN_AREA := 12              # kleinere Restflaechen werden kein Grundstueck
const MAX_SIDE := 14              # groessere Flaechen werden zerlegt
const RESERVATION_DAYS := 14
## Planungsregeln je Zone (Etappe 2 baut darauf auf): zulaessige Nutzungen, Geschosse, Anteil bebaubarer Grundflaeche, Preis je Feld
const ZONES := {
	"wohnen": {"label": "Wohngebiet", "types": ["house", "semi", "villa", "apartment"], "floors": 3, "cover": 0.45, "price": 40.0, "buildable": true},
	"mischgebiet": {"label": "Mischgebiet", "types": ["shop", "restaurant", "office", "apartment", "pharmacy", "highrise", "house"], "floors": 6, "cover": 0.6, "price": 70.0, "buildable": true},
	"gewerbe": {"label": "Gewerbegebiet", "types": ["warehouse", "shop", "office", "gas_station", "workshop", "depot"], "floors": 3, "cover": 0.6, "price": 35.0, "buildable": true},
	"industrie": {"label": "Industriegebiet", "types": ["factory", "warehouse", "containers", "port_office"], "floors": 2, "cover": 0.7, "price": 25.0, "buildable": true},
	"oeffentlich": {"label": "Fläche für öffentliche Einrichtungen", "types": ["school", "kindergarten", "clinic", "office"], "floors": 4, "cover": 0.5, "price": 0.0, "buildable": true},
	"gruen": {"label": "Grünfläche", "types": [], "floors": 0, "cover": 0.0, "price": 0.0, "buildable": false},
	"korridor": {"label": "Korridor für Straße und Leitungen", "types": [], "floors": 0, "cover": 0.0, "price": 0.0, "buildable": false},
}
## Stadtbezirk (CityData.district) -> Zone
const ZONE_OF_DISTRICT := ["mischgebiet", "wohnen", "industrie", "industrie", "gewerbe", "wohnen"]
const DYNAMIC := ["owner", "state", "rights", "reservation", "application", "project", "use", "building", "erschliessung"]

var city: CityData
var sim
var items := {}                   # "G<n>" -> Grundstueck
var by_building := {}             # Gebaeude-ID -> Grundstueck-ID
var touched := {}                 # geaenderte Grundstuecke (werden gespeichert)
var _next := 1
var _cell := PackedInt32Array()   # Grundstueck-Nummer je Zelle (0 = keines)


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)


# ------------------------------------------------------------------ Aufbau aus der Karte
func build(c: CityData) -> void:
	city = c
	items.clear()
	by_building.clear()
	touched.clear()
	_next = 1
	_cell = PackedInt32Array()
	_cell.resize(c.size * c.size)
	for b in c.buildings:
		_add_built(b)
	_split_free_areas()
	for p in items.values():
		if not p.has("erschliessung"):
			p.erschliessung = utilities_of(p)


func _new(r: Rect2i, zone: String, state: String, owner: String, use: String) -> Dictionary:
	var id := "G%d" % _next
	_next += 1
	var z: Dictionary = ZONES[zone]
	var area := r.size.x * r.size.y
	var p := {"id": id, "rect": [r.position.x, r.position.y, r.size.x, r.size.y], "area": area, "zone": zone,
		"district": city.district_of(r.position + r.size / 2), "owner": owner, "state": state, "use": use, "rights": {},
		"reservation": {}, "application": "", "project": "", "building": -1,
		"price": snappedf(float(z.price) * area * _centrality(r), 1.0), "lease_month": 0.0}
	p.lease_month = snappedf(float(p.price) * 0.01, 1.0)
	items[id] = p
	var n := int(id.substr(1))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_cell[city.idx(Vector2i(x, y))] = n
	return p


## Zentrumsnahe Grundstuecke sind teurer (1.0 am Rand bis 1.5 im Zentrum).
func _centrality(r: Rect2i) -> float:
	var mid := Vector2(r.position + r.size / 2)
	var d := mid.distance_to(Vector2(city.size * 0.45, city.size * 0.5)) / city.size
	return 1.0 + 0.5 * clampf(1.0 - d * 2.0, 0.0, 1.0)


func _add_built(b: Dictionary) -> Dictionary:
	var r := Rect2i(b.x, b.y, b.w, b.h)
	var zone: String = ZONE_OF_DISTRICT[clampi(int(b.district), 0, 5)]
	if b.type in ["school", "kindergarten", "clinic"]:
		zone = "oeffentlich"
	var owner := CITY if b.type in ["school", "kindergarten", "clinic", "fountain", "job_board", "staffing"] else "privat"
	var p := _new(r, zone, "bebaut", owner, str(b.type))
	p.building = int(b.id)
	p.erschliessung = {"strasse": true, "strom": true, "wasser": true, "abwasser": true}
	by_building[int(b.id)] = p.id
	return p


static func _hash(x: int, y: int, salt: int) -> int:
	return absi(hash(Vector3i(x, y, salt)))


func _is_free(p: Vector2i) -> bool:
	var i := city.idx(p)
	if city.building_at[i] != -1 or _cell[i] != 0:
		return false
	return city.ground[i] in [G.GRASS, G.CONCRETE, G.GRAVEL, G.PLAZA, G.FIELD, G.CROP, G.PARKING, G.PARK]


func _split_free_areas() -> void:
	var n := city.size
	var done := PackedByteArray()
	done.resize(n * n)
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			if done[city.idx(p)] != 0 or not _is_free(p):
				continue
			var park := city.ground[city.idx(p)] == G.PARK
			# Rechteck wachsen lassen: erst nach rechts, dann nach unten (gleiche Bodenart)
			var w := 1
			while x + w < n and _is_free(Vector2i(x + w, y)) and done[city.idx(Vector2i(x + w, y))] == 0 and (city.ground[city.idx(Vector2i(x + w, y))] == G.PARK) == park:
				w += 1
			var h := 1
			while y + h < n:
				var ok := true
				for k in w:
					var q := Vector2i(x + k, y + h)
					if not _is_free(q) or done[city.idx(q)] != 0 or (city.ground[city.idx(q)] == G.PARK) != park:
						ok = false
						break
				if not ok:
					break
				h += 1
			var r := Rect2i(x, y, w, h)
			for yy in range(r.position.y, r.end.y):
				for xx in range(r.position.x, r.end.x):
					done[city.idx(Vector2i(xx, yy))] = 1
			if r.size.x * r.size.y >= MIN_AREA:
				_subdivide(r, park)


## Grosse Flaechen in Grundstuecke unterschiedlicher Groesse zerlegen; bei sehr grossen Flaechen bleibt ein Korridor frei.
func _subdivide(r: Rect2i, park: bool) -> void:
	var longer_x := r.size.x >= r.size.y
	var side := r.size.x if longer_x else r.size.y
	if r.size.x <= MAX_SIDE and r.size.y <= MAX_SIDE:
		_make_free(r, park)
		return
	var h := _hash(r.position.x, r.position.y, 7)
	var cut := int(side * (0.4 + 0.2 * float(h % 100) / 100.0))
	cut = clampi(cut, 4, side - 4)
	var corridor := not park and side >= 20 and h % 3 == 0
	if longer_x:
		_subdivide(Rect2i(r.position, Vector2i(cut, r.size.y)), park)
		var rest := Rect2i(r.position.x + cut, r.position.y, r.size.x - cut, r.size.y)
		if corridor:
			_make_corridor(Rect2i(rest.position, Vector2i(1, rest.size.y)))
			rest = Rect2i(rest.position.x + 1, rest.position.y, rest.size.x - 1, rest.size.y)
		_subdivide(rest, park)
	else:
		_subdivide(Rect2i(r.position, Vector2i(r.size.x, cut)), park)
		var rest2 := Rect2i(r.position.x, r.position.y + cut, r.size.x, r.size.y - cut)
		if corridor:
			_make_corridor(Rect2i(rest2.position, Vector2i(rest2.size.x, 1)))
			rest2 = Rect2i(rest2.position.x, rest2.position.y + 1, rest2.size.x, rest2.size.y - 1)
		_subdivide(rest2, park)


func _make_corridor(r: Rect2i) -> void:
	_new(r, "korridor", "frei", CITY, "korridor")


func _make_free(r: Rect2i, park: bool) -> void:
	if r.size.x * r.size.y < MIN_AREA and not park:
		return
	if park:
		_new(r, "gruen", "frei", CITY, "park")
		return
	var d := city.district_of(r.position + r.size / 2)
	var zone: String = ZONE_OF_DISTRICT[clampi(d, 0, 5)]
	var h := _hash(r.position.x, r.position.y, 11) % 100
	var state := "frei"
	var owner := CITY
	if h < 4 and d in [0, 1, 4]:
		zone = "oeffentlich"
		owner = CITY
	elif h < 18 and d in [0, 1, 4, 5]:
		state = "privat_gehalten"
		owner = "privat:%d" % (_hash(r.position.x, r.position.y, 13) % 900 + 100)
	elif r.size.x * r.size.y >= 90 and d == 5:
		state = "zur_entwicklung"
	_new(r, zone, state, owner, "unbebaut")


# ------------------------------------------------------------------ Erschliessung
## Vereinfachtes Versorgungsmodell: Zugang zur Strasse, Strom/Wasser/Abwasser liegen nur nahe Bebauung an.
func utilities_of(p: Dictionary) -> Dictionary:
	var r := Rect2i(p.rect[0], p.rect[1], p.rect[2], p.rect[3])
	var road := false
	var built := 0
	for y in range(r.position.y - 3, r.end.y + 3):
		for x in range(r.position.x - 3, r.end.x + 3):
			var q := Vector2i(x, y)
			if not city.inside(q):
				continue
			if city.is_road(q):
				var near_x := x >= r.position.x - 2 and x < r.end.x + 2
				var near_y := y >= r.position.y - 2 and y < r.end.y + 2
				if near_x and near_y:
					road = true
			elif city.building_at[city.idx(q)] >= 0:
				built += 1
	var net := built >= 4
	return {"strasse": road, "strom": net and road, "wasser": net and road, "abwasser": net and road}


func utility_level(p: Dictionary) -> String:
	var u: Dictionary = p.get("erschliessung", {})
	var n := 0
	for k in u:
		if u[k]:
			n += 1
	return "voll" if n == 4 else ("keine" if n == 0 else "teilweise")


# ------------------------------------------------------------------ Abfragen
func parcel(id: String) -> Dictionary:
	return items.get(id, {})


func of_building(building_id: int) -> Dictionary:
	return items.get(by_building.get(building_id, ""), {})


func at_cell(c: Vector2i) -> Dictionary:
	if not city.inside(c):
		return {}
	var n := _cell[city.idx(c)]
	return items.get("G%d" % n, {}) if n > 0 else {}


func is_buildable(p: Dictionary) -> bool:
	return bool(ZONES[p.zone].buildable)


## Freie Grundstuecke nach Kriterien: zone, min_area, max_area, max_price, utilities ("voll"|"teilweise"|"keine" = mindestens), limit.
func search(criteria: Dictionary = {}) -> Array:
	var out: Array = []
	var order := ["keine", "teilweise", "voll"]
	for p in items.values():
		if p.state != "frei" or not is_buildable(p) or p.owner != CITY:
			continue
		if criteria.has("zone") and p.zone != criteria.zone:
			continue
		if criteria.has("min_area") and p.area < int(criteria.min_area):
			continue
		if criteria.has("max_area") and p.area > int(criteria.max_area):
			continue
		if criteria.has("max_price") and float(p.price) > float(criteria.max_price):
			continue
		if criteria.has("utilities") and order.find(utility_level(p)) < order.find(str(criteria.utilities)):
			continue
		out.append(p)
	out.sort_custom(func(a, b): return a.price < b.price)
	return out.slice(0, int(criteria.get("limit", 20)))


## Anteil unbebauter, grundsaetzlich bebaubarer Flaeche (ohne Korridore, Gruen, Strassen).
func reserve_share() -> float:
	var free := 0
	var built := 0
	for p in items.values():
		if not is_buildable(p):
			continue
		if p.state == "bebaut":
			built += int(p.area)
		else:
			free += int(p.area)
	return float(free) / maxf(1.0, float(free + built))


func summary() -> Dictionary:
	var by_state := {}
	var by_zone := {}
	for p in items.values():
		by_state[p.state] = int(by_state.get(p.state, 0)) + 1
		by_zone[p.zone] = int(by_zone.get(p.zone, 0)) + 1
	return {"anzahl": items.size(), "nach_status": by_state, "nach_zone": by_zone, "reserveanteil": reserve_share()}


# ------------------------------------------------------------------ Vergabe
func _touch(p: Dictionary) -> void:
	touched[p.id] = true


## Aenderung an einem Grundstueck zum Speichern vormerken (fuer Aenderungen von aussen).
func touch(pid: String) -> void:
	if items.has(pid):
		touched[pid] = true


## Reservierung durch einen Bewerber (z. B. "H3" Haushalt, "C1" Unternehmen). Ein Grundstueck hat hoechstens einen Reservierer.
func reserve(pid: String, holder: String, days: int = RESERVATION_DAYS) -> Dictionary:
	var p := parcel(pid)
	if p.is_empty():
		return {"ok": false, "msg": "Grundstück %s gibt es nicht." % pid}
	if p.state != "frei" or not is_buildable(p) or p.owner != CITY:
		return {"ok": false, "msg": "Grundstück %s ist nicht verfügbar (%s)." % [pid, p.state]}
	p.state = "reserviert"
	p.reservation = {"holder": holder, "until_day": _day() + days}
	_touch(p)
	return {"ok": true, "msg": "Grundstück %s bis Tag %d für %s reserviert." % [pid, int(p.reservation.until_day), holder]}


func release(pid: String, holder: String) -> Dictionary:
	var p := parcel(pid)
	if p.is_empty() or p.state != "reserviert" or p.reservation.get("holder", "") != holder:
		return {"ok": false, "msg": "Keine Reservierung von %s auf %s." % [holder, pid]}
	p.state = "frei"
	p.reservation = {}
	_touch(p)
	return {"ok": true, "msg": "Reservierung aufgehoben."}


## Zustand und Antrag eines Grundstuecks setzen (Bauantragsprozess, Erschliessung, Bau).
func mark(pid: String, state: String, application: String) -> void:
	var p := parcel(pid)
	if p.is_empty() or state not in STATES:
		return
	p.state = state
	p.application = application
	_touch(p)


## Kauf durch einen Haushalt. Nur reservierte Flaechen des Reservierers; der Kaufpreis geht an die Stadt (P0).
func buy_for_household(pid: String, home_id: String) -> Dictionary:
	var p := parcel(pid)
	if p.is_empty() or p.state != "reserviert" or p.reservation.get("holder", "") != home_id:
		return {"ok": false, "msg": "Grundstück %s ist nicht für %s reserviert." % [pid, home_id]}
	var h: Dictionary = sim.households.homes.get(home_id, {})
	if h.is_empty():
		return {"ok": false, "msg": "Haushalt %s gibt es nicht." % home_id}
	if float(h.balance) < float(p.price):
		return {"ok": false, "msg": "Haushalt %s hat nur %s, das Grundstück kostet %s." % [home_id, Catalog.money(float(h.balance)), Catalog.money(float(p.price))]}
	h.balance = float(h.balance) - float(p.price)
	sim.economy.transfer("H0", "P0", float(p.price))
	p.owner = home_id
	p.state = "privat_gehalten"
	p.reservation = {}
	_touch(p)
	return {"ok": true, "msg": "Haushalt %s kauft %s für %s." % [home_id, pid, Catalog.money(float(p.price))]}


## Die Stadt darf nur ueber Flaechen verfuegen, die ihr gehoeren; private Rechte bleiben unangetastet.
func city_can_assign(pid: String) -> bool:
	var p := parcel(pid)
	return not p.is_empty() and p.owner == CITY and p.state in ["frei", "zur_entwicklung"] and p.rights.is_empty()


func on_day(day: int) -> void:
	for p in items.values():
		if p.state == "reserviert" and int(p.reservation.get("until_day", 0)) <= day:
			p.state = "frei"
			p.reservation = {}
			_touch(p)


func _day() -> int:
	return GameCalendar.day_of(sim.game_min)


## Zur Laufzeit entstandene Gebaeude (Neueroeffnungen, Gewerbegebiet, Laden): dem Grundstueck an ihrer Position zuordnen.
func sync_buildings() -> void:
	for b in city.buildings:
		if by_building.has(int(b.id)):
			continue
		var p := at_cell(Vector2i(b.x, b.y))
		if not p.is_empty() and p.state != "bebaut" and is_buildable(p):
			p.state = "bebaut"
			p.use = str(b.type)
			p.building = int(b.id)
			p.reservation = {}
			by_building[int(b.id)] = p.id
			_touch(p)
		else:
			var q := _add_built(b)
			_touch(q)


# ------------------------------------------------------------------ Speichern
func to_dict() -> Dictionary:
	var out := {}
	for id in touched:
		var p: Dictionary = items[id]
		var d := {}
		for k in DYNAMIC:
			d[k] = p[k]
		out[id] = d
	return {"touched": out}


func from_dict(d: Dictionary) -> void:
	var t: Dictionary = d.get("touched", {})
	for id in t:
		if not items.has(id):
			continue
		var p: Dictionary = items[id]
		for k in t[id]:
			p[k] = t[id][k]
		p.building = int(p.building)
		if p.reservation.has("until_day"):
			p.reservation.until_day = int(p.reservation.until_day)
		touched[id] = true
