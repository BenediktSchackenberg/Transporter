class_name PowerNet
extends RefCounted
## Stromnetz als Graph (Auftrag 22 Phase 3 Schritt 2, docs/INFRASTRUCTURE.md). Knoten: das gemeinsame Kraftwerk ("KW") und je Stadt
## ein Umspannwerk ("U<k>", neben dem Rathaus). Kanten: Hochspannungstrassen als echte Zellenfolge (Freileitung, gerade Linie,
## quert Wasser und Bebauung). Startnetz = minimaler Spannbaum ab dem Kraftwerk (kuerzeste Gesamtlaenge), so ist jede Stadt
## angeschlossen. Eine Stadt bekommt Kraftwerksstrom nur, wenn ihr Umspannwerk ueber intakte Trassen ("ok") mit dem Kraftwerk
## verbunden ist; sonst nur den begrenzten Notstrom (PowerGrid).
## Schritt 3: Leitungsschaeden. Taeglich kann eine intakte Trasse reissen (Sturm: starke Boeen, sonst selten durch Alterung). Die
## Stelle liegt an einem Mast mit Strassenzufahrt; der Netztrupp der naechsten angeschlossenen Stadt faehrt vom Rathaus hin (echtes
## Fahrzeug der CityFleet), repariert vor Ort REPAIR_MIN Spielminuten und meldet die Trasse wieder in Betrieb. Die Reparatur zahlt
## die Kraftwerksgesellschaft E0 (an Dienstleister S0, Netzbaumaterial). Bis dahin haben die Staedte dahinter nur Notstrom.

const MAST_EVERY := 4                 # Mast alle n Felder (Darstellung)
const STORM_P := 0.12                 # Schadenswahrscheinlichkeit je Trasse und Sturmtag
const AGE_P := 0.002                  # ... an sonstigen Tagen (Alterung, Vogelschlag)
const REPAIR_MIN := 40.0              # Arbeit vor Ort (Spielminuten; ein Spieltag hat 120)
const REPAIR_COST := 2500.0           # Material und Fremdleistung je Reparatur (E0 -> S0)
const ROAD_RADIUS := 6                # Zufahrt: Strasse hoechstens so weit vom Schadensmast
## Schritt 4: Ringschluss. Hat ein Schaden Staedte vom Kraftwerk getrennt, beschliesst die Region nach der Reparatur eine zweite
## Trasse, die genau diese Seite auf kuerzestem Weg mit dem restlichen Netz verbindet (Redundanz). Sie wird wie jedes regionale
## Bauwerk ausgeschrieben (Anteile gleich je Stadt, wie das Kraftwerk), eine Baufirma baut, die Abnahme fuegt die Kante hinzu.
const LINE_EUR_PER_CELL := 400.0      # Baukosten je Trassenfeld (Masten, Seile, Fundamente)
const LINE_CELLS_PER_DAY := 15        # Baufortschritt
const LINE_DAYS_MIN := 10

var sim
var nodes := {}                       # id -> {id, cell: Vector2i, town: int (-1 = Kraftwerk)}
var edges: Array = []                 # [{id, a, b, cells: [[x, y], ...], len, state: "ok"|"defekt"}]
var planned := {}                     # Projekt-ID -> {a, b}: beschlossene Trassen im Bau (Ringschluss)
var repairs := {}                     # Trassen-ID -> {cell: [x, y], road: [x, y], town, vehicle, since, cause}
var stats := {"schaeden": 0, "reparaturen": 0, "kosten": 0.0, "ausfall_min": 0.0}
var rng := RandomNumberGenerator.new()   # eigener Zufall: der gemeinsame Strom sim.rng bleibt unveraendert
var _reach := {}                      # Cache: Knoten-ID -> true (vom Kraftwerk erreichbar)
var _dirty := true


func setup(simulation) -> void:
	sim = simulation
	rng.seed = hash("stromnetz") ^ int(sim.rng.seed)


