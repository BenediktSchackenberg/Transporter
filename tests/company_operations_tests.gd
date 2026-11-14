extends RefCounted
## Integrationstests: Auftrag -> Crew -> Hof -> echte Einlagerung -> Kunde -> Abrechnung.


static func fixture(t):
	var s = t.new_sim(2)
	s.traffic.clear()
	for c in s.companies:
		c.known.clear()
	return s


static func parcel(s, id: String, owner: int = -1):
	var k := Contract.new()
	k.id = id
	var road: Vector2i = s.depot_road(0)
	var places: Array = s.city.buildings.filter(func(b): return b.id not in s.companies[0].depots and b.road != road and b.type != "plot")
	places.sort_custom(func(a, b): return a.road.distance_squared_to(road) < b.road.distance_squared_to(road))
	k.pickup = int(places[0].id)
	k.dropoff = int(places[1].id)
	k.cargo = "pakete"
	k.qty = 3
	k.reward = 1200.0
	k.min_rep = 0.0
	k.owner = owner
	k.status = "accepted" if owner >= 0 else "open"
	k.deadline = s.game_min + 5000.0
	k.offer_until = k.deadline
	k.created = s.game_min
	k.distance = maxi(1, absi(places[0].road.x - places[1].road.x) + absi(places[0].road.y - places[1].road.y))
	s.contracts[id] = k
	s.companies[0].known[id] = true
	return k


static func run(t) -> void:
	var s = fixture(t)
	var v: FleetVehicle = s.company_vehicles(0)[0]
	var k: Contract = parcel(s, "OPS1")
	var other: Contract = parcel(s, "OPS2")
	var r: Dictionary = s.executor.execute(0, {"action": "create_transport_line", "name": "Paketverteilung", "cargo": "pakete", "vehicle_ids": [v.id], "pickup_id": k.pickup, "dropoff_id": k.dropoff, "via_depot": true})
	t.ok(r.ok, "Linie als KI-Aktion angelegt: " + r.msg)
	t.ok(not s.executor.execute(1, {"action": "pause_transport_line", "line_id": r.id}).ok, "fremde Linie nicht steuerbar")
	t.ok(not s.executor.execute(1, {"action": "create_transport_line", "name": "fremd", "cargo": "pakete", "vehicle_ids": [v.id]}).ok, "kein fremdes Fahrzeug in eigener Linie")
	var line_id: String = r.id
	var saw_check := false
	var saw_store := false
	var saw_carry := false
	var saw_parking := false
	var saw_dock := false
	var dock_save := false
	var restored := false
	var site := int(s.companies[0].depots[0])
	for i in 5000:
		s.step(0.2)
		v = s.vehicles[v.id]
		k = s.contracts["OPS1"]
		other = s.contracts["OPS2"]
		saw_check = saw_check or v.state == "dispatching"
		saw_parking = saw_parking or v.state == "yard_parking"
		saw_carry = saw_carry or s.personnel.employed(0).any(func(w): return w.duty_carrying)
		if v.state == "unloading" and not v.stops.is_empty() and Logistics.store_site(str(v.stops[0].ort)) == site:
			saw_dock = v.tile() == s.operations.yard_layout(site).dock and not s.city.is_road(v.tile())
		if not dock_save and v.state == "to_dropoff" and v.goal == s.operations.yard_layout(site).dock and not v.arrived():
			s = Simulation.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
			dock_save = true
		if s.logistics.stored(site, k.id) == k.qty:
			saw_store = true
			if not restored:
				t.ok(k.status != "delivered" and k.paid == 0.0, "Einlagerung ist noch keine bezahlte Kundenzustellung")
				var data: Dictionary = s.to_dict()
				s = Simulation.from_dict(JSON.parse_string(JSON.stringify(data)))
				restored = true
				t.ok(s.operations.line_of(v.id) == line_id and s.operations.jobs.has(k.id), "Linie und laufende Warenkette ueberstehen Laden")
		if other.status == "delivered":
			break
	t.ok(saw_check, "Tour benoetigt Hofkontrolle und Freigabe")
	t.ok(saw_store, "Ware erreicht physisch das Firmenlager")
	t.ok(saw_carry, "echte Mitarbeiter arbeiten an der Fracht")
	t.ok(saw_parking, "Fahrzeug faehrt auf den Hof statt am Strassenrand zu verschwinden")
	t.ok(saw_dock and dock_save, "Anfahrt durch die Hofeinfahrt endet an der echten Ladezone und uebersteht Laden")
	t.ok(k.status == "delivered" and other.status == "delivered", "Dauerauftrag liefert zwei Frachten ohne weitere KI-Anfrage")
	t.ok(s.logistics.storage_used(site) == 0 and v.load.is_empty(), "Fracht weder im Lager noch im Fahrzeug dupliziert")
	t.ok(int(s.operations.lines[line_id].delivered) == 2 and absf(float(s.operations.lines[line_id].revenue) - 2400.0) < 0.01, "Linie zaehlt nur tatsaechliche Zustellungen und Erloese")
	t.ok(t.identity_ok(s), "Geld-, Waren- und Firmenbilanz bleiben erhalten")
	t.ok("BETRIEBSFUNK" in LiveText.operations(s) and "OPS1" in LiveText.operations(s), "Zuschauer sehen zusammenhaengenden Ablauf und belegte Rueckmeldungen")
	var observation := ObservationBuilder.build(s, 0, [], 0.0, 60.0)
	t.ok(observation.betriebsablauf.linien.size() == 1 and observation.fahrzeuge[0].linie == line_id, "KI sieht Linienzuteilung und Betriebsstatus")
	var before := v.pos
	var driver: Worker = s.driver_of(v)
	driver.vehicle_id = -1
	v.state = "returning"
	s._drive(v, 1.0)
	t.ok(v.pos == before, "ohne Fahrer faehrt kein Firmen-Lkw los")
	s.executor.execute(0, {"action": "pause_transport_line", "line_id": line_id})
	s.operations.tick()
	t.ok(s.operations.line_of(v.id) == "", "pausierte abgearbeitete Linie gibt Fahrzeuge frei")
	s.operations.park(v)
	before = v.pos
	s._update_vehicle(v, 1.0)
	t.ok(v.pos == before, "auch beim Einparken bewegt sich ein Lkw nur mit Fahrer")


