class_name Simulation
extends RefCounted
## Spielzustand und Simulationsschritt. Kennt kein Rendering und keine KI-API.
## Fahrzeuge, Figuren, Verkehr, Wirtschaft, Auftraege und Ereignisse laufen hier.

signal logged(entry: Dictionary)                       # {t, text, kind, company}
signal agent_event(company_id: int, text: String)      # Anlass fuer eine vorgezogene KI-Entscheidung
signal sfx(name: String)
signal day_changed(day: int)       # absoluter Spieltag (0 = erster)
signal month_changed(month: int)

var city: CityData
var nav := NavGrid.new()
var rng := RandomNumberGenerator.new()
var market := Market.new()
var social := Social.new()
var rivalry := Rivalry.new()
var executor := ActionExecutor.new()
var personnel := Personnel.new()
var resources := ResourceMarket.new()
var logistics := Logistics.new()
var plans := PlanBook.new()
var memory := MemoryBook.new()
var decisions := DecisionLog.new()
var events := EventDirector.new()
var fuel := FuelPrices.new()
var households := Households.new()
var public_sector := PublicSector.new()
var citizens := Citizens.new()
var parcels := Parcels.new()
var permits := Permits.new()
var mayor := Mayor.new()
var construction := Construction.new()
var city_depot := CityDepot.new()
var reserve_share := 0.0
var care := BuildingCare.new()
var workforce := Workforce.new()
var news := NewsFeed.new()
var standings := Standings.new()
var stock := StockBook.new()
var trader := Trader.new()
var banking := Banking.new()
var insolvency := Insolvency.new()
var economy := Economy.new()        # Konten ausserhalb der Firmen, Geldkonservierung
var world_events := WorldEvents.new()   # automatischer Ereignismanager
var residents := Residents.new()        # Kundenfiguren mit Beduerfnissen
var experiments := ExperimentBook.new()
var estate := Estate.new()
var remaining_real_min := 9999.0   # von der Spielsitzung gesetzt (fuer Abbruchbedingung restzeit_unter_min)
var storage := {}              # Depotstandort -> {Auftrags-ID: Menge} (Zwischenlager)
var step_count := 0            # feste Simulationsschritte (Grundlage fuer exakte Wiederholung)
var sim_time := 0.0
var game_min := 0.0
var companies: Array[Company] = []
var vehicles := {}             # id -> FleetVehicle
var avatars := {}              # Firmen-ID -> Avatar
var traffic: Array[Mover] = [] # NPC-Verkehr
var contracts := {}            # id -> Contract
var customers := {}            # Gebaeude-ID -> {"loyal": Firmen-ID, "streak": {"<id>": n}}
var depot_owner := {}          # Depotstandort -> Firmen-ID
var wx := Weather.new()        # oeffentlicher Wetterstand (Mainz, siehe Weather)
var traffic_events: Array = [] # {kind, cells, until, text}
var log_entries: Array = []
var log_total := 0             # Anzahl aller bisherigen Eintraege (fuer inkrementelle Anzeige)
var action_results := {}       # Firmen-ID -> [{t, text}]
var next_vehicle_id := 1
var finished := false
var _minute_acc := 0.0
var _last_day := 0
var minute_index := 0       # fortlaufende Spielminute der Minuten-Ticks (fuer periodische Pruefungen)
var _fuel := {}                # Firmen-ID -> aufgelaufene Treibstoffkosten
var _hash := {}                # Vector2i -> [Mover] (Stauerkennung)

const FIRST_NAMES := ["Jonas", "Lena", "Mehmet", "Sophie", "Lukas", "Mia", "Paul", "Elif", "Finn", "Hannah",
	"Ben", "Emma", "Can", "Laura", "Tim", "Nina", "Max", "Zoe", "Jan", "Lea", "Ole", "Ida", "Erik", "Marie"]


## players: [{player_name, company_name, color: Color, avatar_style, personality}]
func setup(seed_value: int, players: Array, map_size: int = Catalog.MAP_SIZE, traffic_density: float = 1.0, reserve: float = Catalog.RESERVE_TARGET) -> void:
	rng.seed = seed_value
	reserve_share = reserve
	city = CityGenerator.new().generate(seed_value, map_size, reserve)
	parcels.setup(self)
	parcels.build(city)
	nav.build(city)
	market.setup(self)
	social.setup(self)
	rivalry.setup(self)
	executor.setup(self)
	logistics.setup(self)
	estate.setup(self)
	plans.setup(self)
	decisions.setup(self)
	events.setup(self)
	world_events.setup(self)
	banking.setup(self)
	insolvency.setup(self)
	trader.setup(self)
	standings.setup(self)
	public_sector.setup(self)
	citizens.setup(self)
	permits.setup(self)
	mayor.setup(self)
	construction.setup(self)
	city_depot.setup(self)
	households.setup(self)
	care.setup(self)
	workforce.setup(self)
	experiments.setup(self)
	var order := [0, 2] if players.size() == 2 else [0, 1, 2, 3]
	for i in players.size():
		var p: Dictionary = players[i]
		var c := Company.new()
		c.id = i
		c.player_name = p.player_name
		c.company_name = p.company_name
		c.color = p.color
		c.avatar_style = int(p.avatar_style)
		c.personality = p.personality
		c.form = str(p.get("form", "einzel"))
		var site: int = city.start_depots[order[i]]
		c.depots.append(site)
		depot_owner[site] = i
		city.buildings[site].name = c.company_name + " (Betriebshof)"
		companies.append(c)
		economy.attach(c.ledger, "C%d" % i)
		estate.grant_start(i, site)
		action_results[i] = []
		_fuel[i] = 0.0
		# Startausstattung: 1 Kleintransporter (aus dem Startkapital gekauft = Investition), Personal siehe unten
		var v := _create_vehicle(i, "van", Catalog.model("van").price, depot_road(i))
		c.ledger.invest(v.purchase_price)
		var a := Avatar.new()
		a.owner = i
		a.pos = city.tile_center(city.building(site).walk)
		avatars[i] = a
	personnel.setup(self)
	resources.setup(self)
	memory.setup(self)
	residents.setup(self)
	events.buildings_added.connect(residents.add_for_buildings)
	events.buildings_added.connect(func(_ids): parcels.sync_buildings())
	for c in companies:   # Startpersonal: Fahrer im Startfahrzeug + Allrounder (fuer alle gleich)
		personnel.start_staff(c.id, c.vehicle_ids[0])
	citizens.generate()
	mayor.start()
	var cars := int(city.road_count / 45.0 * traffic_density)
	for k in cars:
		_spawn_traffic_car()
	for k in market.target_open():
		market.spawn(0.0)
	for c in companies:   # Startauftraege sind allen bekannt (Zeitung vom Morgen)
		for kid in contracts:
			c.known[kid] = true
	for c in companies:
		c.ledger.sample(0.0)
	log_event("Die Partie beginnt. %d Unternehmen, Startkapital je %s." % [companies.size(),
		Catalog.money(Catalog.START_CAPITAL)], "system")


