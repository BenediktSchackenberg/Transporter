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
const HUB_DIST := 40            # Abstand zum Grosslager-Gelaende (Benedikt 18.11.: keine Stadt am zentralen Marktplatz)
const HALL_R := 30              # Buergeramt hoechstens so weit vom eigenen Betriebshof (Mitte des 24x24-Stammsitzes; dort entsteht die Stadt)
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
		var td := absi(int(t.center[0]) - cell.x) + absi(int(t.center[1]) - cell.y)
		if bool(t.get("siedlung", false)) and td < MIN_TOWN_DIST:   # Partie 18.11.: ohne Zahlen rieten die Wesen eine Stunde lang Plaetze
			out["grund"] = "zu nah an %s (Mitte bei %s, %d Felder entfernt; nötig sind mindestens %d Felder: waagerecht + senkrecht gezählt)" % [
				t.name, str(t.center), td, MIN_TOWN_DIST]
			return out
	var hub := Vector2i(-1, -1)
	if not C.hub.is_empty():
		var hr: Array = C.hub.rect
		if Rect2i(int(hr[0]), int(hr[1]), int(hr[2]), int(hr[3])).grow(HUB_DIST).has_point(cell):
			out["grund"] = "zu nah am Großlager (Lagergelände x %d–%d, y %d–%d; nötig sind mindestens %d Felder Abstand zum Gelände – der zentrale Marktplatz bleibt frei)" % [
				int(hr[0]), int(hr[0]) + int(hr[2]) - 1, int(hr[1]), int(hr[1]) + int(hr[3]) - 1, HUB_DIST]
			return out
		hub = Vector2i(int(C.hub.center[0]), int(C.hub.center[1]))
	var free := 0
	var total := 0
	var guard := 0
	var ring := 0
	var water := 0
	var harbor_water := 0
	for dy in range(-14, 15, 2):   # jedes zweite Feld (18.11.: best_near bewertet ~225 Plaetze je Aufruf – Bildrate)
		for dx in range(-14, 15, 2):
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
				water += 4   # Stichprobe: ein Feld steht fuer vier
				if d <= HARBOR_R:
					harbor_water += 4
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
	var sea := harbor_water >= 12 and _sea_near(cell, HARBOR_R)
	if water >= 25:
		pts += 20.0
		out.gruende.append("Wasser in der Nähe" + (" – Anleger möglich (Siedlerschiff)" if sea else (" (See, kein Meer: kein Schiff)" if harbor_water >= 12 else "")))
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
	out["hafen"] = sea
	out["schutz"] = int(schutz * 100.0)
	return out


## Beste Plaetze im Umkreis (fuer die Beobachtung), hoechstens n. Zwischengespeichert je Feld (~225 Bewertungen je Aufruf).
## Nur Plaetze, die der Gelaende-LKW von cell aus erreicht (Partie 18.11.: Amira bekam zweimal einen unerreichbaren Platz empfohlen).
func best_near(cell: Vector2i, radius: int = 70, n: int = 3) -> Array:
	var key := "%d,%d,%d" % [cell.x / 8, cell.y / 8, radius]
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
	for sc in cands:
		sc["entfernung"] = maxi(absi(int(sc.feld[0]) - cell.x), absi(int(sc.feld[1]) - cell.y))
	_best_cache[key] = {"t": float(_sim().game_min), "r": cands.slice(0, 5)}
	return cands.slice(0, n)


## Bester Platz, den der Gelaende-LKW von cell aus erreicht (Partie 18.11.: Amira bekam unerreichbare Plaetze empfohlen).
## Wegsuche nur fuer die besten Kandidaten (hoechstens 3) und gemerkt je Grobfeld – eine Wegsuche ins Unerreichbare kostet ~50 ms.
var _reach_memo := {}


