class_name RegionalProjects
extends RefCounted
## Gemeinschaftsprojekte mehrerer Staedte (Auftrag 17, Abschnitt 7): ein einziges regionales Projekt mit Kostenanteilen, Beschluessen
## der beteiligten Staedte, Reservierungen und genau einem Bauauftrag.
##
## Ablauf: Eine Stadt schlaegt vor (propose: Art "verbindung" = neue Schotterstrasse zwischen zwei Orten, Weg und Kosten werden
## berechnet; Anteile je Stadt). Jede beteiligte Stadt beschliesst (decide) zustimmen | ablehnen; ohne Beschluss bis zur Frist gilt
## die Beteiligung als abgelehnt. Stimmen alle zu, reserviert jede Stadt ihren Anteil; die vorschlagende Stadt schreibt EIN
## Stadtprojekt aus (Kind "verbindung", Feld "shares"), eine Baufirma baut, und bei der Abnahme zahlt jede Stadt genau ihren Anteil
## (Construction._finish_public). Erst danach werden die Strassenzellen befahrbar. Lehnt ein Partner ab, scheitert das Projekt mit
## Begruendung; die vorschlagende Stadt kann es allein (Anteil 100 %) neu vorschlagen.

const DEADLINE_DAYS := 5
const COST_BASE := 4000.0
const COST_CELL := 140.0
const CELLS_PER_DAY := 12
const MATERIAL_CELL := {"schotter": 2, "kies": 1}

var sim
var items := {}        # "R<n>" -> {id, kind, from, to, initiator, shares: {town: Anteil 0..1}, votes: {town: offen|zugestimmt|abgelehnt},
                       #            status: vorgeschlagen|beschlossen|gescheitert|im_bau|fertig, cells, cost, days, day, deadline, project, reason, note}
var _next := 1


func setup(simulation) -> void:
	sim = simulation
	sim.day_changed.connect(on_day)


## Weg fuer eine neue Verbindung zwischen zwei Ortszentren: ueber Land, bestehende Strassen nur an den Enden (sonst waere es keine neue
## Verbindung); kein Wasser (Bruecken laufen ueber Bridges), keine Berge, keine Gebaeude.
func plan_link(a: int, b: int) -> Dictionary:
	var T: Towns = sim.towns
	if a == b or a < 0 or b < 0 or a >= T.count() or b >= T.count():
		return {"ok": false, "msg": "Zwei verschiedene Städte nötig."}
	var cd: CityData = sim.city
	var n := cd.size
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in n:
		for x in n:
			var p := Vector2i(x, y)
			var i := cd.idx(p)
			if cd.ground[i] in [CityData.G.WATER, CityData.G.QUAY, CityData.G.RUNWAY, CityData.G.APRON] or (cd.height.size() > 0 and cd.height[i] > 0) or cd.building_at[i] >= 0:
				astar.set_point_solid(p, true)
			elif cd.ground[i] == CityData.G.ROAD:
				astar.set_point_weight_scale(p, 6.0)   # vorhandene Strassen moeglichst nicht mitbenutzen
	var pa: Vector2i = T.get_t(a).center + Vector2i(-30, 0)
	var pb: Vector2i = T.get_t(b).center + Vector2i(-30, 0)
	var path := astar.get_id_path(pa, pb)
	if path.is_empty():
		return {"ok": false, "msg": "Kein Landweg zwischen %s und %s (Brücke nötig)." % [T.name_of(a), T.name_of(b)]}
	var cells: Array = []
	for p in path:
		if not cd.is_road(p):
			cells.append([p.x, p.y])
	var cost := snappedf(COST_BASE + COST_CELL * float(cells.size()), 10.0)
	return {"ok": true, "cells": cells, "laenge": path.size(), "neue_felder": cells.size(), "kosten": cost, "tage": maxi(3, ceili(float(cells.size()) / float(CELLS_PER_DAY)))}


