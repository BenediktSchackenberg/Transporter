class_name EventDirector
extends RefCounted
## Ereignisregler fuer Zuschauer. Jedes Ereignis hat Beginn, Dauer und definierte Wirkung in der Simulation.
## Die KI erfaehrt davon nur ueber regulaere Quellen (Verkehrsmeldungen, Markt, Preise, Arbeitsmarkt).
## Beim Ausloesen wird pro Firma ein Schnappschuss gemacht; impact() zeigt spaeter, was sich tatsaechlich geaendert hat.

signal buildings_added(ids: Array)

const TYPES := {
	"strassensperre": "Straße sperren (Abschnitt nahe Kameramitte)",
	"grossauftrag": "Großauftrag veröffentlichen",
	"treibstoffpreis": "Treibstoffpreise ändern",
	"arbeitskraeftemangel": "Arbeitskräftemangel auslösen",
	"gewerbegebiet": "Neues Gewerbegebiet mit Kunden öffnen",
	"nachfrage": "Nachfrage nach einer Warenart erhöhen",
}

var sim
var events: Array = []
var next_id := 1
var demand := {}          # Ware -> Faktor (aktive Nachfrageereignisse)
var reroutes := {}        # Firma -> Anzahl Umplanungen wegen Sperrungen (Messgroesse)
var added_buildings: Array = []   # {type, x, y, w, h, name} der zur Laufzeit gebauten Gebaeude (fuer das Laden)


func setup(simulation) -> void:
	sim = simulation


func demand_factor(cargo: String) -> float:
	return float(demand.get(cargo, 1.0)) * sim.world_events.demand_factor(cargo)


func get_event(id: String) -> Dictionary:
	for e in events:
		if e.id == id:
			return e
	return {}


## Automatisches Ereignis (WorldEvents). Pflichtfelder fuer die Nachvollziehbarkeit:
## ID, Ursache und Bedingungen, Orte, Beginn und Dauer, Schwere, Wirkung, Informationsquellen, Endebedingung.
func create(typ: String, cause: String, text: String, severity: int, duration_min: float, o: Dictionary = {}) -> Dictionary:
	var now: float = sim.game_min
	var e := {"id": "E%d" % next_id, "typ": typ, "params": o.get("params", {}), "start": now, "ende": now + duration_min, "status": "aktiv",
		"text": text, "snapshot": _snapshot(), "reroutes_start": reroutes.duplicate(), "data": o.get("data", {}).duplicate(true), "auto": true,
		"ursache": cause, "bedingungen": str(o.get("conditions", "")), "orte": o.get("places", []).duplicate(), "schwere": severity,
		"wirkung": o.get("effects", []).duplicate(), "quellen": o.get("sources", []).duplicate(), "ende_bedingung": str(o.get("end", "Dauer abgelaufen")),
		"ende_key": str(o.get("end_key", "")), "need": o.get("need", {}).duplicate(), "demand": o.get("demand", {}).duplicate()}
	next_id += 1
	events.append(e)
	sim.log_event("Ereignis %s: %s – Ursache: %s" % [e.id, text, cause], "warn" if severity >= 2 else "info")
	sim.decisions.note(-1, "world", "%s (Ursache: %s)" % [text, cause], {"event_id": e.id})
	return e


