class_name VehicleFuel
extends RefCounted
## Physischer Tankablauf. Auftraege und Ladung bleiben waehrend des Tankstopps erhalten.
## Kraftstoff wird erst nach Anfahrt, Zapfsaeulen-Wartezeit und Tankdauer nutzbar.

const STATES := ["to_fuel", "waiting_fuel", "refueling", "fuel_rescue", "out_of_fuel"]
const CAPACITY := {"cargobike": 0.0, "van": 120.0, "transporter": 180.0, "reefer": 240.0, "truck": 400.0, "semi": 600.0}
const RESCUE_FEE := 150.0
const RESCUE_MIN := 60.0


static func payer(v: FleetVehicle) -> int:
	return v.operator if v.operator >= 0 else v.owner


static func liters_per_tile(sim: Simulation, v: FleetVehicle) -> float:
	if v.tank_capacity() == 0.0:
		return 0.0
	return float(v.spec().cost_per_tile) * (1.0 + 0.15 * sim.logistics.load_total(v) / float(v.spec().capacity)) * sim.wx.fuel_factor() / ResourceMarket.FUEL_BASE_PRICE


static func begin(sim: Simulation, cid: int, vid: int, station: String, liters: float = 0.0) -> Dictionary:
	var v: FleetVehicle = sim.vehicles.get(vid)
	if v == null or payer(v) != cid:
		return {"ok": false, "msg": "Kein eigenes oder gemietetes Fahrzeug."}
	if v.tank_capacity() <= 0.0:
		return {"ok": false, "msg": "Ein Lastenrad braucht keinen Kraftstoff."}
	if v.state not in ["idle", "returning", "to_pickup", "to_dropoff", "out_of_fuel"] or not v.refueling.is_empty() or v.held_by != "":
		return {"ok": false, "msg": "Fahrzeug kann gerade keinen Tankstopp beginnen."}
	if sim.driver_of(v) == null:
		return {"ok": false, "msg": "Fuer die Anfahrt wird ein Fahrer benoetigt."}
	var c := sim.company(cid)
	var cell := Vector2i(-1, -1)
	if station == "depot":
		if c.fuel <= 0.0:
			return {"ok": false, "msg": "Betriebstank ist leer; Treibstofflieferung bestellen oder Tankstelle waehlen."}
		cell = sim.nearest_depot_road(cid, v.tile())
	else:
		var s: Dictionary = sim.resources.supplies.get(station, {})
		if s.is_empty() or s.kind != "fuel" or float(s.stock) <= 0.0:
			return {"ok": false, "msg": "Tankstelle unbekannt oder leer."}
		cell = sim.city.building(s.building).road
	var path := sim.nav.road_path(v.tile(), cell)
	if path.is_empty():
		return {"ok": false, "msg": "Tankstelle ist derzeit nicht erreichbar."}
	var needed := (path.size() + 1) * liters_per_tile(sim, v)
	if v.tile() != cell and needed > v.fuel_l:
		return {"ok": false, "msg": "Kraftstoff reicht nicht fuer die Anfahrt; request_fuel_rescue anfordern."}
	if not is_finite(liters) or liters < 0.0:
		return {"ok": false, "msg": "Ungueltige Tankmenge."}
	var free := v.tank_capacity() - v.fuel_l
	if free < 0.01:
		return {"ok": false, "msg": "Fahrzeugtank ist bereits voll."}
	v.timer = 0.0
	v.refueling = {"payer": cid, "station": station, "liters": minf(liters, free) if liters > 0.0 else v.tank_capacity(),
		"resume_state": v.state if v.state != "out_of_fuel" else "idle", "goal": [v.goal.x, v.goal.y], "filled": 0.0}
	sim.route(v, cell, "to_fuel")
	sim.decisions.note(cid, "auto", "%s faehrt zum Tanken (%s, Tankreserve pruefen)" % [v.display_name(), station], {"vehicle_id": vid})
	return {"ok": true, "msg": "%s faehrt zu %s; Tankfuellung erst nach Anfahrt und Tanken verfuegbar." % [v.display_name(), station]}


