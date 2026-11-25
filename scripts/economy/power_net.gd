class_name PowerNet
extends RefCounted
## Stromnetz als Graph (Auftrag 22 Phase 3 Schritt 2, docs/INFRASTRUCTURE.md). Knoten: das gemeinsame Kraftwerk ("KW") und je Stadt
## ein Umspannwerk ("U<k>"). Kanten: Hochspannungstrassen als echte Zellenfolge. Eine Stadt bekommt Kraftwerksstrom nur, wenn
## ihr Umspannwerk ueber intakte Trassen ("ok") mit dem Kraftwerk
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
var planned := {}                     # Projekt-ID -> {a, b, cells, station}: beschlossene Trassen im Bau
var repairs := {}                     # Trassen-ID -> {cell: [x, y], road: [x, y], town, vehicle, since, cause}
var stats := {"schaeden": 0, "reparaturen": 0, "kosten": 0.0, "ausfall_min": 0.0}
var rng := RandomNumberGenerator.new()   # eigener Zufall: der gemeinsame Strom sim.rng bleibt unveraendert
var _reach := {}                      # Cache: Knoten-ID -> true (vom Kraftwerk erreichbar)
var _dirty := true
var _local_cache := {}
var _local_keys := {}


func setup(simulation) -> void:
	sim = simulation
	rng.seed = hash("stromnetz") ^ int(sim.rng.seed)


func built() -> bool:
	return not nodes.is_empty()


## Das Startgebiet hat einen Anschluss; neue und weitere Staedte entscheiden selbst ueber ihre Trasse.
## Gespeicherte Netze bleiben erhalten. Spaeter gegruendete Orte erhalten nur einen Knoten.
func ensure() -> void:
	if sim.plant == null or int(sim.plant.building) < 0:
		return
	var fresh := not built()
	if fresh:
		nodes = {"KW": {"id": "KW", "cell": _center(int(sim.plant.building)), "town": -1}}
		edges = []
	for k in maxi(1, sim.towns.count()):
		var id := "U%d" % k
		if not nodes.has(id):
			nodes[id] = {"id": id, "cell": _substation_cell(k), "town": k}
			_dirty = true
		elif sim.town_ready(k) and not connected(k) and not planned.values().any(func(p): return str(p.b) == id):
			# In der Wildnis wird das Rathaus erst spaeter gesetzt; bis zum Trassenbau folgt
			# der freie Umspannwerk-Knoten diesem Ort statt dem alten Ankunftsplatz.
			nodes[id].cell = _substation_cell(k)
	if fresh and not sim.wildnis:
		add_edge("KW", "U0")


## Eine Wildnisstadt kann weit vom generierten Ankunftsort entstehen. Alte Knoten und bereits
## bezahlte Trassen muessen dann dem wirklichen Rathaus folgen, auch nach dem Laden eines Spielstands.
func reanchor_town(k: int) -> bool:
	var id := "U%d" % k
	if not nodes.has(id) or not sim.town_ready(k):
		return false
	var target := _substation_cell(k)
	if _dist(nodes[id].cell, target) <= 8:
		return false   # bewusst gewaehlt: ein Umspannwerk darf ein paar Felder neben dem Rathaus stehen
	nodes[id].cell = target
	for e in edges:
		if str(e.a) != id and str(e.b) != id:
			continue
		var a: Vector2i = nodes[str(e.a)].cell
		var b: Vector2i = nodes[str(e.b)].cell
		var route: Array = line_cells(a, b)
		e.cells = route.map(func(c): return [c.x, c.y])
		e.len = route.size()
	for project_id in planned:
		var p: Dictionary = planned[project_id]
		if str(p.get("a", "")) != id and str(p.get("b", "")) != id:
			continue
		p.station = [target.x, target.y]
		var route: Array = line_cells(nodes[str(p.a)].cell, nodes[str(p.b)].cell)
		p.cells = route.map(func(c): return [c.x, c.y])
	_dirty = true
	_local_cache.erase(k)
	_local_keys.erase(k)
	return true


func add_edge(a: String, b: String, route: Array = []) -> Dictionary:
	var cells := route if not route.is_empty() else line_cells(nodes[a].cell, nodes[b].cell)
	var e := {"id": "L%d" % (edges.size() + 1), "a": a, "b": b, "cells": cells.map(func(c): return [c.x, c.y]), "len": cells.size(), "state": "ok"}
	edges.append(e)
	_dirty = true
	_local_keys.clear()
	return e