func built() -> bool:
	return not nodes.is_empty()


## Netz einmalig anlegen (nachdem Kraftwerk und Orte stehen; auch fuer alte Spielstaende ohne Netz).
func ensure() -> void:
	if built() or sim.plant == null or int(sim.plant.building) < 0:
		return
	nodes = {"KW": {"id": "KW", "cell": _center(int(sim.plant.building)), "town": -1}}
	for k in maxi(1, sim.towns.count()):
		nodes["U%d" % k] = {"id": "U%d" % k, "cell": _substation_cell(k), "town": k}
	edges = []
	# Prim: vom Kraftwerk aus immer die kuerzeste Verbindung eines angeschlossenen zu einem neuen Knoten
	var inside := {"KW": true}
	while inside.size() < nodes.size():
		var best := []
		var best_d := 1 << 30
		for a in inside:
			for b in nodes:
				if inside.has(b):
					continue
				var d := _dist(nodes[a].cell, nodes[b].cell)
				if d < best_d or (d == best_d and str(b) < str(best[1])):
					best_d = d
					best = [a, b]
		inside[best[1]] = true
		add_edge(str(best[0]), str(best[1]))
	_dirty = true


func add_edge(a: String, b: String) -> Dictionary:
	var cells := line_cells(nodes[a].cell, nodes[b].cell)
	var e := {"id": "L%d" % (edges.size() + 1), "a": a, "b": b, "cells": cells.map(func(c): return [c.x, c.y]), "len": cells.size(), "state": "ok"}
	edges.append(e)
	_dirty = true
	return e


func edge(id: String) -> Dictionary:
	for e in edges:
		if str(e.id) == id:
			return e
	return {}


func set_state(id: String, state: String) -> void:
	var e := edge(id)
	if not e.is_empty() and str(e.state) != state:
		e.state = state
		_dirty = true


## Ist das Umspannwerk der Stadt ueber intakte Trassen mit dem Kraftwerk verbunden? (ohne Netz: ja, wie bisher)
func connected(k: int) -> bool:
	if not built():
		return true
	if _dirty:
		_reach = _bfs("KW")
		_dirty = false
	return _reach.has("U%d" % k)


func _bfs(start: String, skip: String = "") -> Dictionary:
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var n: String = queue.pop_front()
		for e in edges:
			if str(e.state) != "ok" or str(e.id) == skip:
				continue
			var o := ""
			if str(e.a) == n:
				o = str(e.b)
			elif str(e.b) == n:
				o = str(e.a)
			if o != "" and not seen.has(o):
				seen[o] = true
				queue.append(o)
	return seen


## Trassen, ueber die die Stadt versorgt wird (Pfad Kraftwerk -> Umspannwerk im intakten Netz; Anzeige).
func path_to(k: int) -> Array:
	var target := "U%d" % k
	var prev := {"KW": ""}
	var queue := ["KW"]
	while not queue.is_empty():
		var n: String = queue.pop_front()
		if n == target:
			break
		for e in edges:
			if str(e.state) != "ok":
				continue
			var o := str(e.b) if str(e.a) == n else (str(e.a) if str(e.b) == n else "")
			if o != "" and not prev.has(o):
				prev[o] = [n, str(e.id)]
				queue.append(o)
	if not prev.has(target):
		return []
	var out := []
	var cur := target
	while cur != "KW":
		out.push_front(prev[cur][1])
		cur = prev[cur][0]
	return out


## Tageslauf (vor der Zuteilung): neue Schaeden wuerfeln, Netztrupps fuer offene Schaeden ohne Fahrzeug (z. B. nach dem Laden) schicken.
func on_day(_day: int) -> void:
	if not built():
		return
	var storm: bool = sim.wx != null and sim.wx.is_strong_wind()
	for e in edges:
		if str(e.state) == "ok" and rng.randf() < (STORM_P if storm else AGE_P):
			damage(str(e.id), "Sturmböen" if storm else "Materialermüdung")
	for id in repairs:
		var vid := int(repairs[id].get("vehicle", -1))
		if not sim.fleet.vehicles.any(func(v): return int(v.id) == vid and v.kind == "netztrupp"):
			_dispatch(str(id))


