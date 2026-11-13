class_name RailNet
extends RefCounted
## Eisenbahnnetz der Region (Auftrag 22 Phase 6 Schritt 1, docs/INFRASTRUCTURE.md). Jede Stadt hat ab Spielbeginn einen Bahnhof:
## ein Gleis (STATION_LEN Felder), einen Bahnsteig daneben und das Empfangsgebaeude dahinter (Richtung Ortsmitte, an einer Strasse).
## Die Strecke verbindet die Bahnhoefe nacheinander (Reihenfolge nach Lage um die Kartenmitte, wie die Autobahn) als eingleisige
## Hauptbahn: lange Geraden mit rechtwinkligen Bogen auf dem Grobraster der Autobahnplanung (RegionalProjects._hw_route), kurze
## Zufuehrungen von den Gleisenden per feiner Wegsuche. Gleisfelder werden Boden RAIL (kein Bau darauf, Baeume gerodet); wo die Strecke
## eine Strasse quert, bleibt die Strasse und es entsteht ein Bahnuebergang. Fluesse und Buchten quert sie auf Bruecken, Berge im
## Tunnel (beides teuer in der Wegsuche, damit nur gebaut wird, wo kein Landweg besteht); dort bleibt der Boden unveraendert.
## Das Netz entsteht beim ersten Tageslauf (Laufzeitbau wie die Startausstattung) und wird beim Laden wieder auf den Boden gelegt.

signal built(cells: Array)   # neue Gleis-/Bahnsteigfelder (Darstellung)

const STATION_LEN := 10       # Gleis und Bahnsteig (Felder)
const BUILDING_LEN := 4       # Empfangsgebaeude 4x2 (bzw. 2x4)
const SEARCH_MIN := 8         # Suchradius um die Ortsmitte (Felder)
const SEARCH_MAX := 90
const LEAD := 4               # so viele Felder hinter jedem Gleisende muessen frei sein (Ausfahrt geradeaus)
const ROAD_NEAR := 3          # Strasse hoechstens so weit vom Empfangsgebaeude
const ROAD_COST := 4.0        # Wegsuche: Strasse queren ja, laengs nein
const BLOCK := 4              # Grobraster wie die Autobahn (RegionalProjects.HW_BLOCK)
const BLOCK_ROAD := 3.0       # Kosten je Grobblock
const BLOCK_WATER := 10.0     # Bruecke
const BLOCK_MOUNTAIN := 14.0  # Tunnel

var sim
var stations := {}            # Stadt (str) -> {town, name, orient: "h"|"v", rect, track, platform, building, ends}
var edges: Array = []         # [{id, a, b, cells: [[x, y]...] (Gleisende a -> Gleisende b), crossings: [[x, y]...], len}]
var tried := false
var cells := {}               # Vector2i -> "gleis"|"ausweiche"|"bahnsteig"|"uebergang"|"bruecke"|"tunnel" (abgeleitet, nicht gespeichert)
var failed: Array = []        # nicht baubare Abschnitte [{von, nach, grund}]
var _grid0 := {}              # Grobraster vor dem Bau (nur waehrend ensure)
var _open := {}               # Grobbloecke, die mit dem offenen Land (Kartenmitte) verbunden sind (nur waehrend ensure)


func setup(simulation) -> void:
	sim = simulation
	if not enabled():
		return
	sim.day_changed.connect(func(_d): ensure())


func enabled() -> bool:
	return sim != null and sim.towns != null and sim.towns.is_region() and sim.towns.count() >= 2


func is_built() -> bool:
	return not stations.is_empty()


func station_of(k: int) -> Dictionary:
	return stations.get(str(k), {})


func is_rail(q: Vector2i) -> bool:
	return cells.has(q)


