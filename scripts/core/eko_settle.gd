class_name EkoSettle
extends RefCounted
## Wildnis (Benedikt 17.11.2026): "Es gibt am Anfang keine Stadt. Jede KI sucht sich die beste Stelle ... findet einen sicheren Platz,
## eroeffnet dort ihren Bauplatz, sichert sich ab und baut dort die Stadt." Nachtrag: "Er soll frei entscheiden, wo er seine Stadt
## gruendet und den Bauhof; er hat einen Gelaende-LKW und braucht keine Strassen; er muss alles bauen, Strassen, Haeuser, solange er
## keine Angestellten hat; seine Basis entsteht da, wo der Betriebshof ist, die muss er schuetzen."
##
## Bewertung (score_at): freie ebene Flaeche, natuerlicher Schutz (Wasser/Huegel ringsum), Wasser (Anleger), Lagerstaette, Weg zum Lager.
## Gruendung (found): Betriebshof und Basis (Stammsitz) am gewaehlten Platz, Land ringsum wird Bauland der kuenftigen Stadt.
## Alles Weitere baut die KI selbst (EkoHomes): Buergeramt (danach gibt es die Stadt und den Buergermeister), Haeuser, Strassen.

const MIN_TOWN_DIST := 60       # Abstand zu anderen Siedlungen (Mitte zu Mitte)
const HARBOR_R := 6
const DEPOSIT_R := 30
const AREA := 12                # halbe Kantenlaenge der Flaeche, die frei und eben sein muss
const FOUND_COST := 10000.0     # Vermessung und Platz (Firma -> Kasse der kuenftigen Stadt)
const ROAD_COST := 60.0         # EUR je Strassenfeld (Vermessung, Kleinmaterial) – Kies kommt vom eigenen Hof
const ROAD_KIES := 2
const ROAD_MAX := 40
const ON_SITE := 15             # so nah muss das Wesen am Platz sein, um zu gruenden (selbst hinfahren)
const PLOT := Vector2i(9, 8)    # Baugrundstueck: Einfamilien-, Doppel- und Mehrfamilienhaus passen

var w                           # EkoWorld
var _deposit_cells: Array = []  # [[Vector2i, art], ...]
var _best_cache := {}


func setup(world) -> void:
	w = world


func _sim():
	return w.sim


## Hat die KI dieses Orts schon ihren Betriebshof gegruendet? (Die Stadt selbst gibt es erst mit dem Buergeramt: sim.town_ready.)
func founded(k: int) -> bool:
	var sim = _sim()
	return not sim.wildnis or (k >= 0 and k < sim.city.towns.size() and bool(sim.city.towns[k].get("siedlung", false)))


func _deposits() -> Array:
	if _deposit_cells.is_empty():
		var sim = _sim()
		sim.prod.deposit_of("")   # legt die Lagerstaetten an (vor jeder Umwidmung)
		for pid in sim.prod._deposits:
			var p: Dictionary = sim.parcels.parcel(str(pid))
			if not p.is_empty():
				_deposit_cells.append([Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2), str(sim.prod._deposits[pid].art)])
	return _deposit_cells