## Trasse beschaedigen: Schadstelle an einem Mast mit Strassenzufahrt, Netztrupp losschicken.
func damage(id: String, cause: String) -> bool:
	var e := edge(id)
	if e.is_empty() or str(e.state) != "ok":
		return false
	var cells: Array = e.cells
	var start: int = rng.randi_range(0, cells.size() - 1)
	var site := Vector2i(int(cells[start][0]), int(cells[start][1]))
	var road := Vector2i(-1, -1)
	for i in cells.size():   # ab der Wuerfelstelle die erste Mastzelle mit Strasse in der Naehe
		var j: int = (start + i) % cells.size()
		var c := Vector2i(int(cells[j][0]), int(cells[j][1]))
		var r := _road_near(c)
		if r.x >= 0:
			site = c
			road = r
			break
	if road.x < 0:
		road = site
	set_state(id, "defekt")
	e["cause"] = cause
	repairs[id] = {"cell": [site.x, site.y], "road": [road.x, road.y], "town": -1, "vehicle": -1, "since": sim.game_min, "cause": cause, "getrennt": 0}
	stats.schaeden = int(stats.schaeden) + 1
	var off: Array = []
	for k in maxi(1, sim.towns.count()):
		if not connected(k):
			off.append(sim.towns.name_of(k))
	repairs[id].getrennt = off.size()
	sim.log_event("Stromnetz: Hochspannungstrasse %s (%s – %s) durch %s unterbrochen. Ohne Kraftwerksstrom: %s – Notstrom von außen, Netztrupp ist unterwegs." % [
		id, _label(str(e.a)), _label(str(e.b)), cause, ", ".join(off) if not off.is_empty() else "keine Stadt"], "warn")
	_dispatch(id)
	return true


func _dispatch(id: String) -> void:
	var rp: Dictionary = repairs[id]
	var road := Vector2i(int(rp.road[0]), int(rp.road[1]))
	var best := 0
	var best_d := 1 << 30
	for k in maxi(1, sim.towns.count()):   # Netztrupp der naechsten Stadt, bevorzugt einer mit Strom
		var d := _dist(nodes["U%d" % k].cell, road) + (0 if connected(k) else 100000)
		if d < best_d:
			best_d = d
			best = k
	var home := _home_road(best)
	var v: Dictionary = sim.fleet._spawn("netztrupp", home, road, 0.0, home, "Netztrupp %s: Trasse %s" % [sim.towns.name_of(best), id])
	v["edge"] = id
	rp.town = best
	rp.vehicle = int(v.id)


## Vom Netztrupp nach getaner Arbeit vor Ort gemeldet.
func repaired(id: String) -> void:
	if not repairs.has(id):
		return
	var rp: Dictionary = repairs[id]
	repairs.erase(id)
	set_state(id, "ok")
	sim.economy.transfer(PowerPlant.ACCT, "S0", REPAIR_COST)
	stats.reparaturen = int(stats.reparaturen) + 1
	stats.kosten = float(stats.kosten) + REPAIR_COST
	var dur: float = sim.game_min - float(rp.since)
	stats.ausfall_min = float(stats.ausfall_min) + dur
	sim.log_event("Stromnetz: Trasse %s repariert (Netztrupp %s, Ausfall %.1f Spieltage, %s)." % [
		id, sim.towns.name_of(int(rp.town)), dur / GameCalendar.days_to_min(1.0), Catalog.money(REPAIR_COST)], "good")
	if int(rp.get("getrennt", 0)) > 0:
		plan_ring(id)


