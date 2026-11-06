class_name AccessRoads
extends RefCounted
## Zufahrten (Auftrag 15, Etappe B): Schotterweg von einer abgelegenen Lagerstaette zur naechsten Strasse. Ein Unternehmer
## bezahlt die Zufahrt an die Stadt (Erschliessungsbeitrag), die Strassenmeisterei baut sie Tag fuer Tag sichtbar; jede fertige
## Zelle wird Strasse (Wegfindung, Grundstuecksanschluss). Gesucht wird nur ueber Land: Berge, Wasser und Gebaeude sind
## Hindernisse, Wald wird gerodet. Liegt Wasser im Weg, ist eine Bruecke noetig (Etappe D).

signal roads_built(cells: Array)   # neue Strassenzellen (Darstellung)

const BASE_COST := 3000.0          # Planung, Vermessung, Anschluss
const CELL_COST := 80.0            # Schotterweg je Feld
const CLEAR_COST := 60.0           # Rodung je Baumfeld
const CELLS_PER_DAY := 15          # Baufortschritt der Strassenmeisterei
const MAX_RUNNING := 2

var sim
var jobs := {}                     # "Z<n>" -> {id, parcel, company, cells: [[x, y]], built, cost, start, status}
var _next := 1
var _cache := {}                   # Grundstueck -> Plan (gueltig bis eine Zufahrt fertig wird)
var _fields := {}                  # "land"/"wasser" -> Entfernungsfeld zur Strasse


func setup(simulation) -> void:
	sim = simulation


## Weg vom Grundstueck zur naechsten Strasse (Breitensuche ueber Land). Ergebnis: {ok, cells, kosten, tage, baeume} oder {ok: false, msg}.
func plan(pid: String) -> Dictionary:
	if _cache.has(pid):
		return _cache[pid]
	var p: Dictionary = sim.parcels.parcel(pid)
	if p.is_empty():
		return {"ok": false, "msg": "Unbekanntes Grundstück %s." % pid}
	var res := _search(p, false)
	if not res.ok and _search(p, true).ok:
		res = {"ok": false, "msg": "Kein Landweg zu %s: Fluss, See oder Meer im Weg – dafür ist eine Brücke nötig." % pid, "bruecke": true}
	elif res.ok:
		var trees := 0
		for c in res.cells:
			if sim.city.blocked[sim.city.idx(c)] == 1:
				trees += 1
		res.baeume = trees
		res.kosten = snappedf(BASE_COST + CELL_COST * res.cells.size() + CLEAR_COST * trees, 1.0)
		res.tage = ceili(float(res.cells.size()) / CELLS_PER_DAY)
	_cache[pid] = res
	return res


func _search(p: Dictionary, allow_water: bool) -> Dictionary:
	var city: CityData = sim.city
	var key := "wasser" if allow_water else "land"
	if not _fields.has(key):
		_fields[key] = _field(allow_water)
	var toward: PackedInt32Array = _fields[key][0]
	var dist: PackedInt32Array = _fields[key][1]
	# Startzellen: Rand um jeden freien Bauplatz des Betriebsgebaeudes (der Weg endet direkt am Hof, nicht am Grundstuecksrand)
	var best := -1
	var best_len := 1 << 30
	var lots := _lots(p)
	if lots.is_empty():
		return {"ok": false, "msg": "Auf dem Grundstück ist kein freier Bauplatz für den Betrieb."}
	for r in lots:
		for y in range(r.position.y - 1, r.end.y + 1):
			for x in range(r.position.x - 1, r.end.x + 1):
				var q := Vector2i(x, y)
				if r.has_point(q) or not city.inside(q):
					continue
				if city.is_road(q):
					return {"ok": true, "cells": []}   # schon angeschlossen
				if not _passable(q, allow_water, true) or toward[city.idx(q)] == -2:
					continue
				if dist[city.idx(q)] < best_len:
					best_len = dist[city.idx(q)]
					best = city.idx(q)
	if best < 0:
		return {"ok": false, "msg": "Kein Weg zur nächsten Straße (Berge oder Bebauung im Weg)."}
	return {"ok": true, "cells": _trace(toward, best)}


## Zellen vom Start bis vor die Strasse (Folge der Vorgaenger im Entfernungsfeld).
func _trace(toward: PackedInt32Array, from: int) -> Array:
	var n: int = sim.city.size
	var cells: Array = []
	var k := from
	while k >= 0:
		cells.append(Vector2i(k % n, k / n))
		k = toward[k]
	return cells


