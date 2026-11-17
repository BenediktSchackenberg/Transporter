class_name EkoSettle
extends RefCounted
## Wildnis (Benedikt 17.11.2026): "Es gibt am Anfang keine Stadt. Jede KI sucht sich die beste Stelle – in der Naehe vom Wasser?
## An einem Bergwerk? – findet einen sicheren Platz, eroeffnet dort ihren Bauplatz, sichert sich ab und baut dort die Stadt."
##
## Bewertung eines Platzes (score_at): Wasser (Hafen, Siedlerschiff), Lagerstaette in der Naehe (Bergwerk), freie ebene Flaeche,
## Schutz durch Huegel, Weg zur naechsten Strasse; Abstand zu anderen Siedlungen ist Pflicht.
## Gruendung (found): Ort der eigenen Firma (home_town) bekommt Mitte und Gebiet am gewaehlten Platz, Zufahrt zur naechsten Strasse,
## Dorfstrasse, Buergeramt mit Bauhof, Betriebshof der Firma, bei Wasser ein Anleger mit Hafenlager; das Land ringsum wird
## Bauland der neuen Stadt; der Stammsitz entsteht am Ortsrand; ein Buergermeister-Wesen uebernimmt das Amt.

const MIN_TOWN_DIST := 60       # Abstand zu anderen Siedlungen (Mitte zu Mitte)
const MAX_ROAD_DIST := 45       # hoechstens so weit von einer bestehenden Strasse (die Zufahrt baut die Gruendung)
const WATER_R := 10
const HARBOR_R := 6
const DEPOSIT_R := 30
const AREA := 12                # halbe Kantenlaenge der Flaeche, die frei und eben sein muss
const ROAD_COST := 120.0        # EUR je Zufahrtsfeld (aus der Firmenkasse an die Stadtkasse der neuen Stadt)
const FOUND_COST := 25000.0     # Vermessung, Buergeramt, Bauhof (Firma -> neue Stadtkasse)

var w                           # EkoWorld
var _deposit_cells: Array = []  # [[Vector2i, art], ...]


func setup(world) -> void:
	w = world


func _sim():
	return w.sim


func founded(k: int) -> bool:
	return _sim().town_ready(k)


func _deposits() -> Array:
	if _deposit_cells.is_empty():
		var sim = _sim()
		sim.prod.deposit_of("")   # legt die Lagerstaetten an (vor jeder Umwidmung)
		for pid in sim.prod._deposits:
			var p: Dictionary = sim.parcels.parcel(str(pid))
			if not p.is_empty():
				_deposit_cells.append([Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2), str(sim.prod._deposits[pid].art)])
	return _deposit_cells


