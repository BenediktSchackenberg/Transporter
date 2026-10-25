class_name ResourceMarket
extends RefCounted
## Knappe Ressourcen an konkreten Orten:
##  - Fahrzeugangebote bei den Autohaeusern (begrenzter Bestand, verkauft = weg, kontrollierte Nachlieferung)
##  - Treibstoff an Tankstellen und Ersatzteile in Werkstaetten (Bestand, Preis, Nachschub)
## Betriebsmittel werden beim Kauf als Aufwand gebucht ("supplies"); Restbestaende am Ende verfallen.

const FUEL_BASE_PRICE := 1.5           # EUR/Liter, Grundlage des Verbrauchs je Tile
const FUEL_EMERGENCY_PRICE := 2.0      # Nachtanken ohne eigenen Vorrat
const OFFERS_PER_DEALER := 5
const PUMP_LITERS_PER_MIN := 30.0       # Zapfgeschwindigkeit je Saeule
const TANKER_ORDER_BELOW := 0.35        # Bestellung unter diesem Fuellstand
const WHOLESALE_FACTOR := 0.86          # Einkaufspreis des Betreibers (Anteil Referenzpreis)
const BACKGROUND_L_PER_DAY := 600.0     # Verkauf an Haushalte (Privatfahrzeuge) je Station und Spieltag
const STATION_WAGE_PER_MONTH := 900.0   # Personal je Tankstelle

var sim
var offers := {}       # "F<n>" -> {id, dealer, model, price, condition, status}
var supplies := {}     # "S<n>" -> {id, kind (fuel|parts), building, stock, max, price, regen}
var next_offer := 1
var tanker_orders: Array = []          # {station, qty, due, cost}
var fuel_price_factor := 1.0           # Ereignisregler: Treibstoffpreise


func setup(simulation) -> void:
	sim = simulation
	var n := 1
	for b in sim.city.buildings:
		if b.role == "dealer":
			for k in OFFERS_PER_DEALER:
				_new_offer(b.id)
		elif b.type == "gas_station":
			supplies["S%d" % n] = {"id": "S%d" % n, "kind": "fuel", "building": b.id, "stock": 3000.0, "max": 3000.0,
				"price": 0.0, "markup": snappedf(sim.rng.randf_range(-0.04, 0.06), 0.001), "regen": 0.0,
				"pumps": 2 + n % 3, "busy": [], "sales_l": 0.0, "revenue": 0.0, "wait_min": 0.0, "customers": 0, "deliveries": 0, "dry_days": 0}
			n += 1
		elif b.role == "workshop":
			supplies["S%d" % n] = {"id": "S%d" % n, "kind": "parts", "building": b.id, "stock": 20.0, "max": 20.0,
				"price": float(sim.rng.randi_range(100, 140)), "regen": 0.02}
			n += 1


func _new_offer(dealer: int) -> void:
	var rng: RandomNumberGenerator = sim.rng
	var models := ["cargobike", "van", "van", "transporter", "transporter", "reefer", "truck", "semi"]
	var model: String = models[rng.randi() % models.size()]
	var used := rng.randf() < 0.4
	var base: float = Catalog.model(model).price
	var o := {"id": "F%d" % next_offer, "dealer": dealer, "model": model, "status": "verfügbar",
		"condition": rng.randi_range(55, 85) if used else 100,
		"price": roundf(base * (rng.randf_range(0.6, 0.75) if used else rng.randf_range(0.95, 1.08)) / 50.0) * 50.0}
	next_offer += 1
	offers[o.id] = o


func available_offers() -> Array:
	return offers.values().filter(func(o): return o.status == "verfügbar")


func cheapest_offer(model: String) -> Dictionary:
	var best := {}
	for o in available_offers():
		if o.model == model and (best.is_empty() or o.price < best.price):
			best = o
	return best


## Spielpreis je Liter Diesel: reale Referenz x Aufschlag der Tankstelle x Ereignisfaktor (alles getrennt sichtbar, siehe FuelPrices).
func fuel_price(s: Dictionary) -> float:
	var markup: float = float(s.get("markup", float(s.price) / 1.7 - 1.0))
	return snappedf(sim.fuel.station_price("diesel", markup) * fuel_price_factor, 0.01)


func emergency_fuel_price() -> float:
	return maxf(FUEL_EMERGENCY_PRICE, float(sim.fuel.ref.diesel) * 1.2) * fuel_price_factor


