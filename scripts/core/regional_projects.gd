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
const RETRY_DAYS := 30               # Sperrfrist nach einem gescheiterten Vorschlag fuer dasselbe Staedtepaar
const COST_BASE := 4000.0
const COST_CELL := 140.0
const CELLS_PER_DAY := 12
const MATERIAL_CELL := {"schotter": 2, "kies": 1}
const MATERIAL_FACTOR := 0.35   # Wachstum: Schotterstrasse braucht gut ein Drittel der frueheren Menge

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
	var pa: Vector2i = _inland_anchor(a)
	var pb: Vector2i = _inland_anchor(b)
	var path := astar.get_id_path(pa, pb)
	if path.is_empty():
		return {"ok": false, "msg": "Kein Landweg zwischen %s und %s (Brücke nötig)." % [T.name_of(a), T.name_of(b)]}
	var cells: Array = []
	for p in path:
		if not cd.is_road(p):
			cells.append([p.x, p.y])
	var cost := snappedf(COST_BASE + COST_CELL * float(cells.size()), 10.0)
	return {"ok": true, "cells": cells, "laenge": path.size(), "neue_felder": cells.size(), "kosten": cost, "tage": maxi(3, ceili(float(cells.size()) / float(CELLS_PER_DAY)))}


func _inland_anchor(town: int) -> Vector2i:
	var ctr: Vector2i = sim.towns.get_t(town).center
	var info: Dictionary = sim.city.towns[town] if town < sim.city.towns.size() else {}
	return ctr + Vector2i(30 if str(info.get("ecke", "")).ends_with("W") else -30, 0)


## Vorschlag einer Stadt. shares: {Stadt-ID: Anteil}; Summe 1. Ohne Angabe je Hälfte (Initiator und Partner).
func propose(initiator: int, kind: String, partner: int, shares: Dictionary = {}, reason: String = "") -> Dictionary:
	if kind != "verbindung":
		return {"ok": false, "msg": "Unbekannte Projektart %s (verbindung)." % kind}
	var today := GameCalendar.day_of(sim.game_min)
	for r in items.values():
		if str(r.kind) != "verbindung":
			continue
		var pair: bool = (int(r.from) == initiator and int(r.to) == partner) or (int(r.from) == partner and int(r.to) == initiator)
		if pair and r.status in ["vorgeschlagen", "beschlossen", "im_bau"]:
			return {"ok": false, "msg": "Für %s – %s läuft schon das Gemeinschaftsprojekt %s." % [sim.towns.name_of(initiator), sim.towns.name_of(partner), r.id]}
		if pair and r.status == "gescheitert" and today - int(r.deadline) < RETRY_DAYS:
			return {"ok": false, "msg": "%s ist vor kurzem gescheitert (%s); neuer Vorschlag frühestens an Tag %d." % [r.id, r.note, int(r.deadline) + RETRY_DAYS]}
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
		mat[it] = int(ceil(float(MATERIAL_CELL[it]) * r.cells.size() * MATERIAL_FACTOR))
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
	if str(r.kind) == "autobahn":
		_open_highway(r)
		sim.log_event("Autobahn %s abgenommen und freigegeben: %d Felder, %d Anschlussstellen – Fahrzeuge fahren dort %.1f-mal so schnell." % [r.id, r.cells.size(),
			r.get("junctions", []).size(), HIGHWAY_SPEED], "good")
		return
	sim.access._apply_cells(r.cells.map(func(c): return Vector2i(int(c[0]), int(c[1]))))
	sim.log_event("Gemeinschaftsprojekt %s abgenommen: neue Straße %s – %s ist befahrbar." % [r.id, sim.towns.name_of(int(r.from)), sim.towns.name_of(int(r.to))], "good")


