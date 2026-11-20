class_name EkoHomes
extends RefCounted
## Neubeginn/Wildnis (Benedikt 17.11.2026): KI-Unternehmer bauen selbst – "er muss alles bauen, Strassen, Haeuser, solange er selber
## keine Angestellten hat".
##
## Baustellen: Wohnhaus (haus_bauen), Buergeramt (buergeramt_bauen; danach gibt es die Stadt und ihren Buergermeister), Strasse
## (strasse_bauen, EkoSettle.plan_road). Ablauf: Material im Grosslager kaufen und mit dem eigenen LKW auf den Betriebshof holen ->
## sobald alles da ist, beginnt der Bau -> gearbeitet wird nur, wenn das Wesen selbst vor Ort arbeitet (Handlung Bauen) oder
## zugeteilte Mitarbeiter (bauleute) da sind. Haeuser wachsen sichtbar Block fuer Block, Strassen Feld fuer Feld.
## Fertige Wohnungen gehoeren der Firma (Miete ueber Housing, Verkauf mit sell_property).

const BOM := {   # Material je Bau (Grosslager-Waren)
	"einfamilienhaus": {"holz": 16, "ziegel": 40, "beton": 12, "glas": 4, "installation": 2},
	"doppelhaus": {"holz": 24, "ziegel": 64, "beton": 20, "glas": 6, "installation": 4},
	"mehrfamilienhaus": {"holz": 30, "ziegel": 120, "beton": 50, "glas": 14, "stahl": 10, "installation": 6},
	"buergeramt": {"holz": 20, "ziegel": 60, "beton": 30, "glas": 8, "installation": 4},
}
const COMMERCIAL := ["supermarkt", "baeckerei_laden", "getraenkemarkt", "drogerie_laden", "moebelhaus", "technik_fachmarkt",
	"restaurant_neu", "buerogebaeude", "lager_werkstatt", "wohn_gewerbehaus"]
const HOMES := ["einfamilienhaus", "doppelhaus", "mehrfamilienhaus", "stadtvilla", "hochhaus"]
# Benedikt 18.11.: Bauzeiten an die Spieluhr angepasst (1 Spieltag = 2 Spielstunden): Einfamilienhaus ~2 Spieltage Arbeit statt 12
const WORK_HOURS := {"einfamilienhaus": 4.0, "doppelhaus": 6.0, "mehrfamilienhaus": 13.0, "buergeramt": 5.0}
const ROAD_HOURS_PER_CELL := 0.1
# Tageloehner vom Grosslager (Benedikt 18.11.): bauen auch ohne den Inhaber, aber nur mit Material; Lohn je Spieltag
const HELPER_MAX := 4
const HELPER_HIRE := 300.0      # Anwerbung und Anfahrt je Kopf
const HELPER_WAGE := 150.0      # Lohn je Kopf und Spieltag
const HALL_HELPER_DELAY := 180.0 # Bürgeramt: nach drei Spielstunden Stillstand fährt ein sichtbarer Bautrupp los
const MAX_SITES := 3
const MAX_CREW := 6
const NEAR := 6                 # so nah muss das Wesen an der Arbeitsstelle sein (Felder)
const AKKU_PER_MIN := 0.12      # Akkuverbrauch beim Bauen je Spielminute
const WALL_H := 6               # Wandhoehe der Bau-Bloecke

var w                           # EkoWorld
var sites := {}                 # ID -> Baustelle
var _next := 1


func setup(world) -> void:
	w = world


func _sim():
	return w.sim


func _depot(cid: int) -> int:
	var c = _sim().company(cid)
	return int(c.depots[0]) if not c.depots.is_empty() else -1


func open_sites(cid: int) -> Array:
	return sites.values().filter(func(s): return int(s.cid) == cid and s.status in ["genehmigung", "material", "bau"])


# ------------------------------------------------------------------ Baustellen anlegen
## Firma {aktion: {action: "haus_bauen", typ, grundstueck?}}
func plan(cid: int, a: Dictionary) -> Dictionary:
	var typ := str(a.get("typ", a.get("art", "einfamilienhaus"))).to_lower().replace(" ", "")
	if typ not in HOMES:
		return {"ok": false, "msg": "Wohnhaustyp unbekannt. Wähle einen Typ aus bauentwuerfe."}
	var design_id := str(a.get("entwurf", ""))
	if not BuildingDesigns.valid_for(design_id, typ):
		return {"ok": false, "msg": "Entwurf %s passt nicht zu %s." % [design_id, typ]}
	return _plan_building(cid, typ, str(a.get("grundstueck", "")), design_id)


func plan_commercial(cid: int, a: Dictionary) -> Dictionary:
	var typ := str(a.get("typ", a.get("art", ""))).to_lower().replace(" ", "")
	if typ not in COMMERCIAL:
		return {"ok": false, "msg": "Gewerbeart unbekannt. Wähle einen Typ aus gewerbeentwuerfe."}
	var design_id := str(a.get("entwurf", ""))
	if not BuildingDesigns.valid_for(design_id, typ):
		return {"ok": false, "msg": "Entwurf %s passt nicht zu %s." % [design_id, typ]}
	return _plan_building(cid, typ, str(a.get("grundstueck", "")), design_id)


## Firma {aktion: {action: "buergeramt_bauen", grundstueck?}} – erst danach gibt es die Stadt (Buergermeister, Siedler, Dienste).
func plan_town_hall(cid: int, a: Dictionary) -> Dictionary:
	var sim = _sim()
	var k: int = sim.companies[cid].home_town
	if sim.town_ready(k):
		return {"ok": false, "msg": "%s hat schon ein Bürgeramt." % sim.towns.name_of(k)}
	if sites.values().any(func(s): return s.typ == "buergeramt" and int(s.cid) == cid and s.status != "abgelehnt"):
		return {"ok": false, "msg": "Das Bürgeramt ist schon in Arbeit."}
	return _plan_building(cid, "buergeramt", str(a.get("grundstueck", "")))