# ------------------------------------------------------------------ Aufbau
func ensure() -> void:
	if tried or not enabled():
		return
	tried = true
	_grid0 = _blocks()
	_open = _open_land(_grid0)
	for t in sim.towns.list:
		var st := _place_station(int(t.id))
		if not st.is_empty():
			stations[str(int(t.id))] = st
	var order: Array = stations.keys().map(func(k): return int(k))
	var mid := Vector2(sim.city.size, sim.city.size) * 0.5
	order.sort_custom(func(a, b): return (Vector2(sim.towns.get_t(a).center) - mid).angle() < (Vector2(sim.towns.get_t(b).center) - mid).angle())
	var made: Array = []
	for st in stations.values():
		made.append_array(_apply(st.track + st.platform + st.get("loop", [])))
	_index()
	for i in order.size() - 1:
		var e := _route(int(order[i]), int(order[i + 1]))
		if e.is_empty():
			continue
		edges.append(e)
		made.append_array(_apply(e.cells))
		_index()
	if not stations.is_empty():
		var total := 0
		for e in edges:
			total += int(e.len)
		sim.log_event("Eisenbahn: %d Bahnhöfe, %d Streckenabschnitte mit %d Gleisfeldern und %d Bahnübergängen in Betrieb." % [stations.size(), edges.size(),
			total, edges.reduce(func(acc, e): return acc + e.crossings.size(), 0)], "info")
	_grid0 = {}
	_open = {}
	built.emit(made)


## Grobbloecke, die von der Kartenmitte aus (Breitensuche ueber passierbare Bloecke) erreichbar sind. Ein Bahnhof, dessen Gleisenden
## nur in eine von Bebauung und Kaianlagen eingeschlossene Tasche fuehren, waere nicht anschliessbar (gemessen 13.11., Seed 4242).
func _open_land(grid: Dictionary) -> Dictionary:
	var nb: int = grid.nb
	var cost: PackedFloat32Array = grid.cost
	var start := Vector2i(nb / 2, nb / 2)
	var best := INF
	for by in nb:
		for bx in nb:
			var c := cost[by * nb + bx]
			if c > 0.0 and c < BLOCK_ROAD:
				var d := Vector2(bx, by).distance_squared_to(Vector2(nb / 2, nb / 2))
				if d < best:
					best = d
					start = Vector2i(bx, by)
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= nb or q.y >= nb or seen.has(q) or cost[q.y * nb + q.x] <= 0.0:
				continue
			seen[q] = true
			todo.append(q)
	return seen


## Bahnhof der Stadt k: freies Rechteck STATION_LEN x 5 moeglichst nahe der Ortsmitte; Ausweich- und Hauptgleis aussen, Bahnsteig, Empfangsgebaeude
## zur Ortsmitte hin an einer Strasse.
func _place_station(k: int) -> Dictionary:
	var c: Vector2i = sim.towns.get_t(k).center
	for r in range(SEARCH_MIN, SEARCH_MAX, 2):
		for p in _ring(c, r):
			for orient in ["h", "v"]:
				var lay := _layout(p, orient, c)
				if not _free(lay):
					continue
				var st := _build_station(k, lay)
				if not st.is_empty():
					return st
	failed.append({"von": k, "nach": -1, "grund": "kein Bauplatz für den Bahnhof"})
	sim.log_event("%s: kein Bauplatz für den Bahnhof gefunden." % sim.towns.name_of(k), "warn")
	return {}


static func _ring(c: Vector2i, r: int) -> Array:
	var out: Array = []
	for d in range(-r, r + 1, 2):
		out.append(c + Vector2i(d, -r))
		out.append(c + Vector2i(d, r))
		out.append(c + Vector2i(-r, d))
		out.append(c + Vector2i(r, d))
	return out


