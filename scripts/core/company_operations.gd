class_name CompanyOperations
extends RefCounted
## Verbindet KI-Auftrag, Disposition, Personal, Hof, Waren und verbindliche Kooperation.
## Routine fuehrt nur erteilte Auftraege aus. Investitionen und Preiszusagen bleiben KI-Entscheidungen.

const SCHEMA := {
	"set_operations_policy": {"params": {"auto_driver": "bool?", "return_home": "bool?", "yard_checks": "bool?"}, "desc": "Betriebsroutine steuern: vorhandene Fahrer automatisch einteilen, nach Zustellung zum Hof zurueckkehren, vor neuer Tour Hofkontrolle. Keine automatische Anwerbung/Investition. Standard jeweils true."},
	"create_transport_line": {"params": {"name": "string", "cargo": "string", "vehicle_ids": "array", "pickup_id": "int?", "dropoff_id": "int?", "via_depot": "bool?"},
		"desc": "Dauerauftrag an die Disposition: eigene Fahrzeuge bedienen bekannte, passende Auftraege dieser Warenart. Optional feste Abholung/Ziel, sonst wechselnde Kunden. via_depot=true: Abholung, echter Umschlag am eigenen Hof, Zustellung. Fahrzeuge sind fuer die Linie reserviert. Keine automatischen Kaeufe, Kredite oder Anwerbungen."},
	"pause_transport_line": {"params": {"line_id": "string"}, "desc": "Keine neuen Auftraege fuer die eigene Linie; laufende Ware wird fertig zugestellt, danach Fahrzeuge freigeben."},
	"request_transport_help": {"params": {"contract_id": "string", "max_fee": "number"}, "desc": "Eigene unverplante Fracht ausschreiben. Andere Unternehmer koennen quote_transport_help abgeben. Erst deine Annahme des Preisangebots bindet und bezahlt einen Unterauftrag."},
	"quote_transport_help": {"params": {"request_id": "string", "fee": "number"}, "desc": "Auf eine offene Frachtanfrage mit einem verbindlichen Preis antworten. Auftraggeber entscheidet per accept_trade/counter_offer/reject_trade. Kein Geldtransfer bei der Anfrage oder Preisabgabe."},
}

var sim
var lines := {}
var jobs := {}                 # Auftrags-ID -> {line, vehicle, stage, qty, counted}
var requests := {}
var policies := {}
var dialogue: Array = []        # belegte Betriebsmeldungen, keine fingierten Modellantworten
var _next_line := 1
var _next_request := 1
var _layout := {}
var _yard_nav := {}
var _layout_revision := ""
var _last_phase := {}


const DISPATCH_DETOUR_MAX := 18       # Felder: weiter vom Hof entfernt fährt ein Fahrzeug ohne Hofkontrolle direkt zum nächsten Auftrag


func setup(s) -> void:
	sim = s


func run(cid: int, name: String, a: Dictionary) -> Dictionary:
	match name:
		"set_operations_policy":
			var policy: Dictionary = policies.get(cid, {"auto_driver": true, "return_home": true, "yard_checks": true})
			for key in ["auto_driver", "return_home", "yard_checks"]:
				if a.has(key):
					policy[key] = bool(a[key])
			policies[cid] = policy
			return {"ok": true, "msg": "Betriebsroutine aktualisiert."}
		"create_transport_line": return create_line(cid, a)
		"pause_transport_line":
			var l: Dictionary = lines.get(str(a.line_id), {})
			if l.is_empty() or int(l.owner) != cid or int(l.generation) != sim.company(cid).generation:
				return {"ok": false, "msg": "Keine eigene aktuelle Linie."}
			l.active = false
			return {"ok": true, "msg": "Linie pausiert; laufende Transporte werden abgeschlossen."}
		"request_transport_help": return request_help(cid, str(a.contract_id), float(a.max_fee))
		"quote_transport_help": return quote_help(cid, str(a.request_id), float(a.fee))
	return {}