static func cooperation(t) -> void:
	var s = fixture(t)
	var k: Contract = parcel(s, "HELP1", 0)
	var a: Company = s.companies[0]
	var b: Company = s.companies[1]
	var cash_a := a.ledger.cash
	var cash_b := b.ledger.cash
	var req: Dictionary = s.executor.execute(0, {"action": "request_transport_help", "contract_id": k.id, "max_fee": 300})
	t.ok(req.ok and s.social.messages.size() == 1, "Frachtanfrage erzeugt wirtschaftlich begruendete Kommunikation")
	t.ok(not s.executor.execute(0, {"action": "quote_transport_help", "request_id": req.id, "fee": 200}).ok, "keine eigene Anfrage als fremdes Angebot ausgeben")
	t.ok(not s.executor.execute(1, {"action": "quote_transport_help", "request_id": req.id, "fee": 999}).ok, "Preisrahmen gilt")
	var quote: Dictionary = s.executor.execute(1, {"action": "quote_transport_help", "request_id": req.id, "fee": 200})
	t.ok(quote.ok, "Mitspieler bietet verbindlichen Transportpreis: " + quote.msg)
	t.ok(a.ledger.cash == cash_a and b.ledger.cash == cash_b and s.social.agreements.is_empty(), "Anfrage und Preisangebot bewegen weder Geld noch Frachtrechte")
	t.ok(not s.executor.execute(1, {"action": "accept_trade", "offer_id": quote.id}).ok, "Bieter kann eigenen Preis nicht im Namen des Auftraggebers annehmen")
	var counter: Dictionary = s.executor.execute(0, {"action": "counter_offer", "offer_id": quote.id, "price": 180})
	t.ok(counter.ok and bool(s.operations.summary(1).hilfeanfragen[0].quote_pending), "Gegenangebot bleibt derselben offenen Frachtverhandlung zugeordnet")
	t.ok(not s.executor.execute(1, {"action": "quote_transport_help", "request_id": req.id, "fee": 190}).ok, "keine zweite Preisverhandlung parallel zum Gegenangebot")
	var accepted: Dictionary = s.executor.execute(1, {"action": "accept_trade", "offer_id": counter.id})
	t.ok(accepted.ok and s.social.split_quota(1, k.id) == 3, "beide Seiten bestaetigen den ausgehandelten Unterauftrag")
	for i in 6000:
		s.step(0.2)
		if k.status == "delivered" and s.social.agreements.values()[0].status != "aktiv":
			break
	t.ok(k.status == "delivered", "Partnerfahrzeug fuehrt den bestaetigten Unterauftrag wirklich aus")
	t.ok(absf(float(b.ledger.totals.get("trade_income", 0.0)) - 180.0) < 0.01, "Partner verdient erst durch reale Warenlieferung zum ausgehandelten Preis")
	t.ok(absf(float(a.ledger.totals.get("trade_expense", 0.0)) + 180.0) < 0.01 and t.identity_ok(s), "Unterauftrag wird genau einmal als Geldtransfer abgerechnet")