## Lage eines Bahnhofs mit Mittelpunkt p (Schritt 2: 5 Reihen). Von aussen nach innen: Ausweichgleis (STATION_LEN - 2 Felder, an
## beiden Enden per Weiche ans Hauptgleis), Hauptgleis, Bahnsteig, Empfangsgebaeude (2 Reihen) zur Ortsmitte hin.
## Achse u laeuft laengs des Gleises, v quer (v = 0 aussen); "h": u = x, "v": u = y.
static func _layout(p: Vector2i, orient: String, center: Vector2i) -> Dictionary:
	var L := STATION_LEN
	var horiz := orient == "h"
	var inward := (center.y >= p.y) if horiz else (center.x >= p.x)   # Ortsmitte liegt bei groesserem v
	var u0 := (p.x if horiz else p.y) - L / 2
	var v0 := (p.y if horiz else p.x) - 2
	var row := func(k: int) -> int: return v0 + k if inward else v0 + 4 - k   # k: 0 Ausweiche, 1 Gleis, 2 Bahnsteig, 3/4 Gebaeude
	var cell := func(u: int, v: int) -> Vector2i: return Vector2i(u, v) if horiz else Vector2i(v, u)
	var track: Array = []
	var platform: Array = []
	var loop: Array = []
	for u in range(u0, u0 + L):
		track.append(cell.call(u, row.call(1)))
		platform.append(cell.call(u, row.call(2)))
		if u > u0 and u < u0 + L - 1:
			loop.append(cell.call(u, row.call(0)))
	var bv: int = mini(row.call(3), row.call(4))
	var bu := u0 + (L - BUILDING_LEN) / 2
	var brect := Rect2i(bu, bv, BUILDING_LEN, 2) if horiz else Rect2i(bv, bu, 2, BUILDING_LEN)
	var ends := [cell.call(u0 - 1, row.call(1)), cell.call(u0 + L, row.call(1))]
	var lead: Array = []
	for i in LEAD:
		lead.append(cell.call(u0 - 1 - i, row.call(1)))
		lead.append(cell.call(u0 + L + i, row.call(1)))
	var rect := Rect2i(u0, v0, L, 5) if horiz else Rect2i(v0, u0, 5, L)
	var ld: Vector2i = cell.call(0, row.call(0) - row.call(1))   # Richtung Hauptgleis -> Ausweichgleis
	return {"orient": orient, "rect": rect, "track": track, "platform": platform, "loop": loop, "loop_dir": ld, "building": brect, "ends": ends, "lead": lead}


func _blocked(q: Vector2i, allow_road := false) -> bool:
	var C: CityData = sim.city
	if not C.inside(q):
		return true
	var i := C.idx(q)
	if C.building_at[i] != -1 or (C.height.size() > 0 and C.height[i] > 0):
		return true
	var g: int = C.ground[i]
	if g == CityData.G.ROAD:
		return not allow_road
	if g in [CityData.G.WATER, CityData.G.RAIL, CityData.G.QUAY, CityData.G.RUNWAY, CityData.G.APRON, CityData.G.PARKING]:
		return true
	return sim.access != null and sim.access.reserved(q)


func _free(lay: Dictionary) -> bool:
	var r: Rect2i = lay.rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if _blocked(Vector2i(x, y)):
				return false
	for q in lay.lead:
		if _blocked(q, true):
			return false
	if sim.civic != null and not sim.civic._cells_free(r):
		return false
	if not _open.is_empty() and not lay.ends.any(func(e): return _open.has(sim.regional._hw_near_block(_grid0, e))):
		return false
	var br: Rect2i = lay.building
	var C: CityData = sim.city
	for y in range(br.position.y - ROAD_NEAR, br.end.y + ROAD_NEAR):
		for x in range(br.position.x - ROAD_NEAR, br.end.x + ROAD_NEAR):
			var q := Vector2i(x, y)
			if C.inside(q) and C.is_road(q) and not r.has_point(q):
				return true
	return false


func _build_station(k: int, lay: Dictionary) -> Dictionary:
	var bt := "train_station" if lay.orient == "h" else "train_station_v"
	var nm := "Bahnhof %s" % sim.towns.name_of(k)
	var b: Dictionary = sim.events._add_building(bt, lay.building, nm)
	if b.is_empty():
		return {}
	b["role"] = "station"
	b["town"] = k
	var style: String = sim.municipal.style_of(k) if sim.municipal != null else "modern"
	var v := absi(hash("bahnhof%d_%d" % [k, int(sim.city.seed_value)])) % 6
	b["sprite"] = "pub_%s_%d_%s" % ["bf" if lay.orient == "h" else "bfv", v, style]
	for ab in sim.events.added_buildings:   # Laden legt das Gebaeude mit genau diesem Bild wieder an
		if int(ab.x) == int(b.x) and int(ab.y) == int(b.y) and str(ab.type) == bt:
			ab["sprite"] = b.sprite
	sim.events.buildings_added.emit([b.id])
	var r: Rect2i = lay.rect
	return {"town": k, "name": nm, "orient": lay.orient, "rect": [r.position.x, r.position.y, r.size.x, r.size.y],
		"track": lay.track.map(func(q): return [q.x, q.y]), "platform": lay.platform.map(func(q): return [q.x, q.y]),
		"loop": lay.loop.map(func(q): return [q.x, q.y]), "loop_dir": [lay.loop_dir.x, lay.loop_dir.y],
		"building": int(b.id), "ends": lay.ends.map(func(q): return [q.x, q.y])}