func line_of(vid: int) -> String:
	var vehicle: FleetVehicle = sim.vehicles.get(vid)
	if vehicle == null:
		return ""
	for l in lines.values():
		if vehicle.owner != int(l.owner) or int(l.generation) != sim.company(int(l.owner)).generation or not sim.company(int(l.owner)).is_active():
			continue
		if vid in l.vehicles and (l.active or jobs.values().any(func(j): return j.line == l.id and not j.counted)):
			return str(l.id)
	return ""


func create_line(cid: int, a: Dictionary) -> Dictionary:
	var cargo := str(a.cargo)
	if not Catalog.CARGO.has(cargo) or a.vehicle_ids.is_empty():
		return {"ok": false, "msg": "Gueltige Warenart und mindestens ein Fahrzeug angeben."}
	var ids: Array = []
	for id in a.vehicle_ids:
		if not (id is int or id is float) or float(id) != floorf(float(id)):
			return {"ok": false, "msg": "Fahrzeug-IDs muessen ganze Zahlen sein."}
		var v: FleetVehicle = sim.vehicles.get(int(id))
		if v == null or v.owner != cid or v.operator >= 0 or line_of(v.id) != "":
			return {"ok": false, "msg": "Fahrzeug fehlt, ist fremd, vermietet oder bereits einer Linie zugeteilt."}
		if v.id not in ids:
			ids.append(v.id)
			if sim.driver_of(v) == null:
				v.crew_requested = true
	var pickup := int(a.get("pickup_id", -1))
	var dropoff := int(a.get("dropoff_id", -1))
	for site in [pickup, dropoff]:
		if site < -1 or site >= sim.city.buildings.size():
			return {"ok": false, "msg": "Unbekannter Linienhalt."}
	var l := {"id": "L%d" % _next_line, "owner": cid, "generation": sim.company(cid).generation,
		"name": str(a.name).left(70), "cargo": cargo, "vehicles": ids, "pickup": pickup, "dropoff": dropoff,
		"depot": int(sim.company(cid).depots[0]), "via_depot": bool(a.get("via_depot", true)), "active": true,
		"status": "wartet auf passende Fracht", "delivered": 0, "revenue": 0.0, "created": sim.game_min}
	_next_line += 1
	lines[l.id] = l
	# Bereits disponierte Einzelauftraege bleiben bestehen; keine Tour wird ueberschrieben.
	say(cid, "Disposition", "Linie %s eingerichtet: %s. Ich teile Fahrer und Hofarbeit ein." % [l.name, Catalog.CARGO[cargo].name])
	return {"ok": true, "msg": "Linie %s aktiv. Passende bekannte Auftraege werden ohne weitere KI-Aufrufe abgewickelt." % l.id, "id": l.id}


func tick() -> void:
	for c in sim.companies:
		if not c.is_active():
			continue
		_crew(c.id)
	for l in lines.values():
		if int(l.generation) != sim.company(int(l.owner)).generation or not sim.company(int(l.owner)).is_active():
			l.active = false
			l.status = "Unternehmen geschlossen"
			continue
		_advance(l)
	for r in requests.values():
		var k: Contract = sim.contracts.get(str(r.contract))
		if int(r.generation) != sim.company(int(r.owner)).generation or k == null or k.owner != int(r.owner) or k.status not in ["accepted", "assigned", "in_transit"] or sim.game_min > float(r.expires):
			r.status = "geschlossen"
	# Bestaetigte Unterauftraege erhalten dieselbe Fahrer- und Dispositionskette.
	for g in sim.social.agreements.values():
		if g.kind != "split_contract" or g.status != "aktiv":
			continue
		var cid := int(g.to)
		if not sim.company(cid).is_active():
			continue
		var k: Contract = sim.contracts.get(str(g.contract_id))
		var quota: int = sim.social.split_quota(cid, str(g.contract_id))
		if k == null or quota <= 0 or sim.vehicles.values().any(func(v): return v.stops.any(func(st): return st.contract_id == k.id and (v.operator if v.operator >= 0 else v.owner) == cid)):
			continue
		for v in sim.company_vehicles(cid):
			if _free(v) and line_of(v.id) == "" and sim.driver_of(v) != null and k.vehicle_ok(v.model):
				var q := mini(quota, int(v.spec().capacity))
				var result: Dictionary = sim.executor._assign(cid, v.id, k.id, q)
				if result.ok:
					say(cid, "Disposition", "Bestaetigter Unterauftrag %s: #%d uebernimmt %d Einheiten." % [k.id, v.id, q], k.id)
				break