static func planning_limits(t) -> void:
	var s = fixture(t)
	var v: FleetVehicle = s.company_vehicles(0)[0]
	var k: Contract = parcel(s, "TIGHT")
	var estimate: Dictionary = s.operations.route_estimate(v, k, true)
	t.ok(float(estimate.minutes) > 0.0 and float(estimate.cost) > 0.0, "Routenplanung weist Zeit- und Kostenschaetzung aus")
	k.deadline = s.game_min + 1.0
	var r: Dictionary = s.executor.execute(0, {"action": "create_transport_line", "name": "Nur sinnvolle Fracht", "cargo": k.cargo, "vehicle_ids": [v.id]})
	s.operations.tick()
	t.ok(k.status == "open" and str(s.operations.lines[r.id].status).begins_with("Frist zu knapp"), "Linienroutine nimmt wissentlich unerfuellbare Fristen nicht an")
	k.deadline = s.game_min + 5000.0
	k.reward = 0.01
	s.operations.tick()
	t.ok(k.status == "open" and str(s.operations.lines[r.id].status).contains("Fahrerkosten"), "Fracht mit vorhersehbar negativem Fahrtbeitrag bleibt liegen")
	t.ok(not s.executor.execute(0, {"action": "move_vehicle", "vehicle_id": v.id, "site_id": int(s.companies[0].depots[0])}).ok, "reservierte Linienfahrzeuge erhalten keine konkurrierende Fahrt")
	t.ok(not s.social.create_offer(0, 1, "sell_vehicle", {"vehicle_id": v.id, "price": 500}).ok, "ein verbindlicher Fahrzeughandel kann die Linienreservierung nicht umgehen")
	var reserved: String = s.operations.line_of(v.id)
	s.company(0).generation += 1
	t.ok(reserved != "" and s.operations.line_of(v.id) == "", "Nachfolgeunternehmer erbt keine Dispositionsvollmacht des alten Unternehmens")


static func intentions(t) -> void:
	var s = fixture(t)
	for i in 120:
		s.step(0.2)
	var destinations := {}
	for w in s.personnel.employed(0):
		if w.vehicle_id < 0:
			destinations[str(w.pos)] = true
	t.ok(destinations.size() >= 5, "Hofpersonal verteilt sich auf mehrere reale Arbeitsplaetze")
	var a: Avatar = s.avatars[0]
	t.ok(a.state != "wander", "Unternehmer fuehrt ohne Besuch Disposition aus statt Zufallsspaziergang")
	var cells: Dictionary = s.operations.yard_layout(int(s.companies[0].depots[0]))
	t.ok(a.goal == cells.office or a.tile().distance_to(cells.office) <= 1.5, "Unternehmer kehrt an benannten Arbeitsplatz zurueck")
	var driver: Worker = s.personnel.employed(0).filter(func(w): return w.vehicle_id < 0 and int(w.skills.fahren) > 0)[0]
	var truck: FleetVehicle = s.add_vehicle(0, "van", 12000.0, s.nearest_building_of("dealer", s.depot_road(0)).road)
	var origin := truck.pos
	s._update_vehicle(truck, 1.0)
	t.ok(truck.pos == origin and s.driver_of(truck) == null, "gekaufter Lkw wartet auf Abholung durch einen eingeteilten Fahrer")
	s.operations.tick()
	t.ok(s.personnel._has_task_for(truck.id, "fahren"), "Disposition weist vorhandenen Fahrer fuer den gekauften Lkw zu")


static func daily_routes(t) -> void:
	var s = fixture(t)
	var residents: Array = s.citizens.people.filter(func(p): return str(p.get("home", "")) != "" and p.employer != "")
	t.ok(not residents.is_empty(), "Passanten haben echte Wohn- und Arbeitsdatensaetze")
	var person: Dictionary = residents[0]
	var night: Dictionary = s.citizens.travel_plan(person, 22.0)
	t.ok(night.building == int(s.housing.units[str(person.home)].building) and night.purpose == "Nach Hause", "Nachtweg fuehrt zur tatsaechlich gemieteten Wohnung")
	var work: Dictionary = s.citizens.travel_plan(person, 9.0)
	t.ok(work.purpose.begins_with("Zur Arbeit") and s.city.walkable(work.cell), "Arbeitsweg hat einen benannten erreichbaren Zugang")
	# Buerger-KI (Auftrag 23): Gastronomie nicht jeden Abend, sondern an einzelnen Tagen des persoenlichen Plans
	var meal := {}
	for d in 28:
		for e in s.citizens.brain.day_plan(person, d):
			if str(e[2]) == "restaurant" and meal.is_empty():
				meal = s.citizens.travel_plan(person, (float(e[0]) + float(e[1])) * 0.5, d)
	t.ok(not meal.is_empty() and meal.purpose == "Restaurantbesuch nach der Arbeit", "erwerbstaetiger Bewohner besucht an manchen Abenden Gastronomie")
	var unemployed := person.duplicate()
	unemployed.id = int(person.id) + 100000   # eigener Plan (Zwischenspeicher je Person)
	unemployed.employer = ""
	unemployed.wage = 0.0
	var search := {}
	for d in 7:
		for e in s.citizens.brain.day_plan(unemployed, d):
			if str(e[2]) == "jobs" and search.is_empty():
				search = s.citizens.travel_plan(unemployed, float(e[0]) + 0.1, d)
	t.ok(not search.is_empty() and search.purpose == "Zur Arbeitsvermittlung", "arbeitsloser Bewohner geht an Werktagen zur Arbeitsvermittlung")