## Ringschluss planen: die Knoten hinter der Trasse `cut` (ohne sie vom Kraftwerk nicht erreichbar) auf kuerzestem Weg mit dem
## uebrigen Netz verbinden. Nur eine geplante Trasse zugleich; keine, wenn die Seite schon anders erreichbar ist.
func plan_ring(cut: String) -> Dictionary:
	if sim.towns.count() < 2 or not planned.is_empty():
		return {}
	var e := edge(cut)
	if e.is_empty():
		return {}
	var reach := _bfs("KW", cut)
	if reach.size() == nodes.size():
		return {}   # schon redundant angebunden
	var best := []
	var best_d := 1 << 30
	for x in nodes:
		if reach.has(x):
			continue
		for y in reach:
			if (str(x) == str(e.a) and str(y) == str(e.b)) or (str(x) == str(e.b) and str(y) == str(e.a)):
				continue
			var d := _dist(nodes[x].cell, nodes[y].cell)
			if d < best_d:
				best_d = d
				best = [str(y), str(x)]
	if best.is_empty():
		return {}
	var cells := line_cells(nodes[best[0]].cell, nodes[best[1]].cell).size()
	var cost := snappedf(float(cells) * LINE_EUR_PER_CELL, 100.0)
	var days := maxi(LINE_DAYS_MIN, ceili(float(cells) / float(LINE_CELLS_PER_DAY)))
	var k := 0
	for t in sim.towns.list:   # Traegerstadt: die groesste (wie bei den gemeinsamen Muellanlagen)
		if sim.citizens.population_of(int(t.id)) > sim.citizens.population_of(k):
			k = int(t.id)
	var M: Mayor = sim.towns.mayor(k)
	var prj: Dictionary = M.add_works_project("trasse", "%s|%s" % best, cost, days, {}, "Ringschluss Hochspannung: %s – %s" % [_label(best[0]), _label(best[1])])
	M.commitments = maxf(0.0, M.commitments - cost)   # Anteile gleich je Stadt (wie das Kraftwerk)
	prj["shares"] = {}
	var n: int = sim.towns.count()
	for t in n:
		sim.towns.mayor(t).commitments += cost / float(n)
		prj.shares[str(t)] = cost / float(n)
	prj["regional"] = "trasse"
	prj.status = "ausgeschrieben"
	prj.tender = {"opened_day": GameCalendar.day_of(sim.game_min) - 1, "bids": [], "by": "Stadtwerke"}
	planned[str(prj.id)] = {"a": best[0], "b": best[1]}
	sim.log_event("Stromnetz: Nach dem Ausfall auf Trasse %s beschließt die Region einen Ringschluss %s – %s (%d Felder, %s, Anteile je Stadt gleich) – ausgeschrieben als %s." % [
		cut, _label(best[0]), _label(best[1]), cells, Catalog.money(cost), prj.id], "info")
	return prj


## Abnahme der Ringschluss-Trasse durch die Baufirma (Construction._finish_public).
func on_line_done(prj: Dictionary) -> void:
	var p: Dictionary = planned.get(str(prj.id), {})
	if p.is_empty():
		return
	planned.erase(str(prj.id))
	var e := add_edge(str(p.a), str(p.b))
	sim.log_event("Stromnetz: Trasse %s (%s – %s) in Betrieb – das Netz ist jetzt ringförmig und übersteht einen Leitungsschaden." % [
		e.id, _label(str(p.a)), _label(str(p.b))], "good")


## Mittelpunkt einer geplanten Trasse (Bautrupp-Ziel).
func planned_mid(project_id: String) -> Vector2i:
	var p: Dictionary = planned.get(project_id, {})
	if p.is_empty():
		return Vector2i(-1, -1)
	return (nodes[str(p.a)].cell + nodes[str(p.b)].cell) / 2


func _road_near(c: Vector2i) -> Vector2i:
	for r in ROAD_RADIUS + 1:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if sim.city.is_road(q):
					return q
	return Vector2i(-1, -1)