func _free(v: FleetVehicle) -> bool:
	return v.state in ["idle", "returning", "yard_parking"] and v.stops.is_empty() and v.load.is_empty() and v.operator < 0 and v.held_by == ""


func _matches(l: Dictionary, k: Contract) -> bool:
	return k.cargo == l.cargo and (int(l.pickup) < 0 or k.pickup == int(l.pickup)) and (int(l.dropoff) < 0 or k.dropoff == int(l.dropoff))


func _advance(l: Dictionary) -> void:
	var cid := int(l.owner)
	var pending := false
	for kid in jobs:
		var j: Dictionary = jobs[kid]
		if j.line != l.id or j.counted:
			continue
		var k: Contract = sim.contracts.get(kid)
		if k == null or k.status in ["delivered", "failed", "cancelled", "expired"]:
			if k and k.status == "delivered":
				completed(k)
			else:
				j.counted = true
			continue
		pending = true
		if j.stage == "inbound" and sim.logistics.stored(int(l.depot), kid) >= int(j.qty):
			for vid in l.vehicles:
				var v: FleetVehicle = sim.vehicles.get(int(vid))
				if v and _free(v) and sim.driver_of(v) != null:
					var r: Dictionary = sim.executor._assign(cid, v.id, kid, int(j.qty), "lager:%d" % int(l.depot), Logistics.DROP)
					if r.ok:
						j.stage = "outbound"
						j.vehicle = v.id
						say(cid, "Lager", "%s ist am Hof eingelagert. #%d uebernimmt die Zustellung." % [kid, v.id], kid)
					break
	if pending or not l.active:
		return
	var fleet: Array = []
	for vid in l.vehicles:
		var v: FleetVehicle = sim.vehicles.get(int(vid))
		if v and _free(v) and sim.driver_of(v) != null:
			fleet.append(v)
	if fleet.is_empty():
		_set_status(l, "Fahrzeug oder Fahrer noch nicht bereit")
		return
	var delegated: Array = requests.values().filter(func(r): return int(r.owner) == cid and (r.status == "offen" or r.offers.any(func(oid): return sim.social.offers.get(oid, {}).get("status", "") == "accepted"))).map(func(r): return r.contract)
	var candidates: Array = sim.contracts.values().filter(func(k): return k.id not in delegated and sim.company(cid).known.has(k.id) and _matches(l, k) and k.internal == "" and (k.status == "open" or (k.status == "accepted" and k.owner == cid and not jobs.has(k.id))))
	candidates.sort_custom(func(a, b): return a.deadline < b.deadline)
	var refusal := ""
	for k in candidates:
		for v in fleet:
			if not k.vehicle_ok(v.model) or k.qty > int(v.spec().capacity) or k.min_rep > sim.company(cid).reputation:
				continue
			var estimate := route_estimate(v, k, bool(l.via_depot))
			if sim.game_min + float(estimate.minutes) > k.deadline:
				refusal = "Frist zu knapp: %s benoetigt geschaetzt %d min. Direktlinie oder andere Fracht waehlen." % [k.id, ceili(float(estimate.minutes))]
				continue
			if k.reward < float(estimate.cost):
				refusal = "Fracht %s deckt die geschaetzten Fahrt- und Fahrerkosten nicht." % k.id
				continue
			if l.via_depot and (k.qty > sim.logistics.storage_cap(int(l.depot)) - sim.logistics.storage_used(int(l.depot)) or (k.needs_cold and sim.estate.is_plot(int(l.depot)) and k.qty > sim.estate.storage_cap(int(l.depot), true))):
				_set_status(l, "Lagerplatz oder Kuehllager fehlt: Hof ausbauen oder Direktlinie waehlen")
				continue
			if k.status == "open":
				var accepted: Dictionary = sim.executor._accept_contract(cid, k.id, -1)
				if not accepted.ok:
					continue
			var dest := "lager:%d" % int(l.depot) if l.via_depot else Logistics.DROP
			var r: Dictionary = sim.executor._assign(cid, v.id, k.id, k.qty, Logistics.PICKUP, dest)
			if r.ok:
				jobs[k.id] = {"line": l.id, "vehicle": v.id, "stage": "inbound" if l.via_depot else "outbound", "qty": k.qty, "counted": false}
				_set_status(l, "%s: %s → %s → %s" % [k.id, sim.city.building(k.pickup).name, "Betriebshof" if l.via_depot else "Direktfahrt", sim.city.building(k.dropoff).name])
				say(cid, "Disposition", "%s an #%d: %d x %s, danach %s." % [k.id, v.id, k.qty, k.cargo_name(), "Umschlag am Hof" if l.via_depot else "zum Kunden"], k.id)
				return
	_set_status(l, refusal if refusal != "" else "Keine passende bekannte Fracht: Auftraege sammeln, Linie anpassen oder pausieren")