func reachable_best(cell: Vector2i, radius: int = 70) -> Dictionary:
	var sim = _sim()
	if _reach_memo.size() > 400:
		_reach_memo.clear()
	var checks := 0
	for sc in best_near(cell, radius, 5):
		var f := Vector2i(int(sc.feld[0]), int(sc.feld[1]))
		var mk := "%d,%d>%d,%d" % [cell.x / 8, cell.y / 8, f.x, f.y]
		var hit: Dictionary = _reach_memo.get(mk, {})
		if hit.is_empty() or float(sim.game_min) - float(hit.t) > 240.0:
			if checks >= 3:
				break
			checks += 1
			hit = {"t": float(sim.game_min), "ok": not sim.offroad_path(cell, f).is_empty()}
			_reach_memo[mk] = hit
		if bool(hit.ok):
			return sc
	return {}


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
		var pre := score_at(cell)   # erst pruefen, ob der Platz ueberhaupt geht – sonst faehrt das Wesen umsonst hin
		if not pre.ok:
			return {"ok": false, "msg": "Dieser Platz geht nicht: %s. %s" % [str(pre.get("grund", "")), _suggest(here)], "bewertung": pre}
		return {"ok": false, "msg": "Du bist nicht dort (%d Felder entfernt). Fahr erst selbst hin: LKW {ziel: [%d, %d]} – dann Siedlung {feld: [%d, %d]}." % [
			maxi(absi(here.x - cell.x), absi(here.y - cell.y)), cell.x, cell.y, cell.x, cell.y]}
	var sc := score_at(cell)
	if not sc.ok:
		return {"ok": false, "msg": "Hier geht es nicht: %s. %s" % [str(sc.get("grund", "")), _suggest(here)], "bewertung": sc}
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
	# Partie 18.11.: Amira kaufte Kies vor der Gruendung – er ging an den Startplatz und fehlte am neuen Hof. Noch nicht geladene
	# Grosslager-Kaeufe der Firma werden deshalb auf den neuen Hof umgeleitet.
	for d in sim.hub.deals.values():
		if str(d.kind) == "kauf" and str(d.party) == "C%d" % cid and str(d.status) not in ["geliefert", "storniert"]:
			d.dest = yard
			var hk = sim.contracts.get(str(d.get("contract", "")))
			if hk != null and hk.status in ["open", "accepted", "assigned"] and int(hk.picked) == 0:
				hk.dropoff = yard
	var t: Dictionary = C.towns[k]
	t["center"] = [ctr.x, ctr.y]
	t["rect"] = [ctr.x - 23, ctr.y - 24, 46, 48]
	t["siedlung"] = true
	sim.towns.sync_from_city(k)
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
	if hall < 0:   # Partie 18.11.: Viktors Buergeramt hing bei 100 % ("passt nicht aufs Grundstueck") – freien Platz daneben suchen
		hall = _place_near("townhall", rect.get_center(), 14, "Bürgeramt %s" % nm)
	var bauhof := _place("freight_shed", rect.position + Vector2i(4, 0), rect.end - Vector2i(1, 1), "Städtischer Bauhof")
	if bauhof < 0:
		bauhof = _place_near("freight_shed", rect.get_center(), 18, "Städtischer Bauhof")
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
	sim.towns.sync_from_city(k)
	sim.town_plan.ensure(k, "gruendung")   # Auftrag 8: Profil vor den ersten regulaeren Bauplatzentscheidungen
	_start_package(k)
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


## Meer oder See? Ein Gewaesser zaehlt als Meer, wenn es den Kartenrand erreicht (oder sehr gross ist). Ergebnis je Wasserfeld gemerkt
## (eine Flutfuellung je Gewaesser).
var _sea_memo := {}
const SEA_FILL_MAX := 60000


func is_sea(cell: Vector2i) -> bool:
	var C: CityData = _sim().city
	if not C.inside(cell) or C.ground[C.idx(cell)] != CityData.G.WATER:
		return false
	if _sea_memo.has(cell):
		return bool(_sea_memo[cell])
	var seen := {cell: true}
	var todo: Array[Vector2i] = [cell]
	var sea := false
	var i := 0
	while i < todo.size():
		var c: Vector2i = todo[i]
		i += 1
		if c.x == 0 or c.y == 0 or c.x == C.size - 1 or c.y == C.size - 1 or todo.size() > SEA_FILL_MAX:
			sea = true
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if not seen.has(q) and C.inside(q) and C.ground[C.idx(q)] == CityData.G.WATER:
				seen[q] = true
				todo.append(q)
	for c in seen:
		_sea_memo[c] = sea
	return sea