## Kauf von Treibstoff (Liter) oder Ersatzteilen (Stueck); Bestand am Ort sinkt sofort.
func buy_supplies(cid: int, sid: String, amount: float) -> Dictionary:
	var s: Dictionary = supplies.get(sid, {})
	if s.is_empty():
		return {"ok": false, "msg": "Unbekannte Bezugsquelle %s." % sid}
	amount = floorf(amount)
	if amount <= 0.0:
		return {"ok": false, "msg": "Menge muss positiv sein."}
	if amount > float(s.stock):
		return {"ok": false, "msg": "Nur noch %d %s vorrätig." % [int(s.stock), "Liter" if s.kind == "fuel" else "Ersatzteile"]}
	var unit: float = fuel_price(s) if s.kind == "fuel" else float(s.price)
	var cost := unit * amount
	var c: Company = sim.company(cid)
	if c.ledger.cash < cost:
		return {"ok": false, "msg": "Nicht genug Bargeld (%s)." % Catalog.money(cost)}
	if s.kind == "fuel" and c.fuel + amount > c.fuel_cap:
		return {"ok": false, "msg": "Tank fasst nur %d l (Vorrat %d l)." % [int(c.fuel_cap), int(c.fuel)]}
	s.stock = float(s.stock) - amount
	c.ledger.book("supplies", -cost, true, "%s %d × %s" % ["Treibstoff" if s.kind == "fuel" else "Ersatzteile", int(amount),
		sim.city.building(s.building).name], sim.game_min, "G0" if s.kind == "fuel" else "S0")
	var wait_txt := ""
	if s.kind == "fuel":
		c.fuel += amount
		var wait: float = _use_pump(s, amount)
		s.sales_l = float(s.sales_l) + amount
		s.revenue = float(s.revenue) + cost
		s.customers = int(s.customers) + 1
		if wait > 0.5:
			wait_txt = " Wartezeit an der Zapfsäule: %d min." % int(ceil(wait))
	else:
		c.parts += int(amount)
	return {"ok": true, "msg": "%d %s gekauft für %s (Vorrat: %d l Treibstoff, %d Ersatzteile).%s" % [int(amount),
		"Liter" if s.kind == "fuel" else "Ersatzteile", Catalog.money(cost), int(c.fuel), c.parts, wait_txt]}


## Belegt die frueheste freie Zapfsaeule; gibt die Wartezeit (Spielminuten) zurueck. Besetzte Saeulen sind ein echter Engpass.
func _use_pump(s: Dictionary, liters: float) -> float:
	var busy: Array = s.busy
	while busy.size() < int(s.pumps):
		busy.append(0.0)
	var best := 0
	for i in busy.size():
		if float(busy[i]) < float(busy[best]):
			best = i
	var start := maxf(sim.game_min, float(busy[best]))
	busy[best] = start + liters / PUMP_LITERS_PER_MIN
	var wait: float = start - sim.game_min
	s.wait_min = float(s.wait_min) + wait
	return wait


func pumps_busy(s: Dictionary) -> int:
	var n := 0
	for b in s.busy:
		if float(b) > sim.game_min:
			n += 1
	return n


## Taeglich: Verkauf an Haushalte (H0 zahlt), Tankwagen bestellen (Betreiber G0 zahlt an das Ausland X0), Anlieferungen eintragen.
func _daily_stations() -> void:
	var now: float = sim.game_min
	var gas := 0
	for sid in supplies:
		var s: Dictionary = supplies[sid]
		if s.kind != "fuel":
			continue
		gas += 1
		var sold := minf(BACKGROUND_L_PER_DAY, float(s.stock))
		if sold > 0.0:
			var pay := sold * fuel_price(s)
			s.stock = float(s.stock) - sold
			s.sales_l = float(s.sales_l) + sold
			s.revenue = float(s.revenue) + pay
			sim.economy.transfer("H0", "G0", pay)
		s.dry_days = int(s.dry_days) + (1 if float(s.stock) < 1.0 else 0)
		var pending := 0.0
		for o in tanker_orders:
			if o.station == sid:
				pending += float(o.qty)
		if float(s.stock) + pending < TANKER_ORDER_BELOW * float(s.max):
			var wholesale: float = float(sim.fuel.ref.diesel) * WHOLESALE_FACTOR * fuel_price_factor
			var qty := minf(float(s.max) - float(s.stock) - pending, floorf(maxf(0.0, sim.economy.accounts.G0) / wholesale))
			qty = floorf(qty / 100.0) * 100.0
			if qty >= 100.0:
				var cost := qty * wholesale
				sim.economy.transfer("G0", "X0", cost)
				tanker_orders.append({"station": sid, "qty": qty, "due": now + GameCalendar.day_game_min, "cost": cost})
	for o in tanker_orders.duplicate():
		if now >= float(o.due):
			var st: Dictionary = supplies[o.station]
			st.stock = minf(float(st.max), float(st.stock) + float(o.qty))
			st.deliveries = int(st.deliveries) + 1
			tanker_orders.erase(o)


func _monthly_stations() -> void:
	var gas := supplies.values().filter(func(s): return s.kind == "fuel").size()
	var wages := minf(STATION_WAGE_PER_MONTH * gas, maxf(0.0, sim.economy.accounts.G0))
	sim.economy.transfer("G0", "H0", wages)