func route_estimate(v: FleetVehicle, k: Contract, via_depot: bool) -> Dictionary:
	var depot: Vector2i = sim.depot_road(v.owner)
	var pickup: Vector2i = sim.city.building(k.pickup).road
	var dropoff: Vector2i = sim.city.building(k.dropoff).road
	var points: Array[Vector2i] = [v.tile()]
	if v.needs_dispatch and enabled(v.owner, "yard_checks"):
		points.append(depot)
	points.append(pickup)
	if via_depot:
		points.append(depot)
	points.append(dropoff)
	var tiles := 0.0
	for i in range(1, points.size()):
		tiles += absi(points[i].x - points[i - 1].x) + absi(points[i].y - points[i - 1].y)
	# Ausgewiesene Planungsschaetzung: Kreuzungen/Umwege +35 %, vier Handhabungsschritte beim Umschlag.
	tiles *= 1.35
	var minutes := tiles / maxf(0.1, v.speed * sim.wx.drive_factor()) * Catalog.GAME_MIN_PER_SIM_SEC
	minutes += (4.0 if via_depot else 2.0) * Catalog.LOADING_MIN + (6.0 if v.needs_dispatch else 0.0)
	var driver: Worker = sim.driver_of(v)
	var wage := driver.wage if driver else Catalog.DRIVER_BASE_WAGE
	return {"minutes": minutes, "cost": tiles * float(v.spec().cost_per_tile) * 1.15 + minutes * wage / 60.0}


func completed(k: Contract) -> void:
	var j: Dictionary = jobs.get(k.id, {})
	if j.is_empty() or j.counted:
		return
	j.counted = true
	var l: Dictionary = lines.get(str(j.line), {})
	if l.is_empty() or int(l.generation) != sim.company(int(l.owner)).generation:
		return
	l.delivered += 1
	l.revenue += k.paid
	say(int(l.owner), "Disposition", "%s zugestellt; %s Erloes. Naechste Fracht wird eingeplant." % [k.id, Catalog.money(k.paid)], k.id)


func _set_status(l: Dictionary, status: String) -> void:
	if str(l.status) != status:
		l.status = status
		if status.begins_with("Keine passende") or status.begins_with("Frist zu knapp") or status.begins_with("Fracht "):
			if not l.has("idle_since"):
				l["idle_since"] = sim.game_min
		else:
			l.erase("idle_since")
		sim.agent_event.emit(int(l.owner), "Linie %s: %s" % [l.name, status])


func enabled(cid: int, key: String) -> bool:
	return bool(policies.get(cid, {}).get(key, true))


func _crew(cid: int) -> void:
	if not enabled(cid, "auto_driver"):
		return
	for v in sim.company_vehicles(cid):
		if (not v.crew_requested and line_of(v.id) == "") or v.operator >= 0 or sim.driver_of(v) != null or sim.personnel._has_task_for(v.id, "fahren"):
			continue
		var candidates: Array = sim.personnel.employed(cid).filter(func(w): return int(w.skills.fahren) > 0 and sim.personnel.can_take(w, "fahren") == "" and w.vehicle_id < 0)
		candidates.sort_custom(func(a, b): return int(a.skills.fahren) > int(b.skills.fahren))
		if candidates.is_empty():
			continue
		var w: Worker = candidates[0]
		sim.personnel.create_task(cid, "fahren", {"vehicle_id": v.id}, w.id, "", 1, "Disposition")
		say(cid, "Disposition", "%s, uebernimm #%d. Danach Hofkontrolle und Tourfreigabe." % [w.name, v.id], "", w.id)


