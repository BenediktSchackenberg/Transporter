class_name AccessRoads
extends RefCounted
## Zufahrten (Auftrag 15, Etappen B und D): Schotterweg von einer abgelegenen Lagerstaette zur naechsten Strasse, bei Bedarf mit
## Bruecken ueber Fluss oder See (nie ueber das Meer). Ablauf: der Unternehmer stellt einen Erschliessungsantrag (`request`), der
## Buergermeister entscheidet (`decide`; ohne Entscheidung nach ANTRAG_FRIST Tagen das Bauamt). Genehmigt: der Unternehmer zahlt den
## Erschliessungsbeitrag fuer den Weg, die Stadt traegt die Bruecken; Weg und Bruecken werden als Stadtprojekte an Baufirmen vergeben
## (Unternehmer-Baufirmen bevorzugt). Der Weg waechst mit dem Baufortschritt der Firma von der Strasse her; jede fertige Zelle wird
## Strasse. Der Buergermeister kann auch selbst erschliessen (`order_city`, alles aus der Stadtkasse).

signal roads_built(cells: Array)   # neue Strassenzellen (Darstellung)

const BASE_COST := 3000.0          # Planung, Vermessung, Anschluss
const CELL_COST := 80.0            # Schotterweg je Feld
const CLEAR_COST := 60.0           # Rodung je Baumfeld
const CELLS_PER_DAY := 15          # Baufortschritt einer Wegebau-Kolonne
const MAX_RUNNING := 2
const ANTRAG_FRIST := 1            # Tage bis das Bauamt ohne Buergermeister entscheidet
const ROAD_MATERIAL := {"schotter": 2, "kies": 1}   # je Feld Schotterweg
const DETOUR_MIN := 40             # Bruecke lohnt, wenn sie mindestens so viele Felder Umweg spart ...
const DETOUR_FACTOR := 2.0         # ... und der Landweg mindestens doppelt so lang ist

var sim
var jobs := {}                     # "Z<n>" -> {id, parcel, company, cells: [[x, y]], built, cost, beitrag, stadtanteil, spans, bridges, project, status (antrag|im_bau|fertig|abgelehnt)}
var _next := 1
var _cache := {}                   # Grundstueck -> Plan (gueltig bis eine Zufahrt fertig wird)
var _fields := {}                  # "land"/"wasser" -> Entfernungsfeld zur Strasse


func setup(simulation) -> void:
	sim = simulation


## Weg vom Grundstueck zur naechsten Strasse (Breitensuche ueber Land, sonst ueber Fluss/See mit Bruecken).
## Ergebnis: {ok, cells, kosten, tage, baeume, bruecken: [Brueckenplan]} oder {ok: false, msg}. need_t: noetige Tragfaehigkeit.
func plan(pid: String, need_t: int = Bridges.LOAD_MINE) -> Dictionary:
	var key := "%s:%d" % [pid, need_t]
	if _cache.has(key):
		return _cache[key]
	var p: Dictionary = sim.parcels.parcel(pid)
	if p.is_empty():
		return {"ok": false, "msg": "Unbekanntes Grundstück %s." % pid}
	var res := _search(p, false)
	if res.ok:
		_price(res, {"spans": [], "kosten": 0.0, "tage": 0})
	if not res.ok or res.cells.size() > DETOUR_MIN:
		# Weg ueber Fluss/See: noetig, wenn kein Landweg besteht; sonst nur, wenn er billiger ist oder einen langen Umweg spart
		var wet := _search(p, true)
		var spans: Dictionary = sim.bridges.plan_spans(wet.cells, need_t) if wet.ok else {}
		if wet.ok and spans.ok and not spans.spans.is_empty():
			_price(wet, spans)
			var saved: int = res.cells.size() - wet.cells.size() if res.ok else 0
			if not res.ok or float(wet.kosten) < float(res.kosten) or (saved >= DETOUR_MIN and float(res.cells.size()) >= DETOUR_FACTOR * wet.cells.size()):
				wet.ersparnis_felder = saved
				res = wet
		elif not res.ok and wet.ok:
			res = {"ok": false, "msg": "Kein Landweg zu %s: %s" % [pid, spans.msg], "bruecke": true}
	_cache[key] = res
	return res