func _plan_building(cid: int, typ: String, want: String, design_id: String = "") -> Dictionary:
	var sim = _sim()
	if open_sites(cid).size() >= MAX_SITES:
		return {"ok": false, "msg": "Höchstens %d Baustellen gleichzeitig – erst eine fertigstellen." % MAX_SITES}
	var k: int = sim.companies[cid].home_town
	if sim.wildnis and not w.settle.founded(k):
		return {"ok": false, "msg": "Erst deinen Betriebshof eröffnen: Siedlung {feld: [x, y]}."}
	var is_hall := typ == "buergeramt"
	var is_commercial := typ in COMMERCIAL
	if not is_hall and design_id == "":
		var profile: Dictionary = sim.town_plan.of(k) if sim.town_plan != null else {}
		var style := str(profile.get("form", ""))
		if style == "" and sim.eko != null:
			style = str(sim.eko.conflict.strategy_for_town(k).get("form", ""))
		if style == "":
			style = "gartenstadt"
		var choice: Dictionary = BuildingDesigns.pick(typ, style, _next + cid * 11, maxf(0.0, sim.company(cid).ledger.cash * 0.75), 0.65)
		if choice.is_empty():
			return {"ok": false, "msg": "Für %s fehlt noch Baukapital. Günstigeren Entwurf wählen oder Mittel ansparen." % typ}
		design_id = str(choice.get("id", ""))
	var design: Dictionary = BuildingDesigns.design(design_id)
	if not is_hall and not sim.tiers.unlocked(typ):
		return {"ok": false, "msg": sim.tiers.unlock_text(typ)}
	var who := "C%d" % cid
	var def_id := "einfamilienhaus" if is_hall else typ
	var floors := 3 if typ == "mehrfamilienhaus" else int(Planning.DEFS[def_id].floors[0])
	var probe := {"def": def_id, "design": design_id, "floors": floors, "parking": int(Planning.DEFS[def_id].parking), "financing": {"eigenmittel": sim.company(cid).ledger.cash}}
	var cands: Array = []
	if want != "":
		var p0: Dictionary = sim.parcels.parcel(want)
		if p0.is_empty():
			return {"ok": false, "msg": "Grundstück %s gibt es nicht." % want}
		if Planning.assess(p0, probe).ok:
			cands = [p0]
	if cands.is_empty() and sim.wildnis and not is_commercial:
		# Wildnis: zuerst die Baugrundstuecke der Siedlung (17.11.: die Suche lieferte nur die 30 billigsten Reststreifen);
		# sind alle belegt, neue um den Hof anlegen
		for attempt in 2:
			for pl in sim.settlements.get(str(k), {}).get("plots", []):
				var pp: Dictionary = sim.parcels.at_cell(Vector2i(int(pl[0]) + 1, int(pl[1]) + 1))
				if not pp.is_empty() and str(pp.state) == "frei":
					cands.append(pp)
			if not cands.is_empty():
				break
			var t: Dictionary = sim.city.towns[k]
			w.settle.carve_area(k, Vector2i(int(t.center[0]), int(t.center[1])), 6)
	if cands.is_empty():
		var utils: Array = ["voll", "teilweise", "keine"] if sim.wildnis else ["voll", "teilweise"]   # Wildnis: Gelaende-LKW braucht keine Strasse
		for z in Planning.DEFS[def_id].zones:
			if z == "oeffentlich" and is_commercial:
				continue
			for u in utils:
				cands += sim.parcels.search({"zone": z, "utilities": u, "town": k, "min_area": int(Planning.DEFS[def_id].w) * int(Planning.DEFS[def_id].h), "limit": 30})
	if want == "" and cands.size() > 1 and sim.town_plan.has(k):   # Auftrag 8: bewertete Reihenfolge (Viertel, Kern, Nachbarschaft)
		var dd: Dictionary = Planning.DEFS[def_id]
		cands = sim.sites.order_parcels(k, cands, {"w": int(dd.w), "h": int(dd.h), "art": "gewerbe" if is_commercial else "wohnen", "floors": floors, "label": str(dd.label)})
	if is_hall and sim.wildnis:   # Stadtkern beim eigenen Betriebshof, nicht in einer anderen Stadt oder am Grosslager
		var bad := ""
		var kept: Array = []
		for p in cands:
			var pc := Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)
			var prob: String = w.settle.hall_site_problem(k, pc)
			if prob == "":
				kept.append(p)
			else:
				bad = "Grundstück %s: %s" % [p.id, prob]
		if kept.is_empty():   # 18.11.: Bauland lag nur an der Strasse zum Grosslager – Platz fuer den Stadtkern direkt am Hof anlegen
			var st: Dictionary = sim.settlements.get(str(k), {})
			if st.has("center"):
				var ctr := Vector2i(int(st.center[0]), int(st.center[1]))
				var ring: Array = []
				for rad in [16, 19, 22]:
					for ang in range(0, 360, 30):
						ring.append(ctr + Vector2i(int(round(cos(deg_to_rad(ang)) * rad)), int(round(sin(deg_to_rad(ang)) * rad))))
				for pl in w.settle.carve_plots(k, ring, 3, true):
					var pp: Dictionary = sim.parcels.at_cell(Vector2i(int(pl[0]) + 1, int(pl[1]) + 1))
					if not pp.is_empty() and str(pp.state) == "frei" and w.settle.hall_site_problem(k, Vector2i(int(pl[0]) + int(pl[2]) / 2, int(pl[1]) + int(pl[3]) / 2)) == "":
						kept.append(pp)
		if kept.is_empty():
			return {"ok": false, "msg": "Kein Platz für das Bürgeramt bei deinem Betriebshof%s. Baue eine Straße am Betriebshof (strasse_bauen) – daran entsteht Bauland." % ((" – " + bad) if bad != "" else "")}
		cands = kept
	var why := "kein freies Baugrundstück – mit strasse_bauen entstehen neue an der Straße"
	for p in cands:
		var chk := Planning.assess(p, probe)
		if not chk.ok or not chk.questions.is_empty():
			why = " ".join(chk.blocking + chk.questions)
			continue
		if float(p.price) > sim.company(cid).ledger.cash:
			why = "Grundstück %s kostet %s" % [p.id, Catalog.money(float(p.price))]
			continue
		if not sim.parcels.reserve(p.id, who).ok:
			continue
		var app := ""
		var status := "material"
		if sim.town_ready(k) and not is_hall:   # mit Buergeramt: Bauantrag, der Buergermeister entscheidet
			var dr: Dictionary = sim.permits.draft(who, p.id, probe)
			if not dr.ok:
				sim.parcels.release(p.id, who)
				why = str(dr.msg)
				continue
			sim.permits.submit(dr.id)
			app = str(dr.id)
			status = "genehmigung"
		sim.company(cid).ledger.invest(float(p.price), Towns.account_of(maxi(0, k)))   # Grund ist Vermoegen
		p.owner = Towns.owner_of(k) if is_hall else who
		p.state = "privat_gehalten"
		p.reservation = {}
		sim.parcels._touch(p)
		var foot := int(Planning.DEFS[def_id].w) * int(Planning.DEFS[def_id].h) * floors
		var need: Dictionary = BOM[typ].duplicate() if BOM.has(typ) else {"holz": foot * 2, "ziegel": foot * 3, "beton": foot,
			"glas": maxi(3, int(ceil(float(foot) / 3.0))), "installation": maxi(2, int(ceil(float(foot) / 6.0)))}
		for item in need:
			need[item] = ceili(float(need[item]) * float(design.get("cost_factor", 1.0)))
		var s := {"id": "BS%d" % _next, "cid": cid, "typ": typ, "design": design_id, "floors": floors, "parcel": p.id, "app": app, "status": status,
			"need": need, "progress": 0.0, "work": float(WORK_HOURS.get(typ, maxf(4.0, float(foot) * 0.25))) * float(design.get("cost_factor", 1.0)), "crew": [], "building": -1, "day": sim.game_min, "placed": 0}
		_next += 1
		sites[s.id] = s
		var label: String = "Bürgeramt" if is_hall else str(design.get("label", Planning.DEFS[typ].label))
		sim.log_event("%s plant %s auf %s." % [sim.company(cid).company_name, label, p.id], "info", cid)
		return {"ok": true, "msg": "Baustelle %s: %s auf %s (%s)%s. Material: %s – kaufen (hub_buy), mit dem LKW holen (LKW {ziel: \"grosslager\"}), dann selbst bauen (Bauen {baustelle: \"%s\"})." % [
			s.id, label, p.id, Catalog.money(float(p.price)), (", Bauantrag %s" % app) if app != "" else "", _need_text(s), s.id], "baustelle": s.id}
	return {"ok": false, "msg": "Kein Bauplatz gefunden: %s." % why}


