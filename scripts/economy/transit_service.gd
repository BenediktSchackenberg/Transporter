class_name TransitService
extends RefCounted
## OEPNV (Auftrag 20, Etappe 7, docs/PUBLIC_SERVICES.md). Ein Busbetriebshof (VB-01, Municipal) betreibt eine Linie in seiner Stadt:
##  - Linienplanung aus den Daten: Haltestellen an den Wohnschwerpunkten (Wohneinheiten je 8 x 8 Felder), an den Arbeitsschwerpunkten
##    (Geschaefte, Betriebe) und am Rathaus; Reihenfolge als Rundkurs ab dem Betriebshof (naechster Nachbar).
##  - Betrieb 6-22 Uhr: der Bus faehrt den Rundkurs sichtbar, haelt 2 Minuten je Haltestelle; nachts steht er im Betriebshof.
##    Takt = gemessene Umlaufzeit.
##  - Fahrgaeste: an jeder Haltestelle warten je Betriebsstunde Anwohner im Umkreis (Wohneinheiten im Radius 8) x Fahrtrate.
##    Einsteigen bis zur Platzzahl; jeder Fahrgast zahlt den Fahrpreis von seinem eigenen Guthaben (R0) an die Stadtkasse.
##  - Wirtschaftlichkeit: Erloese gegen Kosten (Sachkosten des Betriebshofs, Fahrzeugkosten, Loehne des Fahrpersonals);
##    Kostendeckungsgrad je Linie.
##  - Wirkung: Anbindung = Anteil der Wohneinheiten der Stadt im Einzugsbereich; bringt bis zu +3 Punkte Zustimmung.

const FARE := 2.0
const TRIP_RATE := 0.03            # Fahrtwuensche je Wohneinheit und Betriebsstunde
const RADIUS := 8
const CAPACITY := 40
const DWELL_MIN := 2.0
const SERVICE := [6.0, 22.0]
const MAX_STOPS := 6
const SPEED := 2.6
const APPROVAL_MAX := 3.0

var sim
var lines := {}          # "L<n>" -> {id, town, depot (Einrichtung), vehicle, stops: [[x,y]], names: [], next, phase, until, takt, lap_start, ...}
var movers := {}
var stats := {"fahrgaeste": 0, "erloese": 0.0, "nicht_bezahlt": 0}
var _next := 1
var _hour := -1


func setup(simulation) -> void:
	sim = simulation


func enabled() -> bool:
	return sim != null and sim.municipal != null and sim.municipal.enabled()


# ------------------------------------------------------------------ Linienplanung
func plan_line(depot_id: String) -> Dictionary:
	var M: Municipal = sim.municipal
	var f: Dictionary = M.facilities.get(depot_id, {})
	if f.is_empty() or f.code != "VB-01":
		return {}
	var k := int(f.town)
	var vid := ""
	for v in f.vehicles:
		if str(M.vehicles[v].type) == "Linienbus" and not lines.values().any(func(l): return l.vehicle == v):
			vid = v
			break
	if vid == "":
		return {}
	var home: Vector2i = sim.city.building(int(f.building)).road
	var stops := _stop_cells(k)
	if stops.size() < 2:
		return {}
	var order: Array = []
	var cur := home
	while not stops.is_empty():   # Rundkurs: naechster Nachbar
		stops.sort_custom(func(a, b): return (a.cell - cur).length_squared() < (b.cell - cur).length_squared())
		var s: Dictionary = stops.pop_front()
		order.append(s)
		cur = s.cell
	var l := {"id": "L%d" % _next, "town": k, "depot": depot_id, "vehicle": vid, "stops": order.map(func(s): return [s.cell.x, s.cell.y]),
		"names": order.map(func(s): return s.name), "waiting": order.map(func(_s): return 0), "next": 0, "phase": "depot", "until": 0.0,
		"takt": 0.0, "lap_start": -1.0, "load": 0, "riders": 0, "revenue": 0.0, "day": GameCalendar.day_of(sim.game_min)}
	_next += 1
	lines[l.id] = l
	sim.log_event("%s: Buslinie %s eingerichtet (%s)." % [sim.towns.name_of(k), l.id, " – ".join(l.names)], "info")
	return l