func _sea_near(cell: Vector2i, r: int) -> bool:
	var C: CityData = _sim().city
	for dy in range(-r, r + 1, 2):
		for dx in range(-r, r + 1, 2):
			var q := cell + Vector2i(dx, dy)
			if C.inside(q) and C.ground[C.idx(q)] == CityData.G.WATER and is_sea(q):
				return true
	return false


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
		if int(t.get("harbor", -1)) >= 0:
			var hb: Dictionary = sim.city.building(int(t.harbor))
			if hb.is_empty() or not _sea_near(Vector2i(int(hb.x), int(hb.y)), 12):   # alter Anleger an einem See: kein Hafen
				t["harbor"] = -1
				st.erase("harbor")
		if st.has("center"):
			t["center"] = st.center
			t["rect"] = st.rect
		sim.towns.sync_from_city(k)
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
	var fv = a.get("von", [])
	var from_given: bool = fv is Array and (fv as Array).size() >= 2
	var from := Vector2i(int(fv[0]), int(fv[1])) if from_given else Vector2i(-1, -1)
	if C.town_of(to) != k and (not from_given or C.town_of(from) != k):
		var link: Dictionary = road_link(k)
		var tip := (" Vorschlag: strasse_bauen {von: %s, bis: %s}." % [str(link.von), str(link.bis)]) if link.has("von") else ""
		return {"ok": false, "msg": "Mindestens ein Endpunkt muss in deiner Siedlung %s liegen.%s" % [sim.towns.name_of(k), tip]}
	var path: Array = []
	if from_given:
		if not C.is_road(from):
			return {"ok": false, "msg": "von: %s muss ein bestehendes Straßenfeld sein – nur dort kann die Baustelle beginnen." % str([from.x, from.y])}
		path = _road_between(from, to)
	else:
		path = _road_path(to, ROAD_MAX)
	if path.is_empty():
		return {"ok": false, "msg": "Keine durchgehende Strecke gefunden. Wähle einen freien Zielpunkt oder einen anderen Straßenanschluss."}
	# Erst ab dem bestehenden Netz bauen. Hindernisse duerfen die Trasse nicht nachtraeglich zerreissen.
	path = path.filter(func(q): return not C.is_road(q)).slice(0, ROAD_MAX)
	if path.is_empty():
		return {"ok": false, "msg": "Die Strecke besteht bereits aus Straße."}
	var cost := float(path.size()) * ROAD_COST
	var c = sim.company(cid)
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Straßenbau kostet %s, Kasse %s." % [Catalog.money(cost), Catalog.money(c.ledger.cash)]}
	c.ledger.book("property_costs", -cost, true, "Straßenbau %d Felder in %s" % [path.size(), sim.towns.name_of(k)], sim.game_min, Towns.account_of(k))
	return w.homes.add_road_site(cid, path, {"kies": path.size() * ROAD_KIES})


## Strassenanschluss einer gegruendeten Stadt ans Grosslager (Benedikt 18.11.: "ohne Strassen keine Warenlieferung"):
## {verbunden, von: naechstes angebundenes Strassenfeld, bis: Rathaus-Zufahrt, felder}. Je Stadt einmal je Spieltag gerechnet.
var _link_cache := {}
var _access_reset_at := -1.0e9


func road_link(k: int) -> Dictionary:
	var sim = _sim()
	var C: CityData = sim.city
	var day := GameCalendar.day_of(sim.game_min)
	var hit: Dictionary = _link_cache.get(k, {})
	if not hit.is_empty() and int(hit.day) == day:
		return hit
	var out := {"day": day, "verbunden": true}
	var hall: Dictionary = C.building(int(C.towns[k].get("town_hall", -1))) if k >= 0 and k < C.towns.size() else {}
	var hub_b: Dictionary = C.building(int(C.hub.get("buildings", {}).get("hauptlager", -1))) if not C.hub.is_empty() else {}
	if hall.is_empty() or hub_b.is_empty():
		_link_cache[k] = out
		return out
	var tr: Vector2i = hall.road
	if not C.is_road(tr):   # 19.11. Falkenwiek: Rathauszufahrt keine Strasse, die Ortsstrasse liegt daneben
		for r in range(1, 7):
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if not C.is_road(tr) and C.is_road(hall.road + Vector2i(dx, dy)):
						tr = hall.road + Vector2i(dx, dy)
	var hr: Vector2i = hub_b.road
	if C.is_road(tr) and not sim.nav.road_path(tr, hr).is_empty():
		_link_cache[k] = out
		return out
	out.verbunden = false
	# naechstes Strassenfeld, das ans Grosslager angebunden ist (ringweise, hoechstens 8 Pruefungen)
	var checks := 0
	for r in range(1, 160):
		var found := Vector2i(-1, -1)
		for dy in range(-r, r + 1):
			for dx in [-r, r] if absi(dy) != r else range(-r, r + 1):
				var q := tr + Vector2i(dx, dy)
				if C.inside(q) and C.is_road(q) and C.town_of(q) != k:
					checks += 1
					if not sim.nav.road_path(q, hr).is_empty():
						found = q
						break
					if checks >= 8:
						break
			if found.x >= 0 or checks >= 8:
				break
		if found.x >= 0:
			out["von"] = [found.x, found.y]
			out["felder"] = absi(found.x - tr.x) + absi(found.y - tr.y)
			break
		if checks >= 8:
			break
	out["bis"] = [tr.x, tr.y]
	_link_cache[k] = out
	return out