func say(cid: int, speaker: String, text: String, kid: String = "", worker: String = "") -> void:
	dialogue.append({"t": sim.game_min, "company": cid, "speaker": speaker, "text": text, "contract": kid, "worker": worker, "source": "Betrieb"})
	if dialogue.size() > 160:
		dialogue.pop_front()
	sim.log_event("%s · %s: %s" % [sim.company(cid).company_name, speaker, text], "info", cid)
	if speaker == "Disposition":
		sim.avatars[cid].say(text, true)


func prepare_dispatch(v: FleetVehicle) -> bool:
	if not enabled(v.owner, "yard_checks") or not v.needs_dispatch or v.stops.is_empty() or sim.driver_of(v) == null:
		return false
	if not sim.at_depot(v):
		var home: Vector2i = sim.nearest_depot_road(v.owner, v.tile())
		if absi(home.x - v.tile().x) + absi(home.y - v.tile().y) > DISPATCH_DETOUR_MAX:
			return false   # weit weg vom Hof: keine Hofkontrolle, sonst kostet der Umweg mehr als die Fahrt (Fristen, Ruf)
		sim.route(v, home, "to_dispatch")
		return true
	begin_dispatch(v)
	return true


func begin_dispatch(v: FleetVehicle) -> void:
	if v.stops.is_empty():
		park(v)
		return
	if approach_dock(v, _nearest_site(v)):
		v.state = "to_dispatch"
		return
	v.state = "dispatching"
	v.timer = 6.0
	v.path.clear()
	var driver: Worker = sim.driver_of(v)
	say(v.owner, driver.name if driver else "Fahrer", "#%d: Fahrzeug geprueft, Frachtpapiere fuer %s. Abfahrt nach Freigabe." % [v.id, v.stops[0].contract_id], str(v.stops[0].contract_id), driver.id if driver else "")


func park(v: FleetVehicle) -> void:
	var site := _nearest_site(v)
	var points := yard_layout(site)
	var cell: Vector2i = points.parking[posmod(sim.company(v.owner).vehicle_ids.find(v.id), points.parking.size())]
	v.set_path(_yard_path(v.tile(), cell, site))
	v.lane = 0.0
	v.state = "yard_parking"
	v.needs_dispatch = true


func _nearest_site(v: FleetVehicle) -> int:
	var sites: Array = sim.company(v.owner).depots.duplicate()
	sites.sort_custom(func(a, b): return sim.city.building(int(a)).road.distance_squared_to(v.tile()) < sim.city.building(int(b)).road.distance_squared_to(v.tile()))
	return int(sites[0])


## Am Hof faehrt das Fahrzeug wirklich durch die Einfahrt zur Ladezone.
func approach_dock(v: FleetVehicle, site: int) -> bool:
	if site not in sim.company(v.owner).depots or not sim.estate.is_plot(site):
		return false
	var dock: Vector2i = yard_layout(site).dock
	if v.tile() == dock:
		return false
	var path := _yard_path(v.tile(), dock, site)
	if path.is_empty():
		return false
	v.set_path(path)
	v.lane = 0.0
	return true