## Eine Breitensuche von allen Strassenzellen aus: je Zelle der Nachbar in Richtung Strasse (-1 = grenzt an Strasse, -2 = unerreichbar).
## Einmal je Strassennetz berechnet (verworfen, wenn eine Zufahrt fertig wird).
func _field(allow_water: bool) -> Array:
	var city: CityData = sim.city
	var n := city.size
	var toward := PackedInt32Array()
	toward.resize(n * n)
	toward.fill(-2)
	var dist := PackedInt32Array()
	dist.resize(n * n)
	var queue := PackedInt32Array()
	for i in n * n:
		if city.ground[i] == CityData.G.ROAD:
			toward[i] = -3   # Strasse selbst (kein Wegbestandteil)
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x := i % n
		var y := i / n
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = Vector2i(x, y) + d
			if not city.inside(q):
				continue
			var j := city.idx(q)
			if toward[j] != -2 or not _passable(q, allow_water, false):
				continue
			toward[j] = -1 if toward[i] == -3 else i
			dist[j] = dist[i] + 1
			queue.append(j)
	return [toward, dist]


## Freie Bauplaetze (Rechtecke in Groesse des Bergwerksgebaeudes) auf dem Grundstueck: flach, unbebaut, ohne Baum, kein Wasser.
func _lots(p: Dictionary) -> Array:
	var city: CityData = sim.city
	var info: Array = CityGenerator.TYPES[str(Businesses.branches().get("bergwerk", {}).get("gebaeude", "farm"))]
	var w := int(info[1])
	var h := int(info[2])
	var r0 := Rect2i(int(p.rect[0]), int(p.rect[1]), int(p.rect[2]), int(p.rect[3]))
	var out: Array = []
	for y in range(r0.position.y, r0.end.y - h + 1):
		for x in range(r0.position.x, r0.end.x - w + 1):
			var r := Rect2i(x, y, w, h)
			var free := true
			for yy in range(y, y + h):
				for xx in range(x, x + w):
					var i := city.idx(Vector2i(xx, yy))
					if city.building_at[i] >= 0 or city.blocked[i] == 1 or city.ground[i] in [CityData.G.ROAD, CityData.G.WATER] or (city.height.size() > 0 and city.height[i] > 0):
						free = false
			if free:
				out.append(r)
	return out


## Land ohne Berg und ohne Gebaeude; Baeume werden gerodet. Strassen sind Ziel, nie Durchgang.
func _passable(q: Vector2i, allow_water: bool, start: bool) -> bool:
	var city: CityData = sim.city
	var i := city.idx(q)
	if city.height.size() > 0 and city.height[i] > 0:
		return false
	if city.building_at[i] >= 0:
		return false
	if city.ground[i] == CityData.G.WATER:
		return allow_water and not start
	return true


## Zufahrt beauftragen: der Unternehmer zahlt den Erschliessungsbeitrag an die Stadt, die Strassenmeisterei baut.
func order(cid: int, pid: String) -> Dictionary:
	if jobs.values().any(func(j): return j.parcel == pid and j.status == "im_bau"):
		return {"ok": false, "msg": "Zur Lagerstätte %s wird schon eine Zufahrt gebaut." % pid}
	if running() >= MAX_RUNNING:
		return {"ok": false, "msg": "Die Straßenmeisterei baut schon %d Zufahrten; später erneut beauftragen." % MAX_RUNNING}
	var pl := plan(pid)
	if not pl.ok:
		return {"ok": false, "msg": str(pl.msg)}
	if pl.cells.is_empty():
		return {"ok": false, "msg": "Grundstück %s hat schon Straßenanschluss." % pid}
	var c: Company = sim.company(cid)
	if c.ledger.cash < float(pl.kosten):
		return {"ok": false, "msg": "Nicht genug Bargeld für die Zufahrt (%s)." % Catalog.money(float(pl.kosten))}
	c.ledger.book("property_costs", -float(pl.kosten), true, "Zufahrt zu %s (%d Felder)" % [pid, pl.cells.size()], sim.game_min)
	var j := {"id": "Z%d" % _next, "parcel": pid, "company": cid, "cells": pl.cells.map(func(v): return [v.x, v.y]), "built": 0,
		"cost": float(pl.kosten), "start": GameCalendar.day_of(sim.game_min), "status": "im_bau"}
	_next += 1
	jobs[j.id] = j
	var msg := "%s lässt eine Zufahrt zu %s bauen: %d Felder Schotterweg%s, %s, etwa %d Tage." % [c.company_name, pid, pl.cells.size(),
		" mit Rodung von %d Bäumen" % int(pl.baeume) if int(pl.baeume) > 0 else "", Catalog.money(float(pl.kosten)), int(pl.tage)]
	sim.log_event(msg, "info", cid)
	sim.activity.add("stadt", cid, "bau", "Zufahrt %s zu %s: Baubeginn" % [j.id, pid], "bezahlt von %s" % c.company_name, _head(j))
	_send_crew(j)
	return {"ok": true, "msg": msg, "ref": j.id}