## Kosten und Dauer eines Weges: Schotterweg und Rodung je Landfeld, dazu die Bruecken (Bauzeit laeuft parallel).
func _price(res: Dictionary, spans: Dictionary) -> void:
	var trees := 0
	var land := 0
	for c in res.cells:
		if sim.city.g(c) == CityData.G.WATER:
			continue
		land += 1
		if sim.city.blocked[sim.city.idx(c)] == 1:
			trees += 1
	res.baeume = trees
	res.bruecken = spans.spans
	res.kosten_bruecken = float(spans.kosten)
	res.ersparnis_felder = 0
	res.kosten = snappedf(BASE_COST + CELL_COST * land + CLEAR_COST * trees + float(spans.kosten), 1.0)
	res.tage = maxi(ceili(float(land) / CELLS_PER_DAY), int(spans.tage))


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


## Land ohne Berg und ohne Gebaeude; Baeume werden gerodet; Fluss und See nur mit Bruecke, Meer nie. Strassen sind Ziel, nie Durchgang.
func _passable(q: Vector2i, allow_water: bool, start: bool) -> bool:
	var city: CityData = sim.city
	var i := city.idx(q)
	if city.height.size() > 0 and city.height[i] > 0:
		return false
	if city.building_at[i] >= 0:
		return false
	if city.ground[i] == CityData.G.WATER:
		return allow_water and not start and not sim.bridges.is_sea(q)
	return true


## Erschliessungsantrag eines Unternehmers: Plan, Beitrag (Weg) und Stadtanteil (Bruecken) liegen dem Buergermeister zur Entscheidung vor.
func request(cid: int, pid: String, reason: String = "") -> Dictionary:
	var chk := _check_new(pid)
	if not chk.ok:
		return chk
	var pl := plan(pid, Bridges.LOAD_MINE)
	if not pl.ok:
		return {"ok": false, "msg": str(pl.msg)}
	if pl.cells.is_empty():
		return {"ok": false, "msg": "Grundstück %s hat schon Straßenanschluss." % pid}
	var c: Company = sim.company(cid)
	var share := float(pl.kosten) - float(pl.kosten_bruecken)
	if c.ledger.cash < share:
		return {"ok": false, "msg": "Nicht genug Bargeld für den Erschließungsbeitrag (%s)." % Catalog.money(share)}
	var j := _new_job(pid, cid, pl)
	j.reason = reason.left(200)
	var msg := "%s beantragt die Erschließung von %s: %d Felder Schotterweg%s; Beitrag der Firma %s, Anteil der Stadt %s. Der Bürgermeister entscheidet (spätestens nach %d Tagen das Bauamt)." % [
		c.company_name, pid, _land(j), (", %d Brücke(n)" % pl.bruecken.size()) if not pl.bruecken.is_empty() else "", Catalog.money(share),
		Catalog.money(float(pl.kosten_bruecken)), ANTRAG_FRIST]
	sim.log_event(msg, "info", cid)
	sim.activity.add("unternehmen", cid, "bau", "Erschließungsantrag %s für %s" % [j.id, pid], reason, _head(j))
	return {"ok": true, "msg": msg, "ref": j.id}


## Erschliessung auf Initiative der Stadt (Buergermeister): Weg und Bruecken aus der Stadtkasse, sofort beschlossen.
## Verwaltung, in deren Gebiet das Grundstueck liegt (Auftrag 17): sie entscheidet, traegt ihren Anteil und schreibt aus.
func _mayor_of(j: Dictionary) -> Mayor:
	return sim.towns.mayor(sim.towns.of_parcel(str(j.parcel)))