func on_day(day: int) -> void:
	for r in items.values():
		if r.status == "vorgeschlagen" and day > int(r.deadline):
			# Ohne Beschluss entscheidet die Verwaltung der Partnerstadt (wie das Bauamt bei Antraegen): zustimmen, wenn der Anteil hoechstens
			# die Haelfte der verfuegbaren Mittel bindet, sonst ablehnen.
			for k in r.votes.keys().filter(func(x): return r.votes[x] == "offen"):
				var Mk: Mayor = sim.towns.mayor(int(k))
				var ok_share := share_amount(r, int(k)) <= Mk.available_budget() * 0.5
				decide(str(r.id), int(k), ok_share, "Frist verstrichen, Verwaltung entscheidet: %s" % ("Anteil gedeckt" if ok_share else "Anteil bindet zu viel der verfügbaren Mittel"))
				if r.status != "vorgeschlagen":
					break
		elif r.status == "beschlossen":
			var prj: Dictionary = sim.towns.project(str(r.project))
			if str(prj.get("status", "")) in ["beauftragt", "laufend"]:
				r.status = "im_bau"


## Offene Vorschlaege fuer eine Stadt (Beobachtung des Buergermeisters).
func pending_for(town: int) -> Array:
	return items.values().filter(func(r): return r.status == "vorgeschlagen" and str(r.votes.get(str(town), "")) == "offen").map(func(r): return {
		"id": r.id, "von": sim.towns.name_of(int(r.initiator)), "verbindung": "%s – %s" % [sim.towns.name_of(int(r.from)), sim.towns.name_of(int(r.to))],
		"anteil_eur": int(share_amount(r, town)), "kosten_gesamt": int(r.cost), "neue_felder": r.cells.size(), "frist_tag": int(r.deadline), "begruendung": r.reason})


## Direkt per Strasse verbundene Staedte (Startstrassen und fertige Verbindungen).
func linked(town: int) -> Array:
	var out: Array = []
	for r in sim.city.region_roads:
		if int(r.von) == town:
			out.append(int(r.nach))
		elif int(r.nach) == town:
			out.append(int(r.von))
	for r in items.values():
		if r.status == "fertig":
			if int(r.from) == town:
				out.append(int(r.to))
			elif int(r.to) == town:
				out.append(int(r.from))
	return out


func summary() -> Array:
	return items.values().map(func(r): return {"id": r.id, "status": r.status, "verbindung": "%s – %s" % [sim.towns.name_of(int(r.from)), sim.towns.name_of(int(r.to))],
		"kosten": int(r.cost), "anteile": _shares_text(r), "projekt": r.project, "hinweis": r.note})


func to_dict() -> Dictionary:
	return {"items": items.duplicate(true), "next": _next, "traffic": traffic.duplicate(true)}


## Laden: die Welt wird neu erzeugt; fertige Verbindungen werden wieder angelegt.
func from_dict(d: Dictionary) -> void:
	items = d.get("items", {}).duplicate(true)
	_next = int(d.get("next", 1))
	traffic = d.get("traffic", []).duplicate(true)
	for r in items.values():
		if r.status == "fertig" and str(r.get("kind", "")) == "autobahn":
			_open_highway(r)
		elif r.status == "fertig":
			sim.access._apply_cells(r.cells.map(func(c): return Vector2i(int(c[0]), int(c[1]))))