## Strecke zwischen den Bahnhoefen a und b: naechstgelegene Gleisenden, Grobraster wie die Autobahn, Zufuehrungen fein.
func _route(a: int, b: int) -> Dictionary:
	var sa: Dictionary = stations[str(a)]
	var sb: Dictionary = stations[str(b)]
	var pairs: Array = []
	for ea in sa.ends:
		for eb in sb.ends:
			var d := Vector2(int(ea[0]), int(ea[1])).distance_to(Vector2(int(eb[0]), int(eb[1])))
			if _end_used(ea) or _end_used(eb):
				d += 40.0   # durchgehender Bahnhof: zweite Strecke moeglichst am anderen Ende
			pairs.append([d, Vector2i(int(ea[0]), int(ea[1])), Vector2i(int(eb[0]), int(eb[1]))])
	pairs.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var astar := _astar()
	var R = sim.regional
	var grid: Dictionary = _blocks()
	var ja := Vector2i(-1, -1)
	var jb := Vector2i(-1, -1)
	var coarse: Array = []
	var spur_a := PackedVector2Array()
	var spur_b := PackedVector2Array()
	for pr in pairs:   # naechstes Endenpaar zuerst; liegt ein Ende in einer Tasche, das naechste Paar
		ja = pr[1]
		jb = pr[2]
		var ba: Vector2i = R._hw_near_block(grid, ja)
		var bb: Vector2i = R._hw_near_block(grid, jb)
		if ba.x < 0 or bb.x < 0:
			continue
		coarse = R._hw_route(grid, ba, bb)
		if coarse.is_empty():
			continue
		astar.set_point_solid(ja, false)
		astar.set_point_solid(jb, false)
		spur_a = astar.get_id_path(ja, R._hw_center(ba))
		spur_b = astar.get_id_path(R._hw_center(bb), jb)
		if not spur_a.is_empty() and not spur_b.is_empty():
			break
		coarse = []
	if coarse.is_empty():
		return _fail(a, b, "kein Weg (eingeschlossene Gleisenden oder Kai/Flugfeld dazwischen)")
	var path: Array = []
	for p in spur_a:
		path.append(Vector2i(p))
	for i in coarse.size() - 1:
		var c0: Vector2i = R._hw_center(coarse[i])
		var c1: Vector2i = R._hw_center(coarse[i + 1])
		var d := Vector2i(signi(c1.x - c0.x), signi(c1.y - c0.y))
		var q := c0
		while q != c1:
			path.append(q)
			q += d
	path.append(R._hw_center(coarse[-1]))
	for p in spur_b:
		path.append(Vector2i(p))
	# zusammenhaengende Zellfolge ohne Doppelungen (Schleifen an den Uebergaengen Zufuehrung/Hauptstrecke abschneiden)
	var seq: Array = []
	var pos := {}
	for q in path:
		if pos.has(q):
			var cut: int = pos[q]
			for j in range(cut + 1, seq.size()):
				pos.erase(seq[j])
			seq.resize(cut + 1)
			continue
		if not seq.is_empty() and absi(q.x - seq[-1].x) + absi(q.y - seq[-1].y) != 1:
			var f: Vector2i = seq[-1]   # Luecke (sollte nicht vorkommen): rechtwinklig schliessen
			while f.x != q.x:
				f.x += signi(q.x - f.x)
				if f != q:
					pos[f] = seq.size()
					seq.append(f)
			while f.y != q.y:
				f.y += signi(q.y - f.y)
				if f != q:
					pos[f] = seq.size()
					seq.append(f)
		pos[q] = seq.size()
		seq.append(q)
	var crossings: Array = []
	var bridges := 0
	var tunnels := 0
	for q in seq:
		if sim.city.is_road(q):
			crossings.append([q.x, q.y])
		elif _water(q):
			bridges += 1
		elif _mountain(q):
			tunnels += 1
	return {"id": "S%d" % (edges.size() + 1), "a": a, "b": b, "cells": seq.map(func(q): return [q.x, q.y]), "crossings": crossings, "len": seq.size(),
		"bruecke": bridges, "tunnel": tunnels}