## Bewertung eines Platzes: {ok, punkte, gruende, grund (wenn nicht ok), wasser, hafen, strasse}
func score_at(cell: Vector2i) -> Dictionary:
	var sim = _sim()
	var C: CityData = sim.city
	var out := {"feld": [cell.x, cell.y], "ok": false, "punkte": 0, "gruende": []}
	if not C.inside(cell) or cell.x < AREA + 2 or cell.y < AREA + 2 or cell.x > C.size - AREA - 3 or cell.y > C.size - AREA - 3:
		out["grund"] = "am Kartenrand"
		return out
	for t in C.towns:
		if bool(t.get("gegruendet", false)) and absi(int(t.center[0]) - cell.x) + absi(int(t.center[1]) - cell.y) < MIN_TOWN_DIST:
			out["grund"] = "zu nah an %s" % t.name
			return out
	if not C.hub.is_empty():
		var hr: Array = C.hub.rect
		if Rect2i(int(hr[0]), int(hr[1]), int(hr[2]), int(hr[3])).grow(20).has_point(cell):
			out["grund"] = "zu nah am Großlager"
			return out
	var free := 0
	var total := 0
	var hills := 0
	var water := 0
	var harbor_water := 0
	for dy in range(-WATER_R - 2, WATER_R + 3):
		for dx in range(-WATER_R - 2, WATER_R + 3):
			var q := cell + Vector2i(dx, dy)
			if not C.inside(q):
				continue
			var i := C.idx(q)
			var core := absi(dx) <= AREA and absi(dy) <= AREA
			var is_water := C.ground[i] == CityData.G.WATER
			if core:
				total += 1
				if not is_water and C.building_at[i] < 0 and (C.height.is_empty() or C.height[i] == 0) and C.ground[i] != CityData.G.ROAD:
					free += 1
			if is_water:
				water += 1
				if absi(dx) <= HARBOR_R and absi(dy) <= HARBOR_R:
					harbor_water += 1
			elif not C.height.is_empty() and C.height[i] > 0:
				hills += 1
	var flat := float(free) / float(maxi(1, total))
	if flat < 0.6:
		out["grund"] = "zu wenig freie, ebene Fläche (%d %%)" % int(flat * 100.0)
		return out
	var road_d := _road_dist(cell, MAX_ROAD_DIST)
	if road_d < 0:
		out["grund"] = "mehr als %d Felder bis zur nächsten Straße" % MAX_ROAD_DIST
		return out
	var pts := 20.0 + 30.0 * (flat - 0.6) / 0.4
	out.gruende.append("Fläche frei und eben %d %%" % int(flat * 100.0))
	if water >= 25:
		pts += 25.0
		out.gruende.append("Wasser in der Nähe" + (" – Anleger möglich (Siedlerschiff)" if harbor_water >= 12 else ""))
	var dep := {}
	var dep_d := 9999
	for d in _deposits():
		var dd: int = absi(d[0].x - cell.x) + absi(d[0].y - cell.y)
		if dd < dep_d:
			dep_d = dd
			dep = {"art": d[1], "dist": dd}
	if dep_d <= DEPOSIT_R:
		pts += 20.0
		out.gruende.append("Lagerstätte %s %d Felder entfernt (Bergwerk)" % [dep.art, dep_d])
	if hills >= 20:
		pts += 10.0
		out.gruende.append("Hügel schützen den Platz")
	pts -= float(road_d) * 0.4
	out.gruende.append("%d Felder bis zur Straße (Zufahrt %s)" % [road_d, Catalog.money(float(road_d) * ROAD_COST)])
	out.ok = true
	out.punkte = int(round(pts))
	out["hafen"] = harbor_water >= 12
	out["strasse"] = road_d
	return out


## Breitensuche ueber Land bis zur naechsten Strasse; -1 wenn weiter als `limit`.
func _road_dist(cell: Vector2i, limit: int) -> int:
	var path := _road_path(cell, limit)
	return path.size() if not path.is_empty() or _sim().city.is_road(cell) else -1


func _road_path(cell: Vector2i, limit: int) -> Array:
	var C: CityData = _sim().city
	if C.is_road(cell):
		return []
	var prev := {cell: cell}
	var frontier: Array = [cell]
	var dist := 0
	while not frontier.is_empty() and dist <= limit:
		var nxt: Array = []
		for p in frontier:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + d
				if prev.has(q) or not C.inside(q):
					continue
				var i := C.idx(q)
				if C.ground[i] == CityData.G.ROAD:
					var out: Array = []
					var c: Vector2i = p
					while c != cell:
						out.push_front(c)
						c = prev[c]
					out.push_front(cell)
					return out
				if C.ground[i] == CityData.G.WATER or C.building_at[i] >= 0 or (not C.height.is_empty() and C.height[i] > 0):
					continue
				prev[q] = p
				nxt.append(q)
		frontier = nxt
		dist += 1
	return []