## Vorschlag einer Stadt. shares: {Stadt-ID: Anteil}; Summe 1. Ohne Angabe je Hälfte (Initiator und Partner).
func propose(initiator: int, kind: String, partner: int, shares: Dictionary = {}, reason: String = "") -> Dictionary:
	if kind != "verbindung":
		return {"ok": false, "msg": "Unbekannte Projektart %s (verbindung)." % kind}
	for r in items.values():
		if r.status in ["vorgeschlagen", "beschlossen", "im_bau"] and ((int(r.from) == initiator and int(r.to) == partner) or (int(r.from) == partner and int(r.to) == initiator)):
			return {"ok": false, "msg": "Für %s – %s läuft schon das Gemeinschaftsprojekt %s." % [sim.towns.name_of(initiator), sim.towns.name_of(partner), r.id]}
	var pl := plan_link(initiator, partner)
	if not pl.ok:
		return pl
	var sh := {}
	if shares.is_empty():
		sh = {str(initiator): 0.5, str(partner): 0.5}
	else:
		for k in shares:
			sh[str(int(k))] = float(shares[k])
	var total := 0.0
	for k in sh:
		total += float(sh[k])
		if int(k) not in [initiator, partner]:
			return {"ok": false, "msg": "Anteile nur für die beteiligten Städte."}
	if absf(total - 1.0) > 0.01:
		return {"ok": false, "msg": "Anteile müssen zusammen 100 % ergeben (%.0f %%)." % (total * 100.0)}
	var day := GameCalendar.day_of(sim.game_min)
	var r := {"id": "R%d" % _next, "kind": kind, "from": initiator, "to": partner, "initiator": initiator, "shares": sh, "votes": {},
		"status": "vorgeschlagen", "cells": pl.cells, "cost": float(pl.kosten), "days": int(pl.tage), "day": day, "deadline": day + DEADLINE_DAYS,
		"project": "", "reason": reason.left(200), "note": ""}
	_next += 1
	for k in sh:
		r.votes[k] = "zugestimmt" if int(k) == initiator else ("zugestimmt" if float(sh[k]) <= 0.0 else "offen")
	items[r.id] = r
	sim.log_event("%s schlägt eine neue Verbindungsstraße nach %s vor (%s, %d Felder, %s; Anteile %s)." % [sim.towns.name_of(initiator), sim.towns.name_of(partner), r.id,
		int(pl.neue_felder), Catalog.money(float(pl.kosten)), _shares_text(r)], "info")
	_try_start(r)
	return {"ok": true, "msg": "Gemeinschaftsprojekt %s vorgeschlagen; %s entscheidet bis Tag %d." % [r.id, sim.towns.name_of(partner), int(r.deadline)], "ref": r.id}


func _shares_text(r: Dictionary) -> String:
	var parts: Array = []
	for k in r.shares:
		parts.append("%s %d %%" % [sim.towns.name_of(int(k)), int(round(float(r.shares[k]) * 100.0))])
	return ", ".join(parts)


func share_amount(r: Dictionary, town: int) -> float:
	return snappedf(float(r.cost) * float(r.shares.get(str(town), 0.0)), 1.0)


## Beschluss einer beteiligten Stadt. Zustimmung nur mit gedecktem Anteil (verfuegbare Mittel).
func decide(rid: String, town: int, accept: bool, reason: String = "") -> Dictionary:
	var r: Dictionary = items.get(rid, {})
	if r.is_empty() or r.status != "vorgeschlagen":
		return {"ok": false, "msg": "Gemeinschaftsprojekt %s steht nicht zur Entscheidung." % rid}
	if not r.votes.has(str(town)):
		return {"ok": false, "msg": "%s ist an %s nicht beteiligt." % [sim.towns.name_of(town), rid]}
	if accept and sim.towns.mayor(town).available_budget() < share_amount(r, town):
		return {"ok": false, "msg": "Anteil %s nicht gedeckt (verfügbar %s)." % [Catalog.money(share_amount(r, town)), Catalog.money(sim.towns.mayor(town).available_budget())]}
	r.votes[str(town)] = "zugestimmt" if accept else "abgelehnt"
	sim.log_event("%s %s die Beteiligung an %s (%s)%s." % [sim.towns.name_of(town), "beschließt" if accept else "lehnt", rid, Catalog.money(share_amount(r, town)),
		"" if accept else " ab" + (": " + reason.left(120) if reason != "" else "")], "info")
	if not accept:
		_fail(r, "%s lehnt die Beteiligung ab%s" % [sim.towns.name_of(town), (": " + reason.left(120)) if reason != "" else ""])
		return {"ok": true, "msg": "Beteiligung abgelehnt; %s ist gescheitert." % rid}
	_try_start(r)
	return {"ok": true, "msg": "Beteiligung an %s beschlossen." % rid}


func _fail(r: Dictionary, why: String) -> void:
	r.status = "gescheitert"
	r.note = why
	sim.log_event("Gemeinschaftsprojekt %s gescheitert: %s. Es wird nicht gebaut; %s kann es allein neu vorschlagen." % [r.id, why, sim.towns.name_of(int(r.initiator))], "warn")