## Automatischer Sicherheitstankstopp bei 25 %; Preisvergleich bleibt eine KI-Entscheidung.
static func auto_plan(sim: Simulation, v: FleetVehicle) -> void:
	if v.tank_capacity() <= 0.0 or v.fuel_l > v.tank_capacity() * 0.25 or sim.game_min < v.fuel_retry_at:
		return
	if v.state not in ["idle", "returning", "to_pickup", "to_dropoff"] or not v.refueling.is_empty():
		return
	v.fuel_retry_at = sim.game_min + 30.0
	var cid := payer(v)
	if sim.at_depot(v) and sim.company(cid).fuel > 0.0 and begin(sim, cid, v.id, "depot").ok:
		return
	var opts := FuelPlanner.compare(sim, cid, minf(30.0, v.tank_capacity() - v.fuel_l), v.tile())
	for o in opts:
		if begin(sim, cid, v.id, o.id).ok:
			return
	# Ein erreichbarer Betriebshof kann auch bei leeren oeffentlichen Stationen versorgen.
	if sim.company(cid).fuel > 0.0:
		begin(sim, cid, v.id, "depot")


static func arrived(sim: Simulation, v: FleetVehicle) -> void:
	v.state = "waiting_fuel"
	v.refueling["queued_at"] = sim.game_min
	v.path.clear()   # steht am Stationszugang, blockiert keinen durchgehenden Fahrstreifen
	update(sim, v, 0.0)


static func update(sim: Simulation, v: FleetVehicle, dt: float) -> void:
	if v.state == "out_of_fuel":
		return
	if v.state in ["refueling", "fuel_rescue"]:
		v.timer -= dt * Catalog.GAME_MIN_PER_SIM_SEC
		if v.timer <= 0.0:
			v.fuel_l = minf(v.tank_capacity(), v.fuel_l + float(v.refueling.get("filled", 0.0)))
			v.fuel_payer = int(v.refueling.get("payer", payer(v)))
			resume(sim, v, "Tankvorgang abgeschlossen")
		return
	if v.state != "waiting_fuel":
		return
	var cid := payer(v)
	var c := sim.company(cid)
	var station := str(v.refueling.get("station", ""))
	var liters := minf(float(v.refueling.get("liters", 0.0)), v.tank_capacity() - v.fuel_l)
	# Beim Wechsel des Mieters vorhandenen, vom bisherigen Betreiber bezahlten Diesel abloesen.
	var remaining_cost := v.fuel_l * ResourceMarket.FUEL_BASE_PRICE if v.fuel_payer >= 0 and v.fuel_payer != cid else 0.0
	if station == "depot":
		liters = minf(liters, c.fuel)
		if liters <= 0.0:
			resume(sim, v, "Betriebstank ist inzwischen leer")
			return
		if c.ledger.cash < remaining_cost:
			resume(sim, v, "Bargeld reicht nicht fuer die Uebernahme des Restkraftstoffs")
			return
		c.fuel -= liters
	else:
		var s: Dictionary = sim.resources.supplies.get(station, {})
		if s.is_empty() or float(s.stock) <= 0.0:
			resume(sim, v, "Tankstelle ist inzwischen leer")
			return
		# Aeltere Ankuenfte haben Vorrang, bei gleichem Zeitpunkt die kleinere Fahrzeug-ID.
		for other in sim.vehicles.values():
			if other == v or other.state != "waiting_fuel" or other.refueling.get("station", "") != station:
				continue
			var their_time := float(other.refueling.get("queued_at", sim.game_min))
			var our_time := float(v.refueling.get("queued_at", sim.game_min))
			if their_time < our_time or (their_time == our_time and other.id < v.id):
				return
		if sim.resources.pumps_busy(s) >= int(s.pumps):
			return   # Geld und Bestand bleiben beim Warten unberuehrt
		liters = minf(liters, float(s.stock))
		var cost: float = snappedf(liters * sim.resources.fuel_price(s), 0.01)
		if c.ledger.cash < cost + remaining_cost:
			resume(sim, v, "Bargeld reicht nicht fuer die Tankfuellung")
			return
		s.wait_min = float(s.wait_min) + maxf(0.0, sim.game_min - float(v.refueling.get("queued_at", sim.game_min)))
		sim.resources._use_pump(s, liters)
		s.stock = float(s.stock) - liters
		s.sales_l = float(s.sales_l) + liters
		s.revenue = float(s.revenue) + cost
		s.customers = int(s.customers) + 1
		c.ledger.book("supplies", -cost, true, "Tankfuellung " + v.display_name(), sim.game_min, "G0")
	if remaining_cost > 0.0:
		c.ledger.book("fuel", -remaining_cost, true, "Restkraftstoff uebernommen", sim.game_min, "G0")
		sim.company(v.fuel_payer).ledger.book("trade_income", remaining_cost, true, "Restkraftstoff an Mieter", sim.game_min, "G0")
	v.refueling.filled = liters
	v.state = "refueling"
	v.timer = liters / ResourceMarket.PUMP_LITERS_PER_MIN