## Beste Plaetze im Umkreis (fuer die Beobachtung), hoechstens n. Zwischengespeichert je Feld (Beobachtung und naechste Schritte
## fragen kurz hintereinander; ~225 Bewertungen je Aufruf), verworfen bei jeder Gruendung.
var _best_cache := {}
func best_near(cell: Vector2i, radius: int = 70, n: int = 3) -> Array:
	var key := "%d,%d,%d" % [cell.x / 4, cell.y / 4, radius]
	var hit: Dictionary = _best_cache.get(key, {})
	if not hit.is_empty() and float(_sim().game_min) - float(hit.t) < 120.0:
		return (hit.r as Array).slice(0, n)
	if _best_cache.size() > 64:
		_best_cache.clear()
	var cands: Array = []
	for dy in range(-radius, radius + 1, 10):
		for dx in range(-radius, radius + 1, 10):
			var sc := score_at(cell + Vector2i(dx, dy))
			if sc.ok:
				cands.append(sc)
	cands.sort_custom(func(a, b): return int(a.punkte) > int(b.punkte))
	_best_cache[key] = {"t": float(_sim().game_min), "r": cands.slice(0, 5)}
	return cands.slice(0, n)


## Gruendung durch das Wesen b mit Firma cid am Feld cell.
func found(b: Dictionary, cid: int, cell: Vector2i) -> Dictionary:
	var sim = _sim()
	var C: CityData = sim.city
	var k: int = sim.companies[cid].home_town
	if founded(k):
		return {"ok": false, "msg": "Deine Siedlung %s ist schon gegründet." % sim.towns.name_of(k)}
	var sc := score_at(cell)
	if not sc.ok:
		return {"ok": false, "msg": "Hier geht keine Siedlung: %s." % str(sc.get("grund", "")), "bewertung": sc}
	var path := _road_path(cell, MAX_ROAD_DIST)
	var cost := FOUND_COST + float(path.size()) * ROAD_COST
	var c = sim.company(cid)
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Gründung kostet %s (Vermessung, Bürgeramt, Zufahrt), die Firma hat %s." % [Catalog.money(cost), Catalog.money(c.ledger.cash)]}
	# Ortsmitte und Gebiet: town_of (naechste Mitte) ordnet ab jetzt alles hier der neuen Stadt zu
	var t: Dictionary = C.towns[k]
	t.center = [cell.x, cell.y]
	t.rect = [cell.x - 23, cell.y - 24, 46, 48]
	t["gegruendet"] = true
	_best_cache.clear()
	# Zufahrt und Dorfstrasse (12 Felder quer zur Zufahrt)
	var roads: Array = []
	for q in path:
		roads.append(q)
	var dir := Vector2i(1, 0) if path.size() < 2 or path[1].y != path[0].y else Vector2i(0, 1)
	for i in range(-8, 9):
		var q: Vector2i = cell + dir * i
		if C.inside(q) and C.ground[C.idx(q)] != CityData.G.WATER and C.building_at[C.idx(q)] < 0 and (C.height.is_empty() or C.height[C.idx(q)] == 0):
			roads.append(q)
	sim.access._apply_cells(roads)
	sim.access._fields.clear()
	sim.access._cache.clear()
	var nm: String = str(t.name)
	var side := Vector2i(dir.y, dir.x)   # quer zur Dorfstrasse
	var hall := _place("townhall", cell + side * 2 + dir * -6, cell + side * 6 + dir * -2, "Bürgeramt %s" % nm)
	var bauhof := _place("freight_shed", cell - side * 5 + dir * -7, cell - side * 1 + dir * -1, "Städtischer Bauhof")
	var yard := _place("freight_shed", cell + side * 2 + dir * 2, cell + side * 6 + dir * 8, "%s (Betriebshof)" % c.company_name)
	if hall < 0 or bauhof < 0:
		return {"ok": false, "msg": "Bürgeramt passt hier nicht an die Dorfstraße – anderen Platz wählen."}
	t.town_hall = hall
	t.bauhof = bauhof
	var harbor := -1
	if bool(sc.get("hafen", false)):
		harbor = _harbor_at(cell, nm)
	if harbor >= 0:
		t.harbor = harbor
		var H = sim.towns.harbor(k)
		H.building = harbor
		H.enabled = true
		if not sim.day_changed.is_connected(H.on_day):
			sim.day_changed.connect(H.on_day)
	sim.towns.depot(k).activate(bauhof)
	if yard >= 0:
		c.depots.push_front(yard)
		sim.depot_owner[yard] = cid
	# Geld: Firma -> neue Stadtkasse
	c.ledger.book("property_costs", -cost, true, "Gründung %s (Bürgeramt, Zufahrt %d Felder)" % [nm, path.size()], sim.game_min, Towns.account_of(k))
	# Bauland: freies oeffentliches Land ringsum gehoert der neuen Stadt
	for p in sim.parcels.items.values():
		var pc := Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)
		var d: int = absi(pc.x - cell.x) + absi(pc.y - cell.y)
		if d <= 26 and str(p.state) == "frei" and Towns.is_public(str(p.owner)):
			p.owner = Towns.owner_of(k)
			if str(p.zone) not in ["korridor", "gruen"]:
				p.zone = "wohnen" if d <= 14 else "mischgebiet"
			sim.parcels._touch(p)
	sim.parcels.sync_buildings()
	sim.events.buildings_added.emit([hall, bauhof] + ([yard] if yard >= 0 else []) + ([harbor] if harbor >= 0 else []))
	sim.settlements[str(k)] = {"center": t.center, "rect": t.rect, "roads": roads.map(func(q): return [q.x, q.y])}
	carve_plots(k, roads, 10)   # Baugrundstuecke an Dorfstrasse und Zufahrt
	# Stammsitz am Ortsrand, Buergermeister uebernimmt das Amt
	w.estates.assign_near(str(b.name), cell)
	for n in w.beings:
		var o: Dictionary = w.beings[n]
		if int(o.get("amt", -1)) == k:
			o.mover.pos = C.tile_center(C.building(hall).walk)
			w._event(o, "Die Siedlung %s ist gegründet – du bist Bürgermeister, dein Amtssitz ist das Bürgeramt." % nm)
	sim.log_event("%s gründet die Siedlung %s (%s)." % [b.name, nm, ", ".join(sc.gruende)], "good", cid)
	return {"ok": true, "msg": "Siedlung %s gegründet: Bürgeramt, Bauhof, Betriebshof%s, Zufahrt %d Felder. Kosten %s. Jetzt Wohnhäuser bauen (haus_bauen) – mit Wohnraum kommen Siedler." % [
		nm, ", Anleger" if harbor >= 0 else "", path.size(), Catalog.money(cost)], "stadt": k, "bewertung": sc}