## Bewertung eines Platzes fuer Betriebshof und Basis: {ok, punkte, gruende, grund (wenn nicht ok), hafen, schutz}.
## Schutz: Anteil Wasser und Huegel im Ring 6-14 Felder um die Mitte.
func score_at(cell: Vector2i) -> Dictionary:
	var sim = _sim()
	var C: CityData = sim.city
	var out := {"feld": [cell.x, cell.y], "ok": false, "punkte": 0, "gruende": []}
	if not C.inside(cell) or cell.x < AREA + 2 or cell.y < AREA + 2 or cell.x > C.size - AREA - 3 or cell.y > C.size - AREA - 3:
		out["grund"] = "am Kartenrand"
		return out
	for t in C.towns:
		if bool(t.get("siedlung", false)) and absi(int(t.center[0]) - cell.x) + absi(int(t.center[1]) - cell.y) < MIN_TOWN_DIST:
			out["grund"] = "zu nah an %s" % t.name
			return out
	var hub := Vector2i(-1, -1)
	if not C.hub.is_empty():
		var hr: Array = C.hub.rect
		if Rect2i(int(hr[0]), int(hr[1]), int(hr[2]), int(hr[3])).grow(20).has_point(cell):
			out["grund"] = "zu nah am Großlager"
			return out
		hub = Vector2i(int(C.hub.center[0]), int(C.hub.center[1]))
	var free := 0
	var total := 0
	var guard := 0
	var ring := 0
	var water := 0
	var harbor_water := 0
	for dy in range(-14, 15):
		for dx in range(-14, 15):
			var q := cell + Vector2i(dx, dy)
			if not C.inside(q):
				continue
			var i := C.idx(q)
			var is_water := C.ground[i] == CityData.G.WATER
			var is_hill := not C.height.is_empty() and C.height[i] > 0
			var d := maxi(absi(dx), absi(dy))
			if d <= AREA:
				total += 1
				if not is_water and not is_hill and C.building_at[i] < 0 and C.ground[i] != CityData.G.ROAD:
					free += 1
			if d >= 6:
				ring += 1
				if is_water or is_hill:
					guard += 1
			if is_water:
				water += 1
				if d <= HARBOR_R:
					harbor_water += 1
	var flat := float(free) / float(maxi(1, total))
	if flat < 0.6:
		out["grund"] = "zu wenig freie, ebene Fläche (%d %%)" % int(flat * 100.0)
		return out
	var pts := 20.0 + 30.0 * (flat - 0.6) / 0.4
	out.gruende.append("Fläche frei und eben %d %%" % int(flat * 100.0))
	var schutz := float(guard) / float(maxi(1, ring))
	if schutz >= 0.1:
		pts += minf(25.0, schutz * 60.0)
		out.gruende.append("natürlicher Schutz: %d %% Wasser/Hügel ringsum" % int(schutz * 100.0))
	if water >= 25:
		pts += 20.0
		out.gruende.append("Wasser in der Nähe" + (" – Anleger möglich (Siedlerschiff)" if harbor_water >= 12 else ""))
	var dep_art := ""
	var dep_d := 9999
	for d2 in _deposits():
		var dd: int = absi(d2[0].x - cell.x) + absi(d2[0].y - cell.y)
		if dd < dep_d:
			dep_d = dd
			dep_art = str(d2[1])
	if dep_d <= DEPOSIT_R:
		pts += 20.0
		out.gruende.append("Lagerstätte %s %d Felder entfernt (Bergwerk)" % [dep_art, dep_d])
	if hub.x >= 0:
		var hd := absi(hub.x - cell.x) + absi(hub.y - cell.y)
		pts -= float(hd) / 40.0
		out.gruende.append("%d Felder bis zum Großlager" % hd)
	out.ok = true
	out.punkte = int(round(pts))
	out["hafen"] = harbor_water >= 12
	out["schutz"] = int(schutz * 100.0)
	return out


## Beste Plaetze im Umkreis (fuer die Beobachtung), hoechstens n. Zwischengespeichert je Feld (~225 Bewertungen je Aufruf).
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