func _driver_name() -> String:
	return "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()],
		CityGenerator.SURNAMES[rng.randi() % CityGenerator.SURNAMES.size()]]


# ------------------------------------------------------------------ Hilfen
func company(id: int) -> Company:
	return companies[id] if id >= 0 and id < companies.size() else null


func depot_road(cid: int) -> Vector2i:
	return city.building(companies[cid].depots[0]).road


func nearest_depot_road(cid: int, from: Vector2i) -> Vector2i:
	var best := depot_road(cid)
	for site in companies[cid].depots:
		var r: Vector2i = city.building(site).road
		if (r - from).length_squared() < (best - from).length_squared():
			best = r
	return best


func at_depot(v: FleetVehicle) -> bool:
	for site in companies[v.owner].depots:
		var r: Vector2i = city.building(site).road
		if absi(r.x - v.tile().x) + absi(r.y - v.tile().y) <= 2:
			return true
	return false


func nearest_building_of(role: String, from: Vector2i) -> Dictionary:
	var best := {}
	var best_d := INF
	for b in city.buildings:
		if b.role == role:
			var d := Vector2(b.road - from).length_squared()
			if d < best_d:
				best_d = d
				best = b
	return best


func driver_of(v: FleetVehicle) -> Worker:
	return personnel.driver_of(v.id)


func company_vehicles(cid: int) -> Array:
	var out: Array = []
	for id in companies[cid].vehicle_ids:
		out.append(vehicles[id])
	return out


func fleet_book_value(cid: int) -> float:
	var s := 0.0
	for v in company_vehicles(cid):
		s += v.book_value
	return s


## Buchwert aller Anlagen (Fahrzeuge, Bueros, Land) plus Einlagen minus aufgelaufene Lohnrueckstaende.
func book_assets(cid: int) -> float:
	return fleet_book_value(cid) + companies[cid].property_book + companies[cid].land_book + companies[cid].ledger.deposits - companies[cid].ledger.payables


func net_worth(cid: int) -> float:
	var c := companies[cid]
	return c.ledger.cash + book_assets(cid) - c.ledger.debt


func max_loan(cid: int) -> float:
	return (Catalog.LOAN_BASE_LIMIT + 0.5 * fleet_book_value(cid)) * CompanyForms.loan_factor(companies[cid])


func loyal_company(building_id: int) -> int:
	return customers.get(building_id, {}).get("loyal", -1)


func log_event(text: String, kind: String = "info", cid: int = -1) -> void:
	var e := {"t": game_min, "text": text, "kind": kind, "company": cid}
	log_entries.append(e)
	log_total += 1
	if log_entries.size() > 400:
		log_entries.pop_front()
	logged.emit(e)


func record_result(cid: int, text: String) -> void:
	var arr: Array = action_results[cid]
	arr.append({"t": game_min, "text": text})
	if arr.size() > 16:
		arr.pop_front()


func notify(cid: int, text: String) -> void:
	record_result(cid, text)
	memory.add_event(cid, "meldung", text)
	agent_event.emit(cid, text)


const BARKS := {
	"auftrag": ["Der Auftrag ist meiner. Jetzt zählt jede Minute.", "Erst die Route, dann der Gewinn.", "Ich habe die Frist im Blick."],
	"laden": ["Ladung wird gesichert.", "Sauber stapeln, dann fahren wir los.", "Die Fracht ist gleich an Bord."],
	"lieferung": ["Pünktlich geliefert. So wächst die Firma.", "Ein Auftrag weniger, ein Kunde mehr.", "Die Rechnung kann raus!"],
	"kauf": ["Mehr Räder, mehr Möglichkeiten.", "Die neue Flotte soll sich bezahlt machen."],
	"frist": ["Die Frist ist gerissen. Das tut weh.", "Wir müssen die Routen besser planen."],
	"jobboerse": ["Neue Aufträge am Brett. Ich prüfe die Fristen.", "Hier hängen die nächsten Touren aus."],
	"personal": ["Verstärkung ist da!", "Ein guter Fahrer ist Gold wert."],
	"buero": ["Ein eigenes Büro gibt uns Überblick.", "Wir wachsen. Das Büro wächst mit."],
	"internet": ["Die Leitung steht. Aufträge kommen schneller rein."],
	"sabotage": ["Die Konkurrenz spielt nicht fair!", "Das wird Konsequenzen haben."],
}


## Situationsspruch als Sprechblase (nur Anzeige, keine Nachricht an andere KI-Spieler).
func bark(cid: int, kind: String) -> void:
	var a: Avatar = avatars.get(cid)
	var lines: Array = BARKS.get(kind, [])
	if a == null or lines.is_empty() or a.bubble_timer > 1.5:
		return
	a.say(lines[(cid * 5 + int(game_min)) % lines.size()], false)
	a.bubble_timer = 4.0


# ------------------------------------------------------------------ Fahrzeuge
func _create_vehicle(cid: int, model_id: String, price: float, cell: Vector2i) -> FleetVehicle:
	var v := FleetVehicle.new()
	v.setup(next_vehicle_id, cid, model_id, price, city.tile_center(cell))
	v.idle_since = game_min
	next_vehicle_id += 1
	vehicles[v.id] = v
	companies[cid].vehicle_ids.append(v.id)
	return v


func add_vehicle(cid: int, model_id: String, price: float, at_cell: Vector2i) -> FleetVehicle:
	var v := _create_vehicle(cid, model_id, price, at_cell)
	route(v, nearest_depot_road(cid, at_cell), "returning")
	return v