func _yard_path(from: Vector2i, to: Vector2i, site: int) -> Array[Vector2i]:
	yard_layout(site) # Cache bei Umbau verwerfen.
	var plot: Dictionary = sim.estate.plots.get(site, sim.city.building(site))
	var gate: Vector2i = yard_layout(site).gate
	if not _yard_nav.has(site):
		var p: Dictionary = plot
		var grid := AStarGrid2D.new()
		grid.region = Rect2i(int(p.x) - 2, int(p.y) - 2, int(p.w) + 4, int(p.h) + 4)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		grid.update()
		for y in range(grid.region.position.y, grid.region.end.y):
			for x in range(grid.region.position.x, grid.region.end.x):
				var cell := Vector2i(x, y)
				var occupied: bool = sim.estate.facilities.values().any(func(f): return int(f.plot) == site and Rect2i(int(f.x), int(f.y), int(f.w), int(f.h)).has_point(cell))
				grid.set_point_solid(cell, occupied or not sim.city.walkable(cell))
		_yard_nav[site] = grid
	var grid: AStarGrid2D = _yard_nav[site]
	if not grid.region.has_point(from) or not grid.region.has_point(to):
		var outer: Array[Vector2i] = sim.nav.walk_path(from, gate)
		var inner: Array[Vector2i] = grid.get_id_path(gate, to) if grid.region.has_point(to) else sim.nav.walk_path(gate, to)
		if outer.is_empty() or inner.is_empty():
			return []
		outer.append_array(inner.slice(1))
		return outer
	# Aktuelle Position kann durch einen zwischenzeitlichen Bau belegt sein: Ausfahrt zulassen.
	var solid := grid.is_point_solid(from)
	grid.set_point_solid(from, false)
	var bounds := Rect2i(int(plot.x), int(plot.y), int(plot.w), int(plot.h))
	var path: Array[Vector2i] = grid.get_id_path(from, to)
	if not bounds.has_point(from) or not bounds.has_point(to):
		var entrance: Array[Vector2i] = grid.get_id_path(from, gate)
		var exit: Array[Vector2i] = grid.get_id_path(gate, to)
		if entrance.is_empty() or exit.is_empty():
			path = []
		else:
			entrance.append_array(exit.slice(1))
			path = entrance
	grid.set_point_solid(from, solid)
	return path


func yard_layout(site: int) -> Dictionary:
	var revision := "%d:%d" % [sim.estate.next_id, sim.estate.facilities.size()]
	if revision != _layout_revision:
		_layout.clear()
		_yard_nav.clear()
		_layout_revision = revision
	var key := str(site)
	if _layout.has(key):
		return _layout[key]
	var b: Dictionary = sim.city.building(site)
	var p: Dictionary = sim.estate.plots.get(site, b)
	var cells: Array[Vector2i] = []
	for y in range(int(p.y) + 1, int(p.y + p.h) - 1):
		for x in range(int(p.x) + 1, int(p.x + p.w) - 1):
			var q := Vector2i(x, y)
			if not sim.city.walkable(q):
				continue
			var occupied := false
			for f in sim.estate.facilities.values():
				if int(f.plot) == site and Rect2i(int(f.x), int(f.y), int(f.w), int(f.h)).has_point(q):
					occupied = true
					break
			if not occupied:
				cells.append(q)
	if cells.is_empty():
		cells.append(b.walk)
	cells.sort_custom(func(a, c): return a.distance_squared_to(b.road) < c.distance_squared_to(b.road))
	var n := cells.size()
	var parking: Array[Vector2i] = []
	for i in mini(4, n):
		parking.append(cells[mini(n - 1, i * 2)])
	var gate: Vector2i = Vector2i(int(p.entrance[0]), int(p.entrance[1])) if p.has("entrance") else b.walk
	var layout := {"gate": gate, "dock": cells[mini(n - 1, 2)], "storage": cells[mini(n - 1, n / 2)],
		"office": cells[-1], "service": cells[maxi(0, n - 3)], "parking": parking, "cells": cells}
	_layout[key] = layout
	return layout