## Firma {aktion: {action: "strasse_bauen", bis: [x, y]}} – Strasse vom Feld `bis` zur naechsten bestehenden Strasse (hoechstens
## ROAD_MAX Felder). Je Feld ROAD_COST aus der Firmenkasse (an die eigene Stadt) und ROAD_KIES Kies vom eigenen Betriebshof.
const ROAD_MAX := 30
const ROAD_KIES := 2
func build_road(b: Dictionary, cid: int, a: Dictionary) -> Dictionary:
	var sim = _sim()
	var C: CityData = sim.city
	var k: int = sim.companies[cid].home_town
	if not founded(k):
		return {"ok": false, "msg": "Erst eine Siedlung gründen (Siedlung {feld: [x, y]})."}
	var f = a.get("bis", a.get("feld", []))
	if not (f is Array) or (f as Array).size() < 2:
		return {"ok": false, "msg": "strasse_bauen braucht bis: [x, y] – dort soll die Straße hinführen (z. B. an ein Grundstück)."}
	var cell := Vector2i(int(f[0]), int(f[1]))
	if C.town_of(cell) != k:
		return {"ok": false, "msg": "Feld %s liegt nicht im Gebiet deiner Stadt %s." % [str(f), sim.towns.name_of(k)]}
	var path := _road_path(cell, ROAD_MAX)
	if path.is_empty():
		return {"ok": false, "msg": "Von %s aus ist keine Straße in %d Feldern erreichbar (Wasser, Berg, Gebäude?)." % [str(f), ROAD_MAX] if not C.is_road(cell) else "Dort ist schon Straße."}
	var c = sim.company(cid)
	var acct := "C%d" % cid
	var dep := int(c.depots[0])
	var kies: int = path.size() * ROAD_KIES
	var have: int = sim.stock.available("kies", acct, dep)
	if have < kies:
		return {"ok": false, "msg": "%d Felder Straße brauchen %d Kies auf deinem Betriebshof (da: %d). Firma {aktion: {action: \"hub_buy\", item: \"kies\", qty: %d}} und mit dem LKW holen." % [
			path.size(), kies, have, kies - have]}
	var cost := float(path.size()) * ROAD_COST
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Straßenbau kostet %s, Kasse %s." % [Catalog.money(cost), Catalog.money(c.ledger.cash)]}
	sim.stock.consume("kies", kies, acct, dep, "Straßenbau", sim.game_min)
	c.ledger.book("property_costs", -cost, true, "Straßenbau %d Felder in %s" % [path.size(), sim.towns.name_of(k)], sim.game_min, Towns.account_of(k))
	sim.access._apply_cells(path)
	sim.access._fields.clear()
	sim.access._cache.clear()
	var st: Dictionary = sim.settlements.get(str(k), {})
	st["roads"] = (st.get("roads", []) as Array) + path.map(func(q): return [q.x, q.y])
	sim.settlements[str(k)] = st
	var plots := carve_plots(k, path, 6)
	sim.log_event("%s baut %d Felder Straße in %s." % [c.company_name, path.size(), sim.towns.name_of(k)], "info", cid)
	return {"ok": true, "msg": "%d Felder Straße gebaut (%s, %d Kies), %d neue Baugrundstücke daran." % [path.size(), Catalog.money(cost), kies, plots.size()]}