## Haltestellen: Wohnschwerpunkte (bis 3), Arbeitsschwerpunkte (bis 2), Rathaus; je Stelle die Strasse vor dem groessten Gebaeude.
func _stop_cells(k: int) -> Array:
	var homes := {}
	var units_by_b := {}
	for u in sim.housing.units.values():
		units_by_b[int(u.building)] = int(units_by_b.get(int(u.building), 0)) + 1
	var work := {}
	for b in sim.city.buildings:
		if sim.towns.of_building(int(b.id)) != k or not b.has("road"):
			continue
		var blk := Vector2i(int(b.x) / 8, int(b.y) / 8)
		var n := int(units_by_b.get(int(b.id), 0))
		if n > 0:
			if not homes.has(blk):
				homes[blk] = {"sum": 0, "n": 0, "b": b}
			homes[blk].sum = int(homes[blk].sum) + n
			if n > int(homes[blk].n):
				homes[blk].n = n
				homes[blk].b = b
		elif b.role == "customer" and str(b.type) in ["shop", "factory", "warehouse", "office", "restaurant", "workshop", "farm"]:
			if not work.has(blk):
				work[blk] = {"sum": 0, "b": b}
			work[blk].sum = int(work[blk].sum) + 1
	var out: Array = []
	var used := {}
	var take := func(src: Dictionary, n: int, label: String) -> void:
		var arr: Array = src.values()
		arr.sort_custom(func(a, b): return int(a.sum) > int(b.sum))
		for e in arr.slice(0, n):
			var c: Vector2i = e.b.road
			if used.keys().any(func(q): return (q - c).length() < 6.0):
				continue
			used[c] = true
			out.append({"cell": c, "name": "%s %s" % [label, sim.municipal.lage(k, c)]})
	take.call(homes, 3, "Wohnen")
	take.call(work, 2, "Gewerbe")
	var th := int(sim.towns.get_t(k).get("town_hall", -1))
	if th >= 0:
		var c: Vector2i = sim.city.building(th).road
		if not used.keys().any(func(q): return (q - c).length() < 6.0):
			out.append({"cell": c, "name": "Rathaus"})
	return out.slice(0, MAX_STOPS)


# ------------------------------------------------------------------ Betrieb
func mover_of(vid: String) -> Mover:
	if not movers.has(vid):
		var M: Municipal = sim.municipal
		var mv := Mover.new()
		mv.speed = SPEED
		mv.pos = sim.city.tile_center(sim.city.building(M.building_of(str(M.vehicles[vid].facility))).road)
		movers[vid] = mv
	return movers[vid]


func in_service(now: float) -> bool:
	var h := GameCalendar.hour_of(now)
	return h >= float(SERVICE[0]) and h < float(SERVICE[1])


func update(dt: float) -> void:
	if lines.is_empty():
		return
	var now: float = sim.game_min
	var hour := int(now / 60.0)
	if hour != _hour:
		_hour = hour
		if in_service(now):
			_demand()
	var M: Municipal = sim.municipal
	for l in lines.values():
		var v: Dictionary = M.vehicles.get(l.vehicle, {})
		var mv := mover_of(l.vehicle)
		if not mv.arrived():
			mv.advance(dt, 1.0)
			continue
		match str(l.phase):
			"depot":
				if in_service(now) and v.status == "bereit" and int(v.driver) >= 0:
					v.status = "im_einsatz"
					l.phase = "fahrt"
					l.next = 0
					l.lap_start = now
					sim.route(mv, _cell(l, 0))
			"fahrt":
				_board(l, int(l.next))
				l.phase = "halt"
				l.until = now + DWELL_MIN
			"halt":
				if now < float(l.until):
					continue
				l.next = (int(l.next) + 1) % l.stops.size()
				if int(l.next) == 0:
					if float(l.lap_start) >= 0.0:
						l.takt = snappedf(now - float(l.lap_start), 1.0)
					l.lap_start = now
					if not in_service(now):
						l.phase = "einruecken"
						sim.route(mv, sim.city.building(M.building_of(str(l.depot))).road)
						continue
				l.phase = "fahrt"
				sim.route(mv, _cell(l, int(l.next)))
			"einruecken":
				v.status = "bereit"
				l.phase = "depot"
				l.load = 0


func _cell(l: Dictionary, i: int) -> Vector2i:
	return Vector2i(int(l.stops[i][0]), int(l.stops[i][1]))


## Je Betriebsstunde: neue Fahrtwuensche an jeder Haltestelle aus den Wohneinheiten im Umkreis.
func _demand() -> void:
	for l in lines.values():
		for i in l.stops.size():
			var n := float(_units_near(_cell(l, i))) * TRIP_RATE
			var whole := int(n)
			if Citizens.roll(i, _hour, 9301 + int(l.id.substr(1))) < n - float(whole):
				whole += 1
			l.waiting[i] = mini(int(l.waiting[i]) + whole, 3 * CAPACITY)


func _units_near(c: Vector2i) -> int:
	var n := 0
	for u in sim.housing.units.values():
		if u.tenant == "":
			continue
		var b: Dictionary = sim.city.building(int(u.building))
		if absi(int(b.x) - c.x) + absi(int(b.y) - c.y) <= RADIUS * 2:
			n += 1
	return n


