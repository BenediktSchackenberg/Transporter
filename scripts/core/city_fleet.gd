class_name CityFleet
extends RefCounted
## Sichtbare Stadtfahrzeuge ohne eigene Wirtschaftswirkung (Darstellung):
## - Bautrupps der Strassenmeisterei fahren vom Rathaus zur Baustelle, arbeiten dort bis zum Ende und fahren zurueck
##   (Instandsetzungen aus RoadCare und die zufaelligen Strassenbaustellen der Simulation).
## - Umzugswagen bringen neu zugezogene Haushalte vom Stadtrand zu ihrer Wohnung, laden ab und fahren wieder hinaus.
## Die Wirkung (Sperrung, Zustand, Zuzug) bleibt in den Fachsystemen; hier wird nur gefahren. Nicht gespeichert.

const MAX_CREWS := 6
const MAX_MOVING := 6
const MAX_GARBAGE := 4
const EMPTY_MIN := 12.0           # Spielminuten je Halt (Tonnen leeren)
const DUMP_MIN := 30.0            # Abladen auf der Deponie
const UNLOAD_DAYS := 0.1          # Umzugswagen steht so lange vor dem Haus
const SPEED := 3.0

var sim
var vehicles: Array = []          # {id, kind (bautrupp|umzug), mover, phase (anfahrt|arbeit|abladen|rueckfahrt), site, until, back, label}
var stats := {"bautrupps": 0, "umzuege": 0, "muelltouren": 0, "halte": 0}
var _next := 1
var _edges: Array = []


func setup(simulation) -> void:
	sim = simulation
	var C = sim.city
	var best := 99
	for y in C.size:
		for x in C.size:
			var p := Vector2i(x, y)
			if not C.is_road(p):
				continue
			var d: int = mini(mini(x, y), mini(C.size - 1 - x, C.size - 1 - y))
			if d < best:
				best = d
				_edges.clear()
			if d == best:
				_edges.append(p)


## Strassenzelle am Rathaus (Sitz der Strassenmeisterei).
func depot_road() -> Vector2i:
	for b in sim.city.buildings:
		if b.role == "town_hall":
			return b.road
	return sim.city.intersections[0]


func _free_neighbor(site: Vector2i) -> Vector2i:
	if not sim.nav.is_blocked_road(site):
		return site
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = site + d
		if sim.city.is_road(q) and not sim.nav.is_blocked_road(q):
			return q
	return site


func _spawn(kind: String, start: Vector2i, site: Vector2i, until: float, back: Vector2i, label: String) -> Dictionary:
	var m := Mover.new()
	m.speed = SPEED
	m.pos = sim.city.tile_center(start)
	var v := {"id": _next, "kind": kind, "mover": m, "phase": "anfahrt", "site": site, "until": until, "back": back, "label": label}
	_next += 1
	var target := _free_neighbor(site)
	if not sim.route(m, target):
		m.pos = sim.city.tile_center(target)   # kein Weg: Fahrzeug steht gleich am Ziel
	vehicles.append(v)
	return v


## Neues Ziel fuer ein Fahrzeug (Bautrupps).
func reroute(v: Dictionary, to: Vector2i) -> void:
	var target := _free_neighbor(to)
	if not sim.route(v.mover, target):
		v.mover.pos = sim.city.tile_center(target)


## Bautrupp zu einer Strassenbaustelle schicken (einer je Stelle).
func send_crew(site: Vector2i, until: float, label: String) -> void:
	if vehicles.any(func(v): return v.kind == "bautrupp" and v.site == site and v.phase != "rueckfahrt"):
		return
	if vehicles.filter(func(v): return v.kind == "bautrupp").size() >= MAX_CREWS:
		return
	var home := depot_road()
	_spawn("bautrupp", home, site, until, home, label)
	stats.bautrupps += 1


## Umzugswagen fuer einen zugezogenen Haushalt: vom Stadtrand zur Wohnung (Gebaeude-ID), dann wieder hinaus.
func send_moving(building_id: int, label: String) -> void:
	if _edges.is_empty() or vehicles.filter(func(v): return v.kind == "umzug").size() >= MAX_MOVING:
		return
	var b: Dictionary = sim.city.building(building_id)
	if b.is_empty():
		return
	var edge: Vector2i = _edges[(_next * 7) % _edges.size()]
	_spawn("umzug", edge, b.road, 0.0, edge, label)
	stats.umzuege += 1


func update(dt: float) -> void:
	var now: float = sim.game_min
	for v in vehicles.duplicate():
		var m: Mover = v.mover
		if not m.arrived():
			if sim.nav.is_blocked_road(m.next_tile()) and m.next_tile() != m.goal:
				sim.route(m, m.goal)
			else:
				m.advance(dt, 1.0)
			continue
		if v.kind == "kolonne":
			continue   # Bautrupps (BuildCrews) steuern Ziel und Zustand selbst
		if v.kind == "muell":
			_garbage(v, now)
			continue
		match str(v.phase):
			"anfahrt":
				if v.kind == "umzug":
					v.phase = "abladen"
					v.until = now + GameCalendar.days_to_min(UNLOAD_DAYS)
				else:
					v.phase = "arbeit"
			"arbeit", "abladen":
				if now >= float(v.until):
					v.phase = "rueckfahrt"
					if not sim.route(m, v.back):
						vehicles.erase(v)
			"rueckfahrt":
				vehicles.erase(v)


## Muellwagen: vom Betriebshof (Rathaus) ueber die Halte der Tour zur Deponie und zurueck. Zwei Muellwerker leeren an jedem Halt.
func send_garbage(stops: Array, landfill: Vector2i, tons: float, label: String) -> void:
	if stops.is_empty() or vehicles.filter(func(v): return v.kind == "muell").size() >= MAX_GARBAGE:
		return
	var home := depot_road()
	var v := _spawn("muell", home, stops[0].road, 0.0, home, label)
	v["stops"] = stops
	v["stop"] = 0
	v["landfill"] = landfill
	v["tons"] = tons
	v["load"] = 0.0
	v["phase"] = "tour"
	stats.muelltouren += 1


func _garbage(v: Dictionary, now: float) -> void:
	var m: Mover = v.mover
	match str(v.phase):
		"tour":
			v.phase = "leeren"
			v.until = now + EMPTY_MIN
		"leeren":
			if now < float(v.until):
				return
			v.load = float(v.load) + float(v.tons) / float(v.stops.size())
			stats.halte += 1
			v.stop = int(v.stop) + 1
			if int(v.stop) < v.stops.size():
				v.phase = "tour"
				if not sim.route(m, _free_neighbor(v.stops[int(v.stop)].road)):
					m.pos = sim.city.tile_center(v.stops[int(v.stop)].road)
			else:
				v.phase = "zur_deponie"
				if not sim.route(m, _free_neighbor(v.landfill)):
					m.pos = sim.city.tile_center(v.landfill)
		"zur_deponie":
			v.phase = "abladen"
			v.until = now + DUMP_MIN
		"abladen":
			if now >= float(v.until):
				v.load = 0.0
				v.phase = "rueckfahrt"
				if not sim.route(m, v.back):
					vehicles.erase(v)
		"rueckfahrt":
			vehicles.erase(v)


## Arbeitende Bautrupps (fuer die Baustellenanzeige).
func crews_at_work() -> Array:
	return vehicles.filter(func(v): return v.kind == "bautrupp" and v.phase == "arbeit")