## Baugrundstuecke (9 x 8 Felder) beidseits entlang der Strassenzellen anlegen, jedes 9. Feld; hoechstens `limit`.
const PLOT := Vector2i(9, 8)
func carve_plots(k: int, cells: Array, limit: int = 8) -> Array:
	var sim = _sim()
	var C: CityData = sim.city
	var st: Dictionary = sim.settlements.get(str(k), {})
	var have: Array = (st.get("plots", []) as Array).map(func(a): return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3])))
	var made: Array = []
	for i in cells.size():
		if made.size() >= limit:
			break
		var c: Vector2i = cells[i]
		var offs: Array = []   # Grundstueck beruehrt die Strassenzelle; entlang der Strasse verschoben (17.11.: vier feste Lagen fanden in Moewenstrand nichts)
		for t in range(0, PLOT.y, 2):
			offs.append(Vector2i(1, -t))
			offs.append(Vector2i(-PLOT.x, -t))
		for t in range(0, PLOT.x, 2):
			offs.append(Vector2i(-t, 1))
			offs.append(Vector2i(-t, -PLOT.y))
		for o in offs:
			var r := Rect2i(c + o, PLOT)
			if have.any(func(h): return h.intersects(r)) or not _plot_free(r):
				continue
			sim.parcels.carve(r, "wohnen", Towns.owner_of(k))
			have.append(r)
			made.append([r.position.x, r.position.y, r.size.x, r.size.y])
	st["plots"] = (st.get("plots", []) as Array) + made
	sim.settlements[str(k)] = st
	return made


func _plot_free(r: Rect2i) -> bool:
	var C: CityData = _sim().city
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var q := Vector2i(x, y)
			if not C.inside(q):
				return false
			var i := C.idx(q)
			if C.ground[i] in [CityData.G.ROAD, CityData.G.WATER] or C.building_at[i] >= 0 or (not C.height.is_empty() and C.height[i] > 0):
				return false
	return true