func _home_road(k: int) -> Vector2i:
	var t: Dictionary = sim.towns.list[k] if k < sim.towns.list.size() else {}
	var b: Dictionary = sim.city.building(int(t.get("town_hall", -1)))
	if not b.is_empty() and b.has("road"):
		return b.road
	return sim.fleet.depot_road()


func _label(node: String) -> String:
	return "Kraftwerk" if node == "KW" else "Umspannwerk %s" % sim.towns.name_of(int(nodes[node].town))


func summary() -> Dictionary:
	var towns := {}
	for k in maxi(1, sim.towns.count()):
		towns[str(k)] = connected(k)
	return {"trassen": edges.size(), "laenge_felder": edges.reduce(func(s, e): return s + int(e.len), 0),
		"defekt": edges.filter(func(e): return str(e.state) != "ok").map(func(e): return str(e.id)), "angeschlossen": towns,
		"reparaturen": repairs.keys().map(func(id): return {"trasse": id, "ursache": str(repairs[id].cause), "trupp": sim.towns.name_of(int(repairs[id].town)) if int(repairs[id].town) >= 0 else "-"}),
		"statistik": stats, "im_bau": planned.keys().map(func(id): return {"projekt": id, "von": _label(str(planned[id].a)), "nach": _label(str(planned[id].b))})}


## Gerade Linie (Bresenham) von a nach b, beide Enden eingeschlossen.
static func line_cells(a: Vector2i, b: Vector2i) -> Array:
	var out := []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var c := a
	while true:
		out.append(c)
		if c == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			c.x += sx
		if e2 <= dx:
			err += dx
			c.y += sy
	return out


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _center(bid: int) -> Vector2i:
	var b: Dictionary = sim.city.building(bid)
	if b.is_empty():
		return Vector2i.ZERO
	return Vector2i(int(b.x) + int(b.get("w", 1)) / 2, int(b.y) + int(b.get("h", 1)) / 2)


## Umspannwerk: unmittelbar neben dem Rathaus (rechts unten), sonst Ortszentrum.
func _substation_cell(k: int) -> Vector2i:
	var t: Dictionary = sim.towns.list[k] if k < sim.towns.list.size() else {}
	var th := int(t.get("town_hall", -1))
	var b: Dictionary = sim.city.building(th) if th >= 0 else {}
	if not b.is_empty():
		return Vector2i(int(b.x) + int(b.get("w", 1)), int(b.y) + int(b.get("h", 1)))
	return t.get("center", Vector2i.ZERO)


func to_dict() -> Dictionary:
	var n := {}
	for id in nodes:
		n[id] = {"id": id, "cell": [nodes[id].cell.x, nodes[id].cell.y], "town": int(nodes[id].town)}
	var rp := {}
	for id in repairs:   # Fahrzeuge werden nicht gespeichert: nach dem Laden faehrt ein neuer Netztrupp los
		rp[id] = repairs[id].duplicate()
		rp[id].vehicle = -1
	return {"nodes": n, "edges": edges.duplicate(true), "repairs": rp, "stats": stats.duplicate(), "planned": planned.duplicate(true), "rng_state": str(rng.state)}


func from_dict(d: Dictionary) -> void:
	if d.is_empty() or d.get("nodes", {}).is_empty():
		return
	nodes = {}
	for id in d.nodes:
		var c: Array = d.nodes[id].cell
		nodes[str(id)] = {"id": str(id), "cell": Vector2i(int(c[0]), int(c[1])), "town": int(d.nodes[id].town)}
	edges = d.get("edges", []).duplicate(true)
	for e in edges:
		e.len = int(e.len)
	repairs = d.get("repairs", {}).duplicate(true)
	planned = d.get("planned", {}).duplicate(true)
	if d.has("rng_state"):
		rng.state = int(str(d.rng_state))
	for k in d.get("stats", {}):
		stats[k] = d.stats[k]
	_dirty = true