## Erschliessung (Auftrag 17: das Strassennetz waechst mit der Stadt): fuer jedes Grundstueck den Landweg vom bestehenden Netz bis an
## einen Bauplatz als echte Strassenzellen anlegen. Gibt die neuen Zellen als [[x, y], ...] zurueck (fuer Speichern/Laden).
func lay_roads(pids: Array) -> Array:
	var out: Array = []
	for pid in pids:
		var p: Dictionary = sim.parcels.parcel(str(pid))
		if p.is_empty():
			continue
		var res := _search(p, false)
		if res.ok and res.cells.is_empty() and int(p.area) >= QUARTER_STREET_MIN_AREA:
			res = _street_to_center(p)   # schon angeschlossen: Erschliessungsstrasse bis in die Mitte des Grundstuecks (Quartiersstrasse)
		if not res.ok or res.cells.is_empty():
			continue
		_apply_cells(res.cells)
		_fields.clear()
		_cache.clear()
		for c in res.cells:
			out.append([c.x, c.y])
	return out


const QUARTER_STREET_MIN_AREA := 30


## Weg von der Mitte eines Grundstuecks zur naechsten Strasse (Entfernungsfeld ueber Land). Leer, wenn die Mitte nicht erreichbar ist.
func _street_to_center(p: Dictionary) -> Dictionary:
	var city: CityData = sim.city
	if not _fields.has("land"):
		_fields["land"] = _field(false)
	var toward: PackedInt32Array = _fields["land"][0]
	var ctr := Vector2i(int(p.rect[0]) + int(p.rect[2]) / 2, int(p.rect[1]) + int(p.rect[3]) / 2)
	if not city.inside(ctr) or city.is_road(ctr) or toward[city.idx(ctr)] < 0 or not _passable(ctr, false, true):
		return {"ok": false, "cells": []}
	return {"ok": true, "cells": _trace(toward, city.idx(ctr))}


## Laden: gespeicherte Strassenzellen wieder anlegen (die Welt wird aus dem Seed neu erzeugt).
func reapply(cells: Array) -> void:
	if cells.is_empty():
		return
	_apply_cells(cells.map(func(a): return Vector2i(int(a[0]), int(a[1]))))
	_fields.clear()
	_cache.clear()


func order_city(pid: String, by: String, choice: Dictionary = {}) -> Dictionary:
	var chk := _check_new(pid)
	if not chk.ok:
		return chk
	var pl := plan(pid, Bridges.LOAD_TOWN)
	if not pl.ok:
		return {"ok": false, "msg": str(pl.msg)}
	if pl.cells.is_empty():
		return {"ok": false, "msg": "Grundstück %s hat schon Straßenanschluss." % pid}
	var j := _new_job(pid, -1, pl)
	j.need_t = Bridges.LOAD_TOWN
	j.beitrag = 0.0
	var chosen := _apply_choice(j, choice)
	if chosen.ok and _mayor_of(j).available_budget() < float(j.stadtanteil):
		chosen = {"ok": false, "msg": "Verfügbare Stadtkasse reicht nicht (%s nötig)." % Catalog.money(float(j.stadtanteil))}
	if not chosen.ok:
		jobs.erase(j.id)
		return chosen
	return _start(j, by)