func running() -> int:
	return jobs.values().filter(func(j): return j.status == "im_bau").size()


## Tagesfortschritt: von der Strasse her wachsen (letzte Zelle zuerst), damit jede fertige Zelle sofort angeschlossen ist.
func on_day(_day: int) -> void:
	for j in jobs.values():
		if j.status != "im_bau":
			continue
		var from := int(j.built)
		j.built = mini(j.cells.size(), from + CELLS_PER_DAY)
		_apply(j, from, int(j.built))
		if int(j.built) >= j.cells.size():
			j.status = "fertig"
			_cache.clear()
			_fields.clear()
			sim.log_event("Zufahrt %s zu %s ist fertig – die Lagerstätte hat jetzt Straßenanschluss." % [j.id, j.parcel], "good", int(j.company))
		else:
			_send_crew(j)


## Zellen [from, to) in Bauordnung (vom Strassenende her) zu Strasse machen.
func _apply(j: Dictionary, from: int, to: int) -> void:
	if to <= from:
		return
	var city: CityData = sim.city
	var made: Array = []
	var n: int = j.cells.size()
	for k in range(from, to):
		var a: Array = j.cells[n - 1 - k]
		var q := Vector2i(int(a[0]), int(a[1]))
		var i := city.idx(q)
		city.ground[i] = CityData.G.ROAD
		if city.blocked[i] == 1:
			city.blocked[i] = 0
			city.trees = city.trees.filter(func(t): return t[0] != q)
		sim.nav.road.set_point_solid(q, false)
		sim.nav.walk.set_point_solid(q, false)
		sim.nav.walk.set_point_weight_scale(q, 4.0)
		made.append(q)
	city.road_count += made.size()
	roads_built.emit(made)


func _head(j: Dictionary) -> Vector2i:
	var n: int = j.cells.size()
	var a: Array = j.cells[clampi(n - 1 - int(j.built), 0, n - 1)]
	return Vector2i(int(a[0]), int(a[1]))


## Bautrupp faehrt zur zuletzt gebauten Zelle (bzw. zur Einmuendung), denn Fahrzeuge brauchen ein Strassenziel.
func _send_crew(j: Dictionary) -> void:
	var n: int = j.cells.size()
	var at := _head(j)
	if int(j.built) > 0:
		var a: Array = j.cells[n - int(j.built)]
		at = Vector2i(int(a[0]), int(a[1]))
	else:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if sim.city.is_road(at + d):
				at += d
				break
	sim.fleet.send_crew(at, GameCalendar.day_start(GameCalendar.day_of(sim.game_min) + 1), "Straßenmeisterei")


## Fuer Beobachtung und Anzeige.
func summary() -> Array:
	return jobs.values().map(func(j): return {"id": j.id, "grundstueck": j.parcel, "unternehmen": int(j.company), "status": j.status,
		"fortschritt": snappedf(float(j.built) / maxf(1.0, float(j.cells.size())), 0.01), "felder": j.cells.size(), "kosten": int(j.cost)})


func to_dict() -> Dictionary:
	return {"jobs": jobs.duplicate(true), "next": _next}


## Laden: die Welt wird aus dem Seed neu erzeugt, gebaute Wegzellen werden wieder angelegt.
func from_dict(d: Dictionary) -> void:
	jobs = d.get("jobs", {}).duplicate(true)
	_next = int(d.get("next", 1))
	for j in jobs.values():
		j.built = int(j.built)
		_apply(j, 0, int(j.built))