## Gruendung durch das Wesen b mit Firma cid am Feld cell: Betriebshof und Basis (Stammsitz) entstehen hier; das Land ringsum wird
## Bauland der kuenftigen Stadt.
func found(b: Dictionary, cid: int, cell: Vector2i) -> Dictionary:
	var sim = _sim()
	var C: CityData = sim.city
	var k: int = sim.companies[cid].home_town
	if founded(k):
		return {"ok": false, "msg": "Dein Betriebshof steht schon (%s)." % sim.towns.name_of(k)}
	var here: Vector2i = w.tile_of(b)
	if maxi(absi(here.x - cell.x), absi(here.y - cell.y)) > ON_SITE:   # 17.11.: Sonnenklippe wurde vom Grosslager aus "eroeffnet"
		return {"ok": false, "msg": "Du bist nicht dort (%d Felder entfernt). Fahr erst selbst hin: LKW {ziel: [%d, %d]} – dann Siedlung {feld: [%d, %d]}." % [
			maxi(absi(here.x - cell.x), absi(here.y - cell.y)), cell.x, cell.y, cell.x, cell.y]}
	var sc := score_at(cell)
	if not sc.ok:
		return {"ok": false, "msg": "Hier geht es nicht: %s." % str(sc.get("grund", "")), "bewertung": sc}
	var c = sim.company(cid)
	if c.ledger.cash < FOUND_COST:
		return {"ok": false, "msg": "Vermessung und Platz kosten %s, die Firma hat %s." % [Catalog.money(FOUND_COST), Catalog.money(c.ledger.cash)]}
	if not w.estates.assign_near(str(b.name), cell):
		return {"ok": false, "msg": "Für deine Basis (24 × 24 Felder) ist hier kein freier Platz – etwas versetzt versuchen."}
	var ctr: Vector2i = w.estates.center_of(str(b.name))
	var yard := -1
	for f in [1, 3, 5, 0, 2, 6, 8]:   # erst das obere Mittelfeld, sonst ein anderes freies Feld der Basis (Wasser/Huegel in der Basis)
		var fr: Rect2i = w.estates.field_rect(str(b.name), f)
		yard = _place("freight_shed", fr.position + Vector2i(1, 1), fr.end - Vector2i(2, 2), "%s (Betriebshof)" % c.company_name)
		if yard >= 0:
			break
	if yard < 0:
		return {"ok": false, "msg": "Der Betriebshof passt hier nicht – etwas versetzt versuchen."}
	c.depots.push_front(yard)
	sim.depot_owner[yard] = cid
	var t: Dictionary = C.towns[k]
	t["center"] = [ctr.x, ctr.y]
	t["rect"] = [ctr.x - 23, ctr.y - 24, 46, 48]
	t["siedlung"] = true
	_best_cache.clear()
	c.ledger.book("property_costs", -FOUND_COST, true, "Vermessung und Betriebshof %s" % t.name, sim.game_min, Towns.account_of(k))
	for p in sim.parcels.items.values():   # Land ringsum gehoert der kuenftigen Stadt und wird Bauland
		var pc := Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)
		var d: int = absi(pc.x - ctr.x) + absi(pc.y - ctr.y)
		if d <= 34 and str(p.state) == "frei" and Towns.is_public(str(p.owner)):
			p.owner = Towns.owner_of(k)
			if str(p.zone) not in ["korridor", "gruen"]:
				p.zone = "wohnen" if d <= 22 else "mischgebiet"
			sim.parcels._touch(p)
	sim.parcels.sync_buildings()
	sim.events.buildings_added.emit([yard])
	sim.settlements[str(k)] = {"center": t.center, "rect": t.rect, "roads": [], "plots": [], "yard": yard}
	carve_area(k, ctr, 10)
	sim.log_event("%s eröffnet den Bauplatz %s (%s)." % [b.name, t.name, ", ".join(sc.gruende)], "good", cid)
	return {"ok": true, "msg": ("Betriebshof und Basis %s eröffnet (%s). Jetzt baust du alles selbst: Material kaufen (hub_buy) und mit deinem LKW holen " +
		"(LKW {ziel: \"grosslager\"}), Basis sichern (Bauwerk), Bürgeramt (buergeramt_bauen), Häuser (haus_bauen), Straßen (strasse_bauen); " +
		"gearbeitet wird mit Bauen {baustelle}.") % [t.name, Catalog.money(FOUND_COST)], "stadt": k, "bewertung": sc}