func update_worker(w: Worker) -> void:
	if w.employer < 0 or w.lost or w.vehicle_id >= 0:
		return
	var c: Company = sim.company(w.employer)
	if not c.is_active():
		return
	var site := int(c.depots[0])
	var layout := yard_layout(site)
	var cell: Vector2i = layout.cells[posmod(int(w.id.trim_prefix("W")), layout.cells.size())]
	var busy: Array = sim.company_vehicles(c.id).filter(func(v): return v.state in ["loading", "unloading", "dispatching"] and sim.at_depot(v))
	w.duty_carrying = false
	w.duty_label = "Bereitschaft am Hof"
	if w.fatigue >= 85.0 or sim.game_min < w.rest_until:
		cell = layout.office
		w.duty_label = "Pause / Erholung"
	elif int(w.skills.verladen) >= 1 and not busy.is_empty():
		var v: FleetVehicle = busy[posmod(int(w.id.trim_prefix("W")), busy.size())]
		w.duty_label = "Frachtpapiere pruefen" if v.state == "dispatching" else "Ware fuer #%d kommissionieren" % v.id
		if w.arrived():
			w.duty_leg = 1 - w.duty_leg
		cell = layout.dock if w.duty_leg == 1 else layout.storage
		w.duty_carrying = v.state in ["loading", "unloading"] and (w.duty_leg == 1 if v.state == "loading" else w.duty_leg == 0)
	elif int(w.skills.reparieren) >= 2:
		cell = layout.service
		w.duty_label = "Wartungsmaterial kontrollieren"
	elif int(w.skills.bewachen) >= 2:
		cell = layout.gate
		w.duty_label = "Zufahrt kontrollieren"
	if w.arrived() and w.tile() != cell:
		var path := _yard_path(w.tile(), cell, site)
		if not path.is_empty():
			w.set_path(path)


func loading_factor(cid: int, site: int) -> float:
	if site not in sim.company(cid).depots:
		return 1.0
	var count := 0
	for w in sim.personnel.employed(cid):
		var wt: WorkerTask = sim.personnel.tasks.get(w.task_id)
		var free: bool = w.task_id == "" or wt == null or wt.is_final() or wt.is_filler()   # Füllaufgaben der Leerlauf-Routine zählen als frei
		if w.vehicle_id < 0 and free and w.fatigue < 85.0 and int(w.skills.verladen) > 0 and sim.estate.on_plot(cid, w.pos) >= 0:
			count += 1
	return maxf(0.55, 1.0 - count * 0.12)


func request_help(cid: int, kid: String, max_fee: float) -> Dictionary:
	var k: Contract = sim.contracts.get(kid)
	if k == null or k.owner != cid or k.status not in ["accepted", "assigned"] or sim.logistics.available(k, Logistics.PICKUP) <= 0:
		return {"ok": false, "msg": "Nur eigene unverplante Fracht kann ausgeschrieben werden."}
	if not is_finite(max_fee) or max_fee <= 0.0 or max_fee > sim.company(cid).ledger.cash:
		return {"ok": false, "msg": "Preislimit muss positiv und durch Bargeld gedeckt sein."}
	if requests.values().any(func(r): return r.contract == kid and r.status == "offen" and sim.game_min < float(r.expires)):
		return {"ok": false, "msg": "Fuer diese Fracht gibt es bereits eine offene Anfrage."}
	var id := "H%d" % _next_request
	_next_request += 1
	requests[id] = {"id": id, "owner": cid, "generation": sim.company(cid).generation, "contract": kid, "max_fee": max_fee,
		"status": "offen", "expires": minf(k.deadline, sim.game_min + 1440.0), "offers": []}
	for other in sim.companies:
		if other.id != cid and other.is_active():
			sim.social.send_message(cid, other.id, "Frachtanfrage %s: %s, %d x %s. Wer uebernimmt bis %s? Preisvorschlaege bis %s." % [id, kid, k.qty, k.cargo_name(), Catalog.game_minutes_to_text(k.deadline), Catalog.money(max_fee)], true)
			sim.agent_event.emit(other.id, "Neue Frachtanfrage %s mit verbindlichem Preislimit" % id)
	return {"ok": true, "msg": "Anfrage %s veroeffentlicht. Noch kein Auftrag und keine Zahlung; Preisangebot muss bestaetigt werden." % id, "id": id}