func _water(q: Vector2i) -> bool:
	return sim.city.g(q) == CityData.G.WATER


func _mountain(q: Vector2i) -> bool:
	var C: CityData = sim.city
	return C.height.size() > 0 and C.height[C.idx(q)] > 0


## Grobraster der Hauptstrecke (Format wie RegionalProjects._hw_blocks): 0 = gesperrt (Gebaeude, Kai, Flugfeld, Parkplatz, Bahnhof),
## sonst Kosten je Schritt: Land 1, Strasse BLOCK_ROAD, Wasser (Bruecke) BLOCK_WATER, Berg (Tunnel) BLOCK_MOUNTAIN, vorhandenes Gleis guenstig.
func _blocks() -> Dictionary:
	var C: CityData = sim.city
	var nb: int = C.size / BLOCK
	var cost := PackedFloat32Array()
	cost.resize(nb * nb)
	var station_cells := {}
	for st in stations.values():
		var r := Rect2i(int(st.rect[0]), int(st.rect[1]), int(st.rect[2]), int(st.rect[3]))
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				station_cells[Vector2i(x, y)] = true
	for by in nb:
		for bx in nb:
			var c := 1.0
			for dy in BLOCK:
				for dx in BLOCK:
					var p := Vector2i(bx * BLOCK + dx, by * BLOCK + dy)
					var i := C.idx(p)
					var g: int = C.ground[i]
					if C.building_at[i] >= 0 or station_cells.has(p) or g in [CityData.G.QUAY, CityData.G.RUNWAY, CityData.G.APRON, CityData.G.PARKING]:
						c = 0.0
					elif c > 0.0:
						if g == CityData.G.WATER:
							c = maxf(c, BLOCK_WATER)
						elif C.height.size() > 0 and C.height[i] > 0:
							c = maxf(c, BLOCK_MOUNTAIN)
						elif g == CityData.G.ROAD:
							c = maxf(c, BLOCK_ROAD)
						elif g == CityData.G.RAIL and c == 1.0:
							c = 0.3
				if c == 0.0:
					break
			cost[by * nb + bx] = c
	return {"nb": nb, "cost": cost}


func _end_used(e: Array) -> bool:
	for x in edges:
		var c0: Array = x.cells[0]
		var c1: Array = x.cells[-1]
		if (int(c0[0]) == int(e[0]) and int(c0[1]) == int(e[1])) or (int(c1[0]) == int(e[0]) and int(c1[1]) == int(e[1])):
			return true
	return false


func _fail(a: int, b: int, why: String) -> Dictionary:
	failed.append({"von": a, "nach": b, "grund": why})
	sim.log_event("Eisenbahn: Strecke %s – %s nicht gebaut (%s)." % [sim.towns.name_of(a), sim.towns.name_of(b), why], "warn")
	return {}


## Wegsuche: gesperrt sind Wasser, Kai, Flugfeld, Parkplatz, Berge, Gebaeude und Bahnhofsanlagen; vorhandene Gleise duerfen
## mitbenutzt werden (Gemeinschaftsstrecke), Strassen werden gequert.
func _astar() -> AStarGrid2D:
	var C: CityData = sim.city
	var n := C.size
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			var i := C.idx(p)
			var g: int = C.ground[i]
			if g == CityData.G.RAIL:
				if cells.get(p, "") != "gleis":
					astar.set_point_solid(p, true)   # Bahnsteig und Bahnhofsgleis
			elif g in [CityData.G.WATER, CityData.G.QUAY, CityData.G.RUNWAY, CityData.G.APRON, CityData.G.PARKING] or (C.height.size() > 0 and C.height[i] > 0) or C.building_at[i] >= 0:
				astar.set_point_solid(p, true)
			elif g == CityData.G.ROAD:
				astar.set_point_weight_scale(p, ROAD_COST)
	for st in stations.values():
		for q in st.track:
			astar.set_point_solid(Vector2i(int(q[0]), int(q[1])), true)   # Strecke endet an den Gleisenden, nicht quer durch den Bahnhof
	return astar