## Buergeramt fertig (EkoHomes): Rathaus und Bauhof stehen, die Stadt ist gegruendet, der Buergermeister zieht ein.
func open_town(k: int, rect: Rect2i) -> bool:
	var sim = _sim()
	var C: CityData = sim.city
	var t: Dictionary = C.towns[k]
	var nm: String = str(t.name)
	var hall := _place("townhall", rect.position, rect.position + Vector2i(3, 3), "Bürgeramt %s" % nm)
	var bauhof := _place("freight_shed", rect.position + Vector2i(4, 0), rect.end - Vector2i(1, 1), "Städtischer Bauhof")
	if hall < 0 or bauhof < 0:
		return false
	t["town_hall"] = hall
	t["bauhof"] = bauhof
	t["gegruendet"] = true
	var st: Dictionary = sim.settlements.get(str(k), {})
	st["town_hall"] = hall
	st["bauhof"] = bauhof
	st["gegruendet"] = true
	sim.settlements[str(k)] = st
	var ctr := Vector2i(int(t.center[0]), int(t.center[1]))
	var harbor := -1
	if _water_near(ctr, 12) >= 12:
		harbor = _harbor_at(ctr, nm)
	if harbor >= 0:
		t["harbor"] = harbor
		st["harbor"] = harbor
	_activate(k)
	sim.towns.depot(k).activate(bauhof)
	sim.events.buildings_added.emit([hall, bauhof] + ([harbor] if harbor >= 0 else []))
	for n in w.beings:
		var o: Dictionary = w.beings[n]
		if int(o.get("amt", -1)) == k:
			o.mover.pos = C.tile_center(C.building(hall).walk)
			w._event(o, "Das Bürgeramt von %s steht – du bist jetzt Bürgermeister und ziehst ein." % nm)
	sim.log_event("%s hat ein Bürgeramt – die Stadt ist gegründet." % nm, "good")
	return true


func _water_near(ctr: Vector2i, r: int) -> int:
	var C: CityData = _sim().city
	var n := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var q := ctr + Vector2i(dx, dy)
			if C.inside(q) and C.ground[C.idx(q)] == CityData.G.WATER:
				n += 1
	return n


## Hafen der Stadt in Betrieb nehmen (Gruendung und Laden).
func _activate(k: int) -> void:
	var sim = _sim()
	var hb := int(sim.city.towns[k].get("harbor", -1))
	if hb >= 0:
		var H = sim.towns.harbor(k)
		H.building = hb
		H.enabled = true
		if not sim.day_changed.is_connected(H.on_day):
			sim.day_changed.connect(H.on_day)


## Laden: Gebaeudenummern der Siedlungen zurueck an die Stadt (die Karte entsteht aus dem Seed ohne sie), Stadtlager und Hafen.
func reapply_loaded() -> void:
	var sim = _sim()
	for key in sim.settlements:
		var st: Dictionary = sim.settlements[key]
		var k := int(key)
		var t: Dictionary = sim.city.towns[k]
		t["siedlung"] = true
		for f in ["town_hall", "bauhof", "harbor"]:
			if st.has(f):
				t[f] = int(st[f])
		if bool(st.get("gegruendet", false)) and int(t.get("bauhof", -1)) >= 0:
			t["gegruendet"] = true
			_activate(k)
			var D = sim.towns.depot(k)
			D.building = int(t.bauhof)
			D.port = sim.towns.harbor(k).building if sim.towns.harbor(k).enabled else D.building