## Strassenbaustelle (EkoSettle.plan_road): cells in Bau-Reihenfolge.
func add_road_site(cid: int, cells: Array, need: Dictionary) -> Dictionary:
	if open_sites(cid).size() >= MAX_SITES:
		return {"ok": false, "msg": "Höchstens %d Baustellen gleichzeitig – erst eine fertigstellen." % MAX_SITES}
	var s := {"id": "BS%d" % _next, "cid": cid, "typ": "strasse", "cells": cells.map(func(q): return [q.x, q.y]), "status": "material", "need": need,
		"progress": 0.0, "work": float(cells.size()) * ROAD_HOURS_PER_CELL, "crew": [], "building": -1, "day": _sim().game_min, "placed": 0}
	_next += 1
	sites[s.id] = s
	_sim().access.invalidate_city_reservations()
	return {"ok": true, "msg": "Straßenbaustelle %s: %d Felder. Material: %s – vom Hof; dann Bauen {baustelle: \"%s\"} (Feld für Feld)." % [
		s.id, cells.size(), _need_text(s), s.id], "baustelle": s.id}


## Firma {aktion: {action: "bauleute", baustelle, worker_ids}}
func assign_crew(cid: int, a: Dictionary) -> Dictionary:
	var s: Dictionary = sites.get(str(a.get("baustelle", "")), {})
	if s.is_empty() or int(s.cid) != cid:
		return {"ok": false, "msg": "Baustelle %s gehört dir nicht. Deine: %s." % [a.get("baustelle", ""), ", ".join(open_sites(cid).map(func(x): return x.id))]}
	var raw = a.get("worker_ids", a.get("mitarbeiter", []))
	var ids: Array = raw if raw is Array else [str(raw)]
	var crew: Array = []
	for id in ids:
		var wk = _sim().personnel.workers.get(str(id))
		if wk == null or wk.employer != cid or wk.lost:
			return {"ok": false, "msg": "%s ist nicht bei dir angestellt." % id}
		crew.append(str(id))
	s.crew = crew.slice(0, MAX_CREW)
	return {"ok": true, "msg": "Baustelle %s: Bautruppe %s." % [s.id, ", ".join(s.crew) if not s.crew.is_empty() else "keine"]}


