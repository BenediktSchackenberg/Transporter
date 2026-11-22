class_name CityFleet
extends RefCounted
## Sichtbare Stadtfahrzeuge ohne eigene Wirtschaftswirkung (Darstellung):
## - Bautrupps der Strassenmeisterei fahren vom Rathaus zur Baustelle, arbeiten dort bis zum Ende und fahren zurueck
##   (Instandsetzungen aus RoadCare und die zufaelligen Strassenbaustellen der Simulation).
## - Umzugswagen bringen neu zugezogene Haushalte vom Stadtrand zu ihrer Wohnung, laden ab und fahren wieder hinaus.
## Die Wirkung (Sperrung, Zustand, Zuzug) bleibt in den Fachsystemen; hier wird nur gefahren. Nicht gespeichert.

const MAX_CREWS := 6
const MAX_MOVING := 6
const TOURIST_SEATS := 8
const MAX_TOURIST_BUSES := 32
const EMPTY_MIN := 1.0            # Spielminuten je Halt (Tonnen leeren; ein Spieltag hat 120 Spielminuten)
const DUMP_MIN := 4.0             # Waage und Abladen auf der Deponie
const UNLOAD_DAYS := 0.1          # Umzugswagen steht so lange vor dem Haus
const SPEED := 3.0

var sim
var vehicles: Array = []          # {id, kind (bautrupp|umzug), mover, phase (anfahrt|arbeit|abladen|rueckfahrt), site, until, back, label}
var stats := {"bautrupps": 0, "umzuege": 0, "muelltouren": 0, "halte": 0}
var _next := 1
var _edges: Array = []


func setup(simulation) -> void:
	sim = simulation
	var C = sim.city
	var best := 99
	for y in C.size:
		for x in C.size:
			var p := Vector2i(x, y)
			if not C.is_road(p):
				continue
			var d: int = mini(mini(x, y), mini(C.size - 1 - x, C.size - 1 - y))
			if d < best:
				best = d
				_edges.clear()
			if d == best:
				_edges.append(p)


## Strassenzelle am Rathaus (Sitz der Strassenmeisterei).
func depot_road() -> Vector2i:
	for b in sim.city.buildings:
		if b.role == "town_hall":
			return b.road
	return sim.city.intersections[0]


func _free_neighbor(site: Vector2i) -> Vector2i:
	if not sim.nav.is_blocked_road(site):
		return site
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = site + d
		if sim.city.is_road(q) and not sim.nav.is_blocked_road(q):
			return q
	return site


