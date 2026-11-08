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
const BACKGROUND_L_PER_DAY := 5000.0    # Verkauf an Haushalte (Privatfahrzeuge) in der ganzen Stadt je Spieltag, verteilt auf alle Tankstellen
const STATION_WAGE_PER_MONTH := 400.0   # Personal je Tankstelle
const OPERATOR_RESERVE := 80000.0       # darueber hinaus gehende Gewinne werden zur Haelfte ausgeschuettet

var sim
var offers := {}       # "F<n>" -> {id, dealer, model, price, condition, status}
var supplies := {}     # "S<n>" -> {id, kind (fuel|parts), building, stock, max, price, regen}
var next_offer := 1
var tanker_orders: Array = []          # {station, qty, due, cost}
var fuel_deliveries: Array = []        # Tankwagenlieferung an ein Depot: {cid, liters, due}
var fuel_shipments := {}               # "F<n>" -> {cid, liters}: eigener Transportauftrag Tankstelle -> Depot
var _next_fuel_ship := 1
const TANKER_FEE := 40.0               # Lieferung durch den Tankwagen: Grundgebuehr + je Liter
const TANKER_PER_LITER := 0.04
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
## Treibstoff (Liter) wird an der Tankstelle gezapft und bezahlt, danach zum Depot gebracht: per Tankwagen der Tankstelle (lieferung "liefern",
## Gebuehr) oder per eigenem Transportauftrag Tankstelle -> Depot (lieferung "abholen", ein Fahrzeug muss fahren). Erst bei Ankunft steigt der
## Vorrat im Depot. Ersatzteile werden sofort uebernommen.
func buy_supplies(cid: int, sid: String, amount: float, mode: String = "liefern") -> Dictionary:
	var s: Dictionary = supplies.get(sid, {})
	if mode not in ["liefern", "abholen"]:
		return {"ok": false, "msg": "Lieferart muss liefern oder abholen sein."}
	if s.is_empty():
		return {"ok": false, "msg": "Unbekannte Bezugsquelle %s." % sid}
	if not is_finite(amount):
		return {"ok": false, "msg": "Menge muss endlich sein."}
	amount = floorf(amount)
	if amount <= 0.0:
		return {"ok": false, "msg": "Menge muss positiv sein."}
	if amount > float(s.stock):
		return {"ok": false, "msg": "Nur noch %d %s vorrätig." % [int(s.stock), "Liter" if s.kind == "fuel" else "Ersatzteile"]}
	var unit: float = fuel_price(s) if s.kind == "fuel" else float(s.price)
	var cost := unit * amount
	var c: Company = sim.company(cid)
	var fee_pre := (TANKER_FEE + TANKER_PER_LITER * amount) if (s.kind == "fuel" and mode != "abholen") else 0.0
	if c.ledger.cash < cost + fee_pre:
		return {"ok": false, "msg": "Nicht genug Bargeld (%s inkl. %s Tankwagen)." % [Catalog.money(cost + fee_pre), Catalog.money(fee_pre)]}
	if s.kind == "fuel" and c.fuel + pending_fuel(cid) + amount > c.fuel_cap:
		return {"ok": false, "msg": "Tank fasst nur %d l (Vorrat %d l, unterwegs %d l)." % [int(c.fuel_cap), int(c.fuel), int(pending_fuel(cid))]}
	s.stock = float(s.stock) - amount
	c.ledger.book("supplies", -cost, true, "%s %d × %s" % ["Treibstoff" if s.kind == "fuel" else "Ersatzteile", int(amount),
		sim.city.building(s.building).name], sim.game_min, "G0" if s.kind == "fuel" else "S0")
	if s.kind == "fuel":
		var wait: float = _use_pump(s, amount)
		s.sales_l = float(s.sales_l) + amount
		s.revenue = float(s.revenue) + cost
		s.customers = int(s.customers) + 1
		var ready: float = sim.game_min + wait + amount / PUMP_LITERS_PER_MIN
		var wait_txt := (" Wartezeit an der Zapfsäule: %d min." % int(ceil(wait))) if wait > 0.5 else ""
		var depot: Dictionary = sim.city.building(c.depots[0])
		var here: Dictionary = sim.city.building(s.building)
		var dist := absi(depot.road.x - here.road.x) + absi(depot.road.y - here.road.y)
		if mode == "abholen":
			var fid := "F%d" % _next_fuel_ship
			_next_fuel_ship += 1
			fuel_shipments[fid] = {"cid": cid, "generation": c.generation, "liters": amount, "ready": ready}
			var k := _fuel_contract(c, s, fid, amount, dist)
			return {"ok": true, "msg": "%d l Diesel gezapft und bezahlt (%s).%s Transportauftrag %s (Tankstelle → Depot) angelegt: ein Fahrzeug muss den Treibstoff holen, erst dann steigt dein Vorrat (jetzt %d l, unterwegs %d l)." % [
				int(amount), Catalog.money(cost), wait_txt, k.id, int(c.fuel), int(pending_fuel(cid))]}
		var fee := TANKER_FEE + TANKER_PER_LITER * amount
		c.ledger.book("supplies", -fee, true, "Tankwagen-Lieferung", sim.game_min, "S0")
		var due: float = ready + 45.0 + 0.5 * dist
		fuel_deliveries.append({"cid": cid, "generation": c.generation, "liters": amount, "due": due})
		return {"ok": true, "msg": "%d l Diesel gezapft und bezahlt (%s + Tankwagen %s).%s Ankunft am Depot in etwa %d min; Vorrat jetzt %d l, unterwegs %d l." % [
			int(amount), Catalog.money(cost), Catalog.money(fee), wait_txt, int(due - sim.game_min), int(c.fuel), int(pending_fuel(cid))]}
	c.parts += int(amount)
	return {"ok": true, "msg": "%d Ersatzteile gekauft für %s (Vorrat: %d Ersatzteile)." % [int(amount), Catalog.money(cost), c.parts]}