# ------------------------------------------------------------------ Autobahn (Auftrag 21, docs/HIGHWAY.md)
## Verkehrszaehlung: RoadCare meldet vor dem Tageswechsel die Fahrzeugsekunden je 16x16-Abschnitt. Ueberland = Abschnitt weiter als
## OVERLAND_DIST Felder vom naechsten Ortszentrum. Je Tag Summe und Zuordnung zur naechsten Stadt (Nutzungsanteile fuer die Kosten).
## Die Trasse verbindet die Staedte nacheinander (Reihenfolge nach Lage um die Kartenmitte): je Abschnitt ein Landweg wie bei der
## Verbindungsstrasse, aber zweibahnig (Parallelfeld je Schritt), mit Anschlussstelle an der naechsten Ortsstrasse jeder Stadt und
## Kreuzungen, wo die Trasse vorhandene Strassen quert. Kosten je neuem Feld plus Anschlussstellen und Kreuzungen; der Bund traegt
## HIGHWAY_FEDERAL, die Staedte den Rest nach Nutzung (Verkehrszaehlung). Gebaut wird sichtbar abschnittsweise (HighwayView zeigt den
## Baufortschritt), befahrbar ist sie bei der Abnahme. Auf der Autobahn fahren Fahrzeuge HIGHWAY_SPEED-mal so schnell, die Wegsuche
## bevorzugt sie (Gewicht HIGHWAY_WEIGHT).
const OVERLAND_DIST := 40
const TRAFFIC_DAYS := 30
const HIGHWAY_CELL := 600.0
const HIGHWAY_JUNCTION := 25000.0
const HIGHWAY_CROSSING := 12000.0
const HIGHWAY_FEDERAL := 0.95
const HIGHWAY_CELLS_PER_DAY := 40
const HIGHWAY_SPEED := 1.8
const HIGHWAY_WEIGHT := 0.55
const HIGHWAY_TRAFFIC := 2000.0         # Fahrzeugsekunden je Tag auf Ueberlandstrassen (Mittel 14 Tage), ab denen ein Antrag sinnvoll ist

var traffic: Array = []                 # [{day, total, by_town: {Stadt: Fahrzeugsekunden}}], letzte TRAFFIC_DAYS Tage
var highway := {}                       # befahrbare Autobahnfelder (Vector2i -> true), aus fertigen Projekten


func count_traffic(usage: Dictionary) -> void:
	var by := {}
	var total := 0.0
	for seg in usage:
		var c: Vector2i = sim.road_care.cells.get(seg, Vector2i(int(seg.x) * 16 + 8, int(seg.y) * 16 + 8))
		var k := -1
		var best := 1.0e9
		for t in sim.towns.list:
			var d: float = Vector2(c).distance_to(Vector2(t.center))
			if d < best:
				best = d
				k = int(t.id)
		if best < float(OVERLAND_DIST):
			continue
		total += float(usage[seg])
		by[str(k)] = float(by.get(str(k), 0.0)) + float(usage[seg])
	traffic.append({"day": GameCalendar.day_of(sim.game_min), "total": snappedf(total, 0.1), "by_town": by})
	if traffic.size() > TRAFFIC_DAYS:
		traffic.pop_front()


## Mittlerer Ueberlandverkehr der letzten `days` Tage.
func traffic_mean(days: int = 14) -> float:
	var t: Array = traffic.slice(maxi(0, traffic.size() - days))
	var s := 0.0
	for e in t:
		s += float(e.total)
	return s / maxf(1.0, float(t.size()))


## Nutzungsanteile je Stadt aus der Verkehrszaehlung (mindestens 5 % je Stadt); ohne Zaehlung nach Einwohnern.
func traffic_shares() -> Dictionary:
	var sums := {}
	var total := 0.0
	for e in traffic:
		for k in e.by_town:
			sums[k] = float(sums.get(k, 0.0)) + float(e.by_town[k])
			total += float(e.by_town[k])
	var out := {}
	var n: int = sim.towns.count()
	for t in sim.towns.list:
		var k := str(int(t.id))
		out[k] = maxf(0.05, float(sums.get(k, 0.0)) / total) if total > 0.0 else 1.0 / float(n)
	var s := 0.0
	for k in out:
		s += float(out[k])
	for k in out:
		out[k] = float(out[k]) / s
	return out


func has_highway() -> bool:
	return items.values().any(func(r): return str(r.kind) == "autobahn" and r.status not in ["gescheitert"])


func on_highway(c: Vector2i) -> bool:
	return highway.has(c)