## Bautrupps stellen das Fahrzeug neben der Fahrbahn ab. Ein Wagen, der auf dem
## einzigen offenen Nachbarfeld stehen bleibt, zwang den Verkehr bisher zum
## Ueberholen auf derselben Spur und verursachte die Leitungsbau-Unfaelle.
func _work_shoulder(road: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = road + d
		if sim.city.walkable(q) and not sim.city.is_road(q) and sim.city.g(q) != CityData.G.WATER and sim.city.building_at[sim.city.idx(q)] < 0:
			return q
	return Vector2i(-1, -1)


func _spawn(kind: String, start: Vector2i, site: Vector2i, until: float, back: Vector2i, label: String, strict := false) -> Dictionary:
	var m := Mover.new()
	m.speed = 1.3 if kind == "stadtlkw" else (1.1 if kind == "zulieferer" else SPEED)
	m.pos = sim.city.tile_center(start)
	var target := _free_neighbor(site)
	if not sim.route(m, target):
		if strict:   # Wildnis (18.11.): ohne Strasse kein Lieferfahrzeug – nicht ans Ziel setzen
			return {}
		m.pos = sim.city.tile_center(target)   # kein Weg: Fahrzeug steht gleich am Ziel
	var v := {"id": _next, "kind": kind, "mover": m, "phase": "anfahrt", "site": site, "until": until, "back": back, "label": label}
	_next += 1
	vehicles.append(v)
	return v


## Reisebusse sind echte Fahrzeuge im Strassennetz. Die Gruppe belegt alle Plaetze bis zur Ankunft.
func can_send_tourist(persons: int) -> bool:
	return persons > 0 and persons <= TOURIST_SEATS and vehicles.filter(func(v): return v.kind == "tourist").size() < MAX_TOURIST_BUSES


func send_tourist(id: String, route: Array, persons: int, arrival_min: float) -> bool:
	if not can_send_tourist(persons) or route.is_empty():
		return false
	var cells: Array[Vector2i] = []
	for a in route:
		cells.append(Vector2i(int(a[0]), int(a[1])))
	var start: Vector2i = cells[0]
	var destination: Vector2i = cells[-1]
	if not sim.city.is_road(start) or not sim.city.is_road(destination):
		return false
	var m := Mover.new()
	m.pos = sim.city.tile_center(start)
	m.set_path(cells)
	m.speed = clampf(float(cells.size()) / maxf(1.0, (arrival_min - sim.game_min) / Catalog.GAME_MIN_PER_SIM_SEC), 0.02, 2.2)
	vehicles.append({"id": _next, "kind": "tourist", "mover": m, "phase": "anfahrt", "site": destination, "until": arrival_min,
		"back": start, "label": "Reisebus · %d Gäste" % persons, "trip": id, "persons": persons})
	_next += 1
	return true


func tourist_vehicle(id: String) -> Dictionary:
	for v in vehicles:
		if v.kind == "tourist" and str(v.trip) == id:
			return v
	return {}


func cancel_tourist(id: String) -> void:
	for v in vehicles.duplicate():
		if v.kind == "tourist" and str(v.trip) == id:
			vehicles.erase(v)


## Neues Ziel fuer ein Fahrzeug (Bautrupps).
func reroute(v: Dictionary, to: Vector2i) -> void:
	var target := _free_neighbor(to)
	if not sim.route(v.mover, target):
		v.mover.pos = sim.city.tile_center(target)


## Bautrupp zu einer Strassenbaustelle schicken (einer je Stelle).
func send_crew(site: Vector2i, until: float, label: String) -> void:
	if vehicles.any(func(v): return v.kind == "bautrupp" and v.site == site and v.phase != "rueckfahrt"):
		return
	if vehicles.filter(func(v): return v.kind == "bautrupp").size() >= MAX_CREWS:
		return
	var home := depot_road()
	var park_road := _free_neighbor(site)
	var garage := _work_shoulder(home)
	var m := Mover.new()
	m.speed = SPEED
	m.pos = sim.city.tile_center(garage if garage.x >= 0 else home)
	vehicles.append({"id": _next, "kind": "bautrupp", "mover": m, "phase": "bereit", "site": site,
		"until": until, "back": home, "label": label, "park_road": park_road,
		"shoulder": _work_shoulder(park_road)})
	_next += 1
	stats.bautrupps += 1


func _crew_departure_clear(home: Vector2i) -> bool:
	var center: Vector2 = sim.city.tile_center(home)
	for t in [home, home + Vector2i.UP, home + Vector2i.RIGHT, home + Vector2i.DOWN, home + Vector2i.LEFT]:
		for other in sim._hash.get(t, []):
			if (other as Mover).pos.distance_to(center) < 30.0:
				return false
	return true


## Kommunaler Lkw (Auftrag 19): bringt Ware eines Stadtlager-Auftrags vom Lieferort zum Stadtlager; meldet die Ankunft dem Stadtlager.
## Partie 18.11.: 41 Bestellungen auf einmal haetten 41 Lkw auf eine Strasse geschickt. Gleicher Abholort: Ladung zusteigen
## (hoechstens TRUCK_ORDERS je Lkw), hoechstens CITY_TRUCKS je Stadt unterwegs; sonst false (Bestellung wartet und versucht es taeglich).
const TRUCK_ORDERS := 8
const CITY_TRUCKS := 4


func send_city_truck(from: Vector2i, to: Vector2i, town: int, order_id: String, label: String) -> bool:
	var mine: Array = vehicles.filter(func(x): return x.kind == "stadtlkw" and int(x.get("town", -1)) == town)
	for x in mine:
		if str(x.phase) == "anfahrt" and x.back == from and (x.get("orders", []) as Array).size() < TRUCK_ORDERS and int(x.mover.path_i) <= 2:   # noch am Abholort
			x.orders.append(order_id)
			return true
	if mine.size() >= CITY_TRUCKS:
		return false
	var v := _spawn("stadtlkw", from, to, 0.0, from, label, sim.wildnis)
	if v.is_empty():
		return false
	v["town"] = town
	v["order"] = order_id
	v["orders"] = [order_id]
	return true


## Liefer-Lkw von ausserhalb: vom Kartenrand (Landstrasse) zum Grosslager, meldet dort die Ankunft (CentralHub.supplier_arrived).
func send_supplier(to: Vector2i, deal_id: String, label: String) -> bool:
	if _edges.is_empty():
		return false
	var edge: Vector2i = _edges[(_next * 5) % _edges.size()]
	var v := _spawn("zulieferer", edge, to, 0.0, edge, label, true)
	if v.is_empty():
		return false
	v["deal"] = deal_id
	return true


## Tageloehner (Wildnis, 18.11.): Transporter vom Grosslager querfeldein zur Baustelle; bleibt dort, bis die Baustelle fertig ist.
func send_helpers(from: Vector2i, to: Vector2i, site_id: String, label: String) -> bool:
	var p: Array[Vector2i] = sim.offroad_path(from, to)
	if p.is_empty():
		return false
	var m := Mover.new()
	m.speed = SPEED * 0.6
	m.lane = 0.0
	m.pos = sim.city.tile_center(from)
	m.set_path(p)
	vehicles.append({"id": _next, "kind": "helfer", "mover": m, "phase": "anfahrt", "site": to, "until": INF, "back": from, "label": label, "baustelle": site_id})
	_next += 1
	return true


func helpers_leave(site_id: String) -> void:
	for v in vehicles:
		if str(v.kind) == "helfer" and str(v.get("baustelle", "")) == site_id:
			v.phase = "rueckfahrt"
			var p: Array[Vector2i] = sim.offroad_path((v.mover as Mover).tile(), v.back)
			if p.is_empty():
				vehicles.erase(v)
			else:
				(v.mover as Mover).set_path(p)
			return


## Umzugswagen fuer einen zugezogenen Haushalt: vom Stadtrand zur Wohnung (Gebaeude-ID), dann wieder hinaus.
func send_moving(building_id: int, label: String) -> void:
	if _edges.is_empty() or vehicles.filter(func(v): return v.kind == "umzug").size() >= MAX_MOVING:
		return
	var b: Dictionary = sim.city.building(building_id)
	if b.is_empty():
		return
	var edge: Vector2i = _edges[(_next * 7) % _edges.size()]
	_spawn("umzug", edge, b.road, 0.0, edge, label)
	stats.umzuege += 1


func update(dt: float) -> void:
	var now: float = sim.game_min
	for v in vehicles.duplicate():
		var m: Mover = v.mover
		if v.kind == "bautrupp" and str(v.phase) == "bereit":
			if now >= float(v.until):
				vehicles.erase(v)
			elif _crew_departure_clear(Vector2i(v.back)):
				m.pos = sim.city.tile_center(Vector2i(v.back))
				if sim.route(m, Vector2i(v.park_road)):
					v.phase = "anfahrt"
					sim._hash_add(m)
					sim._desc[m] = str(v.label)
				else:
					var garage := _work_shoulder(Vector2i(v.back))
					m.pos = sim.city.tile_center(garage if garage.x >= 0 else Vector2i(v.back))
			continue
		if m.wreck_until > sim.sim_time:
			continue   # Unfall: steht
		if not m.arrived():
			if sim.nav.barriers.has(m.next_tile()):
				continue   # Bahnuebergang geschlossen: warten
			if sim.nav.is_blocked_road(m.next_tile()) and m.next_tile() != m.goal:
				sim.route(m, m.goal)
			elif sim._is_blocked(m):
				pass   # Vordermann, Kreuzung: warten (18.11.: staedtische Fahrzeuge fuhren durch andere hindurch)
			else:
				var old_tile := m.tile()
				m.advance(dt, 1.0)
				sim._hash_relocate(m, old_tile, not m.arrived())
			continue
		if v.kind in ["kolonne", "dienstwagen"]:
			continue   # Bautrupps (BuildCrews) und Dienstwagen der Buergermeister (CivicWorks) steuern Ziel und Zustand selbst
		if v.kind == "tourist":
			if now >= float(v.until):
				sim.tourism.transfer_arrived(str(v.trip))
				vehicles.erase(v)
			continue
		if v.kind in ["muell", "wertstoff"]:
			_garbage(v, now)
			continue
		if v.kind == "bahntrupp":   # Auftrag 22 Phase 6 Schritt 4: Stoerung an der Bahnstrecke beheben (Arbeit erst ab Ankunft)
			if str(v.phase) == "anfahrt":
				v.phase = "arbeit"
				v.until = now + RailTraffic.repair_min(str(v.get("art", "")))
			elif str(v.phase) == "arbeit" and now >= float(v.until):
				sim.trains.repaired(int(v.block))
				v.phase = "rueckfahrt"
				if not sim.route(m, v.back):
					vehicles.erase(v)
			elif str(v.phase) == "rueckfahrt":
				vehicles.erase(v)
			continue
		if v.kind == "wassertrupp":   # Auftrag 22 Phase 4 Schritt 3: Rohrbruch erst ab Ankunft vor Ort reparieren
			if str(v.phase) == "anfahrt":
				v.phase = "arbeit"
				v.until = now + WaterSupply.REPAIR_MIN
			elif str(v.phase) == "arbeit" and now >= float(v.until):
				sim.water.repaired(int(v.town))
				v.phase = "rueckfahrt"
				if not sim.route(m, v.back):
					vehicles.erase(v)
			elif str(v.phase) == "rueckfahrt":
				vehicles.erase(v)
			continue
		if v.kind == "netztrupp":   # Auftrag 22 Phase 3: Reparatur der Hochspannungstrasse erst ab Ankunft vor Ort
			if str(v.phase) == "anfahrt":
				v.phase = "arbeit"
				v.until = now + PowerNet.REPAIR_MIN * (0.5 if bool(v.get("urgent", false)) else 1.0)
			elif str(v.phase) == "arbeit" and now >= float(v.until):
				sim.grid.net.repaired(str(v.edge))
				v.phase = "rueckfahrt"
				if not sim.route(m, v.back):
					vehicles.erase(v)
			elif str(v.phase) == "rueckfahrt":
				vehicles.erase(v)
			continue
		if v.kind == "helfer":
			if str(v.phase) == "anfahrt":
				sim.eko.homes.helpers_arrived(str(v.baustelle))
				v.phase = "arbeit"
			elif str(v.phase) == "rueckfahrt":
				vehicles.erase(v)
			continue
		if v.kind == "zulieferer" and str(v.phase) == "anfahrt":
			sim.hub.supplier_arrived(str(v.deal))
			v.phase = "rueckfahrt"
			if not sim.route(m, v.back):
				vehicles.erase(v)
			continue
		if v.kind == "stadtlkw" and str(v.phase) == "anfahrt":
			var D = sim.towns.depot(int(v.town)) if sim.towns != null else sim.city_depot
			for oid in v.get("orders", [v.order]):
				D.city_truck_arrived(str(oid))
			v.phase = "rueckfahrt"
			if not sim.route(m, v.back):
				vehicles.erase(v)
			continue
		match str(v.phase):
			"anfahrt":
				if v.kind == "umzug":
					v.phase = "abladen"
					v.until = now + GameCalendar.days_to_min(UNLOAD_DAYS)
				elif v.kind == "bautrupp" and Vector2i(v.get("shoulder", Vector2i(-1, -1))).x >= 0:
					v.phase = "einparken"
					m.lane = 0.0
					m.set_path([m.tile(), Vector2i(v.shoulder)] as Array[Vector2i])
				else:
					v.phase = "arbeit"
			"einparken":
				v.phase = "arbeit"
			"arbeit", "abladen":
				if now >= float(v.until):
					if v.kind == "bautrupp" and Vector2i(v.get("shoulder", Vector2i(-1, -1))).x >= 0:
						v.phase = "ausparken"
						m.set_path([m.tile(), Vector2i(v.park_road)] as Array[Vector2i])
					else:
						v.phase = "rueckfahrt"
						if not sim.route(m, v.back):
							vehicles.erase(v)
			"ausparken":
				v.phase = "rueckfahrt"
				m.lane = 7.0
				if not sim.route(m, v.back):
					vehicles.erase(v)
			"rueckfahrt":
				vehicles.erase(v)


## Muellwagen der Stadt k: vom Betriebshof (sonst Rathaus) ueber die Halte der Tour zur gemeinsamen Deponie und zurueck. Zwei Muellwerker leeren an jedem
## Halt die Tonne (Waste.empty_bin); ist der Wagen voll, faehrt er gleich zur Deponie. Dort wiegt die Waage die Ladung (Waste.weigh_in).
## stream: "rest" = Restmuell (Deponie, Waste.weigh_in) oder "wert" = Wertstoffe (Recyclinghof, Waste.deliver_wert; Bio+Wertstoffe werden am Halt zusammen geleert).
func send_garbage(stops: Array, landfill: Vector2i, tons: float, label: String, town: int = 0, home := Vector2i(-1, -1), stream: String = "rest") -> bool:
	if stops.is_empty():
		return false
	var kind := "muell" if stream == "rest" else "wertstoff"
	if vehicles.filter(func(v): return v.kind == kind and int(v.town) == town).size() >= (sim.waste.trucks_for(town) if stream == "rest" else 1):
		return false
	if home.x < 0:   # ohne Betriebshof: Start am Rathaus
		var th := int(sim.towns.get_t(town).get("town_hall", -1)) if sim.towns != null else -1
		home = sim.city.building(th).road if th >= 0 else depot_road()
	var v := _spawn(kind, home, stops[0].road, 0.0, home, label)
	v["stops"] = stops
	v["stop"] = 0
	v["landfill"] = landfill
	v["tons"] = tons
	v["load"] = 0.0
	v["town"] = town
	v["stream"] = stream
	v["phase"] = "tour"
	stats.muelltouren += 1
	return true


func _garbage(v: Dictionary, now: float) -> void:
	var m: Mover = v.mover
	match str(v.phase):
		"tour":
			v.phase = "leeren"
			v.until = now + EMPTY_MIN
		"leeren":
			if now < float(v.until):
				return
			var kg: float
			if str(v.stream) == "wert":
				kg = sim.waste.empty_wert(int(v.stops[int(v.stop)].building), (float(v.tons) - float(v.load)) * 1000.0)
			else:
				kg = sim.waste.empty_bin(int(v.stops[int(v.stop)].building), (float(v.tons) - float(v.load)) * 1000.0)
			v.load = float(v.load) + kg / 1000.0
			stats.halte += 1
			v.stop = int(v.stop) + 1
			var full := float(v.load) >= float(v.tons) * 0.98
			if int(v.stop) < v.stops.size() and not full:
				v.phase = "tour"
				if not sim.route(m, _free_neighbor(v.stops[int(v.stop)].road)):
					m.pos = sim.city.tile_center(v.stops[int(v.stop)].road)
			else:
				sim.waste.release(v.stops.slice(int(v.stop)).map(func(s): return int(s.building)))
				v.phase = "zur_deponie"
				if not sim.route(m, _free_neighbor(v.landfill)):
					m.pos = sim.city.tile_center(v.landfill)
		"zur_deponie":
			v.phase = "abladen"
			v.until = now + DUMP_MIN
		"abladen":
			if now >= float(v.until):
				if str(v.stream) == "wert":
					sim.waste.deliver_wert(int(v.town), float(v.load))
				else:
					sim.waste.weigh_in(int(v.town), float(v.load))
				v.load = 0.0
				v.phase = "rueckfahrt"
				if not sim.route(m, v.back):
					vehicles.erase(v)
		"rueckfahrt":
			vehicles.erase(v)


## Arbeitende Bautrupps (fuer die Baustellenanzeige).
func crews_at_work() -> Array:
	return vehicles.filter(func(v): return v.kind == "bautrupp" and v.phase == "arbeit")
