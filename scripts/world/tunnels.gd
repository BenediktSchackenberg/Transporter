class_name Tunnels
extends RefCounted
## Strassentunnel durch ein zusammenhaengendes Bergmassiv. Die Bergzellen bleiben bis zur Abnahme
## unpassierbar; das Hoehenfeld bleibt auch danach fuer die sichtbare Felsdecke erhalten.

const MAX_LENGTH := 12
const MAX_APPROACH := 16
const BASE_COST := 40000.0
const CELL_COST := 9000.0
const REQUEST_DAYS := 3
const COMPANY_SHARE := 0.25
const MATERIAL := {"betonfertigteil": 8, "stahl": 4, "schotter": 4}
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

var sim
var items := {}  # TU<n> -> {from, to, cells, company, town, cost, status, project, day, reason}
var _next := 1
var _cells := {} # nur freigegebene Tunnelzellen
var _proposals_day := -1
var _proposals_roads := -1
var _proposals := {}


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)


func _point(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func plan(start: Vector2i, finish: Vector2i) -> Dictionary:
	var city: CityData = sim.city
	if not city.inside(start) or not city.inside(finish) or not city.is_road(start):
		return {"ok": false, "msg": "Das Eingangsportal braucht eine bestehende Strasse."}
	if city.height.is_empty() or city.height[city.idx(start)] > 0 or city.height[city.idx(finish)] > 0:
		return {"ok": false, "msg": "Die Portale muessen ausserhalb des Berges liegen."}
	if not city.is_road(finish) and not _clear_approach(finish):
		return {"ok": false, "msg": "Das Ausgangsportal ist bebaut oder gesperrt."}
	var delta := finish - start
	if delta.x != 0 and delta.y != 0 or delta == Vector2i.ZERO:
		return {"ok": false, "msg": "Ein Tunnel braucht eine gerade Achse zwischen zwei Portalen."}
	var length := absi(delta.x) + absi(delta.y) - 1
	if length < 2 or length > MAX_LENGTH:
		return {"ok": false, "msg": "Tunnelstrecke muss 2 bis %d Bergfelder lang sein." % MAX_LENGTH}
	var direction := Vector2i(signi(delta.x), signi(delta.y))
	var cells: Array = []
	for k in range(1, length + 1):
		var q := start + direction * k
		var i := city.idx(q)
		if city.height[i] == 0 or city.ground[i] in [CityData.G.ROAD, CityData.G.WATER, CityData.G.RAIL, CityData.G.RUNWAY, CityData.G.APRON] or city.building_at[i] >= 0:
			return {"ok": false, "msg": "Die Tunnelachse fuehrt nicht durch durchgehenden, unbebauten Fels."}
		if sim.eko != null and sim.eko.protected(q):
			return {"ok": false, "msg": "Auf der Tunnelachse liegt ein geschuetztes Bauwerk."}
		if sim.access != null and sim.access.reserved(q):
			return {"ok": false, "msg": "Die Tunnelachse ist bereits fuer ein anderes Projekt reserviert."}
		cells.append([q.x, q.y])
	var approach: Array = _feeder(finish, start)
	if approach.is_empty() and not city.is_road(finish):
		return {"ok": false, "msg": "Hinter dem Berg fehlt eine anschliessbare Strasse (maximal 16 Zufahrtsfelder)."}
	var cost := BASE_COST + CELL_COST * float(length) + 3000.0 * float(approach.size())
	return {"ok": true, "cells": cells, "approach": approach, "cost": cost, "days": 5 + 2 * length + approach.size(), "from": [start.x, start.y], "to": [finish.x, finish.y]}


func _clear_approach(q: Vector2i) -> bool:
	var city: CityData = sim.city
	if not city.inside(q) or not city.height.is_empty() and city.height[city.idx(q)] > 0:
		return false
	var i := city.idx(q)
	var parcel: Dictionary = sim.parcels.at_cell(q)
	return city.building_at[i] < 0 and city.ground[i] not in [CityData.G.WATER, CityData.G.RAIL, CityData.G.RUNWAY, CityData.G.APRON] \
		and (parcel.is_empty() or Towns.is_public(str(parcel.owner))) and not sim.access.reserved(q) and not sim.eko.protected(q)


## Kuerzeste flache Zufahrt zu einer vorhandenen Strasse auf der anderen Bergseite.
func _feeder(finish: Vector2i, start: Vector2i) -> Array:
	if sim.city.is_road(finish):
		return []
	var queue: Array = [[finish]]
	var seen := {finish: true}
	var head := 0
	while head < queue.size():
		var path: Array = queue[head]
		head += 1
		if path.size() >= MAX_APPROACH:
			continue
		for d in DIRECTIONS:
			var q: Vector2i = path[-1] + d
			if q == start or seen.has(q) or not sim.city.inside(q):
				continue
			if sim.city.is_road(q) and (sim.city.height.is_empty() or sim.city.height[sim.city.idx(q)] == 0):
				return path.map(func(p): return [p.x, p.y])
			if _clear_approach(q):
				seen[q] = true
				queue.append(path + [q])
	return []


func request(cid: int, start: Vector2i, finish: Vector2i, reason: String) -> Dictionary:
	var c: Company = sim.company(cid)
	if c == null or not c.is_active():
		return {"ok": false, "msg": "Nur eine aktive Firma kann einen Tunnel beantragen."}
	var pl := plan(start, finish)
	if not pl.ok:
		return pl
	if c.ledger.cash < float(pl.cost) * COMPANY_SHARE:
		return {"ok": false, "msg": "Der Firmenanteil von %s ist nicht gedeckt." % Catalog.money(float(pl.cost) * COMPANY_SHARE)}
	var j := _new(pl, cid, reason)
	sim.log_event("%s beantragt Tunnel %s: %d Bergfelder, Kosten %s, Firmenanteil 25 %; Stadt entscheidet." % [c.company_name, j.id, j.cells.size(), Catalog.money(float(j.cost))], "info", cid)
	return {"ok": true, "msg": "Tunnelantrag %s wartet auf die Stadt." % j.id, "ref": j.id}


func build_city(town: int, start: Vector2i, finish: Vector2i, reason: String, by: String) -> Dictionary:
	var pl := plan(start, finish)
	if not pl.ok:
		return pl
	if sim.towns.of_cell(start) != town:
		return {"ok": false, "msg": "Das erste Portal liegt nicht in deiner Stadt."}
	if sim.towns.mayor(town).available_budget() < float(pl.cost):
		return {"ok": false, "msg": "Stadtkasse kann den Tunnel nicht finanzieren."}
	var j := _new(pl, -1, reason)
	return _start(j, by)


func _new(pl: Dictionary, cid: int, reason: String) -> Dictionary:
	var town: int = sim.towns.of_cell(_point(pl.from))
	var j := {"id": "TU%d" % _next, "from": pl.from, "to": pl.to, "cells": pl.cells, "approach": pl.approach, "company": cid,
		"town": town, "cost": float(pl.cost), "days": int(pl.days), "reason": reason.left(200),
		"status": "antrag", "project": "", "day": GameCalendar.day_of(sim.game_min)}
	_next += 1
	items[j.id] = j
	return j


func decide(town: int, id: String, approve: bool, reason: String, by: String) -> Dictionary:
	var j: Dictionary = items.get(id, {})
	if j.is_empty() or j.status != "antrag" or int(j.town) != town:
		return {"ok": false, "msg": "Kein offener Tunnelantrag %s in dieser Stadt." % id}
	if not approve:
		j.status = "abgelehnt"
		j["decision"] = reason.left(200)
		return {"ok": true, "msg": "Tunnelantrag %s abgelehnt." % id}
	var c: Company = sim.company(int(j.company))
	if c == null or not c.is_active():
		return {"ok": false, "msg": "Die antragstellende Firma ist nicht mehr aktiv."}
	var share := float(j.cost) * COMPANY_SHARE
	if c.ledger.cash < share:
		return {"ok": false, "msg": "Der Firmenanteil ist nicht mehr gedeckt."}
	if sim.towns.mayor(town).available_budget() + share < float(j.cost):
		return {"ok": false, "msg": "Die Stadtkasse deckt ihren Tunnelanteil nicht."}
	c.ledger.book("property_costs", -share, true, "Tunnelbeitrag %s" % id, sim.game_min, Towns.account_of(town))
	return _start(j, by)


func _start(j: Dictionary, by: String) -> Dictionary:
	var material := {}
	for item in MATERIAL:
		material[item] = int(MATERIAL[item]) * j.cells.size()
	material["schotter"] += j.approach.size() * 2
	var prj: Dictionary = sim.towns.mayor(int(j.town)).add_works_project("tunnel", str(j.id), float(j.cost), int(j.days), material,
		"Tunnel %s (%s)" % [j.id, by])
	j.project = prj.id
	j.status = "im_bau"
	sim.log_event("%s baut Tunnel %s: %d Felsfelder, Materiallieferung und Baufirma; gesperrt bis zur Abnahme." % [by, j.id, j.cells.size()], "info", int(j.company))
	sim.activity.add("stadt", int(j.company), "bau", "Tunnel %s im Bau" % j.id, str(j.reason), _point(j.from))
	return {"ok": true, "msg": "Tunnel %s ausgeschrieben (%s)." % [j.id, prj.id], "ref": j.id}


func finish(id: String) -> void:
	var j: Dictionary = items.get(id, {})
	if j.is_empty() or j.status == "freigegeben":
		return
	j.status = "freigegeben"
	_open(j)
	sim.access.on_bridge_opened() # neue Erreichbarkeit fuer Zufahrtsplaene
	sim.access.roads_built.emit((j.cells + j.get("approach", [])).map(func(a): return _point(a)))
	sim.log_event("Tunnel %s abgenommen: Fahrzeuge fahren jetzt unter dem Berg hindurch." % id, "good", int(j.company))
	sim.activity.add("stadt", int(j.company), "bau", "Tunnel %s freigegeben" % id, "Abnahme bestanden", _point(j.from))


func _open(j: Dictionary) -> void:
	for a in j.cells + j.get("approach", []):
		var q := _point(a)
		if not sim.city.inside(q):
			continue
		var i: int = sim.city.idx(q)
		if sim.city.building_at[i] >= 0:
			continue
		if sim.city.ground[i] != CityData.G.ROAD:
			sim.city.road_count += 1
		sim.city.ground[i] = CityData.G.ROAD
		sim.city.blocked[i] = 0
		sim.nav.road.set_point_solid(q, false)
		sim.nav.walk.set_point_solid(q, false)
		sim.nav.walk.set_point_weight_scale(q, 4.0)
		if j.cells.has(a):
			_cells[q] = str(j.id)


func underground(q: Vector2i) -> bool:
	return _cells.has(q)


func reserved(q: Vector2i) -> bool:
	for j in items.values():
		if str(j.status) in ["antrag", "im_bau"] and (j.cells.has([q.x, q.y]) or j.get("approach", []).has([q.x, q.y])):
			return true
	return false


func progress(j: Dictionary) -> float:
	return 1.0 if j.status == "freigegeben" else sim.construction.public_progress(str(j.project)) if j.status == "im_bau" else 0.0


func on_day(day: int) -> void:
	for j in items.values():
		if j.status == "antrag" and day - int(j.day) >= REQUEST_DAYS:
			var c: Company = sim.company(int(j.company))
			var share := float(j.cost) * COMPANY_SHARE if c != null and c.is_active() else 0.0
			var ok: bool = c != null and c.is_active() and c.ledger.cash >= share and sim.towns.mayor(int(j.town)).available_budget() + share >= float(j.cost)
			decide(int(j.town), str(j.id), ok, "Bauamt nach Antragsfrist", "Bauamt")


func proposals(town: int, limit: int = 5) -> Array:
	var day := GameCalendar.day_of(sim.game_min)
	if day != _proposals_day or sim.city.road_count != _proposals_roads:
		_proposals_day = day
		_proposals_roads = sim.city.road_count
		_proposals.clear()
	var key := str(town)
	if _proposals.has(key):
		return _proposals[key].slice(0, limit)
	var out := []
	var seen := {}
	for y in sim.city.size:
		for x in sim.city.size:
			var start := Vector2i(x, y)
			if not sim.city.is_road(start) or sim.towns.of_cell(start) != town:
				continue
			for direction in DIRECTIONS:
				var first: Vector2i = start + direction
				if not sim.city.inside(first) or sim.city.height.is_empty() or sim.city.height[sim.city.idx(first)] == 0:
					continue
				for span in range(2, MAX_LENGTH + 1):
					var finish: Vector2i = start + direction * (span + 1)
					if not sim.city.inside(finish):
						break
					if sim.city.height[sim.city.idx(finish)] > 0:
						continue
					var ident := "%s:%s" % [str(start), str(finish)]
					if not seen.has(ident):
						var pl := plan(start, finish)
						if pl.ok:
							seen[ident] = true
							out.append({"von": pl.from, "nach": pl.to, "felder": pl.cells.size(), "zufahrt": pl.approach.size(), "kosten": int(pl.cost), "tage": int(pl.days)})
							if out.size() >= 12:
								_proposals[key] = out
								return out.slice(0, limit)
					break
	_proposals[key] = out.slice(0, 12)
	return _proposals[key].slice(0, limit)


func summary(town: int) -> Dictionary:
	return {"vorschlaege": proposals(town), "antraege": items.values().filter(func(j): return int(j.town) == town and j.status == "antrag").map(
		func(j): return {"id": j.id, "firma": int(j.company), "von": j.from, "nach": j.to, "kosten": int(j.cost), "begruendung": j.reason}),
		"projekte": items.values().filter(func(j): return int(j.town) == town and j.status in ["im_bau", "freigegeben"]).map(
		func(j): return {"id": j.id, "status": j.status, "fortschritt": snappedf(progress(j), 0.01), "kosten": int(j.cost), "von": j.from, "nach": j.to})}


func to_dict() -> Dictionary:
	return {"items": items.duplicate(true), "next": _next}


func from_dict(data: Dictionary) -> void:
	items = data.get("items", {}).duplicate(true)
	_next = int(data.get("next", 1))
	_cells.clear()
	for j in items.values():
		if j.status == "freigegeben":
			_open(j)