## Drei begruendbare Bauvarianten fuer den Buergermeister. Kosten und Siedlungskonflikte
## stammen aus der tatsaechlichen Trasse, nicht aus einem pauschalen Ausbauknopf.
func connection_options(k: int) -> Array:
	ensure()
	var target := "U%d" % k
	if not nodes.has(target) or planned.values().any(func(p): return str(p.b) == target):
		return []
	var connected_now := connected(k)
	if connected_now:
		var safe := true
		for e in edges:
			if not _bfs("KW", str(e.id)).has(target):
				safe = false
				break
		if safe:
			return []
	var stations: Array = [nodes[target].cell] if connected_now else _station_candidates(k)
	var options: Array = []
	for origin in nodes:
		if origin == target or (origin != "KW" and not connected(int(nodes[origin].town))):
			continue
		if edges.any(func(e): return (str(e.a) == origin and str(e.b) == target) or (str(e.b) == origin and str(e.a) == target)):
			continue
		for station in stations:
			for variant in 3:
				var cells := _line_route(nodes[origin].cell, station, variant)
				var conflicts := _route_conflicts(cells)
				var cost := snappedf(float(cells.size()) * LINE_EUR_PER_CELL + float(conflicts) * 160.0, 100.0)
				options.append({"id": "%s:%d:%d:%d" % [origin, station.x, station.y, variant], "a": origin, "b": target,
					"station": [station.x, station.y], "cells": cells.map(func(q): return [q.x, q.y]), "felder": cells.size(),
					"kosten": cost, "tage": maxi(LINE_DAYS_MIN, ceili(float(cells.size()) / float(LINE_CELLS_PER_DAY))),
					"konflikte": conflicts, "art": "Ringschluss" if connected_now else "Stadtanschluss"})
	options.sort_custom(func(a, b): return float(a.kosten) < float(b.kosten))
	var out: Array = []
	for option in options:
		if out.size() >= 3:
			break
		if not out.any(func(x): return x.cells == option.cells):
			out.append(option)
	return out


func option_brief(k: int) -> Array:
	return connection_options(k).map(func(o): return {"id": o.id, "art": o.art, "von": _label(str(o.a)), "umspannwerk": o.station,
		"felder": o.felder, "kosten": o.kosten, "tage": o.tage, "konflikte": o.konflikte})


func request_line(k: int, option_id: String, reason: String) -> Dictionary:
	var option := {}
	for o in connection_options(k):
		if str(o.id) == option_id:
			option = o
			break
	if option.is_empty():
		return {"ok": false, "msg": "Trasse nicht verfügbar. Wähle eine ID aus stromtrassen."}
	var M: Mayor = sim.towns.mayor(k)
	if M.available_budget() < float(option.kosten):
		return {"ok": false, "msg": "Trasse kostet %s, verfügbar %s." % [Catalog.money(float(option.kosten)), Catalog.money(M.available_budget())]}
	var vote: Dictionary = M.civic_vote("versorgung", float(option.kosten))
	if not bool(vote.passed):
		return {"ok": false, "msg": "Rat lehnt die Stromtrasse ab: %s" % str(vote.text)}
	var prj: Dictionary = M.add_works_project("trasse", "%s|%s" % [option.a, option.b], float(option.kosten), int(option.tage),
		{"stahl": maxi(1, int(option.felder) / 8), "beton": maxi(1, int(option.felder) / 12)},
		"Stromtrasse %s: %s" % [option.art, reason.left(140)])
	planned[str(prj.id)] = {"a": option.a, "b": option.b, "cells": option.cells, "station": option.station}
	sim.log_event("%s: %s zum Umspannwerk beauftragt: %d Felder, %s, %d Tage. %s" % [sim.towns.name_of(k),
		option.art, int(option.felder), Catalog.money(float(option.kosten)), int(option.tage), reason.left(100)], "info")
	return {"ok": true, "msg": "Trasse %s als Projekt %s ausgeschrieben." % [option.id, prj.id], "projekt": prj.id}


func _station_candidates(k: int) -> Array:
	var C: CityData = sim.city
	var base: Vector2i = nodes["U%d" % k].cell
	var out: Array = []
	for d in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4),
		Vector2i(4, 4), Vector2i(-4, 4), Vector2i(4, -4), Vector2i(-4, -4), Vector2i.ZERO]:
		var q: Vector2i = base + d
		if C.inside(q) and C.building_at[C.idx(q)] < 0 and not C.is_road(q) and C.g(q) != CityData.G.WATER and C.town_of(q) == k and _road_near(q).x >= 0:
			out.append(q)
		if out.size() >= 4:
			break
	if out.is_empty():
		out.append(base)
	return out


func _line_route(a: Vector2i, b: Vector2i, variant: int) -> Array:
	if variant == 0:
		return line_cells(a, b)
	var mid := (a + b) / 2
	var delta := b - a
	var normal := Vector2i(-signi(delta.y), signi(delta.x)) * (12 if variant == 1 else -12)
	var via := mid + normal
	var first := line_cells(a, via)
	first.pop_back()
	return first + line_cells(via, b)