## Boden auf RAIL setzen (Strassen bleiben: Bahnuebergang), Baeume roden. Rueckgabe: veraenderte Zellen.
func _apply(list: Array) -> Array:
	var C: CityData = sim.city
	var made: Array = []
	for a in list:
		var q := Vector2i(int(a[0]), int(a[1])) if a is Array else Vector2i(a)
		if not C.inside(q):
			continue
		var i := C.idx(q)
		if C.ground[i] in [CityData.G.ROAD, CityData.G.WATER] or C.building_at[i] >= 0 or (C.height.size() > 0 and C.height[i] > 0):
			continue   # Bahnuebergang, Bruecke, Tunnel: Boden bleibt
		C.ground[i] = CityData.G.RAIL
		if C.blocked[i] == 1:
			C.blocked[i] = 0
			C.trees = C.trees.filter(func(t): return t[0] != q)
		made.append(q)
	return made


func _index() -> void:
	cells.clear()
	for st in stations.values():
		for a in st.track:
			cells[Vector2i(int(a[0]), int(a[1]))] = "gleis"
		for a in st.platform:
			cells[Vector2i(int(a[0]), int(a[1]))] = "bahnsteig"
		for a in st.get("loop", []):
			cells[Vector2i(int(a[0]), int(a[1]))] = "ausweiche"
	for e in edges:
		for a in e.cells:
			var q := Vector2i(int(a[0]), int(a[1]))
			if not cells.has(q):
				cells[q] = "uebergang" if sim.city.is_road(q) else ("bruecke" if _water(q) else ("tunnel" if _mountain(q) else "gleis"))


# ------------------------------------------------------------------ Abfragen, Anzeige, Speichern
## Nachbarn eines Gleisfelds im Netz (fuer die Darstellung): Richtungen zu benachbarten Gleis-/Uebergangsfeldern.
## Ausweichgleise verbinden nur untereinander (die Weichen zeichnet RailView an ihren Enden).
func links(q: Vector2i) -> Array:
	var out: Array = []
	var mine := ["ausweiche"] if cells.get(q, "") == "ausweiche" else ["gleis", "uebergang", "bruecke", "tunnel"]
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if cells.get(q + d, "") in mine:
			out.append(d)
	return out


func length() -> int:
	var n := 0
	for e in edges:
		n += int(e.len)
	return n


func summary() -> Dictionary:
	var st := {}
	for key in stations:
		st[key] = {"name": stations[key].name, "gebaeude": int(stations[key].building)}
	return {"bahnhoefe": st, "abschnitte": edges.map(func(e): return {"id": e.id, "von": sim.towns.name_of(int(e.a)), "nach": sim.towns.name_of(int(e.b)),
		"felder": int(e.len), "bahnuebergaenge": e.crossings.size(), "brueckenfelder": int(e.get("bruecke", 0)), "tunnelfelder": int(e.get("tunnel", 0))}), "gleisfelder": length(), "nicht_gebaut": failed}


func to_dict() -> Dictionary:
	return {"stations": stations, "edges": edges, "tried": tried, "failed": failed}


## Laden: Welt ist neu erzeugt, Empfangsgebaeude kamen ueber EventDirector zurueck; Gleisboden wieder anlegen.
func from_dict(d: Dictionary) -> void:
	stations = d.get("stations", {})
	edges = d.get("edges", [])
	tried = bool(d.get("tried", false))
	failed = d.get("failed", [])
	for st in stations.values():
		_apply(st.track + st.platform + st.get("loop", []))
	for e in edges:
		_apply(e.cells)
	_index()