func _near_road(c: Vector2i, r: int) -> bool:
	var C: CityData = _sim().city
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if C.is_road(c + Vector2i(dx, dy)):
				return true
	return false


## Strassenfeld fertig (EkoHomes): Zelle anlegen, speichern; bei Abschluss Baugrundstuecke daran.
func lay_road_cells(k: int, cells: Array) -> void:
	var sim = _sim()
	sim.access._apply_cells(cells)
	# Entfernungsfeld der Erschliessung (ganze Karte, ~1 s) hoechstens einmal je Spieltag verwerfen – vorher bei JEDEM Strassenfeld
	# (18.11.: Buergermeister-Beobachtung kostete dadurch staendig 1 s, Bildrate 9-13)
	if float(sim.game_min) - _access_reset_at >= GameCalendar.days_to_min(1.0):
		_access_reset_at = float(sim.game_min)
		sim.access._fields.clear()
		sim.access._cache.clear()
	_link_cache.clear()
	var st: Dictionary = sim.settlements.get(str(k), {})
	st["roads"] = (st.get("roads", []) as Array) + cells.map(func(q): return [q.x, q.y])
	sim.settlements[str(k)] = st


## Baugrundstuecke (9 x 8) beidseits entlang der Strassenzellen; hoechstens `limit`.
func carve_plots(k: int, cells: Array, limit: int = 8, centered := false) -> Array:
	var sim = _sim()
	var st: Dictionary = sim.settlements.get(str(k), {})
	var have: Array = (st.get("plots", []) as Array).map(func(a): return Rect2i(int(a[0]), int(a[1]), int(a[2]), int(a[3])))
	var made: Array = []
	var size: Vector2i = sim.town_plan.plot_size(k) if sim.town_plan.has(k) else PLOT   # Auftrag 8: Grundstuecksgroesse der Grundform
	for i in cells.size():
		if made.size() >= limit:
			break
		var c: Vector2i = cells[i]
		var offs: Array = []
		if centered:   # Bauland im Gelaende: Grundstueck um das Feld
			offs = [-size / 2]
		else:          # Grundstueck beruehrt die Strassenzelle, entlang der Strasse verschoben
			for t in range(0, size.y, 2):
				offs.append(Vector2i(1, -t))
				offs.append(Vector2i(-size.x, -t))
			for t in range(0, size.x, 2):
				offs.append(Vector2i(-t, 1))
				offs.append(Vector2i(-t, -size.y))
		for o in offs:
			var r := Rect2i(c + o, size)
			if have.any(func(h): return h.intersects(r)) or not _plot_free(r):
				continue
			var zone: String = sim.town_plan.zone_at(k, r.get_center())
			if zone == "gruen":
				continue   # Gruenzug/Aussicht/Uferweg des Stadtplans bleibt frei
			sim.parcels.carve(r, zone, Towns.owner_of(k))
			have.append(r)
			made.append([r.position.x, r.position.y, r.size.x, r.size.y, zone])
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
			if _sim().town_plan != null and _sim().town_plan.is_space_cell(q):
				return false
	return true


## Breitensuche ueber Land bis zur naechsten Strasse; Weg ohne die Strassenzelle.
func _road_path(cell: Vector2i, limit: int) -> Array:
	var C: CityData = _sim().city
	if C.is_road(cell) or not _road_cell_ok(cell):
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
					out.reverse()   # Bau beginnt am bestehenden Netz, nicht am freien Ende
					return out
				if not _road_cell_ok(q):
					continue
				prev[q] = p
				nxt.append(q)
		frontier = nxt
		dist += 1
	return []