func _need_text(s: Dictionary) -> String:
	var parts: Array = []
	for item in s.need:
		parts.append("%d %s" % [int(s.need[item]), item])
	return ", ".join(parts)


## Was fehlt noch auf dem Betriebshof? {item: menge}
func missing(s: Dictionary) -> Dictionary:
	var sim = _sim()
	var out := {}
	for item in s.need:
		var have: int = sim.stock.available(item, "C%d" % int(s.cid), _depot(int(s.cid)))
		if have < int(s.need[item]):
			out[item] = int(s.need[item]) - have
	return out


# ------------------------------------------------------------------ Arbeitsstelle und Bautruppe
## Wo wird gerade gearbeitet? Haus: Mitte des Grundstuecks; Strasse: das naechste Feld.
func work_cell(s: Dictionary) -> Vector2i:
	if s.typ == "strasse":
		var cs: Array = s.cells
		var i := mini(int(s.placed), cs.size() - 1)
		return Vector2i(int(cs[i][0]), int(cs[i][1]))
	var p: Dictionary = _sim().parcels.parcel(str(s.parcel))
	return Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2) if not p.is_empty() else Vector2i.ZERO


## Arbeitet das Wesen der Firma gerade selbst hier? (Handlung Bauen, nah genug, nicht im LKW, Akku nicht leer)
func owner_working(s: Dictionary) -> bool:
	var name: String = w.firm_being(int(s.cid))
	if name == "" or not w.beings.has(name):
		return false
	var b: Dictionary = w.beings[name]
	if str(b.get("baut", "")) != str(s.id) or b.has("im_lkw") or float(b.get("akku", 100.0)) < 5.0:
		return false
	var t: Vector2i = w.tile_of(b)
	var c := work_cell(s)
	return maxi(absi(t.x - c.x), absi(t.y - c.y)) <= NEAR


func crew_now(s: Dictionary) -> int:
	var sim = _sim()
	var n := 1 if owner_working(s) else 0
	var hf: Dictionary = s.get("helfer", {})
	if str(hf.get("status", "")) == "vor_ort":
		n += int(hf.n)
	for id in s.crew:
		var wk = sim.personnel.workers.get(str(id))
		if wk != null and wk.employer == int(s.cid) and not wk.lost and str(wk.task_id) == "" and int(wk.vehicle_id) < 0:
			n += 1
	return n


# ------------------------------------------------------------------ Takt
func tick(dt_min: float) -> void:
	var sim = _sim()
	for s in sites.values():
		_pay_helpers(s, dt_min)
		match str(s.status):
			"genehmigung":
				var app: Dictionary = sim.permits.apps.get(str(s.app), {})
				if not app.is_empty() and str(app.status) == "entschieden":
					if str(app.result).begins_with("genehmigt"):
						s.status = "material"
						sim.notify(int(s.cid), "Baustelle %s genehmigt – Material holen: %s." % [s.id, _need_text(s)])
					else:
						s.status = "abgelehnt"
						sim.notify(int(s.cid), "Baustelle %s: Antrag abgelehnt (%s)." % [s.id, str(app.get("decision", "")).left(120)])
			"material":
				if missing(s).is_empty():
					for item in s.need:
						sim.stock.consume(item, int(s.need[item]), "C%d" % int(s.cid), _depot(int(s.cid)), "Baustelle %s" % s.id, sim.game_min)
					s.status = "bau"
					s["ready_min"] = sim.game_min
					if s.typ != "strasse":
						sim.parcels.mark(str(s.parcel), "im_bau", str(s.app))
					sim.log_event("%s: Baustelle %s – Material da, es kann gebaut werden." % [sim.company(int(s.cid)).company_name, s.id], "info", int(s.cid))
			"bau":
				if float(s.progress) >= float(s.work):
					_finish(s)   # 18.11.: Abschluss scheiterte einmal (Platz) – ohne Arbeiter wurde er nie wieder versucht
					continue
				var crew := crew_now(s)
				if crew <= 0:
					# Die KI hat den Bau bereits beschlossen und das Material beschafft. Bleibt das Bürgeramt dennoch liegen,
					# organisiert die Firma einen sichtbaren Bautrupp; die Standort- und Bauentscheidung bleibt bei der KI.
					if s.typ == "buergeramt" and sim.wildnis and not sim.town_ready(sim.company(int(s.cid)).home_town) \
							and not s.has("helfer") and sim.game_min - float(s.get("ready_min", sim.game_min)) >= HALL_HELPER_DELAY \
							and sim.game_min >= float(s.get("helper_retry_min", 0.0)):
						s["helper_retry_min"] = sim.game_min + HALL_HELPER_DELAY
						var hired: Dictionary = hire_helpers(int(s.cid), {"baustelle": s.id, "anzahl": 2})
						if bool(hired.get("ok", false)):
							sim.log_event("%s schickt zwei Tagelöhner zum feststeckenden Bürgeramt %s." % [sim.company(int(s.cid)).company_name, s.id], "good", int(s.cid))
					continue
				if owner_working(s):
					var b: Dictionary = w.beings[w.firm_being(int(s.cid))]
					b.akku = maxf(0.0, float(b.get("akku", 100.0)) - AKKU_PER_MIN * dt_min)
				s.progress = minf(float(s.work), float(s.progress) + float(crew) * dt_min / 60.0)
				if s.typ == "strasse":
					_road_progress(s)
				else:
					_block_progress(s)
				if float(s.progress) >= float(s.work):
					_finish(s)