# ------------------------------------------------------------------ Strassen und Bauland
## Firma {aktion: {action: "strasse_bauen", bis: [x, y], von?: [x, y]}}: Baustelle fuer eine Strasse – ohne von bis zur naechsten
## Strasse, mit von quer uebers Land von dort bis bis. Je Feld ROAD_KIES Kies vom eigenen Hof; gebaut wird mit Bauen (Feld fuer Feld).
func plan_road(cid: int, a: Dictionary) -> Dictionary:
	var sim = _sim()
	var C: CityData = sim.city
	var k: int = sim.companies[cid].home_town
	if not founded(k):
		return {"ok": false, "msg": "Erst deinen Betriebshof eröffnen: Siedlung {feld: [x, y]}."}
	var f = a.get("bis", a.get("feld", []))
	if not (f is Array) or (f as Array).size() < 2:
		return {"ok": false, "msg": "strasse_bauen braucht bis: [x, y] (und wahlweise von: [x, y])."}
	var to := Vector2i(int(f[0]), int(f[1]))
	if C.town_of(to) != k:
		return {"ok": false, "msg": "Feld %s liegt nicht im Gebiet deiner Siedlung %s." % [str(f), sim.towns.name_of(k)]}
	var path: Array = []
	var fv = a.get("von", [])
	if fv is Array and (fv as Array).size() >= 2:
		var from := Vector2i(int(fv[0]), int(fv[1]))
		for q in sim.nav.walk_path(from, to):
			if not C.is_road(q):
				path.append(q)
	else:
		path = _road_path(to, ROAD_MAX)
	path = path.filter(func(q): return C.building_at[C.idx(q)] < 0 and C.ground[C.idx(q)] != CityData.G.WATER).slice(0, ROAD_MAX)
	if path.is_empty():
		return {"ok": false, "msg": "Keine Strecke gefunden (schon Straße, Wasser, Berg oder weiter als %d Felder). Mit von: [x, y] quer übers Land planen." % ROAD_MAX}
	var cost := float(path.size()) * ROAD_COST
	var c = sim.company(cid)
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Straßenbau kostet %s, Kasse %s." % [Catalog.money(cost), Catalog.money(c.ledger.cash)]}
	c.ledger.book("property_costs", -cost, true, "Straßenbau %d Felder in %s" % [path.size(), sim.towns.name_of(k)], sim.game_min, Towns.account_of(k))
	return w.homes.add_road_site(cid, path, {"kies": path.size() * ROAD_KIES})


## Strassenfeld fertig (EkoHomes): Zelle anlegen, speichern; bei Abschluss Baugrundstuecke daran.
func lay_road_cells(k: int, cells: Array) -> void:
	var sim = _sim()
	sim.access._apply_cells(cells)
	sim.access._fields.clear()
	sim.access._cache.clear()
	var st: Dictionary = sim.settlements.get(str(k), {})
	st["roads"] = (st.get("roads", []) as Array) + cells.map(func(q): return [q.x, q.y])
	sim.settlements[str(k)] = st


## Baugrundstuecke (9 x 8) beidseits entlang der Strassenzellen; hoechstens `limit`.
func carve_plots(k: int, cells: Array, limit: int = 8, centered := false) -> Array:
	var sim = _sim()
	var st: Dictionary = sim.settlements.get(str(k), {})
	var have: Array = (st.get("plots", []) as Array).map(func(a): return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3])))
	var made: Array = []
	for i in cells.size():
		if made.size() >= limit:
			break
		var c: Vector2i = cells[i]
		var offs: Array = []
		if centered:   # Bauland im Gelaende: Grundstueck um das Feld
			offs = [-PLOT / 2]
		else:          # Grundstueck beruehrt die Strassenzelle, entlang der Strasse verschoben
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


## Bauland um den Betriebshof: Grundstuecke im Ring 18-32 Felder um die Mitte (vor dem ersten Strassenbau).
func carve_area(k: int, ctr: Vector2i, limit: int) -> Array:
	var cells: Array = []
	for rad in [18, 25, 32]:
		for ang in range(0, 360, 30):
			cells.append(ctr + Vector2i(int(round(cos(deg_to_rad(ang)) * rad)), int(round(sin(deg_to_rad(ang)) * rad))))
	return carve_plots(k, cells, limit, true)