## Ein Weg fuer LKW-Strassen benutzt nur Kanten-Nachbarn. Fusswege koennen diagonal verlaufen
## und erzeugten beim Uebernehmen die isolierten Straßenrauten auf der Karte.
func _road_between(from: Vector2i, to: Vector2i) -> Array:
	if not _road_cell_ok(to):
		return []
	var prev := {from: from}
	var todo: Array = [from]
	var cursor := 0
	var sx := 1 if to.x >= from.x else -1
	var sy := 1 if to.y >= from.y else -1
	var dirs := [Vector2i(sx, 0), Vector2i(0, sy), Vector2i(-sx, 0), Vector2i(0, -sy)]
	var bounds := Rect2i(Vector2i(mini(from.x, to.x) - 40, mini(from.y, to.y) - 40),
		Vector2i(absi(from.x - to.x) + 81, absi(from.y - to.y) + 81))
	while cursor < todo.size() and cursor < 50000:
		var here: Vector2i = todo[cursor]
		cursor += 1
		if here == to:
			var path: Array = []
			while here != from:
				path.push_front(here)
				here = prev[here]
			return path
		for d in dirs:
			var next: Vector2i = here + d
			if prev.has(next) or not bounds.has_point(next) or not _road_cell_ok(next):
				continue
			prev[next] = here
			todo.append(next)
	return []


func _road_cell_ok(q: Vector2i) -> bool:
	var sim = _sim()
	var C: CityData = sim.city
	if not C.inside(q):
		return false
	if C.is_road(q):
		return true
	var i := C.idx(q)
	if C.building_at[i] >= 0 or C.ground[i] in [CityData.G.WATER, CityData.G.RAIL, CityData.G.RUNWAY, CityData.G.QUAY]:
		return false
	if not C.height.is_empty() and C.height[i] > 0:
		return false
	if sim.access != null and sim.access.reserved(q):
		return false
	var parcel: Dictionary = sim.parcels.at_cell(q)
	if not parcel.is_empty() and not Towns.is_public(str(parcel.owner)):
		return false
	for e in w.estates.estates.values():
		if Rect2i(int(e.rect[0]), int(e.rect[1]), EkoEstates.SIDE, EkoEstates.SIDE).grow(1).has_point(q):
			return false
	return true


## Gebaeude im Rechteck zwischen a und b (beliebige Ecken); -1 wenn nichts passt.
## Startpaket der Gruendung (Benedikt 18.11.): die Stadt beschliesst sofort das Strassennetz ihres Kerns nach Grundform (mit Platz),
## als Erschliessungsprojekt aus dem Startbudget (Baufirma, Material, Bauzeit) – der Kern wartet nicht auf den Buergermeister.
func _start_package(k: int) -> void:
	var sim = _sim()
	var M: Mayor = sim.towns.mayor(k)
	if M == null:
		return
	for v in sim.town_plan.of(k).get("viertel", []):
		if str(v.rolle) == "kern":
			var options: Array = sim.town_plan.design_options(k, str(v.id))
			if not options.is_empty():
				sim.town_plan.choose_design(k, {"viertel": str(v.id), "entwurf": str(options[0].id),
					"reason": "Gründungsentwurf passend zu Gelände und Stadtmarke"})
			var r: Dictionary = M._district_streets(v, "Startpaket der Gründung")
			if bool(r.get("ok", false)):
				sim.log_event("%s: Startpaket – %s" % [sim.towns.name_of(k), str(r.msg).left(200)], "good")
			return