func _road_progress(s: Dictionary) -> void:
	var cs: Array = s.cells
	var done := mini(cs.size(), int(float(s.progress) / ROAD_HOURS_PER_CELL))
	if done <= int(s.placed):
		return
	var k: int = _sim().companies[int(s.cid)].home_town
	var new_cells: Array = []
	for i in range(int(s.placed), done):
		new_cells.append(Vector2i(int(cs[i][0]), int(cs[i][1])))
	w.settle.lay_road_cells(k, new_cells)
	s.placed = done


## Sichtbarer Rohbau: Waende (Ziegel) und Dach (Holz) aus Bloecken, je nach Fortschritt.
func _shell(s: Dictionary) -> Array:
	var p: Dictionary = _sim().parcels.parcel(str(s.parcel))
	if p.is_empty():
		return []
	var d: Dictionary = Planning.DEFS["einfamilienhaus" if s.typ == "buergeramt" else s.typ]
	var fw := mini(int(d.w) if s.typ != "buergeramt" else 8, int(p.rect[2]) - 1)
	var fh := mini(int(d.h) if s.typ != "buergeramt" else 3, int(p.rect[3]) - 1)
	var P := EkoWorld.PER_TILE
	var x0 := (int(p.rect[0]) + 1) * P
	var y0 := (int(p.rect[1]) + 1) * P
	var x1 := x0 + fw * P - 1
	var y1 := y0 + fh * P - 1
	var out: Array = []
	for z in WALL_H:
		for x in range(x0, x1 + 1):
			out.append([x, y0, z, "ziegel"])
			out.append([x, y1, z, "ziegel"])
		for y in range(y0 + 1, y1):
			out.append([x0, y, z, "ziegel"])
			out.append([x1, y, z, "ziegel"])
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			out.append([x, y, WALL_H, "holz"])
	return out


func _block_progress(s: Dictionary) -> void:
	var shell := _shell(s)
	var target := int(float(shell.size()) * float(s.progress) / float(s.work))
	for i in range(int(s.placed), mini(target, shell.size())):
		var bl: Array = shell[i]
		var q := Vector3i(int(bl[0]), int(bl[1]), int(bl[2]))
		if not w.blocks.has(q):
			w.blocks[q] = str(bl[3])
	if target > int(s.placed):
		s.placed = target
		w.changed.emit()


func _clear_shell(s: Dictionary) -> void:
	for bl in _shell(s):
		w.blocks.erase(Vector3i(int(bl[0]), int(bl[1]), int(bl[2])))
	w.changed.emit()


func _finish(s: Dictionary) -> void:
	var sim = _sim()
	var cid := int(s.cid)
	var c = sim.company(cid)
	var k: int = sim.companies[cid].home_town
	if s.typ == "strasse":
		s.status = "fertig"
		var cells: Array = (s.cells as Array).map(func(a): return Vector2i(int(a[0]), int(a[1])))
		var plots: Array = w.settle.carve_plots(k, cells, 6)
		sim.log_event("%s hat %d Felder Straße gebaut (%d neue Baugrundstücke)." % [c.company_name, cells.size(), plots.size()], "good", cid)
		_release_builder(s)
		return
	var parcel: Dictionary = sim.parcels.parcel(str(s.parcel))
	var r := Rect2i(int(parcel.rect[0]), int(parcel.rect[1]), int(parcel.rect[2]), int(parcel.rect[3]))
	_clear_shell(s)
	if s.typ == "buergeramt":
		if not w.settle.open_town(k, r):
			s["blockiert"] = "Bürgeramt passt nicht aufs Grundstück."
			return
		s.status = "fertig"
		_release_builder(s)
		return
	var d: Dictionary = Planning.DEFS[s.typ]
	var design: Dictionary = BuildingDesigns.design(str(s.get("design", "")))
	var b: Dictionary = sim.events._add_building(str(d.sprite), r, "%s (%s)" % [str(design.get("label", d.label)), c.company_name], {}, str(design.get("sprite", "")))
	if b.is_empty():
		s["blockiert"] = "Gebäude passt nicht aufs Grundstück."
		return
	s.status = "fertig"
	s.building = int(b.id)
	b["owner"] = "C%d" % cid
	sim.events.added_buildings[-1]["owner"] = b.owner
	sim.market.refresh()
	sim.residents.add_for_buildings([b.id])
	if str(d.use) in ["versorgung", "gewerbe", "misch"]:
		sim.retail.on_building_added(b)
	sim.events.buildings_added.emit([b.id])
	var n := Planning.units_of(str(s.typ), int(s.floors)) if str(d.use) in ["wohnen", "misch"] else 0
	sim.towns.mayor(maxi(0, k)).stock_units += n
	for i in n:
		sim.housing.register_unit(int(b.id), float(design.get("area", 60.0 + 10.0 * float(i % 3))), "C%d" % cid, int(design.get("comfort", 60)))
	sim.log_event("%s hat %s fertig gebaut (%d Wohnungen, Entwurf %s)." % [c.company_name, str(design.get("label", d.label)), n, str(s.get("design", "Standard"))], "good", cid)
	sim.activity.add("stadt", cid, "bau", "Neues %s" % d.label, c.company_name, b.walk)
	_release_builder(s)


func _release_builder(s: Dictionary) -> void:
	_helpers_home(s)
	_release_builder_only(s)


func _release_builder_only(s: Dictionary) -> void:
	var name: String = w.firm_being(int(s.cid))
	if name != "" and w.beings.has(name) and str(w.beings[name].get("baut", "")) == str(s.id):
		w.beings[name].erase("baut")
		w._event(w.beings[name], "Baustelle %s ist fertig." % s.id)