## Gebaeude im Rechteck zwischen a und b (beliebige Ecken) an die Dorfstrasse setzen; -1 wenn nichts passt.
func _place(type: String, a: Vector2i, b: Vector2i, name: String) -> int:
	var r := Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(absi(a.x - b.x) + 1, absi(a.y - b.y) + 1))
	var bd: Dictionary = _sim().events._add_building(type, r, name)
	if bd.is_empty():
		bd = _sim().events._add_building(type, r.grow(2), name)
	return int(bd.id) if not bd.is_empty() else -1


## Anleger und Hafenlager am naechsten Wasser (Strasse dorthin wird mitgebaut).
func _harbor_at(cell: Vector2i, nm: String) -> int:
	var sim = _sim()
	var C: CityData = sim.city
	var best := Vector2i(-1, -1)
	var best_d := 9999
	for dy in range(-HARBOR_R, HARBOR_R + 1):
		for dx in range(-HARBOR_R, HARBOR_R + 1):
			var q := cell + Vector2i(dx, dy)
			if C.inside(q) and C.ground[C.idx(q)] == CityData.G.WATER and absi(dx) + absi(dy) < best_d:
				best_d = absi(dx) + absi(dy)
				best = q
	if best.x < 0:
		return -1
	var land := best + (cell - best).sign() * 3
	var lane: Array = []
	var q := cell
	while q != land and lane.size() < 20:
		q += (land - q).sign() * Vector2i(1, 0) if q.x != land.x else (land - q).sign() * Vector2i(0, 1)
		if C.ground[C.idx(q)] != CityData.G.WATER and C.building_at[C.idx(q)] < 0:
			lane.append(q)
	sim.access._apply_cells(lane)
	var st: Dictionary = sim.settlements.get(str(C.town_of(cell)), {})
	var off := _place("port_office", land + Vector2i(-2, -3), land + Vector2i(2, 3), "Anleger %s" % nm)
	var wh := _place("warehouse", land + Vector2i(-4, -4), land + Vector2i(4, 4), "Hafenlager")
	if not st.is_empty():
		st["roads"] = (st.get("roads", []) as Array) + lane.map(func(x): return [x.x, x.y])
	return wh if off >= 0 and wh >= 0 else -1


## Beobachtung fuer KI-Unternehmer vor und nach der Gruendung.
func obs(b: Dictionary, cid: int) -> Dictionary:
	var sim = _sim()
	if not sim.wildnis or cid < 0:
		return {}
	var k: int = sim.companies[cid].home_town
	if founded(k):
		return {"gegruendet": true, "stadt": sim.towns.name_of(k), "mitte": sim.city.towns[k].center}
	var here: Vector2i = w.tile_of(b)
	return {"gegruendet": false, "hinweis": "Noch keine Siedlung. Erkunde das Land (MoveTo, Fahrt) und gründe am besten Platz: Siedlung {feld: [x, y]}.",
		"hier": score_at(here), "beste_plaetze_in_der_naehe": best_near(here)}


func next_step(b: Dictionary, cid: int) -> String:
	var sim = _sim()
	if not sim.wildnis or cid < 0 or founded(sim.companies[cid].home_town):
		return ""
	var best := best_near(w.tile_of(b), 70, 1)
	if best.is_empty():
		return "Siedlungsplatz suchen – hier in der Nähe passt nichts. Fahr weiter (Fahrt {ziel: ...} oder MoveTo) und prüfe siedlung.hier."
	return "Siedlung gründen – bester Platz in deiner Nähe: Siedlung {feld: %s} (%d Punkte: %s). Oder weiter erkunden." % [
		str(best[0].feld), int(best[0].punkte), "; ".join(best[0].gruende)]