## Anschlussstelle einer Stadt: naechstes Strassenfeld zum Landanker (ausserhalb der Ortsmitte, Richtung Landesinnere).
func _junction(town: int) -> Vector2i:
	var a := _inland_anchor(town)
	var cd: CityData = sim.city
	for r in range(0, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := a + Vector2i(dx, dy)
				if q.x >= 0 and q.y >= 0 and q.x < cd.size and q.y < cd.size and cd.is_road(q):
					return q
	return a


## Trasse durch alle Staedte. Ergebnis: {ok, cells (geordnet, zweibahnig), junctions, crossings, legs, kosten, tage}.
func plan_highway() -> Dictionary:
	var T: Towns = sim.towns
	if T.count() < 2:
		return {"ok": false, "msg": "Eine Autobahn braucht mindestens zwei Städte."}
	var cd: CityData = sim.city
	var n := cd.size
	var mid := Vector2(n, n) * 0.5
	var order: Array = T.list.map(func(t): return int(t.id))
	order.sort_custom(func(a, b): return (Vector2(T.get_t(a).center) - mid).angle() < (Vector2(T.get_t(b).center) - mid).angle())
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
				astar.set_point_weight_scale(p, 3.0)   # kreuzen ja, laengs nein
	var cells: Array = []
	var seen := {}
	var junctions: Array = []
	var crossings: Array = []
	var legs: Array = []
	for i in order.size() - 1:
		var a := int(order[i])
		var b := int(order[i + 1])
		var ja := _junction(a)
		var jb := _junction(b)
		var path := astar.get_id_path(ja, jb)
		if path.is_empty():
			legs.append({"von": a, "nach": b, "ok": false})
			continue
		legs.append({"von": a, "nach": b, "ok": true, "laenge": path.size()})
		for c in [ja, jb]:
			if not junctions.has([c.x, c.y]):
				junctions.append([c.x, c.y])
		for s in path.size():
			var p: Vector2i = path[s]
			var dir: Vector2i = (path[mini(s + 1, path.size() - 1)] - path[maxi(s - 1, 0)])
			dir = Vector2i(signi(dir.x), signi(dir.y))
			var side := Vector2i(-dir.y, dir.x)
			for q in [p, p + side]:
				if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n or seen.has(q):
					continue
				var qi := cd.idx(q)
				if q != p and (astar.is_point_solid(q) or cd.ground[qi] == CityData.G.ROAD):
					continue
				seen[q] = true
				if cd.ground[qi] == CityData.G.ROAD:
					if q.distance_to(ja) > 6.0 and q.distance_to(jb) > 6.0 and not crossings.has([q.x, q.y]):
						crossings.append([q.x, q.y])   # vorhandene Strasse wird gekreuzt
					continue
				cells.append([q.x, q.y])
	if cells.is_empty():
		return {"ok": false, "msg": "Keine Trasse über Land möglich (Wasser oder Berge dazwischen)."}
	var cost := snappedf(HIGHWAY_CELL * float(cells.size()) + HIGHWAY_JUNCTION * float(junctions.size()) + HIGHWAY_CROSSING * float(crossings.size()), 100.0)
	return {"ok": true, "cells": cells, "junctions": junctions, "crossings": crossings, "legs": legs, "kosten": cost,
		"tage": maxi(10, ceili(float(cells.size()) / float(HIGHWAY_CELLS_PER_DAY)))}


## Beschluss des Regionalrats: Trasse planen, Anteile reservieren, ein Bauauftrag (Bund zahlt HIGHWAY_FEDERAL bei der Abnahme).
func propose_highway(initiator: int, shares: Dictionary, reason: String) -> Dictionary:
	if has_highway():
		return {"ok": false, "msg": "Die Region hat bereits eine Autobahn (geplant, im Bau oder fertig)."}
	var pl := plan_highway()
	if not pl.ok:
		return pl
	var day := GameCalendar.day_of(sim.game_min)
	var town_cost := float(pl.kosten) * (1.0 - HIGHWAY_FEDERAL)
	var r := {"id": "R%d" % _next, "kind": "autobahn", "from": initiator, "to": initiator, "initiator": initiator, "shares": shares.duplicate(),
		"votes": {}, "status": "vorgeschlagen", "cells": pl.cells, "junctions": pl.junctions, "crossings": pl.crossings, "legs": pl.legs,
		"cost": float(pl.kosten), "federal": snappedf(float(pl.kosten) * HIGHWAY_FEDERAL, 1.0), "town_cost": snappedf(town_cost, 1.0), "days": int(pl.tage),
		"day": day, "deadline": day, "project": "", "reason": reason.left(200), "note": ""}
	_next += 1
	for k in shares:
		r.votes[str(k)] = "zugestimmt"   # der Regionalrat hat beschlossen
	items[r.id] = r
	for k in shares:
		if sim.towns.mayor(int(k)).available_budget() < float(town_cost) * float(shares[k]):
			_fail(r, "Anteil von %s (%s) ist nicht gedeckt" % [sim.towns.name_of(int(k)), Catalog.money(town_cost * float(shares[k]))])
			return {"ok": false, "msg": r.note, "ref": r.id}
	var M: Mayor = sim.towns.mayor(initiator)
	# Material beschafft die Baufirma selbst (im Preis enthalten) - nicht ueber das Stadtlager eines kleinen Ortes, das diese Mengen nie fuehrt
	var prj: Dictionary = M.add_works_project("autobahn", r.id, float(r.cost), int(r.days), {}, "Autobahn %s (Beschluss Regionalrat)" % r.id)
	M.commitments = maxf(0.0, M.commitments - float(r.cost))
	var sh := {}
	for k in shares:
		var amt := snappedf(town_cost * float(shares[k]), 1.0)
		sim.towns.mayor(int(k)).commitments += amt
		sh[str(k)] = amt
	prj["shares"] = sh
	prj["federal"] = float(r.federal)
	prj["regional"] = r.id
	r.project = prj.id
	r.status = "beschlossen"
	sim.log_event("Autobahn %s beschlossen: %d Felder zweibahnig, %d Anschlussstellen, %d Kreuzungen, %s (Bund %s, Städte %s nach Nutzung: %s)." % [r.id, r.cells.size(),
		r.junctions.size(), r.crossings.size(), Catalog.money(float(r.cost)), Catalog.money(float(r.federal)), Catalog.money(town_cost), _shares_text(r)], "good")
	return {"ok": true, "msg": "Autobahn %s beschlossen und ausgeschrieben (Projekt %s)." % [r.id, prj.id], "ref": r.id}


## Baufortschritt 0..1 einer Autobahn (fuer die Darstellung): laufender Bauauftrag nach verbrauchten Bautagen.
func progress(r: Dictionary) -> float:
	if r.status == "fertig":
		return 1.0
	var e: Dictionary = sim.construction.public.get(str(r.project), {})
	if e.is_empty() or int(e.get("days", 0)) <= 0:
		return 0.0
	return clampf(1.0 - float(e.days_left) / float(e.days), 0.0, 1.0)


func _open_highway(r: Dictionary) -> void:
	var cs: Array = r.cells.map(func(c): return Vector2i(int(c[0]), int(c[1])))
	sim.access._apply_cells(cs)
	for c in cs + r.get("crossings", []).map(func(c): return Vector2i(int(c[0]), int(c[1]))):
		highway[c] = true
		if sim.nav != null and sim.nav.road.is_in_boundsv(c) and not sim.nav.road.is_point_solid(c):
			sim.nav.road.set_point_weight_scale(c, HIGHWAY_WEIGHT)
			sim.nav.base_weight[c] = HIGHWAY_WEIGHT


func highway_summary() -> Dictionary:
	var hw: Array = items.values().filter(func(r): return str(r.kind) == "autobahn")
	var out := {"verkehr_ueberland_14_tage": snappedf(traffic_mean(14), 0.1), "schwelle_antrag": HIGHWAY_TRAFFIC, "nutzungsanteile": traffic_shares()}
	if not hw.is_empty():
		var r: Dictionary = hw[-1]
		out["autobahn"] = {"id": r.id, "status": r.status, "felder": r.cells.size(), "anschlussstellen": r.get("junctions", []).size(),
			"kreuzungen": r.get("crossings", []).size(), "kosten": int(r.cost), "bund": int(r.get("federal", 0)), "fortschritt": snappedf(progress(r), 0.01), "hinweis": r.note}
	return out