func minute_tick(now: float) -> void:
	for s in supplies.values():
		if float(s.regen) > 0.0:
			s.stock = minf(float(s.max), float(s.stock) + float(s.regen))
	var day := int(GameCalendar.day_game_min)
	if sim.minute_index % day == 0:
		_daily_stations()
	if sim.minute_index % (day * GameCalendar.DAYS_PER_MONTH) == 0:
		_monthly_stations()
	if sim.minute_index % 120 == 0:
		for b in sim.city.buildings:
			if b.role == "dealer" and available_offers().filter(func(o): return o.dealer == b.id).size() < OFFERS_PER_DEALER:
				_new_offer(b.id)


## Detailauskunft zu einer oeffentlich sichtbaren Ressource. Fremde interne Daten bleiben verborgen.
func inspect(cid: int, rid: String) -> Dictionary:
	var c: Company = sim.company(cid)
	if offers.has(rid):
		var o: Dictionary = offers[rid]
		var m: Dictionary = Catalog.model(o.model)
		return {"ok": true, "msg": "Fahrzeugangebot %s bei %s: %s, Zustand %d %%, Preis %s, Kapazität %d, %s, Status %s." % [
			rid, sim.city.building(o.dealer).name, m.name, o.condition, Catalog.money(o.price), m.capacity,
			"Kühlung" if m.refrigerated else ("Schwerlast" if m.heavy else "Standard"), o.status]}
	if supplies.has(rid):
		var s: Dictionary = supplies[rid]
		return {"ok": true, "msg": "%s %s bei %s: Bestand %d, Preis %s je %s." % ["Treibstoff" if s.kind == "fuel" else "Ersatzteile",
			rid, sim.city.building(s.building).name, int(s.stock), Catalog.money(fuel_price(s) if s.kind == "fuel" else s.price),
			"Liter" if s.kind == "fuel" else "Stück"]}
	var w: Worker = sim.personnel.workers.get(rid)
	if w:
		if w.lost:
			return {"ok": true, "msg": "%s (%s) steht in dieser Partie nicht mehr zur Verfügung." % [w.name, rid]}
		if w.employer >= 0 and w.employer != cid:
			return {"ok": true, "msg": "%s arbeitet für %s (keine internen Daten)." % [w.name, sim.company(w.employer).company_name]}
		return {"ok": true, "msg": "%s %s (%s): %s, Lohn %.0f EUR/h, Anwerbung %s, Erfahrung %d, Zuverlässigkeit %d %%, Loyalität %d, Erschöpfung %d %%, Ort %s." % [
			"Vorarbeiter" if w.role == "foreman" else "Arbeiter", w.name, rid, w.skill_text(), w.wage, Catalog.money(w.hire_fee),
			int(w.experience), int(w.reliability * 100), int(w.loyalty), int(w.fatigue), str(w.tile())]}
	var k: Contract = sim.contracts.get(rid)
	if k:
		if not c.known.has(rid) and k.owner != cid:
			return {"ok": false, "msg": "Auftrag %s ist dir unbekannt (collect_contracts)." % rid}
		return {"ok": true, "msg": "Auftrag %s: %d × %s von %s nach %s, %s, Frist %s, %s, Status %s." % [rid, k.qty, k.cargo_name(),
			sim.city.building(k.pickup).name, sim.city.building(k.dropoff).name, Catalog.money(k.reward),
			Catalog.game_minutes_to_text(k.deadline), k.requirement_text(), k.status]}
	if rid.begins_with("D") and rid.substr(1).is_valid_int():
		var site := rid.substr(1).to_int()
		if site in sim.city.depot_sites:
			var owner: int = sim.depot_owner.get(site, -1)
			return {"ok": true, "msg": "Depotstandort %s (%s): %s, Miete %s/Tag, 4 Stellplätze." % [rid,
				Catalog.DISTRICTS[sim.city.building(site).district], "frei" if owner < 0 else "vermietet an " + sim.company(owner).company_name,
				Catalog.money(Catalog.EXTRA_DEPOT_RENT)]}
	return {"ok": false, "msg": "Unbekannte Ressourcen-ID %s." % rid}


func to_dict() -> Dictionary:
	return {"offers": offers, "supplies": supplies, "next_offer": next_offer, "fuel_price_factor": fuel_price_factor, "tanker_orders": tanker_orders}


func from_dict(d: Dictionary) -> void:
	offers = d.offers
	for o in offers.values():
		o.dealer = int(o.dealer)
	supplies = d.supplies
	for s in supplies.values():
		s.building = int(s.building)
	next_offer = int(d.next_offer)
	fuel_price_factor = float(d.get("fuel_price_factor", 1.0))
	tanker_orders = d.get("tanker_orders", [])