func remove_vehicle(v: FleetVehicle) -> void:
	var c := companies[v.owner]
	var d := driver_of(v)
	if d:
		d.vehicle_id = -1   # Fahrer steigt aus
		d.pos = v.pos
	for t in personnel.tasks.values():
		if int(t.target.get("vehicle_id", -1)) == v.id and not t.is_final():
			personnel.cancel_task(t, "Fahrzeug abgegeben")
	c.vehicle_ids.erase(v.id)
	vehicles.erase(v.id)


func route(v: Mover, to: Vector2i, new_state: String = "") -> bool:
	var from := v.tile()
	if not city.is_road(from):
		from = _nearest_road(from)
	var was_blocked := nav.is_blocked_road(from)
	if was_blocked:
		nav.road.set_point_solid(from, false)
	var p := nav.road_path(from, to)
	if was_blocked:
		nav.road.set_point_solid(from, true)
	if p.is_empty():
		return false
	v.set_path(p)
	if new_state != "" and v is FleetVehicle:
		v.state = new_state
	return true


func _nearest_road(p: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := p + Vector2i(dx, dy)
				if city.is_road(q):
					return q
	return p


## Naechsten geplanten Stopp anfahren (Laden -> "to_pickup", Abladen -> "to_dropoff").
func start_next_job(v: FleetVehicle) -> void:
	while not v.stops.is_empty():
		var st: Dictionary = v.stops[0]
		var k: Contract = contracts.get(st.contract_id)
		if k == null or k.status not in ["accepted", "assigned", "in_transit"]:
			v.stops.pop_front()
			continue
		logistics.sync_view(v)
		var cell := logistics.place_cell(k, st.ort)
		if not route(v, cell, "to_pickup" if st.art == "laden" else "to_dropoff"):
			v.state = "idle"   # Ziel derzeit unerreichbar (Baustelle) -> spaeter erneut
		return
	logistics.sync_view(v)


func _speed_factor(v: FleetVehicle) -> float:
	var f := wx.drive_factor()
	if companies[v.owner].is_disrupted(game_min):
		f *= 0.6
	if v.condition < Catalog.BREAKDOWN_THRESHOLD:
		f *= 0.8
	var d := driver_of(v)
	if d and d.fatigue >= 95.0:
		f *= 0.8   # uebermuedeter Fahrer
	if nav.jams.has(v.tile()):
		f *= 0.5
	return f


func _update_vehicle(v: FleetVehicle, dt: float) -> void:
	var c := companies[v.owner]
	if v.state == "returning" and not v.stops.is_empty() and driver_of(v) != null 			and not c.is_disrupted(game_min):
		start_next_job(v)   # Rueckfahrt abbrechen, neuer Auftrag hat Vorrang
	match v.state:
		"idle":
			if v.held_by != "":
				return   # wird gerade vor Ort repariert
			if not v.stops.is_empty() and driver_of(v) != null:
				if c.is_disrupted(game_min) and at_depot(v):
					return   # Betriebsstoerung: Depot kann nicht disponieren
				start_next_job(v)
			elif not at_depot(v) and v.stops.is_empty() and game_min - v.idle_since > 20.0:
				route(v, nearest_depot_road(v.owner, v.tile()), "returning")
		"broken":
			if v.no_fuel:
				var pc := companies[v.operator if v.operator >= 0 else v.owner]
				v.timer -= dt * Catalog.GAME_MIN_PER_SIM_SEC
				if pc.fuel >= 30.0:
					v.no_fuel = false
					resume_vehicle(v)
				elif v.timer <= 30.0:
					_emergency_refuel(v, pc)
			elif v.held_by == "":   # ohne Reparatur vor Ort laeuft die Abschlepp-Frist
				v.timer -= dt * Catalog.GAME_MIN_PER_SIM_SEC
				if v.timer <= 0.0:
					tow_to_workshop(v)
		"waiting_bay":
			if _bay_free(v):
				v.state = "to_pickup" if v.stops[0].art == "laden" else "to_dropoff"
				_on_arrival(v)
		"washing":
			v.timer -= dt * Catalog.GAME_MIN_PER_SIM_SEC
			if v.timer <= 0.0:
				v.state = "idle"
				v.idle_since = game_min
		"loading", "unloading", "repairing":
			v.timer -= dt * Catalog.GAME_MIN_PER_SIM_SEC
			if v.timer <= 0.0:
				_on_timer_done(v)
		_:
			_drive(v, dt)


func _drive(v: FleetVehicle, dt: float) -> void:
	if not v.arrived() and nav.is_blocked_road(v.next_tile()) and v.next_tile() != v.goal:
		events.reroutes[v.owner] = int(events.reroutes.get(v.owner, 0)) + 1
		if not route(v, v.goal):
			return   # vorerst kein Weg: warten
	if _is_blocked(v):
		return
	var before := v.tiles_moved
	v.advance(dt, _speed_factor(v))
	var moved := v.tiles_moved - before
	if moved > 0:
		var spec := v.spec()
		v.odometer += moved
		# Treibstoff zuerst aus dem eigenen Vorrat (beim Einkauf bezahlt), sonst Nachtanken zum Notpreis
		var liters := moved * float(spec.cost_per_tile) * (1.0 + 0.15 * logistics.load_total(v) / float(spec.capacity)) * wx.fuel_factor() / ResourceMarket.FUEL_BASE_PRICE
		var payer: int = v.operator if v.operator >= 0 else v.owner   # bei Vermietung zahlt der Mieter den Treibstoff
		var c := companies[payer]
		var own := minf(liters, c.fuel)
		c.fuel -= own
		if own < liters and v.state != "broken":
			# Tank leer: das Fahrzeug bleibt liegen (kein stiller Notkauf). Es geht weiter, sobald das Depot wieder Treibstoff hat
			# oder nach 90 Minuten die kostenpflichtige Notbetankung kommt.
			v.no_fuel = true
			break_vehicle(v, "Tank leer")
		var kc: Contract = contracts.get(v.contract_id)
		if kc:
			kc.fuel_cost += own * ResourceMarket.FUEL_BASE_PRICE   # Vorrat zum Grundpreis bewertet
		v.condition = maxf(0.0, v.condition - moved * float(spec.wear))
		var tired := 2.0 if driver_of(v) != null and driver_of(v).fatigue >= 95.0 else 1.0
		if v.condition < Catalog.BREAKDOWN_THRESHOLD and rng.randf() < 0.004 * moved * tired * wx.breakdown_factor(v.condition >= 60.0):
			break_vehicle(v, "Panne")
			return
	if v.arrived():
		_on_arrival(v)


## Fahrzeug bleibt liegen (Panne oder Sabotage). Reparatur vor Ort durch einen Mechaniker setzt die Fahrt fort;
## ohne Reparatur wird es nach 120 Spielminuten automatisch zur Werkstatt geschleppt (niemand bleibt dauerhaft liegen).
func break_vehicle(v: FleetVehicle, reason: String) -> void:
	if v.state != "broken":
		v.resume_state = v.state
		v.resume_timer = v.timer
	v.state = "broken"
	v.timer = 120.0
	decisions.note(v.owner, "auto", "%s ausgefallen (%s)" % [v.display_name(), reason], {"vehicle_id": v.id})
	world_events.note_breakdown(v, reason)
	log_event("%s: %s ist ausgefallen (%s)." % [companies[v.owner].company_name, v.display_name(), reason], "warn", v.owner)
	if v.no_fuel:
		notify(v.owner, "%s liegt mit leerem Tank fest. Treibstoff im Depot bestellen (buy_supplies); sonst kommt in 90 min die teure Notbetankung." % v.display_name())
	else:
		notify(v.owner, "%s ausgefallen (%s): Mechaniker schicken (repair_vehicle mit worker_id) oder es wird in 120 min abgeschleppt." % [v.display_name(), reason])
	sfx.emit("alert")


## Notbetankung am Straßenrand nach 90 Minuten: teuer (Notpreis plus Pauschale), aber das Fahrzeug faehrt weiter.
func _emergency_refuel(v: FleetVehicle, payer: Company) -> void:
	var liters := 60.0
	var cost := liters * resources.emergency_fuel_price() + 80.0
	payer.ledger.book("fuel", -cost, true, "Notbetankung " + v.display_name(), game_min)
	payer.fuel = minf(payer.fuel_cap, payer.fuel + liters)
	v.no_fuel = false
	notify(payer.id, "Notbetankung für %s: %s (Tank war leer). Besser rechtzeitig Treibstoff bestellen (schedule_refueling)." % [v.display_name(), Catalog.money(cost)])
	resume_vehicle(v)


## Nach Reparatur vor Ort: unterbrochene Taetigkeit fortsetzen.
func resume_vehicle(v: FleetVehicle) -> void:
	if v.state != "broken":
		return
	v.state = v.resume_state if v.resume_state != "" else "idle"
	v.timer = v.resume_timer
	if v.state in ["to_pickup", "to_dropoff", "returning", "to_workshop"] and v.arrived():
		_on_arrival(v)
	if v.state == "idle":
		v.idle_since = game_min
	notify(v.owner, "%s ist wieder einsatzbereit." % v.display_name())


func tow_to_workshop(v: FleetVehicle) -> void:
	var c := companies[v.owner]
	c.ledger.book("repairs", -Catalog.TOW_FEE, true, "Abschleppen " + v.display_name(), game_min)
	var ws := nearest_building_of("workshop", v.tile())
	v.state = "idle"   # Ladung und geplante Stopps bleiben erhalten
	route(v, ws.road, "to_workshop")
	notify(v.owner, "%s wird zur %s geschleppt (%s)." % [v.display_name(), ws.name, Catalog.money(Catalog.TOW_FEE)])


func _on_arrival(v: FleetVehicle) -> void:
	match v.state:
		"to_pickup", "to_dropoff":
			if v.stops.is_empty():
				_after_job(v)
				return
			var st: Dictionary = v.stops[0]
			var k: Contract = contracts.get(st.contract_id)
			if not _bay_free(v):
				v.state = "waiting_bay"   # alle Laderampen des Hofes belegt
				return
			v.state = "loading" if v.state == "to_pickup" else "unloading"
			# Dauer waechst mit der Menge; Helfer und Fahrer-Geschick verkuerzen sie
			v.timer = Catalog.LOADING_MIN * (0.5 + 0.5 * float(st.menge) / float(v.spec().capacity))
			if companies[v.owner].is_disrupted(game_min) and v.state == "loading":
				v.timer *= 2.0
			if k:
				v.timer *= personnel.loading_factor(v.owner, logistics.place_building(k, st.ort), driver_of(v))
			var site := Logistics.store_site(str(st.ort))
			if site >= 0 and estate.is_plot(site) and estate.has_ramp(site):
				v.timer *= 0.6   # Laderampe statt offener Ladeflaeche
			v.timer *= wx.loading_factor(site >= 0 and estate.is_plot(site) and estate.is_covered(site))   # Wetter im Freien
			if v.state == "loading":
				bark(v.owner, "laden")
		"returning":
			v.state = "idle"
			v.idle_since = game_min
		"to_workshop":
			v.state = "repairing"
			v.timer = Catalog.REPAIR_MIN


func _on_timer_done(v: FleetVehicle) -> void:
	var c := companies[v.owner]
	var k: Contract = contracts.get(v.contract_id)
	match v.state:
		"loading", "unloading":
			if not v.stops.is_empty():
				record_result(v.owner, logistics.apply_stop(v))
			if v.stops.is_empty():
				_after_job(v)
			else:
				v.state = "idle"
				start_next_job(v)
		"repairing":
			var cost := (100.0 - v.condition) * v.purchase_price * Catalog.REPAIR_COST_PER_POINT + 50.0
			c.ledger.book("repairs", -cost, true, "Reparatur " + v.display_name(), game_min)
			v.condition = 100.0
			v.state = "idle"
			v.idle_since = game_min
			notify(v.owner, "%s repariert (%s)." % [v.display_name(), Catalog.money(cost)])


func _after_job(v: FleetVehicle) -> void:
	var c := companies[v.owner]
	var d := driver_of(v)
	if d and d.leaving:
		d.vehicle_id = -1
		d.pos = v.pos
		d.leaving = false
		d.employer = d.transfer_to
		d.transfer_to = -1
		log_event("%s: Fahrer %s wechselt zur Konkurrenz." % [c.company_name, d.name], "warn", v.owner)
	v.state = "idle"
	v.idle_since = game_min
	if not v.stops.is_empty() and driver_of(v) != null:
		start_next_job(v)
	else:
		# vor Ort auf den naechsten Auftrag warten; nach 20 Spielminuten faehrt es zum Depot zurueck
		v.path.clear()
		agent_event.emit(v.owner, "%s ist frei" % v.display_name())


func deliver_contract(v: FleetVehicle, k: Contract) -> void:
	var c := companies[k.owner]   # Verguetung an den Auftragsinhaber (auch bei Unterauftrag/Miete)
	if k.internal != "":
		# eigener Materialtransport: kein Umsatz, keine Reputation, Material kommt auf die Baustelle
		k.status = "delivered"
		k.done_at = game_min
		estate.material_delivered(k)
		return
	var late_h := maxf(0.0, game_min - k.deadline) / 60.0
	var factor := maxf(0.0, 1.0 - Catalog.LATE_PENALTY_PER_HOUR * ceilf(late_h))
	var pay := k.reward * factor
	if v.clean_until > game_min and city.building(k.dropoff).type in ["restaurant", "office", "villa", "hotel"]:
		pay *= 1.05   # gepflegtes Fahrzeug
	c.ledger.book("transport", pay, true, "Auftrag %s geliefert" % k.id, game_min, k.payer)   # payer "" = Markt
	k.status = "delivered"
	k.paid = pay
	k.done_at = game_min
	if k.order_ref != "":
		city_depot.contract_delivered(k)
	memory.record_contract(c.id, k, late_h <= 0.0, pay)
	decisions.note(c.id, "auto", "Auftrag %s geliefert: %s%s" % [k.id, Catalog.money(pay), "" if late_h <= 0.0 else " (verspätet)"], {"contract_id": k.id})
	c.stats.completed += 1
	var cust: Dictionary = customers.get(k.pickup, {"loyal": -1, "streak": {}})
	customers[k.pickup] = cust
	var key := str(c.id)
	if late_h <= 0.0:
		c.stats.on_time += 1
		c.reputation = minf(100.0, c.reputation + 1.5)
		cust.streak[key] = int(cust.streak.get(key, 0)) + 1
		if cust.streak[key] >= 3 and cust.loyal != c.id:
			cust.loyal = c.id
			var name: String = city.building(k.pickup).name
			log_event("%s gewinnt %s als Stammkunden." % [c.company_name, name], "good", c.id)
			c.add_key_event("Stammkunde gewonnen: " + name, game_min)
	else:
		c.stats.late += 1
		c.reputation = maxf(0.0, c.reputation - 2.0)
		cust.streak[key] = 0
	log_event("%s liefert %s (%d× %s) – %s%s" % [c.company_name, k.id, k.qty, k.cargo_name(),
		Catalog.money(pay), "" if late_h <= 0.0 else " (verspätet)"], "money", c.id)
	notify(c.id, "Auftrag %s geliefert, Erlös %s%s." % [k.id, Catalog.money(pay), "" if late_h <= 0.0 else " (verspätet)"])
	sfx.emit("cash")
	bark(c.id, "lieferung")


## Am eigenen Hof begrenzen Laderampen die gleichzeitige Abfertigung.
func _bay_free(v: FleetVehicle) -> bool:
	if v.stops.is_empty():
		return true
	var site := Logistics.store_site(str(v.stops[0].ort))
	if site < 0 or not estate.is_plot(site):
		return true
	var busy := 0
	for o in vehicles.values():
		if o != v and o.state in ["loading", "unloading"] and not o.stops.is_empty() and Logistics.store_site(str(o.stops[0].ort)) == site:
			busy += 1
	return busy < estate.loading_bays(site)


func _close_contract_logistics(k: Contract) -> void:
	var affected: Array = []
	for v in vehicles.values():
		if v.contract_id == k.id:
			affected.append(v)
	logistics.close_contract(k)
	for v in affected:
		if v.state in ["to_pickup", "loading", "to_dropoff", "unloading"]:
			v.state = "idle"
			if v.stops.is_empty():
				_after_job(v)
			else:
				start_next_job(v)


func fail_contract(k: Contract, reason: String) -> void:
	var c := companies[k.owner]
	var penalty := k.reward * Catalog.FAIL_PENALTY_SHARE
	c.ledger.book("penalties", -penalty, true, "Vertragsstrafe %s" % k.id, game_min)
	k.status = "failed"
	k.done_at = game_min
	c.stats.failed += 1
	memory.record_contract(c.id, k, false, 0.0)
	decisions.note(c.id, "auto", "Auftrag %s gescheitert (%s)" % [k.id, reason], {"contract_id": k.id})
	c.reputation = maxf(0.0, c.reputation - 6.0)
	_close_contract_logistics(k)
	log_event("%s: Auftrag %s gescheitert (%s), Strafe %s." % [c.company_name, k.id, reason, Catalog.money(penalty)],
		"bad", c.id)
	c.add_key_event("Auftrag %s gescheitert" % k.id, game_min)
	notify(c.id, "Auftrag %s gescheitert: %s. Vertragsstrafe %s." % [k.id, reason, Catalog.money(penalty)])
	bark(c.id, "frist")


# ------------------------------------------------------------------ NPC-Verkehr
func _spawn_traffic_car() -> void:
	var m := Mover.new()
	m.speed = rng.randf_range(2.4, 3.2)
	var start := _random_road()
	m.pos = city.tile_center(start)
	traffic.append(m)
	route(m, _random_road())


func _random_road() -> Vector2i:
	for attempt in 200:
		var p := Vector2i(rng.randi_range(0, city.size - 1), rng.randi_range(0, city.size - 1))
		if city.is_road(p) and not nav.is_blocked_road(p):
			return p
	return city.intersections[0]


func _update_traffic_car(m: Mover, dt: float) -> void:
	if m.arrived():
		route(m, _random_road())
		return
	if nav.is_blocked_road(m.next_tile()) and m.next_tile() != m.goal:
		route(m, m.goal)
		return
	if _is_blocked(m):
		return
	m.advance(dt, wx.drive_factor() * (0.5 if nav.jams.has(m.tile()) else 1.0))


func light_green(cell: Vector2i, horizontal: bool) -> bool:
	var offset := float((cell.x * 31 + cell.y * 17) % 5)
	var phase := int((sim_time + offset) / 5.0) % 2
	return (phase == 0) == horizontal


func _rebuild_hash() -> void:
	_hash.clear()
	for m in traffic:
		_hash_add(m)
	for v in vehicles.values():
		if v.state in ["to_pickup", "to_dropoff", "returning", "to_workshop", "loading", "unloading", "broken"]:
			_hash_add(v)


func _hash_add(m: Mover) -> void:
	var t := m.tile()
	if not _hash.has(t):
		_hash[t] = []
	_hash[t].append(m)


## Auffahrschutz und Ampeln. Nach 6 s Blockade wird nicht mehr gewartet (keine Dauerstaus).
func _is_blocked(m: Mover) -> bool:
	if m.arrived():
		return false
	var nt := m.next_tile()
	var cur := m.tile()
	if nt != cur and city.road_mask(nt) in [7, 11, 13, 14, 15] and city.road_mask(cur) not in [7, 11, 13, 14, 15]:
		var dist := m.pos.distance_to(city.tile_center(nt))
		var dir := Vector2(nt - cur)
		if dist > 14.0 and dist < 30.0 and not light_green(nt, absf(dir.x) > absf(dir.y)):
			return true
	if m.wait_time > 6.0:
		m.wait_time = 0.0
		return false
	for t in [cur, nt]:
		for o in _hash.get(t, []):
			if o == m or m.heading.dot(o.heading) < 0.5:
				continue
			var rel: Vector2 = o.pos - m.pos
			var along := rel.dot(m.heading)
			if along > 0.0 and along < 22.0 and absf(rel.cross(m.heading)) < 7.0:
				m.wait_time += 0.1
				return true
	m.wait_time = 0.0
	return false


# ------------------------------------------------------------------ Figuren
func walk_avatar(a: Avatar, target: Vector2i) -> bool:
	var p := nav.walk_path(a.tile(), target)
	if p.is_empty():
		return false
	a.set_path(p)
	a.state = "walking"
	return true


func _update_avatar(a: Avatar, dt: float) -> void:
	a.bubble_timer -= dt
	match a.state:
		"talking":
			a.talk_timer -= dt
			if a.talk_timer <= 0.0:
				a.state = "idle"
				_resume_visit(a)
		"walking":
			var follow: int = a.pending.get("follow", -1)
			if follow >= 0:
				var other: Avatar = avatars[follow]
				if a.pos.distance_to(other.pos) < 40.0:
					_arrive(a)
					return
				if a.arrived() or int(sim_time * 2.0) % 6 == 0 and a.goal != other.tile():
					walk_avatar(a, other.tile())
			a.advance(dt, 1.0)
			if a.arrived():
				_arrive(a)
		"wander":
			a.advance(dt, 1.0)
			if a.arrived():
				a.state = "idle"
				a.wander_timer = rng.randf_range(3.0, 9.0)
		_:
			if _resume_visit(a):
				return
			a.wander_timer -= dt
			if a.wander_timer <= 0.0:
				var home: Vector2i = city.building(companies[a.owner].depots[0]).walk
				var t := home + Vector2i(rng.randi_range(-6, 6), rng.randi_range(-6, 6))
				if city.walkable(t) and walk_avatar(a, t):
					a.state = "wander"
				a.wander_timer = 4.0


## Offenen Besuch fortsetzen (z. B. nach einem Gespraech unterwegs). Gibt true zurueck, wenn die Figur wieder laeuft.
func _resume_visit(a: Avatar) -> bool:
	if a.pending.is_empty() or not a.pending.has("cell"):
		return false
	var follow: int = a.pending.get("follow", -1)
	var target: Vector2i = avatars[follow].tile() if follow >= 0 else a.pending.cell
	if walk_avatar(a, target):
		return true
	_arrive(a)   # kein Weg moeglich: Besuch abschliessen (wird vor Ort erneut geprueft)
	return false


func _arrive(a: Avatar) -> void:
	a.state = "idle"
	a.wander_timer = 6.0
	var pending := a.pending
	a.pending = {}
	if pending.is_empty():
		return
	var follow: int = pending.get("follow", -1)
	if follow >= 0:
		# Begegnung: beide bleiben kurz stehen und schauen sich an
		var other: Avatar = avatars[follow]
		for x in [a, other]:
			x.state = "talking"
			x.talk_timer = 8.0
			x.path.clear()
		a.heading = (other.pos - a.pos).normalized()
		other.heading = -a.heading
	if pending.has("place"):
		a.visited[pending.place] = game_min
	executor.complete_visit(a.owner, pending)
	executor.start_queued_visit(a.owner)


# ------------------------------------------------------------------ Hauptschritt
func step(dt: float) -> void:
	if finished:
		return
	step_count += 1
	sim_time += dt
	game_min += dt * Catalog.GAME_MIN_PER_SIM_SEC
	_rebuild_hash()
	for m in traffic:
		_update_traffic_car(m, dt)
	for v in vehicles.values():
		_update_vehicle(v, dt)
	for a in avatars.values():
		_update_avatar(a, dt)
	personnel.update(dt)
	_minute_acc += dt * Catalog.GAME_MIN_PER_SIM_SEC
	while _minute_acc >= 1.0:
		_minute_acc -= 1.0
		_minute_tick()


func _minute_tick() -> void:
	minute_index += 1
	if minute_index % 60 == 0:
		fuel.simulate_step()
	if minute_index % 30 == 0:
		FuelPlanner.run_rules(self)
	if minute_index % Workforce.TICK_MIN == 0:
		workforce.minute_tick()
	var now := game_min
	var day := GameCalendar.day_of(now)
	if day != _last_day:
		var new_month := GameCalendar.month_of(now) != GameCalendar.month_of(GameCalendar.day_start(_last_day))
		_last_day = day
		day_changed.emit(day)
		if new_month:
			month_changed.emit(GameCalendar.month_of(now))
	for c in companies:
		if c.status in ["insolvenz", "verwertung", "geschlossen"]:
			continue   # eingefroren: Verwalter fuehrt den Betrieb nicht weiter
		var L := c.ledger
		households.credit_company(c.id, L.accrue_wages(personnel.wages_per_hour(c.id) / 60.0, now))
		var rent := Catalog.EXTRA_DEPOT_RENT * c.depots.filter(func(site): return not estate.is_plot(site)).size()   # Startgrundstueck ist frei
		L.book("rent", -rent / 1440.0, true, "Miete", now)
		L.book("security", -Catalog.SECURITY_PER_DAY[c.security_level] / 1440.0, true, "Sicherheitsdienst", now)
		if c.insurance:
			L.book("insurance", -Catalog.INSURANCE_PER_DAY / 1440.0, true, "Versicherung", now)
		var interest := maxf(0.0, -L.cash) * Catalog.OVERDRAFT_INTEREST_PER_DAY / 1440.0
		L.book("interest", -interest, true, "Zinsen", now)
		for v in company_vehicles(c.id):
			var floor_v: float = v.purchase_price * Catalog.RESIDUAL_SHARE
			var dep := minf(v.purchase_price * Catalog.DEPRECIATION_PER_DAY / 1440.0, maxf(0.0, v.book_value - floor_v))
			v.book_value -= dep
			L.book("depreciation", -dep, false, "Abschreibung", now)
		L.book("fuel", -_fuel[c.id], true, "Treibstoff", now)
		_fuel[c.id] = 0.0
		var office_cost: float = Catalog.OFFICE_PER_DAY * c.offices.size() + Catalog.INTERNET_PER_DAY[c.internet_level]
		L.book("office", -office_cost / 1440.0, true, "Büros & Internet", now)
		var pdep := minf(c.property_cost * Catalog.PROPERTY_DEPRECIATION_PER_DAY / 1440.0, c.property_book)
		c.property_book -= pdep
		L.book("depreciation", -pdep, false, "Abschreibung Büros", now)
		if minute_index % 10 == 0:
			L.sample(now)
	for k in contracts.values():
		if k.owner >= 0 and k.status in ["accepted", "assigned", "loading", "in_transit"] \
				and now > k.deadline + Catalog.FAIL_AFTER_HOURS * 60.0:
			fail_contract(k, "Frist weit überschritten")
	market.tick(now)
	social.tick(now)
	personnel.minute_tick(now)
	resources.minute_tick(now)
	estate.minute_tick(now)
	events.minute_tick(now)
	world_events.minute_tick(now)
	residents.minute_tick(now)
	if minute_index % 5 == 0:
		plans.tick()
		experiments.tick()
	_world_events(now)


## Neuer oeffentlicher Wetterstand (Live-Abruf). Meldet Wechsel der Wetterlage, damit der Ereignismanager reagieren kann.
func apply_weather(state: Dictionary, now_unix: float) -> void:
	var before: String = wx.cur.get("cond", "")
	wx.apply(state, minute_index, now_unix)
	if before != state.cond:
		log_event("Wetter Mainz (Modelldaten): %s" % wx.headline(), "info")


func _world_events(now: float) -> void:
	if nav.expire(now):
		for e in traffic_events.duplicate():
			if e.until <= now:
				traffic_events.erase(e)
	if not wx.replay.is_empty():
		wx.replay_tick(minute_index)
	else:
		wx.simulate(now, rng)   # nur Ersatzwetter; echte Daten kommen ueber apply_weather
	var works := traffic_events.filter(func(e): return e.kind == "baustelle").size()
	if works < 3 and rng.randf() < 0.012:
		var p := _straight_road()
		if p.x >= 0:
			var until := now + rng.randf_range(120.0, 240.0)
			nav.add_roadwork(p, until)
			var txt := "Baustelle im %s (Straße gesperrt)" % Catalog.DISTRICTS[city.district_of(p)]
			traffic_events.append({"kind": "baustelle", "cells": [p], "until": until, "text": txt})
			log_event("Verkehr: " + txt, "info")
	var jams := traffic_events.filter(func(e): return e.kind == "stau").size()
	if jams < 3 and rng.randf() < 0.015:
		var p := _straight_road()
		if p.x >= 0:
			var dir := Vector2i(1, 0) if city.road_mask(p) == 10 else Vector2i(0, 1)
			var cells: Array = []
			var until := now + 60.0
			for k in range(-3, 4):
				var q := p + dir * k
				if city.is_road(q):
					nav.add_jam(q, until)
					cells.append(q)
			var txt := "Stau im %s (halbe Geschwindigkeit)" % Catalog.DISTRICTS[city.district_of(p)]
			traffic_events.append({"kind": "stau", "cells": cells, "until": until, "text": txt})
			log_event("Verkehr: " + txt, "info")


func _straight_road() -> Vector2i:
	for attempt in 50:
		var p := _random_road()
		if city.road_mask(p) in [5, 10]:
			var used := false
			for b in city.buildings:
				if b.road == p:
					used = true
					break
			if not used:
				return p
	return Vector2i(-1, -1)


## Spielende: offene Verpflichtungen abrechnen. Ueberfaellige Auftraege -> Vertragsstrafe,
## noch fristgerechte, unvollendete Auftraege -> storniert ohne Verguetung (Kosten bleiben).
func finalize() -> void:
	if finished:
		return
	for k in contracts.values():
		if k.owner >= 0 and k.status in ["accepted", "assigned", "loading", "in_transit"]:
			if game_min > k.deadline:
				fail_contract(k, "bei Spielende überfällig")
			else:
				k.status = "cancelled"   # unvollstaendig: keine Verguetung
				logistics.close_contract(k)
	for c in companies:
		c.ledger.book("fuel", -_fuel[c.id], true, "Treibstoff", game_min)
		_fuel[c.id] = 0.0
		c.ledger.sample(game_min)
	finished = true
	log_event("Die Partie ist beendet.", "system")


## Rangfolge: Gewinn, dann Reputation, dann abgeschlossene Auftraege.
func ranking() -> Array:
	var r := companies.duplicate()
	r.sort_custom(func(a: Company, b: Company):
		if Standings.solvent(a) != Standings.solvent(b):
			return Standings.solvent(a)
		var pa := snappedf(a.ledger.profit(), 0.01)
		var pb := snappedf(b.ledger.profit(), 0.01)
		if pa != pb:
			return pa > pb
		if a.reputation != b.reputation:
			return a.reputation > b.reputation
		return a.stats.completed > b.stats.completed)
	return r


# ------------------------------------------------------------------ Speichern/Laden
func to_dict() -> Dictionary:
	var vs: Array = []
	for v in vehicles.values():
		vs.append(v.to_dict())
	var ks: Array = []
	for k in contracts.values():
		ks.append(k.to_dict())
	var avs := {}
	for cid in avatars:
		var a: Avatar = avatars[cid]
		avs[str(cid)] = {"x": a.pos.x, "y": a.pos.y}
	var cust := {}
	for b in customers:
		cust[str(b)] = customers[b]
	var owners := {}
	for s in depot_owner:
		owners[str(s)] = depot_owner[s]
	return {"seed": city.seed_value, "map_size": city.size, "reserve": reserve_share, "parcels": parcels.to_dict(), "sim_time": sim_time, "game_min": game_min, "calendar_day_seconds": GameCalendar.day_seconds, "minute_index": minute_index,
		"rng_state": str(rng.state), "companies": companies.map(func(c): return c.to_dict()), "vehicles": vs,
		"contracts": ks, "avatars": avs, "storage": _storage_dict(), "step_count": step_count, "plans": plans.to_dict(), "memory": memory.to_dict(), "decisions": decisions.to_dict(), "events": events.to_dict(), "world_events": world_events.to_dict(), "residents": residents.to_dict(), "experiments": experiments.to_dict(), "estate": estate.to_dict(), "personnel": personnel.to_dict(), "resources": resources.to_dict(), "customers": cust, "depot_owner": owners,
		"weather": wx.to_dict(), "economy": economy.to_dict(), "banking": banking.to_dict(), "insolvency": insolvency.to_dict(), "stock": stock.to_dict(), "standings": standings.to_dict(), "fuel": fuel.to_dict(), "households": households.to_dict(), "public_sector": public_sector.to_dict(), "citizens": citizens.to_dict(), "permits": permits.to_dict(), "mayor": mayor.to_dict(), "construction": construction.to_dict(), "city_depot": city_depot.to_dict(), "care": care.to_dict(), "workforce": workforce.to_dict(), "news": news.to_dict(), "trader": trader.to_dict(), "log": log_entries.slice(-150),
		"next_vehicle_id": next_vehicle_id, "market": market.to_dict(),
		"social": social.to_dict(), "rivalry": rivalry.to_dict(), "action_results": action_results}


func _storage_dict() -> Dictionary:
	var out := {}
	for site in storage:
		out[str(site)] = storage[site]
	return out


static func from_dict(d: Dictionary) -> Simulation:
	var s := Simulation.new()
	var players: Array = []
	for cd in d.companies:
		players.append({"player_name": cd.player_name, "company_name": cd.company_name,
			"color": Color.html(cd.color), "avatar_style": cd.avatar_style, "personality": cd.personality})
	s.setup(int(d.seed), players, int(d.map_size), 1.0, float(d.get("reserve", 0.0)))   # alte Staende: Karte ohne Reserve
	# Ausgangszustand durch gespeicherten Zustand ersetzen
	s.companies.clear()
	for cd in d.companies:
		s.companies.append(Company.from_dict(cd))
	s.economy.detach_all()
	for c in s.companies:
		s.economy.attach(c.ledger, "C%d" % c.id)
	s.economy.from_dict(d.get("economy", {}))
	s.banking.from_dict(d.get("banking", {}))
	s.insolvency.from_dict(d.get("insolvency", {}))
	s.stock.from_dict(d.get("stock", {}))
	s.standings.from_dict(d.get("standings", {}))
	s.fuel.from_dict(d.get("fuel", {}))
	s.households.from_dict(d.get("households", {}))
	s.public_sector.from_dict(d.get("public_sector", {}))
	s.citizens.from_dict(d.get("citizens", {}))
	s.permits.from_dict(d.get("permits", {}))
	s.mayor.from_dict(d.get("mayor", {}))
	s.construction.from_dict(d.get("construction", {}))
	s.city_depot.from_dict(d.get("city_depot", {}))
	s.care.from_dict(d.get("care", {}))
	s.workforce.from_dict(d.get("workforce", {}))
	s.news.from_dict(d.get("news", {}))
	s.trader.from_dict(d.get("trader", {}))
	s.vehicles.clear()
	for vd in d.vehicles:
		var v := FleetVehicle.from_dict(vd)
		s.vehicles[v.id] = v
	s.contracts.clear()
	for kd in d.contracts:
		var k := Contract.from_dict(kd)
		s.contracts[k.id] = k
	s.sim_time = d.sim_time
	s.game_min = d.game_min
	GameCalendar.configure(float(d.get("calendar_day_seconds", GameCalendar.DEFAULT_DAY_SECONDS)))
	s._last_day = GameCalendar.day_of(s.game_min)
	s.minute_index = int(d.get("minute_index", int(d.game_min)))
	s.rng.state = int(d.rng_state)
	s.personnel.from_dict(d.personnel)
	s.step_count = int(d.get("step_count", 0))
	s.plans.from_dict(d.get("plans", {}))
	s.memory.from_dict(d.get("memory", {}))
	s.decisions.from_dict(d.get("decisions", {}))
	s.events.from_dict(d.get("events", {}))
	s.parcels.sync_buildings()
	s.parcels.from_dict(d.get("parcels", {}))
	s.world_events.from_dict(d.get("world_events", {}))
	if d.has("residents"):
		s.residents.from_dict(d.residents)
	s.experiments.from_dict(d.get("experiments", {}))
	s.estate.from_dict(d.get("estate", {}))
	for site in d.get("storage", {}):
		s.storage[int(site)] = {}
		for kid in d.storage[site]:
			s.storage[int(site)][kid] = int(d.storage[site][kid])
	s.resources.from_dict(d.resources)
	s.customers.clear()
	for b in d.customers:
		s.customers[int(b)] = d.customers[b]
		s.customers[int(b)].loyal = int(d.customers[b].loyal)
	s.depot_owner.clear()
	for site in d.depot_owner:
		s.depot_owner[int(site)] = int(d.depot_owner[site])
	for c in s.companies:
		if not c.depots.is_empty():
			s.city.buildings[c.depots[0]].name = c.company_name + " (Betriebshof)"
	if d.get("weather") is Dictionary:
		s.wx.from_dict(d.weather)
	s.log_entries = d.log
	s.log_total = s.log_entries.size()
	s.next_vehicle_id = int(d.next_vehicle_id)
	s.market.from_dict(d.market)
	s.social.from_dict(d.social)
	s.rivalry.from_dict(d.rivalry)
	for cid in d.action_results:
		s.action_results[int(cid)] = d.action_results[cid]
	for cid in d.avatars:
		var a: Avatar = s.avatars[int(cid)]
		a.pos = Vector2(d.avatars[cid].x, d.avatars[cid].y)
	# Fahrzeuge auf ihr gespeichertes Ziel neu routen
	for v in s.vehicles.values():
		s.logistics.sync_view(v)
		if v.state in ["to_pickup", "to_dropoff", "returning", "to_workshop"]:
			if not s.route(v, v.goal):
				v.state = "idle"
	return s