# ------------------------------------------------------------------ Tageloehner
## Firma {aktion: {action: "tageloehner", baustelle, anzahl}}: Hilfskraefte kommen vom Grosslager (sichtbarer Transporter, querfeldein)
## und bauen, sobald sie vor Ort sind und das Material da ist – auch wenn der Inhaber woanders ist. Nach Bauende fahren sie zurueck.
func hire_helpers(cid: int, a: Dictionary) -> Dictionary:
	var sim = _sim()
	var s: Dictionary = sites.get(str(a.get("baustelle", "")), {})
	if s.is_empty() or int(s.cid) != cid or str(s.status) in ["fertig", "abgelehnt"]:
		return {"ok": false, "msg": "Keine offene Baustelle %s von dir. Deine: %s." % [a.get("baustelle", ""), ", ".join(open_sites(cid).map(func(x): return x.id))]}
	var n := clampi(int(a.get("anzahl", a.get("n", 2))), 1, HELPER_MAX)
	var hf: Dictionary = s.get("helfer", {})
	if not hf.is_empty():
		return {"ok": false, "msg": "Auf Baustelle %s sind schon %d Tagelöhner (%s)." % [s.id, int(hf.n), hf.status]}
	var c = sim.company(cid)
	var cost := HELPER_HIRE * float(n)
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Anwerbung kostet %s, Kasse %s." % [Catalog.money(cost), Catalog.money(c.ledger.cash)]}
	var hub_b: Dictionary = sim.city.building(int(sim.city.hub.get("buildings", {}).get("hauptlager", -1)))
	var start: Vector2i = hub_b.road if not hub_b.is_empty() else work_cell(s)
	if not sim.fleet.send_helpers(start, work_cell(s), str(s.id), "%d Tagelöhner → %s" % [n, s.id]):
		return {"ok": false, "msg": "Vom Großlager führt kein Weg zur Baustelle %s." % s.id}
	c.ledger.book("wages", -cost, true, "Tagelöhner anwerben (%d) für %s" % [n, s.id], sim.game_min, "Y0")
	s["helfer"] = {"n": n, "status": "anreise", "acc": 0.0}
	return {"ok": true, "msg": "%d Tagelöhner kommen vom Großlager zur Baustelle %s (%s; danach %s je Kopf und Spieltag). Sie bauen, sobald das Material da ist – auch ohne dich." % [
		n, s.id, Catalog.money(cost), Catalog.money(HELPER_WAGE)]}


func helpers_arrived(site_id: String) -> void:
	var s: Dictionary = sites.get(site_id, {})
	if s.has("helfer"):
		s.helfer.status = "vor_ort"
		_sim().log_event("Tagelöhner sind an Baustelle %s angekommen." % site_id, "info", int(s.cid))


func _pay_helpers(s: Dictionary, dt_min: float) -> void:
	var hf: Dictionary = s.get("helfer", {})
	if hf.is_empty():
		return
	hf.acc = float(hf.get("acc", 0.0)) + dt_min
	var day_min := GameCalendar.days_to_min(1.0)
	if float(hf.acc) < day_min:
		return
	hf.acc = float(hf.acc) - day_min
	var sim = _sim()
	var c = sim.company(int(s.cid))
	var wage := HELPER_WAGE * float(hf.n)
	if c.ledger.cash < wage:
		sim.notify(int(s.cid), "Tagelöhner an %s gehen – kein Geld für den Lohn." % s.id)
		_helpers_home(s)
		return
	c.ledger.book("wages", -wage, true, "Tagelöhner %s (%d)" % [s.id, int(hf.n)], sim.game_min, "Y0")


func _helpers_home(s: Dictionary) -> void:
	if not s.has("helfer"):
		return
	s.erase("helfer")
	_sim().fleet.helpers_leave(str(s.id))


## Gewerbe (Benedikt 18.11.): sobald Menschen in der Stadt wohnen und die Firma noch keinen Betrieb hat, einen ersten vorschlagen.
func business_hint(cid: int) -> String:
	var sim = _sim()
	var k: int = sim.companies[cid].home_town
	if not sim.wildnis or not sim.town_ready(k) or sim.citizens.population_of(k) <= 0:
		return ""
	if sim.biz.items.values().any(func(b): return int(b.get("owner", -1)) == cid and str(b.get("status", "")) != "geschlossen"):
		return ""
	return ("In %s wohnen jetzt Menschen (%d) – Zeit für Gewerbe: ein erster Betrieb bringt Umsatz und Arbeitsplätze, z. B. " +
		"Firma {aktion: {action: \"found_business\", branche: \"baeckerei\"}} (Laden mit Theke) oder eine Kiesgrube für deinen eigenen Straßenbau " +
		"(found_business branche: \"bergwerk\", rohstoff: \"kies\").") % [sim.towns.name_of(k), sim.citizens.population_of(k)]


# ------------------------------------------------------------------ Beobachtung und naechste Schritte
func summary(cid: int) -> Array:
	var out: Array = []
	for s in sites.values():
		if int(s.cid) != cid or s.status == "abgelehnt":
			continue
		var wc := work_cell(s)
		var e := {"id": s.id, "typ": s.typ, "status": s.status, "arbeitsstelle": [wc.x, wc.y]}
		if s.typ != "strasse":
			e["grundstueck"] = s.parcel
		if s.status == "material":
			e["fehlt_auf_dem_betriebshof"] = missing(s)
		if s.status == "bau":
			e["fortschritt"] = "%d %%" % int(100.0 * float(s.progress) / float(s.work))
			e["du_arbeitest_hier"] = owner_working(s)
			e["bautruppe"] = s.crew
		if s.status == "fertig" and int(s.building) >= 0:
			e["gebaeude"] = s.building
		out.append(e)
	return out.slice(-6)