func quote_help(cid: int, rid: String, fee: float) -> Dictionary:
	var r: Dictionary = requests.get(rid, {})
	if r.is_empty() or r.status != "offen" or int(r.owner) == cid or sim.game_min > float(r.expires) or int(r.generation) != sim.company(int(r.owner)).generation:
		return {"ok": false, "msg": "Keine offene fremde Frachtanfrage."}
	if not is_finite(fee) or fee <= 0.0 or fee > float(r.max_fee):
		return {"ok": false, "msg": "Preis liegt ausserhalb des angefragten Rahmens."}
	for oid in r.offers:
		var o: Dictionary = sim.social.offers.get(oid, {})
		if o.get("status", "") == "open":
			return {"ok": false, "msg": "Ein Preisangebot wird bereits verhandelt; erst dessen Entscheidung abwarten."}
	var k: Contract = sim.contracts.get(str(r.contract))
	if k == null or k.owner != int(r.owner):
		return {"ok": false, "msg": "Frachtauftrag nicht mehr verfuegbar."}
	var qty: int = sim.logistics.available(k, Logistics.PICKUP)
	var result: Dictionary = sim.social.create_offer(int(r.owner), cid, "split_contract", {"contract_id": k.id, "menge": qty, "price": fee, "note": "Preisangebot auf " + rid})
	if result.ok:
		var o: Dictionary = sim.social.offers[result.id]
		o["awaiting"] = int(r.owner)   # Auftraggeber muss das Gegenangebot bestaetigen.
		o["quote_by"] = cid
		o["request_id"] = rid
		o["helper_generation"] = sim.company(cid).generation
		r.offers.append(result.id)
		sim.social.send_message(cid, int(r.owner), "Ich biete die Uebernahme von %s fuer %s an. Bitte bestaetige Angebot %s." % [k.id, Catalog.money(fee), result.id], true)
		sim.agent_event.emit(int(r.owner), "Preisangebot %s fuer Frachtanfrage %s" % [result.id, rid])
	return result


func summary(cid: int) -> Dictionary:
	var own: Array = lines.values().filter(func(l): return int(l.owner) == cid and int(l.generation) == sim.company(cid).generation).map(func(l): return l.duplicate())
	for l in own:
		l["pending"] = jobs.values().filter(func(j): return j.line == l.id and not j.counted).size()
	var inquiries: Array = []
	for r in requests.values():
		if r.status != "offen" or sim.game_min >= float(r.expires) or int(r.generation) != sim.company(int(r.owner)).generation:
			continue
		var k: Contract = sim.contracts.get(str(r.contract))
		if k == null or not sim.company(int(r.owner)).is_active():
			continue
		inquiries.append({"id": r.id, "owner": r.owner, "contract_id": k.id, "cargo": k.cargo, "qty": k.qty, "needs_cold": k.needs_cold, "needs_heavy": k.needs_heavy, "max_fee": r.max_fee, "pickup": k.pickup, "dropoff": k.dropoff, "own": int(r.owner) == cid, "quote_pending": r.offers.any(func(oid): return sim.social.offers.get(oid, {}).get("status", "") == "open")})
	return {"routine": policies.get(cid, {"auto_driver": true, "return_home": true, "yard_checks": true}), "linien": own, "hilfeanfragen": inquiries, "funk": dialogue.filter(func(d): return int(d.company) == cid).slice(-6)}


func to_dict() -> Dictionary:
	return {"policies": policies, "lines": lines, "jobs": jobs, "requests": requests, "dialogue": dialogue, "next_line": _next_line, "next_request": _next_request}


func from_dict(d: Dictionary) -> void:
	policies.clear()
	for cid in d.get("policies", {}):
		policies[int(cid)] = d.policies[cid]
	lines = d.get("lines", {})
	jobs = d.get("jobs", {})
	requests = d.get("requests", {})
	dialogue = d.get("dialogue", [])
	_next_line = int(d.get("next_line", 1))
	_next_request = int(d.get("next_request", 1))
	for l in lines.values():
		for key in ["owner", "generation", "pickup", "dropoff", "depot", "delivered"]:
			l[key] = int(l[key])
		l.vehicles = l.vehicles.map(func(id): return int(id))


func offer_accepted(offer: Dictionary) -> void:
	var rid := str(offer.get("request_id", ""))
	if rid == "" or not requests.has(rid):
		return
	requests[rid].status = "beauftragt"
	say(int(offer.from), "Disposition", "%s bestaetigt: %s uebernimmt %s fuer %s bei Lieferung." % [offer.id, sim.company(int(offer.to)).company_name, offer.contract_id, Catalog.money(offer.price)], str(offer.contract_id))