func _route_conflicts(cells: Array) -> int:
	var C: CityData = sim.city
	var n := 0
	for i in range(1, cells.size() - 1, MAST_EVERY):
		var q: Vector2i = cells[i]
		if not C.inside(q) or C.g(q) == CityData.G.WATER:
			n += 4
		elif C.building_at[C.idx(q)] >= 0:
			n += 3
	return n


## Ortsnetz auf den befahrbaren Strassen. Damit ist ein Parzellen-Haekchen allein
## kein Stromanschluss fuer einen abgetrennten neuen Stadtteil.
func local_roads(k: int) -> Dictionary:
	ensure()
	var node := "U%d" % k
	if not nodes.has(node):
		return {}
	var C: CityData = sim.city
	var key := "%d:%d:%s" % [k, C.road_count, str(nodes[node].cell)]
	if str(_local_keys.get(k, "")) != key:
		_local_cache.erase(k)
		_local_keys[k] = key
	if _local_cache.has(k):
		return _local_cache[k]
	var root: Vector2i = nodes[node].cell
	var start := Vector2i(-1, -1)
	var best := 999
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var q := root + Vector2i(dx, dy)
			var dist := absi(dx) + absi(dy)
			if dist < best and C.is_road(q):
				best = dist
				start = q
	var found := {}
	if start.x >= 0:
		found[start] = true
		var todo: Array = [start]
		var i := 0
		while i < todo.size() and i < 20000:
			var here: Vector2i = todo[i]
			i += 1
			for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var next: Vector2i = here + d
				if not found.has(next) and C.is_road(next) and sim.serves_town(next, k):
					found[next] = true
					todo.append(next)
	_local_cache[k] = found
	return found


func distributed(k: int, building_id: int) -> bool:
	var b: Dictionary = sim.city.building(building_id)
	if b.is_empty():
		return false
	return local_roads(k).has(Vector2i(b.road))


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
	var powered_before: Array = []
	for k in maxi(1, sim.towns.count()):
		if connected(k):
			powered_before.append(k)
	set_state(id, "defekt")
	e["cause"] = cause
	repairs[id] = {"cell": [site.x, site.y], "road": [road.x, road.y], "town": -1, "vehicle": -1, "since": sim.game_min, "cause": cause, "getrennt": 0}
	stats.schaeden = int(stats.schaeden) + 1
	var off: Array = []
	for k in powered_before:
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
	if bool(rp.get("urgent", false)):
		v["urgent"] = true


## Buergermeister kann bei einem Ausfall einen zusaetzlichen Bereitschaftstrupp bezahlen.
## Der laufende Netztrupp arbeitet dann vor Ort schneller; die Anfahrt bleibt sichtbar.
func prioritize_repair(k: int, id: String) -> Dictionary:
	if not repairs.has(id):
		return {"ok": false, "msg": "Diese Trasse ist nicht defekt."}
	var rp: Dictionary = repairs[id]
	if bool(rp.get("urgent", false)):
		return {"ok": false, "msg": "Trasse %s hat bereits Vorrang." % id}
	var M: Mayor = sim.towns.mayor(k)
	var cost := 5000.0
	if M.available_budget() < cost:
		return {"ok": false, "msg": "Für zusätzliche Netzkräfte fehlen %s." % Catalog.money(cost)}
	sim.economy.transfer(Towns.account_of(k), "S0", cost)
	rp["urgent"] = true
	for v in sim.fleet.vehicles:
		if v.kind == "netztrupp" and str(v.get("edge", "")) == id:
			v["urgent"] = true
			if str(v.phase) == "arbeit":
				v.until = maxf(sim.game_min + 1.0, float(v.until) - REPAIR_MIN * 0.5)
	sim.log_event("%s priorisiert die Reparatur der Stromtrasse %s: zusätzlicher Bereitschaftstrupp, %s." % [sim.towns.name_of(k), id, Catalog.money(cost)], "info")
	return {"ok": true, "msg": "Reparatur %s hat Vorrang; Netztrupp arbeitet schneller." % id}


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
	if p.has("station") and str(p.b).begins_with("U"):
		var cell: Array = p.station
		nodes[str(p.b)].cell = Vector2i(int(cell[0]), int(cell[1]))
	var route: Array = (p.get("cells", []) as Array).map(func(a): return Vector2i(int(a[0]), int(a[1])))
	var e := add_edge(str(p.a), str(p.b), route)
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
		"reparaturen": repairs.keys().map(func(id): return {"trasse": id, "ursache": str(repairs[id].cause),
			"priorisiert": bool(repairs[id].get("urgent", false)), "trupp": sim.towns.name_of(int(repairs[id].town)) if int(repairs[id].town) >= 0 else "-"}),
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