## Klartext zu einer Baustelle (Inspect BS…): Stand, was fehlt, was zu tun ist.
func site_text(cid: int, id: String) -> String:
	var s: Dictionary = sites.get(id, {})
	if s.is_empty():
		return ""
	var wc := work_cell(s)
	var head := "Baustelle %s (%s) bei %s: " % [s.id, s.typ, str([wc.x, wc.y])]
	match str(s.status):
		"genehmigung":
			return head + "wartet auf die Genehmigung des Bürgermeisters."
		"material":
			var m := missing(s)
			var wg := waiting_goods(cid)
			var to_buy: Array = m.keys().filter(func(x): return int(wg.get(x, 0)) < int(m[x]))
			if to_buy.is_empty():   # alles gekauft, liegt am Grosslager
				return head + "alles Material ist gekauft und liegt am Großlager (%s) – NICHT nochmal kaufen, nur abholen: LKW {ziel: \"grosslager\"}." % ", ".join(m.keys().map(func(x): return "%d %s" % [m[x], x]))
			return head + "es fehlt noch auf deinem Hof: %s – kaufen (hub_buy) nur: %s; Gekauftes liegt am Großlager, mit dem LKW holen." % [", ".join(m.keys().map(func(x): return "%d %s" % [m[x], x])), ", ".join(to_buy)]
		"bau":
			var who := "du arbeitest gerade hier" if owner_working(s) else ("Tagelöhner arbeiten hier" if not (s.get("helfer", {}) as Dictionary).is_empty() else "NIEMAND arbeitet")
			return head + "Material vollständig, %d %% gebaut, %s. %s" % [int(100.0 * float(s.progress) / float(s.work)), who,
				"" if who != "NIEMAND arbeitet" else "Bauen {baustelle: \"%s\"} oder Firma {aktion: {action: \"tageloehner\", baustelle: \"%s\", anzahl: 2}}." % [s.id, s.id]]
		"fertig":
			return head + "fertig."
	return head + str(s.status)


## Kauf ohne Bedarf (Partie 18.11.: Viktor kaufte drei Mal Kies fuer eine Strasse, die es nicht gab, waehrend sein Buergeramt mit vollem
## Material auf Arbeit wartete): Hinweis, welche Baustelle stattdessen wartet. "" = Ware wird gebraucht oder es gibt keine Baustelle.
func purchase_note(cid: int, item: String, qty: int = 0) -> String:
	var open := open_sites(cid)
	if open.is_empty():
		return ""
	var sim = _sim()
	var bought: int = sim.hub.pending("C%d" % cid, item) if sim.hub != null and sim.hub.enabled else 0
	for s in open:
		if s.status == "material" and missing(s).has(item):
			if qty > 0 and bought - qty >= int(missing(s)[item]):   # Partie 18.11.: Greta kaufte das Material fuer ihr Buergeramt dreimal
				return " ACHTUNG: %d %s waren schon gekauft und liegen am Großlager – das war ein Doppelkauf. Nicht nochmal kaufen, sondern abholen: LKW {ziel: \"grosslager\"}." % [bought - qty, item]
			return ""
	var idle: Array = open.filter(func(s): return s.status == "bau" and not owner_working(s) and (s.get("helfer", {}) as Dictionary).is_empty())
	var tip := (" Stattdessen wartet %s (%s) mit vollständigem Material auf Arbeit: Bauen {baustelle: \"%s\"} oder Tagelöhner." % [idle[0].id, idle[0].typ, idle[0].id]) if not idle.is_empty() else ""
	return " Hinweis: keine deiner Baustellen braucht %s (offen: %s).%s" % [item, ", ".join(open.map(func(s): return "%s %s %s" % [s.id, s.typ, s.status])), tip]


## Gekaufte Ware, die noch im Grosslager liegt.
func waiting_goods(cid: int) -> Dictionary:
	var out := {}
	for d in _sim().hub.deals.values():
		if str(d.kind) == "kauf" and str(d.party) == "C%d" % cid and str(d.status) == "abholbereit":
			out[str(d.item)] = int(out.get(str(d.item), 0)) + int(d.qty)
	return out