## Darf hier der Stadtkern (Buergeramt) der Stadt k entstehen? Nah am eigenen Betriebshof, weit weg von anderen Staedten und vom
## Grosslager (Benedikt 18.11.: Liorufers Buergeramt stand mitten in Birkenklippe). "" = ja, sonst der Grund.
func hall_site_problem(k: int, cell: Vector2i) -> String:
	var C: CityData = _sim().city
	var st: Dictionary = _sim().settlements.get(str(k), {})
	if st.has("center"):
		var own := Vector2i(int(st.center[0]), int(st.center[1]))
		if absi(own.x - cell.x) + absi(own.y - cell.y) > HALL_R:
			return "zu weit vom eigenen Betriebshof (%d Felder, höchstens %d)" % [absi(own.x - cell.x) + absi(own.y - cell.y), HALL_R]
	for j in C.towns.size():
		var t: Dictionary = C.towns[j]
		if j == k or not bool(t.get("siedlung", false)):
			continue
		var tc := Vector2i(int(t.center[0]), int(t.center[1]))
		if absi(tc.x - cell.x) + absi(tc.y - cell.y) < MIN_TOWN_DIST:
			return "zu nah an %s (%d Felder, mindestens %d)" % [t.name, absi(tc.x - cell.x) + absi(tc.y - cell.y), MIN_TOWN_DIST]
	if not C.hub.is_empty():
		var hr: Array = C.hub.rect
		if Rect2i(int(hr[0]), int(hr[1]), int(hr[2]), int(hr[3])).grow(HUB_DIST).has_point(cell):
			return "zu nah am Großlager (mindestens %d Felder Abstand zum Gelände)" % HUB_DIST
	return ""


## Gebaeude des Typs auf dem naechsten freien Platz um center (ringweise bis radius) setzen; -1 = nichts frei.
func _place_near(type: String, center: Vector2i, radius: int, name: String) -> int:
	var info: Array = CityGenerator.TYPES.get(type, [type, 3, 3])
	var sz := Vector2i(int(info[1]), int(info[2]))
	for r in range(0, radius + 1, 2):
		for dy in range(-r, r + 1, 2):
			for dx in range(-r, r + 1, 2):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var pos := center + Vector2i(dx, dy) - sz / 2
				var bd: Dictionary = _sim().events._add_building(type, Rect2i(pos, sz), name)
				if not bd.is_empty():
					return int(bd.id)
	return -1


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
			if C.inside(q) and C.ground[C.idx(q)] == CityData.G.WATER and absi(dx) + absi(dy) < best_d and is_sea(q):
				best_d = absi(dx) + absi(dy)
				best = q
	if best.x < 0:
		return -1   # nur Seen in der Naehe: kein Anleger (Benedikt 18.11.: "ein Schiff im See macht keinen Sinn")
	var land := best + (cell - best).sign() * 3
	var off := _place("port_office", land + Vector2i(-2, -3), land + Vector2i(2, 3), "Anleger %s" % nm)
	var wh := _place("warehouse", land + Vector2i(-4, -4), land + Vector2i(4, 4), "Hafenlager")
	return wh if off >= 0 and wh >= 0 else -1


## Vorschlag nach einer Ablehnung: der beste erreichbare Platz in der Naehe (mit Weg dorthin), sonst die Richtung zum Weitersuchen.
func _suggest(here: Vector2i) -> String:
	var best := reachable_best(here, 70)
	if best.is_empty():
		best = reachable_best(here, 130)
	if best.is_empty():
		return "In der Nähe passt nichts, was dein LKW erreicht – fahr weiter weg von Großlager und Orten und prüfe dort siedlung.hier."
	var f: Array = best.feld
	return "Nächster passender Platz, den dein LKW erreicht: %s (%d Punkte, %d Felder von hier) – LKW {ziel: %s}, dort Siedlung {feld: %s}." % [
		str(f), int(best.punkte), int(best.get("entfernung", 0)), str(f), str(f)]


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
	var rb := reachable_best(w.tile_of(b), 70)
	if rb.is_empty():
		return "Platz suchen – hier in der Nähe passt nichts, was dein LKW erreicht. Fahr mit dem LKW weiter (LKW {ziel: [x, y]}) und prüfe siedlung.hier."
	var best: Array = [rb]
	var f: Array = best[0].feld
	var here: Vector2i = w.tile_of(b)
	if maxi(absi(here.x - int(f[0])), absi(here.y - int(f[1]))) > ON_SITE:
		return "Bester Platz in deiner Nähe: %s (%d Punkte: %s) – hinfahren mit LKW {ziel: %s}, dort Siedlung {feld: %s}." % [
			str(f), int(best[0].punkte), "; ".join(best[0].gruende), str(f), str(f)]
	return "Du bist am Platz %s (%d Punkte: %s) – Betriebshof und Basis eröffnen: Siedlung {feld: %s}." % [str(f), int(best[0].punkte), "; ".join(best[0].gruende), str(f)]