## Entscheidung ueber einen Antrag. approve: Beitrag wird faellig, Projekte werden ausgeschrieben.
func decide(id: String, approve: bool, reason: String, by: String, choice: Dictionary = {}) -> Dictionary:
	var j: Dictionary = jobs.get(id, {})
	if j.is_empty() or j.status != "antrag":
		return {"ok": false, "msg": "Kein offener Erschließungsantrag %s." % id}
	var c: Company = sim.company(int(j.company))
	if approve:
		var chosen := _apply_choice(j, choice)
		if not chosen.ok:
			return chosen
	# Kann die Stadt ihren Brueckenanteil nicht tragen, prueft das Amt den Umweg ueber Land ohne Bruecke, den die Firma allein bezahlt
	if float(j.stadtanteil) > 0.0 and _mayor_of(j).available_budget() < float(j.stadtanteil) and _land_only(j) and c.ledger.cash >= float(j.beitrag):
		approve = true
		reason = "Stadtkasse trägt keine Brücke; genehmigt als Umweg über Land (%d Felder), Kosten trägt %s (%s)." % [j.cells.size(), c.company_name, Catalog.money(float(j.beitrag))]
	j.decision = {"by": by, "reason": reason.left(200), "day": GameCalendar.day_of(sim.game_min), "approve": approve, "wahl": choice}
	if approve and _mayor_of(j).available_budget() < float(j.stadtanteil):
		return {"ok": false, "msg": "Die verfügbare Stadtkasse reicht nicht für den Anteil der Stadt (%s)." % Catalog.money(float(j.stadtanteil))}
	if approve and c.ledger.cash < float(j.beitrag):
		approve = false
		reason = "%s kann den Erschließungsbeitrag (%s) nicht mehr zahlen." % [c.company_name, Catalog.money(float(j.beitrag))]
	if not approve:
		j.status = "abgelehnt"
		sim.log_event("%s lehnt den Erschließungsantrag %s von %s ab: %s" % [by, id, c.company_name, reason], "warn", int(j.company))
		return {"ok": true, "msg": "Antrag %s abgelehnt." % id, "ref": id}
	c.ledger.book("property_costs", -float(j.beitrag), true, "Erschließungsbeitrag %s (%s)" % [id, j.parcel], sim.game_min)
	return _start(j, by)


## Bauweise des Entscheiders: Brueckenart (muss Spannweite und Last schaffen) und Vergabe (Direktvergabe an eine Unternehmer-Baufirma).
## Aktualisiert Kosten, Stadtanteil und Bauzeit.
func _apply_choice(j: Dictionary, choice: Dictionary) -> Dictionary:
	var v := str(choice.get("variant", ""))
	if v != "":
		for sp in j.spans:
			if not Bridges.valid_variant(v, sp.cells.size(), int(j.get("need_t", Bridges.LOAD_MINE))):
				return {"ok": false, "msg": "%s schafft die Brücke über %d Felder bei %d t Last nicht (siehe brueckenarten)." % [v, sp.cells.size(), int(j.get("need_t", Bridges.LOAD_MINE))]}
		for sp in j.spans:
			var old := float(sp.cost)
			sp.variant = v
			sp.cost = Bridges.cost_of(v, sp.cells.size())
			sp.days = Bridges.days_of(v, sp.cells.size())
			j.cost = float(j.cost) + float(sp.cost) - old
	var award := str(choice.get("award", ""))
	if award != "":
		sim.construction.sync_company_builders()
		var bd: Dictionary = sim.construction.builders.get(award, {})
		if bd.is_empty() or not bd.has("company") or bd.status != "aktiv":
			return {"ok": false, "msg": "Direktvergabe nicht möglich: Firma %s hat keine aktive Baufirma (siehe erschliessung.baufirmen)." % award.substr(1)}
		j.award = award
	var bridges := float(j.spans.reduce(func(s, x): return s + float(x.cost), 0.0))
	j.stadtanteil = float(j.cost) if int(j.company) < 0 else bridges
	j.beitrag = 0.0 if int(j.company) < 0 else float(j.cost) - bridges
	var days := 0
	for sp in j.spans:
		days = maxi(days, int(sp.days))
	j.tage = maxi(ceili(float(_land(j)) / CELLS_PER_DAY), days)
	return {"ok": true}


func _check_new(pid: String) -> Dictionary:
	if jobs.values().any(func(j): return j.parcel == pid and j.status in ["antrag", "im_bau"]):
		return {"ok": false, "msg": "Für %s läuft schon ein Erschließungsantrag oder Bau." % pid}
	if running() >= MAX_RUNNING:
		return {"ok": false, "msg": "Es laufen schon %d Erschließungen; später erneut beantragen." % MAX_RUNNING}
	return {"ok": true}