## Naechster sinnvoller Schritt fuer die Firma ("" = keiner).
func next_step(cid: int) -> String:
	# Reihenfolge nach dem Ziel Wachstum (Benedikt 18.11.; Partie 14:13: Greta baute 84 Strassenfelder, aber kein Buergeramt, und beiden
	# Unternehmern stand "gekaufte Ware abholen" ganz oben, auch wenn keine Baustelle sie brauchte – Viktors Buergeramt stand bei 0 %).
	var sim = _sim()
	var k: int = sim.companies[cid].home_town
	var open := open_sites(cid)
	var wait := waiting_goods(cid)
	var fetch := "Im Großlager liegt deine gekaufte Ware (%s) – selbst abholen: LKW {ziel: \"grosslager\"} (du fährst mit und lädst auf dem Hof ab)."
	# 1) Buergeramt: erst damit gibt es Stadt, Buergermeister, Siedler und Stadtlager
	if sim.wildnis and w.settle.founded(k) and not sim.town_ready(k) and not sites.values().any(func(s): return s.typ == "buergeramt" and int(s.cid) == cid and s.status != "abgelehnt"):
		return "Zuerst das Bürgeramt – erst damit gibt es deine Stadt, einen Bürgermeister, Siedler und Lieferungen: Firma {aktion: {action: \"buergeramt_bauen\"}}."
	# Ein bereits gewählter Bauauftrag bleibt vorrangig, bis er fertig ist. Sonst schickte die KI den Inhaber mitten im Rohbau
	# erneut zum Großlager und die Baustelle blieb bei 0 % stehen.
	var founder: String = w.firm_being(cid)
	var building: String = str(w.beings.get(founder, {}).get("baut", "")) if founder != "" else ""
	for s in open:
		if s.status == "bau" and str(s.id) == building:
			return "Du baust an Baustelle %s (%s, %d %%). Bleib dort und lass die Arbeit weiterlaufen; warte bis zur Ankunft oder 20 Sekunden. Kaufe dafür kein weiteres Material und fahre nicht weg." % [s.id, s.typ, int(100.0 * float(s.progress) / float(s.work))]
	# 2) stillstehende Baustelle (Buergeramt zuerst)
	var idle: Array = open.filter(func(s): return s.status == "bau" and not owner_working(s) and (s.get("helfer", {}) as Dictionary).is_empty())
	idle.sort_custom(func(a, b): return a.typ == "buergeramt" and b.typ != "buergeramt")
	if not idle.is_empty():
		var s: Dictionary = idle[0]
		return ("Baustelle %s (%s, %d %%) wartet: selbst arbeiten – Bauen {baustelle: \"%s\"} – oder Tagelöhner vom Großlager holen, die auch ohne dich bauen: " +
			"Firma {aktion: {action: \"tageloehner\", baustelle: \"%s\", anzahl: 2}} (%s je Kopf, dann %s je Kopf und Spieltag).") % [
			s.id, s.typ, int(100.0 * float(s.progress) / float(s.work)), s.id, s.id, Catalog.money(HELPER_HIRE), Catalog.money(HELPER_WAGE)]
	# 3) gekaufte Ware abholen, die eine Baustelle braucht; 4) fehlendes Material kaufen
	var needed := {}
	for s in open:
		if s.status == "material":
			for item in missing(s):
				needed[item] = true
	var wanted := {}
	for item in wait:
		if needed.has(item):
			wanted[item] = wait[item]
	if not wanted.is_empty():
		return fetch % ", ".join(wanted.keys().map(func(x): return "%d %s" % [wanted[x], x]))
	for s in open:
		if s.status == "material":
			var m := missing(s)
			if m.is_empty():
				continue   # Material eben angekommen – der Bau beginnt im naechsten Takt (18.11.: Index-Fehler)
			# 19.11.: qwen3.5:9b kaufte die fuenf Materialien des Buergeramts nie einzeln – ein Schritt kauft alles Fehlende
			return "Baustelle %s braucht Material (%s): alles auf einmal kaufen – Firma {aktion: {action: \"hub_buy\", baustelle: \"%s\"}} – dann mit dem LKW holen (LKW {ziel: \"grosslager\"})." % [
				s.id, ", ".join(m.keys().map(func(x): return "%d %s" % [m[x], x])), s.id]
	# 5) Strasse zum Grosslager, Gewerbe, Wohnraum. Der staedtische Anschluss ist bereits ein eigener Bauauftrag.
	# Eine parallel empfohlene Firmenstrasse scheitert an dessen reservierter Trasse und lenkt vom ersten Haus ab.
	if sim.wildnis and sim.town_ready(k) and not open.any(func(s): return s.typ == "strasse"):
		var link: Dictionary = w.settle.road_link(k)
		var city_connector: bool = sim.towns.mayor(k).projects.values().any(func(p): return str(p.get("ref", "")) == "anschluss" and str(p.status) not in ["fertig", "abgelehnt", "abgebrochen"])
		if not city_connector and not bool(link.get("verbunden", true)) and link.has("von"):
			return ("Deine Stadt hat keine Straße zum Großlager – ohne Straße liefert niemand Waren (Stadtlager, Kunden, Siedler). Straße bauen, Stück für Stück " +
				"(je Baustelle bis %d Felder, noch ~%d): Firma {aktion: {action: \"strasse_bauen\", von: %s, bis: %s}} – dann Kies holen und Bauen.") % [
				EkoSettle.ROAD_MAX, int(link.felder), str(link.von), str(link.bis)]
	var biz_hint := business_hint(cid)
	if biz_hint != "":
		return biz_hint
	if sim.town_ready(k) and not open.any(func(s): return s.typ != "strasse"):
		return "Wohnraum bauen – mit Wohnungen kommen Siedler: Firma {aktion: {action: \"haus_bauen\", typ: \"einfamilienhaus\"}}."
	# 6) uebrige gekaufte Ware
	if not wait.is_empty():
		return fetch % ", ".join(wait.keys().map(func(x): return "%d %s" % [wait[x], x]))
	return ""


func to_dict() -> Dictionary:
	return {"sites": sites, "next": _next}


func from_dict(d: Dictionary) -> void:
	sites = d.get("sites", {})
	_next = int(d.get("next", 1))
	for s in sites.values():
		if str(s.status) == "bau" and not s.has("ready_min"):
			s["ready_min"] = _sim().game_min
		for item in s.need:
			s.need[item] = int(s.need[item])
		s["placed"] = int(s.get("placed", 0))
		if not s.has("work"):
			s["work"] = float(WORK_HOURS.get(str(s.typ), 24.0))
		var target: float = float((s.get("cells", []) as Array).size()) * ROAD_HOURS_PER_CELL if str(s.typ) == "strasse" else float(WORK_HOURS.get(str(s.typ), float(s.work)))
		if float(s.work) > target * 1.01:   # alte Spielstaende: lange Bauzeiten anteilig umrechnen (18.11.)
			s["progress"] = float(s.progress) * target / float(s.work)
			s["work"] = target
		var hf: Dictionary = s.get("helfer", {})
		if str(hf.get("status", "")) == "anreise":
			hf["status"] = "vor_ort"   # der Fuhrpark wird nicht gespeichert: Tageloehner gelten als angekommen