## Liter, die bezahlt sind und noch zum Depot unterwegs sind.
func pending_fuel(cid: int) -> float:
	var t := 0.0
	for d in fuel_deliveries:
		if d.cid == cid and int(d.get("generation", sim.company(cid).generation)) == sim.company(cid).generation:
			t += float(d.liters)
	for f in fuel_shipments.values():
		if f.cid == cid and int(f.get("generation", sim.company(cid).generation)) == sim.company(cid).generation:
			t += float(f.liters)
	return t


## Interner Transportauftrag Tankstelle -> Depot (kein Umsatz); beim Abliefern wird der Vorrat erhoeht.
func _fuel_contract(c: Company, s: Dictionary, fid: String, liters: float, dist: int) -> Contract:
	var k := Contract.new()
	k.id = "A%d" % sim.market.next_id
	sim.market.next_id += 1
	k.pickup = int(s.building)
	k.dropoff = int(c.depots[0])
	k.cargo = "getraenke" if not Catalog.CARGO.has("treibstoff") else "treibstoff"
	k.label = "Diesel (%d l) von der Tankstelle" % int(liters)
	k.qty = maxi(1, int(ceil(liters / 250.0)))
	k.reward = 0.0
	k.internal = fid
	k.owner = c.id
	k.status = "accepted"
	k.created = sim.game_min
	k.accepted_at = sim.game_min
	k.deadline = sim.game_min + 99999.0
	k.offer_until = k.deadline
	k.distance = dist
	sim.contracts[k.id] = k
	c.known[k.id] = true
	return k


## Transport kam an: Vorrat im Depot erhoehen. Gibt true zurueck, wenn es ein Treibstofftransport war.
func fuel_delivered(fid: String) -> bool:
	var f: Dictionary = fuel_shipments.get(fid, {})
	if f.is_empty():
		return false
	var c: Company = sim.company(int(f.cid))
	if int(f.get("generation", c.generation)) == c.generation and c.is_active():
		c.fuel = minf(c.fuel_cap, c.fuel + float(f.liters))
	fuel_shipments.erase(fid)
	sim.notify(c.id, "%d l Diesel sind im Depot angekommen (Vorrat %d l)." % [int(f.liters), int(c.fuel)])
	return true


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
	var stations := supplies.values().filter(func(x): return x.kind == "fuel").size()
	for sid in supplies:
		var s: Dictionary = supplies[sid]
		if s.kind != "fuel":
			continue
		gas += 1
		var sold := minf(BACKGROUND_L_PER_DAY / maxf(float(stations), 1.0), float(s.stock))
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
	# Ausschuettung an die Betreiber (Haushalte), soweit das Konto die Reserve ueberschreitet
	var excess: float = float(sim.economy.accounts.G0) - OPERATOR_RESERVE
	if excess > 0.0:
		sim.economy.transfer("G0", "H0", excess * 0.5)


func minute_tick(now: float) -> void:
	for d in fuel_deliveries.duplicate():
		if now >= float(d.due):
			fuel_deliveries.erase(d)
			var fc: Company = sim.company(int(d.cid))
			if int(d.get("generation", fc.generation)) != fc.generation or not fc.is_active():
				continue
			fc.fuel = minf(fc.fuel_cap, fc.fuel + float(d.liters))
			sim.notify(fc.id, "Der Tankwagen hat %d l Diesel am Depot geliefert (Vorrat %d l)." % [int(d.liters), int(fc.fuel)])
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
	return {"offers": offers, "supplies": supplies, "next_offer": next_offer, "fuel_price_factor": fuel_price_factor, "tanker_orders": tanker_orders,
		"fuel_deliveries": fuel_deliveries, "fuel_shipments": fuel_shipments, "next_fuel_ship": _next_fuel_ship}


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
	fuel_deliveries = d.get("fuel_deliveries", [])
	for fd in fuel_deliveries:
		fd.cid = int(fd.cid)
	fuel_shipments = d.get("fuel_shipments", {})
	for fk in fuel_shipments:
		fuel_shipments[fk].cid = int(fuel_shipments[fk].cid)
	_next_fuel_ship = int(d.get("next_fuel_ship", 1))