func _new_job(pid: String, cid: int, pl: Dictionary) -> Dictionary:
	var j := {"id": "Z%d" % _next, "parcel": pid, "company": cid, "cells": pl.cells.map(func(v): return [v.x, v.y]), "built": 0,
		"cost": float(pl.kosten), "beitrag": float(pl.kosten) - float(pl.kosten_bruecken), "stadtanteil": float(pl.kosten_bruecken),
		"spans": pl.bruecken.map(func(s): return {"cells": s.cells.map(func(v): return [v.x, v.y]), "ends": s.ends.map(func(v): return [v.x, v.y]),
			"variant": s.variant, "cost": s.cost, "days": s.days}),
		"ersparnis": int(pl.get("ersparnis_felder", 0)), "tage": int(pl.tage), "day": GameCalendar.day_of(sim.game_min),
		"status": "antrag", "bridges": [], "project": "", "reason": "", "need_t": Bridges.LOAD_MINE, "award": ""}
	_next += 1
	jobs[j.id] = j
	return j


## Antrag auf den reinen Landweg umstellen (ohne Bruecke, ohne Stadtanteil). false, wenn es keinen Landweg gibt.
func _land_only(j: Dictionary) -> bool:
	var p: Dictionary = sim.parcels.parcel(str(j.parcel))
	var res := _search(p, false)
	if not res.ok or res.cells.is_empty():
		return false
	_price(res, {"spans": [], "kosten": 0.0, "tage": 0})
	j.cells = res.cells.map(func(v): return [v.x, v.y])
	j.cost = float(res.kosten)
	j.beitrag = float(res.kosten)
	j.stadtanteil = 0.0
	j.spans = []
	j.tage = int(res.tage)
	j.ersparnis = 0
	return true


## Beschlossen: Wegebau und Bruecken als Stadtprojekte ausschreiben (Baufirmen bieten; Material aus dem Stadtlager).
func _start(j: Dictionary, by: String) -> Dictionary:
	j.status = "im_bau"
	j.start = GameCalendar.day_of(sim.game_min)
	var land := _land(j)
	var mat := {}
	for it in ROAD_MATERIAL:
		mat[it] = int(ceil(float(ROAD_MATERIAL[it]) * land * 0.35))   # wie Verbindungsstrassen: gut ein Drittel
	var road_cost := float(j.cost) - float(j.spans.reduce(func(s, x): return s + float(x.cost), 0.0))
	var prj: Dictionary = _mayor_of(j).add_works_project("zufahrt", j.id, road_cost, maxi(2, ceili(float(land) / CELLS_PER_DAY)), mat,
		"Zufahrt %s zu %s (%s)" % [j.id, j.parcel, by], str(j.get("award", "")))
	j.project = prj.id
	for sp in j.spans:
		var span := {"cells": sp.cells.map(func(a): return Vector2i(int(a[0]), int(a[1]))), "ends": sp.ends.map(func(a): return Vector2i(int(a[0]), int(a[1]))),
			"variant": sp.variant, "cost": float(sp.cost), "days": int(sp.days), "award": str(j.get("award", ""))}
		j.bridges.append(sim.bridges.create(span, -1, j.id, by).id)
	var who: String = "der Stadt" if int(j.company) < 0 else sim.company(int(j.company)).company_name
	var msg := "%s beschließt die Erschließung von %s für %s: Wegebau %s%s ausgeschrieben, %s, etwa %d Tage." % [by, j.parcel, who, prj.id,
		(" und Brücke(n) %s" % ", ".join(j.bridges)) if not j.bridges.is_empty() else "", Catalog.money(float(j.cost)), int(j.tage)]
	sim.log_event(msg, "info", int(j.company))
	sim.activity.add("buergermeister", -1, "stadt", "Erschließung %s beschlossen" % j.id, "Stadt wächst, Auftrag für die Baufirmen", _head(j))
	return {"ok": true, "msg": msg, "ref": j.id}


func _land(j: Dictionary) -> int:
	return j.cells.size() - int(j.spans.reduce(func(s, x): return s + x.cells.size(), 0))


func running() -> int:
	return jobs.values().filter(func(j): return j.status in ["antrag", "im_bau"]).size()