## Einsteigen: wartende Fahrgaeste bis zur Platzzahl (nach Aussteigen an dieser Haltestelle); Fahrpreis vom eigenen Guthaben.
func _board(l: Dictionary, i: int) -> void:
	l.load = int(float(l.load) * 0.5)   # die Haelfte steigt an jeder Haltestelle aus
	var want := mini(int(l.waiting[i]), CAPACITY - int(l.load))
	if want <= 0:
		return
	var payers: Array = []
	var c := _cell(l, i)
	for p in sim.citizens.people:
		if payers.size() >= want:
			break
		if float(p.get("balance", 0.0)) < FARE or sim.citizens.home_town(p) != int(l.town):
			continue
		var u: Dictionary = sim.housing.units.get(str(p.get("home", "")), {})
		if u.is_empty():
			continue
		var b: Dictionary = sim.city.building(int(u.building))
		if absi(int(b.x) - c.x) + absi(int(b.y) - c.y) <= RADIUS * 2:
			payers.append([p, FARE])
	var paid: float = sim.population.pay_out(Towns.account_of(int(l.town)), payers)
	var n := payers.size()
	stats.nicht_bezahlt = int(stats.nicht_bezahlt) + (want - n)
	l.waiting[i] = int(l.waiting[i]) - want
	l.load = int(l.load) + n
	l.riders = int(l.riders) + n
	l.revenue = float(l.revenue) + paid
	stats.fahrgaeste = int(stats.fahrgaeste) + n
	stats.erloese = float(stats.erloese) + paid


# ------------------------------------------------------------------ Kennzahlen
## Kosten je Tag einer Linie: Sachkosten des Betriebshofs, Bus, Loehne des Fahrpersonals.
func cost_per_day(l: Dictionary) -> float:
	var M: Municipal = sim.municipal
	var f: Dictionary = M.facilities.get(l.depot, {})
	if f.is_empty():
		return 0.0
	var wages := 0.0
	for p in M.staff_of(f.id):
		wages += float(p.wage) * Citizens.HOURS_PER_MONTH / 30.0
	return float(f.upkeep) + float(M.vehicles[l.vehicle].cost) + wages


func coverage(k: int) -> float:
	var total := 0
	var covered := 0
	var stops: Array = []
	for l in lines.values():
		if int(l.town) == k:
			for i in l.stops.size():
				stops.append(_cell(l, i))
	for u in sim.housing.units.values():
		var b: Dictionary = sim.city.building(int(u.building))
		if sim.towns.of_building(int(u.building)) != k:
			continue
		total += 1
		if stops.any(func(c): return absi(int(b.x) - c.x) + absi(int(b.y) - c.y) <= RADIUS * 2):
			covered += 1
	return float(covered) / maxf(1.0, float(total))


func approval_bonus(k: int) -> float:
	return APPROVAL_MAX * coverage(k) if lines.values().any(func(l): return int(l.town) == k) else 0.0


func summary(k: int = -1) -> Array:
	var out: Array = []
	for l in lines.values():
		if k >= 0 and int(l.town) != k:
			continue
		var days := maxf(1.0, float(GameCalendar.day_of(sim.game_min) - int(l.day)) + 1.0)
		var cost := cost_per_day(l) * days
		out.append({"linie": l.id, "stadt": sim.towns.name_of(int(l.town)), "haltestellen": l.names, "takt_min": l.takt, "fahrgaeste": l.riders,
			"erloese": snappedf(float(l.revenue), 1.0), "kostendeckung": snappedf(float(l.revenue) / maxf(1.0, cost), 0.01),
			"anbindung": snappedf(coverage(int(l.town)), 0.01), "status": l.phase})
	return out


func on_road() -> Array:
	var out: Array = []
	for l in lines.values():
		if l.phase != "depot" and movers.has(l.vehicle):
			out.append({"vid": l.vehicle, "mover": movers[l.vehicle], "siren": false})
	return out


func to_dict() -> Dictionary:
	return {"lines": lines.duplicate(true), "stats": stats.duplicate(), "next": _next}


## Laden: Busse stehen im Betriebshof und starten zur naechsten Betriebszeit neu.
func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	lines = d.get("lines", {})
	stats = d.get("stats", stats)
	_next = int(d.get("next", 1))
	for l in lines.values():
		l.town = int(l.town)
		l.phase = "depot"
		l.load = 0
		if sim.municipal.vehicles.has(l.vehicle):
			sim.municipal.vehicles[l.vehicle].status = "bereit"