## params: strassensperre {cell:[x,y]}, grossauftrag {}, treibstoffpreis {faktor}, arbeitskraeftemangel {anteil},
## gewerbegebiet {}, nachfrage {ware, faktor}
func trigger(typ: String, params: Dictionary, duration_min: float) -> Dictionary:
	if not TYPES.has(typ):
		return {"ok": false, "msg": "Unbekanntes Ereignis."}
	var now: float = sim.game_min
	var e := {"id": "Z%d" % next_id, "typ": typ, "params": params, "start": now, "ende": now + duration_min, "status": "aktiv",
		"text": "", "snapshot": _snapshot(), "reroutes_start": reroutes.duplicate(), "data": {}}
	next_id += 1
	match typ:
		"strassensperre":
			var c := Vector2i(int(params.cell[0]), int(params.cell[1]))
			var cells := _segment(c)
			if cells.is_empty():
				return {"ok": false, "msg": "Keine Straße in der Nähe gefunden."}
			for p in cells:
				sim.nav.add_roadwork(p, e.ende)
			var where: String = Catalog.DISTRICTS[sim.city.district_of(cells[0])]
			e.text = "Straßensperrung im %s (%d Abschnitte) bis %s" % [where, cells.size(), Catalog.game_minutes_to_text(e.ende)]
			sim.traffic_events.append({"kind": "sperrung", "cells": cells, "until": e.ende, "text": "Vollsperrung im %s – Umleitung nötig" % where})
		"grossauftrag":
			var k: Contract = null
			for i in 40:
				k = sim.market.spawn(now)
				if k and k.qty >= 12:
					break
			if k == null:
				return {"ok": false, "msg": "Kein Großauftrag erzeugbar."}
			k.qty = maxi(k.qty, 60)
			k.needs_heavy = true
			k.reward = roundf(k.reward * 2.5 / 10.0) * 10.0
			k.deadline = now + maxf(duration_min, 600.0)
			k.offer_until = now + duration_min
			k.label = "Großauftrag " + k.cargo_name()
			k.size_class = "groß"
			e.text = "Großauftrag %s: %d × %s, %s, ausgehängt an der Jobbörse" % [k.id, k.qty, Catalog.CARGO[k.cargo].name, Catalog.money(k.reward)]
			e.data["contract"] = k.id
		"treibstoffpreis":
			sim.resources.fuel_price_factor = clampf(float(params.get("faktor", 1.5)), 0.3, 4.0)
			e.text = "Treibstoffpreise ×%.2f" % sim.resources.fuel_price_factor
		"arbeitskraeftemangel":
			var share := clampf(float(params.get("anteil", 0.7)), 0.1, 1.0)
			var avail: Array = sim.personnel.available()
			var gone: Array = avail.slice(0, int(ceil(avail.size() * share)))
			for w in gone:
				w.employer = -2   # voruebergehend nicht am Arbeitsmarkt
			sim.personnel.shortage_until = e.ende
			e.data["withheld"] = gone.map(func(w): return w.id)
			e.text = "Arbeitskräftemangel: %d Arbeitskräfte nicht verfügbar" % gone.size()
		"gewerbegebiet":
			var ids := _open_business_park()
			if ids.is_empty():
				return {"ok": false, "msg": "Kein Platz für ein neues Gewerbegebiet gefunden."}
			e.data["buildings"] = ids
			e.ende = now + 99999.0   # dauerhaft
			e.text = "Neues Gewerbegebiet mit %d Kunden im %s" % [ids.size(), Catalog.DISTRICTS[sim.city.building(ids[0]).district]]
			buildings_added.emit(ids)
		"nachfrage":
			var ware := str(params.get("ware", "lebensmittel"))
			if not Catalog.CARGO.has(ware):
				return {"ok": false, "msg": "Unbekannte Ware."}
			demand[ware] = clampf(float(params.get("faktor", 1.5)), 1.0, 3.0)
			e.text = "Nachfrage nach %s ×%.1f" % [Catalog.CARGO[ware].name, demand[ware]]
	events.append(e)
	sim.log_event("Zuschauer-Ereignis: " + e.text, "system")
	sim.decisions.note(-1, "spectator", e.text)
	return {"ok": true, "msg": e.text, "id": e.id}