## Offene Antraege fuer den Buergermeister.
func pending() -> Array:
	return jobs.values().filter(func(j): return j.status == "antrag").map(func(j): return {"id": j.id, "firma": int(j.company),
		"name": sim.company(int(j.company)).company_name, "grundstueck": j.parcel, "art": sim.prod.deposit_of(j.parcel).get("art", ""),
		"beitrag_firma": int(j.beitrag), "anteil_stadt": int(j.stadtanteil), "bruecken": j.spans.size(), "felder": j.cells.size(),
		"ersparnis_felder": int(j.ersparnis), "tage": int(j.tage), "eingereicht_tag": int(j.day), "begruendung": str(j.reason),
		"brueckenarten_moeglich": _variants(j)})


## Brueckenarten, die alle Bruecken eines Antrags schaffen (Spannweite, Last), mit Kosten fuer die Stadt.
func _variants(j: Dictionary) -> Dictionary:
	if j.spans.is_empty():
		return {}
	var out := {}
	for v in Bridges.ORDER:
		if j.spans.all(func(sp): return Bridges.valid_variant(v, sp.cells.size(), int(j.get("need_t", Bridges.LOAD_MINE)))):
			out[v] = int(j.spans.reduce(func(s, sp): return s + Bridges.cost_of(v, sp.cells.size()), 0.0))
	return out


## Bauordnung: Indizes von der Strasse her (letzte Zelle zuerst); Wasserfelder schliesst die Bruecke.
func _order(j: Dictionary) -> Array:
	var out: Array = []
	var n: int = j.cells.size()
	for k in n:
		var a: Array = j.cells[n - 1 - k]
		if not sim.bridges.is_bridge(Vector2i(int(a[0]), int(a[1]))):
			out.append(n - 1 - k)
	return out


## Fortschritt der Wegebaufirma (0..1).
func road_progress(j: Dictionary) -> float:
	if bool(j.get("road_done", false)):
		return 1.0
	return sim.construction.public_progress(str(j.project))


## Tagesfortschritt: Antraege nach Frist entscheiden; Weg waechst mit dem Fortschritt der Baufirma; fertig, wenn Weg und Bruecken stehen.
func on_day(day: int) -> void:
	for j in jobs.values():
		if j.status == "antrag" and day - int(j.day) >= ANTRAG_FRIST:
			var ok: bool = _mayor_of(j).available_budget() >= float(j.stadtanteil)
			decide(j.id, ok, "Frist abgelaufen, Bauamt entscheidet: %s" % ("Mittel vorhanden" if ok else "Stadtkasse reicht nicht"), "Bauamt")
		if j.status != "im_bau":
			continue
		var order := _order(j)
		var target := int(floor(float(order.size()) * road_progress(j)))
		_build_to(j, order, target)
		_maybe_finish(j)


func _build_to(j: Dictionary, order: Array, target: int) -> void:
	var from := int(j.built)
	if target <= from:
		return
	var idx: Array = order.slice(from, target)
	j.built = target
	_apply_cells(idx.map(func(k): return Vector2i(int(j.cells[k][0]), int(j.cells[k][1]))))


## Vom Bausystem bei Fertigstellung des Wegebaus aufgerufen.
func road_done(id: String) -> void:
	var j: Dictionary = jobs.get(id, {})
	if j.is_empty():
		return
	j.road_done = true
	var order := _order(j)
	_build_to(j, order, order.size())
	_maybe_finish(j)


func _maybe_finish(j: Dictionary) -> void:
	if j.status != "im_bau" or not bool(j.get("road_done", false)):
		return
	if j.bridges.any(func(b): return sim.bridges.items[b].status != "freigegeben"):
		j.waiting = "Brücke"
		return
	j.status = "fertig"
	j.waiting = ""
	_cache.clear()
	_fields.clear()
	sim.log_event("Zufahrt %s zu %s ist fertig – die Lagerstätte hat jetzt Straßenanschluss." % [j.id, j.parcel], "good", int(j.company))


## Freizuhaltender Verkehrskorridor: Zelle einer beantragten oder im Bau befindlichen Zufahrt (Neubauten duerfen sie nicht belegen).
func reserved(q: Vector2i) -> bool:
	if sim.regional != null and sim.regional.reserved(q):
		return true   # Trasse einer beschlossenen oder geplanten Verbindungsstrasse/Autobahn
	for j in jobs.values():
		if str(j.get("status", "")) in ["antrag", "im_bau"]:
			for a in j.cells:
				if int(a[0]) == q.x and int(a[1]) == q.y:
					return true
	return false