## Alle zugestimmt: Anteile reservieren, genau ein Stadtprojekt bei der vorschlagenden Stadt ausschreiben.
func _try_start(r: Dictionary) -> void:
	if r.status != "vorgeschlagen" or r.votes.values().any(func(v): return v != "zugestimmt"):
		return
	for k in r.shares:
		if sim.towns.mayor(int(k)).available_budget() < share_amount(r, int(k)):
			_fail(r, "Anteil von %s ist bei Baubeginn nicht mehr gedeckt" % sim.towns.name_of(int(k)))
			return
	var M: Mayor = sim.towns.mayor(int(r.initiator))
	var mat := {}
	for it in MATERIAL_CELL:
		mat[it] = int(MATERIAL_CELL[it]) * r.cells.size()
	var prj: Dictionary = M.add_works_project("verbindung", r.id, float(r.cost), int(r.days), mat, "Gemeinschaftsprojekt %s" % r.id)
	# add_works_project hat die vollen Kosten beim Initiator reserviert: auf die Anteile umlegen
	M.commitments = maxf(0.0, M.commitments - float(r.cost))
	var shares := {}
	for k in r.shares:
		var amt := share_amount(r, int(k))
		sim.towns.mayor(int(k)).commitments += amt
		shares[k] = amt
	prj["shares"] = shares
	prj["regional"] = r.id
	r.project = prj.id
	r.status = "beschlossen"
	sim.log_event("Gemeinschaftsprojekt %s beschlossen und als %s ausgeschrieben (eine Vergabe; Anteile %s)." % [r.id, prj.id, _shares_text(r)], "good")


## Vom Bausystem bei der Abnahme: Strasse oeffnen.
func finish(rid: String) -> void:
	var r: Dictionary = items.get(rid, {})
	if r.is_empty():
		return
	r.status = "fertig"
	r["done_day"] = GameCalendar.day_of(sim.game_min)
	sim.access._apply_cells(r.cells.map(func(c): return Vector2i(int(c[0]), int(c[1]))))
	sim.log_event("Gemeinschaftsprojekt %s abgenommen: neue Straße %s – %s ist befahrbar." % [r.id, sim.towns.name_of(int(r.from)), sim.towns.name_of(int(r.to))], "good")


func on_day(day: int) -> void:
	for r in items.values():
		if r.status == "vorgeschlagen" and day > int(r.deadline):
			var late: Array = r.votes.keys().filter(func(k): return r.votes[k] == "offen").map(func(k): return sim.towns.name_of(int(k)))
			_fail(r, "Frist verstrichen ohne Beschluss von %s" % ", ".join(late))
		elif r.status == "beschlossen":
			var prj: Dictionary = sim.towns.project(str(r.project))
			if str(prj.get("status", "")) in ["beauftragt", "laufend"]:
				r.status = "im_bau"


## Offene Vorschlaege fuer eine Stadt (Beobachtung des Buergermeisters).
func pending_for(town: int) -> Array:
	return items.values().filter(func(r): return r.status == "vorgeschlagen" and str(r.votes.get(str(town), "")) == "offen").map(func(r): return {
		"id": r.id, "von": sim.towns.name_of(int(r.initiator)), "verbindung": "%s – %s" % [sim.towns.name_of(int(r.from)), sim.towns.name_of(int(r.to))],
		"anteil_eur": int(share_amount(r, town)), "kosten_gesamt": int(r.cost), "neue_felder": r.cells.size(), "frist_tag": int(r.deadline), "begruendung": r.reason})


func summary() -> Array:
	return items.values().map(func(r): return {"id": r.id, "status": r.status, "verbindung": "%s – %s" % [sim.towns.name_of(int(r.from)), sim.towns.name_of(int(r.to))],
		"kosten": int(r.cost), "anteile": _shares_text(r), "projekt": r.project, "hinweis": r.note})


func to_dict() -> Dictionary:
	return {"items": items.duplicate(true), "next": _next}


## Laden: die Welt wird neu erzeugt; fertige Verbindungen werden wieder angelegt.
func from_dict(d: Dictionary) -> void:
	items = d.get("items", {}).duplicate(true)
	_next = int(d.get("next", 1))
	for r in items.values():
		if r.status == "fertig":
			sim.access._apply_cells(r.cells.map(func(c): return Vector2i(int(c[0]), int(c[1]))))