func _plot_free(r: Rect2i) -> bool:
	var C: CityData = _sim().city
	for e in w.estates.estates.values():   # nicht auf eine Basis
		if Rect2i(int(e.rect[0]), int(e.rect[1]), EkoEstates.SIDE, EkoEstates.SIDE).grow(1).intersects(r):
			return false
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var q := Vector2i(x, y)
			if not C.inside(q):
				return false
			var i := C.idx(q)
			if C.ground[i] in [CityData.G.ROAD, CityData.G.WATER] or C.building_at[i] >= 0 or (not C.height.is_empty() and C.height[i] > 0):
				return false
	return true


## Breitensuche ueber Land bis zur naechsten Strasse; Weg ohne die Strassenzelle.
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


## Gebaeude im Rechteck zwischen a und b (beliebige Ecken); -1 wenn nichts passt.
func _place(type: String, a: Vector2i, b: Vector2i, name: String) -> int:
	var r := Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(absi(a.x - b.x) + 1, absi(a.y - b.y) + 1))
	var bd: Dictionary = _sim().events._add_building(type, r, name)
	if bd.is_empty():
		bd = _sim().events._add_building(type, r.grow(2), name)
	return int(bd.id) if not bd.is_empty() else -1


## Anleger und Hafenlager am naechsten Wasser.
func _harbor_at(cell: Vector2i, nm: String) -> int:
	var C: CityData = _sim().city
	var best := Vector2i(-1, -1)
	var best_d := 9999
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var q := cell + Vector2i(dx, dy)
			if C.inside(q) and C.ground[C.idx(q)] == CityData.G.WATER and absi(dx) + absi(dy) < best_d:
				best_d = absi(dx) + absi(dy)
				best = q
	if best.x < 0:
		return -1
	var land := best + (cell - best).sign() * 3
	var off := _place("port_office", land + Vector2i(-2, -3), land + Vector2i(2, 3), "Anleger %s" % nm)
	var wh := _place("warehouse", land + Vector2i(-4, -4), land + Vector2i(4, 4), "Hafenlager")
	return wh if off >= 0 and wh >= 0 else -1


# ------------------------------------------------------------------ Beobachtung
func obs(b: Dictionary, cid: int) -> Dictionary:
	var sim = _sim()
	if not sim.wildnis or cid < 0:
		return {}
	var k: int = sim.companies[cid].home_town
	if founded(k):
		return {"betriebshof": true, "stadt": sim.towns.name_of(k), "mitte": sim.city.towns[k].center, "buergeramt": sim.town_ready(k),
			"baugrundstuecke": (sim.settlements.get(str(k), {}).get("plots", []) as Array).size()}
	var here: Vector2i = w.tile_of(b)
	return {"betriebshof": false, "hinweis": "Noch kein Betriebshof. Erkunde das Land (mit deinem Gelände-LKW: LKW {ziel: [x, y]}, oder MoveTo) und eröffne am besten Platz: Siedlung {feld: [x, y]}.",
		"hier": score_at(here), "beste_plaetze_in_der_naehe": best_near(here)}


func next_step(b: Dictionary, cid: int) -> String:
	var sim = _sim()
	if not sim.wildnis or cid < 0 or founded(sim.companies[cid].home_town):
		return ""
	var best := best_near(w.tile_of(b), 70, 1)
	if best.is_empty():
		return "Platz suchen – hier in der Nähe passt nichts. Fahr mit dem LKW weiter (LKW {ziel: [x, y]}) und prüfe siedlung.hier."
	var f: Array = best[0].feld
	var here: Vector2i = w.tile_of(b)
	if maxi(absi(here.x - int(f[0])), absi(here.y - int(f[1]))) > ON_SITE:
		return "Bester Platz in deiner Nähe: %s (%d Punkte: %s) – hinfahren mit LKW {ziel: %s}, dort Siedlung {feld: %s}." % [
			str(f), int(best[0].punkte), "; ".join(best[0].gruende), str(f), str(f)]
	return "Du bist am Platz %s (%d Punkte: %s) – Betriebshof und Basis eröffnen: Siedlung {feld: %s}." % [str(f), int(best[0].punkte), "; ".join(best[0].gruende), str(f)]