## Zellen zu Strasse machen (Rodung, Wegfindung, Darstellung).
func _apply_cells(cells: Array) -> void:
	var city: CityData = sim.city
	var made: Array = []
	for q in cells:
		var i := city.idx(q)
		if city.ground[i] == CityData.G.ROAD:
			continue   # Bruecke (bei der Abnahme schon freigegeben)
		if city.building_at[i] >= 0:
			# nie eine Strasse unter ein Haus malen (Auftrag 18): Zelle bleibt, die Blockade wird gemeldet
			sim.log_event("Straßenbau: Feld %d,%d ist bebaut (%s) – dort wird keine Straße angelegt." % [q.x, q.y, str(city.building(city.building_at[i]).get("name", "Gebäude"))], "warn")
			continue
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


## Eine Bruecke wurde abgenommen: Plaene neu rechnen (neue Wege); Zufahrt fertig, wenn auch der Weg steht.
func on_bridge_opened() -> void:
	_cache.clear()
	_fields.clear()
	for j in jobs.values():
		_maybe_finish(j)


func _head(j: Dictionary) -> Vector2i:
	var order := _order(j)
	if order.is_empty():
		return Vector2i(int(j.cells[0][0]), int(j.cells[0][1]))
	var a: Array = j.cells[order[clampi(int(j.built), 0, order.size() - 1)]]
	return Vector2i(int(a[0]), int(a[1]))


## Arbeitsfront fuer die Darstellung: Zellen in Bauordnung, Anzahl fertig, Tagesziel.
func front(j: Dictionary) -> Dictionary:
	var order := _order(j)
	return {"cells": order.map(func(k): return Vector2(float(j.cells[k][0]), float(j.cells[k][1]))), "built": int(j.built),
		"rate": float(CELLS_PER_DAY), "running": sim.construction.public_running(str(j.project))}


## Kolonnenwagen der Baufirma faehrt zur zuletzt gebauten Zelle (bzw. zur Einmuendung), denn Fahrzeuge brauchen ein Strassenziel.
func _send_crew(j: Dictionary) -> void:
	var at := _head(j)
	var order := _order(j)
	if int(j.built) > 0 and int(j.built) <= order.size():
		var a: Array = j.cells[order[int(j.built) - 1]]
		at = Vector2i(int(a[0]), int(a[1]))
	else:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if sim.city.is_road(at + d):
				at += d
				break
	if sim.city.is_road(at):
		sim.fleet.send_crew(at, GameCalendar.day_start(GameCalendar.day_of(sim.game_min) + 1), sim.construction.public_builder_name(str(j.project)))


## Fuer Beobachtung und Anzeige.
func summary() -> Array:
	return jobs.values().map(func(j): return {"id": j.id, "grundstueck": j.parcel, "unternehmen": int(j.company), "status": j.status,
		"fortschritt": snappedf(road_progress(j) if j.status == "im_bau" else (1.0 if j.status == "fertig" else 0.0), 0.01), "felder": j.cells.size(), "kosten": int(j.cost),
		"beitrag_firma": int(j.get("beitrag", 0.0)), "anteil_stadt": int(j.get("stadtanteil", 0.0)),
		"bruecken": j.get("bridges", []), "wartet_auf": str(j.get("waiting", ""))})


func to_dict() -> Dictionary:
	return {"jobs": jobs.duplicate(true), "next": _next}


## Laden: die Welt wird aus dem Seed neu erzeugt, gebaute Wegzellen werden wieder angelegt.
func from_dict(d: Dictionary) -> void:
	jobs = d.get("jobs", {}).duplicate(true)
	_next = int(d.get("next", 1))
	for j in jobs.values():
		j.built = int(j.built)
		j.company = int(j.company)
		var order := _order(j)
		_apply_cells(order.slice(0, int(j.built)).map(func(k): return Vector2i(int(j.cells[k][0]), int(j.cells[k][1]))))