static func resume(sim: Simulation, v: FleetVehicle, message: String) -> void:
	var data := v.refueling
	v.refueling = {}
	v.state = "idle"
	v.idle_since = sim.game_min
	v.fuel_retry_at = sim.game_min + 30.0
	sim.notify(payer(v), "%s: %s (%d/%d l)." % [v.display_name(), message, int(v.fuel_l), int(v.tank_capacity())])
	var state := str(data.get("resume_state", "idle"))
	if state in ["to_pickup", "to_dropoff", "returning"]:
		var goal: Array = data.get("goal", [-1, -1])
		if not sim.route(v, Vector2i(int(goal[0]), int(goal[1])), state):
			v.state = "idle"


static func rescue(sim: Simulation, cid: int, vid: int) -> Dictionary:
	var v: FleetVehicle = sim.vehicles.get(vid)
	if v == null or payer(v) != cid or v.tank_capacity() <= 0.0:
		return {"ok": false, "msg": "Kein eigenes oder gemietetes Motorfahrzeug."}
	if v.state != "out_of_fuel" or not v.refueling.is_empty():
		return {"ok": false, "msg": "Pannendienst nur fuer liegengebliebene Fahrzeuge ohne laufenden Tankauftrag."}
	var liters := minf(30.0, v.tank_capacity())
	var stations := FuelPlanner.compare(sim, cid, liters, v.tile())
	if stations.is_empty():
		return {"ok": false, "msg": "Kein Pannendienst verfuegt ueber genug Kraftstoff."}
	var s: Dictionary = sim.resources.supplies[stations[0].id]
	var cost: float = snappedf(RESCUE_FEE + liters * sim.resources.emergency_fuel_price(), 0.01)
	var c := sim.company(cid)
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Nicht genug Bargeld fuer den Pannendienst (%s)." % Catalog.money(cost)}
	s.stock = float(s.stock) - liters
	s.sales_l = float(s.sales_l) + liters
	s.revenue = float(s.revenue) + cost
	c.ledger.book("fuel", -cost, true, "Kraftstoff-Pannendienst " + v.display_name(), sim.game_min, "G0")
	v.refueling = {"payer": cid, "station": s.id, "filled": liters, "resume_state": "idle", "goal": [-1, -1]}
	v.state = "fuel_rescue"
	v.timer = RESCUE_MIN
	return {"ok": true, "msg": "Pannendienst unterwegs: %d l in %d Spielminuten, Kosten %s." % [int(liters), int(RESCUE_MIN), Catalog.money(cost)]}