func minute_tick(now: float) -> void:
	for e in events:
		if e.status != "aktiv":
			continue
		if e.typ == "nachfrage" and sim.rng.randf() < 0.3:
			# zusaetzliche Auftraege der gefragten Ware
			for i in 3:
				var k: Contract = sim.market.spawn(now)
				if k and k.cargo == str(e.params.get("ware", "")):
					break
		if now >= float(e.ende) or (e.get("auto", false) and sim.world_events.ended(e, now)):
			e.status = "beendet"
			if e.get("auto", false):
				sim.world_events.on_end(e, now)
			match e.typ:
				"treibstoffpreis":
					sim.resources.fuel_price_factor = 1.0
				"arbeitskraeftemangel":
					for wid in e.data.get("withheld", []):
						var w: Worker = sim.personnel.workers.get(wid)
						if w and w.employer == -2:
							w.employer = -1
				"nachfrage":
					demand.erase(str(e.params.get("ware", "")))
			sim.log_event(("Ereignis %s beendet: %s" % [e.id, e.text]) if e.get("auto", false) else ("Zuschauer-Ereignis beendet: " + e.text), "system")


## Strassenabschnitt zwischen zwei Kreuzungen (gerade Strecke) nahe einer Zelle.
func _segment(c: Vector2i) -> Array:
	var start := Vector2i(-1, -1)
	for r in range(0, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := c + Vector2i(dx, dy)
				if start.x < 0 and sim.city.is_road(q) and sim.city.road_mask(q) in [5, 10]:
					start = q
	if start.x < 0:
		return []
	var dir := Vector2i(1, 0) if sim.city.road_mask(start) == 10 else Vector2i(0, 1)
	var cells: Array = [start]
	for sgn in [1, -1]:
		var q: Vector2i = start + dir * sgn
		while sim.city.is_road(q) and sim.city.road_mask(q) in [5, 10] and cells.size() < 16:
			cells.append(q)
			q += dir * sgn
	return cells


## Neue Kundengebaeude auf freier Flaeche am Stadtrand (an das Strassennetz angebunden).
func _open_business_park() -> Array:
	var c: CityData = sim.city
	var types := [["warehouse", 4, 3, "Logistikpark"], ["shop", 2, 2, "Supermarkt Neu"], ["office", 3, 3, "Gewerbehof"],
		["factory", 4, 4, "Neue Fabrik"]]
	var ids: Array = []
	var tries := 0
	while ids.size() < 4 and tries < 4000:
		tries += 1
		var spec: Array = types[ids.size() % types.size()]
		var r := Rect2i(sim.rng.randi_range(4, c.size - 20), sim.rng.randi_range(4, c.size - 10), spec[1], spec[2])
		if c.district_of(r.position) not in [4, 5] or not _free(r):
			continue
		var b := _add_building(spec[0], r, spec[3])
		if b.is_empty():
			continue
		ids.append(b.id)
	if not ids.is_empty():
		sim.market.refresh()
	return ids


func _free(r: Rect2i) -> bool:
	var c: CityData = sim.city
	var near_road := false
	for y in range(r.position.y - 1, r.end.y + 1):
		for x in range(r.position.x - 1, r.end.x + 1):
			var p := Vector2i(x, y)
			if not c.inside(p):
				return false
			var inner := x >= r.position.x and x < r.end.x and y >= r.position.y and y < r.end.y
			if inner and (c.building_at[c.idx(p)] != -1 or c.blocked[c.idx(p)] == 1 or c.g(p) in [CityData.G.ROAD, CityData.G.WATER]):
				return false
			if c.is_road(p) or c.road_mask(p) != 0:
				near_road = true
	return near_road


func _add_building(type: String, r: Rect2i, name: String) -> Dictionary:
	var c: CityData = sim.city
	var info: Array = CityGenerator.TYPES[type]
	var b := {"id": c.buildings.size(), "type": type, "sprite": info[0][0], "x": r.position.x, "y": r.position.y,
		"w": r.size.x, "h": r.size.y, "district": c.district_of(r.position), "in": info[3], "out": info[4], "role": "customer",
		"name": name}
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			c.building_at[c.idx(p)] = b.id
			c.blocked[c.idx(p)] = 1
			sim.nav.walk.set_point_solid(p, true)
	b["road"] = _nearest(r, func(p): return c.is_road(p))
	b["walk"] = _nearest(r, func(p): return c.walkable(p) and c.g(p) != CityData.G.ROAD)
	if not c.is_road(b.road):
		return {}
	c.buildings.append(b)
	added_buildings.append({"type": type, "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y, "name": name})
	return b


func _nearest(r: Rect2i, pred: Callable) -> Vector2i:
	for rad in range(1, 10):
		for y in range(r.position.y - rad, r.end.y + rad):
			for x in range(r.position.x - rad, r.end.x + rad):
				var p := Vector2i(x, y)
				if sim.city.inside(p) and pred.call(p):
					return p
	return Vector2i(r.position.x, r.end.y)


## Zustand je Firma (Plan, Touren, Auftraege, Aufgaben) fuer den spaeteren Vergleich.
func _snapshot() -> Dictionary:
	var snap := {}
	for c in sim.companies:
		var p: Dictionary = sim.plans.current(c.id)
		snap[str(c.id)] = {"plan": "%s:%s" % [p.get("id", "-"), p.get("status", "-")],
			"stops": sim.company_vehicles(c.id).map(func(v): return "%d:%s" % [v.id, JSON.stringify(v.stops)]),
			"contracts": sim.contracts.values().filter(func(k): return k.owner == c.id and k.status in ["accepted", "assigned", "in_transit"]).map(func(k): return k.id),
			"tasks": sim.personnel.tasks.values().filter(func(t): return t.company == c.id and not t.is_final()).map(func(t): return t.id),
			"profit": c.ledger.profit(), "offers": sim.social.offers.values().filter(func(o): return o.from == c.id or o.to == c.id).size()}
	return snap


## Was hat sich seit dem Ereignis je Firma tatsaechlich veraendert?
func impact(e: Dictionary) -> Array:
	var out: Array = []
	var now := _snapshot()
	for c in sim.companies:
		var a: Dictionary = e.snapshot.get(str(c.id), {})
		var b: Dictionary = now[str(c.id)]
		var parts: Array = []
		if a.get("plan", "") != b.plan:
			parts.append("Plan %s → %s" % [a.get("plan", "-"), b.plan])
		var changed_routes := 0
		for s in b.stops:
			if s not in a.get("stops", []):
				changed_routes += 1
		if changed_routes > 0:
			parts.append("%d Fahrzeugtouren geändert" % changed_routes)
		var rr: int = int(reroutes.get(c.id, 0)) - int(e.reroutes_start.get(c.id, 0))
		if rr > 0:
			parts.append("%d Umleitungen gefahren" % rr)
		var new_k: Array = b.contracts.filter(func(k): return k not in a.get("contracts", []))
		var gone_k: Array = a.get("contracts", []).filter(func(k): return k not in b.contracts)
		if not new_k.is_empty() or not gone_k.is_empty():
			parts.append("Aufträge +%d/−%d" % [new_k.size(), gone_k.size()])
		var new_t: Array = b.tasks.filter(func(t): return t not in a.get("tasks", []))
		if not new_t.is_empty():
			parts.append("%d neue Arbeitsaufgaben" % new_t.size())
		if int(b.offers) > int(a.get("offers", 0)):
			parts.append("%d neue Verhandlungsangebote" % (int(b.offers) - int(a.get("offers", 0))))
		parts.append("Gewinn seit Ereignis %s" % Catalog.money(float(b.profit) - float(a.get("profit", 0.0))))
		out.append("%s: %s" % [c.company_name, ", ".join(parts)])
	return out


func to_dict() -> Dictionary:
	return {"events": events, "next_id": next_id, "demand": demand, "reroutes": reroutes, "added_buildings": added_buildings}


func from_dict(d: Dictionary) -> void:
	for ab in d.get("added_buildings", []):   # zur Laufzeit entstandene Gebaeude in gleicher Reihenfolge (= gleiche IDs) neu anlegen
		_add_building(ab.type, Rect2i(int(ab.x), int(ab.y), int(ab.w), int(ab.h)), ab.name)
	events = d.get("events", [])
	next_id = int(d.get("next_id", 1))
	demand = d.get("demand", {})
	for k in d.get("reroutes", {}):
		reroutes[int(k)] = int(d.reroutes[k])
