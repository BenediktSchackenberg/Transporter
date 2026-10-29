class_name Trader
extends RefCounted
## Grosshaendler "Bauhof" (Konto T0): importiert Material aus dem Ausland (X0), produziert, verkauft an Firmen, exportiert Ueberschuesse
## (docs/ECONOMY.md Abschnitte 8-10). Regelbasiert. Alle Waren stehen im StockBook mit Eigentuemer und Standort.

const MATERIALS := {
	"holz": {"name": "Holz", "base": 18.0, "target": 260, "min": 80, "max": 500, "lead": 3},
	"stahl": {"name": "Stahl", "base": 55.0, "target": 160, "min": 50, "max": 320, "lead": 4},
	"ziegel": {"name": "Ziegel", "base": 12.0, "target": 520, "min": 160, "max": 900, "lead": 3},
	"beton": {"name": "Betonbauteile", "base": 40.0, "target": 360, "min": 110, "max": 640, "lead": 0},
	"glas": {"name": "Glas", "base": 35.0, "target": 90, "min": 30, "max": 180, "lead": 4},
	"installation": {"name": "Installationsmaterial", "base": 45.0, "target": 90, "min": 30, "max": 180, "lead": 4},
	"werkzeug": {"name": "Werkzeug", "base": 60.0, "target": 40, "min": 12, "max": 80, "lead": 5},
	"module": {"name": "Gebäudemodule", "base": 320.0, "target": 24, "min": 4, "max": 48, "lead": 0},
	"paletten": {"name": "Paletten", "base": 14.0, "target": 120, "min": 30, "max": 240, "lead": 0},
	"verbindung": {"name": "Verbindungsmaterial", "base": 6.0, "target": 300, "min": 100, "max": 600, "lead": 2},
	"rohmaterial": {"name": "Rohmaterial", "base": 9.0, "target": 600, "min": 200, "max": 1000, "lead": 2},
	"altmaterial": {"name": "Altmaterial", "base": 4.0, "target": 0, "min": 0, "max": 400, "lead": 0},
	"sekundaer": {"name": "Sekundärrohstoff", "base": 11.0, "target": 60, "min": 0, "max": 400, "lead": 0},
}
## Bestellbar im Ausland (Import). Beton, Module, Paletten und Sekundaerrohstoff stammen aus eigener Produktion.
const IMPORTED := ["holz", "stahl", "ziegel", "glas", "installation", "werkzeug", "verbindung", "rohmaterial"]
## Stueckliste je Material-Einheit einer Baustelle (Estate.FACILITIES[..].mat)
const BOM_UNIT := {"ziegel": 3, "beton": 2, "holz": 2, "verbindung": 1}
const PLANTS := {
	"palettenwerk": {"name": "Palettenwerk", "in": {"holz": 2, "verbindung": 1}, "out": {"paletten": 2}, "cycles": 10},
	"betonwerk": {"name": "Betonwerk", "in": {"rohmaterial": 3}, "out": {"beton": 2}, "cycles": 14},
	"modulwerk": {"name": "Modulwerk", "in": {"stahl": 2, "beton": 2}, "out": {"module": 1}, "cycles": 4},
	"recycling": {"name": "Recycling", "in": {"altmaterial": 3}, "out": {"sekundaer": 2}, "cycles": 12},
}
const MARGIN := 0.18
const IMPORT_FACTOR := 0.8        # Einkaufspreis im Ausland (Anteil Basispreis)
const EXPORT_FACTOR := 0.75
const BUYBACK_FACTOR := 0.5       # Ankauf von Firmen (Anteil Basispreis)
const DELIVERY_FEE := 30.0        # Lieferung frei Depot: Grundgebuehr + je Einheit
const DELIVERY_PER_UNIT := 0.15
const STAFF := 8
const WAGE_PER_MONTH := 2400.0
const PLANT_ENERGY := 25.0        # EUR je Produktionszyklus (an S0)

var sim: Simulation
var bauhof := -1                  # Gebaeude-ID des Bauhofs
var orders: Array = []            # {id, item, qty, due, cost}
var shipments := {}               # "S<n>" -> {cid, items: {item: qty}, to_loc}   (Abholung per Transportauftrag)
var deliveries: Array = []        # {cid, items, to_loc, due}                      (Lieferung frei Depot)
var produced := {}                # Anlage -> Zyklen
var stats := {"sales": 0.0, "imports": 0.0, "exports": 0.0, "wages": 0.0, "energy": 0.0, "buyback": 0.0}
var _next_order := 1
var _next_ship := 1


func setup(s: Simulation) -> void:
	sim = s
	s.day_changed.connect(on_day)
	s.month_changed.connect(on_month)
	var center := Vector2(s.city.size, s.city.size) * 0.5
	var best_d := INF
	for b in s.city.buildings:
		if b.role != "plot" and "baustoffe" in b.out:
			var d := Vector2(b.x, b.y).distance_to(center)
			if d < best_d:
				best_d = d
				bauhof = b.id
	if bauhof >= 0:
		s.city.buildings[bauhof].name = "Bauhof (Großhandel)"
		for it in MATERIALS:
			var t: int = MATERIALS[it].target
			if t > 0 and it not in ["beton", "module", "paletten", "sekundaer", "altmaterial"]:
				s.stock.add(it, t, "T0", bauhof, "Anfangsbestand")
		for it in ["beton", "paletten"]:
			s.stock.add(it, int(MATERIALS[it].target * 0.6), "T0", bauhof, "Anfangsbestand")
		s.stock.add("module", 10, "T0", bauhof, "Anfangsbestand")


func cash() -> float:
	return sim.economy.accounts.T0


func stock_of(item: String) -> int:
	return sim.stock.available(item, "T0", bauhof)


## Verkaufspreis je Einheit: Basis x (1 + Marge) x Bestandsfaktor, Mengenrabatt ab 50 (-5 %) und 200 (-10 %).
func price(item: String, amount: int = 1) -> float:
	var m: Dictionary = MATERIALS[item]
	var target: float = maxf(float(m.target), 1.0)
	var ratio := float(stock_of(item)) / target
	var factor := clampf(1.4 - 0.4 * ratio, 0.9, 1.4)
	var discount := 0.9 if amount >= 200 else (0.95 if amount >= 50 else 1.0)
	return snappedf(float(m.base) * (1.0 + MARGIN) * factor * discount, 0.01)


## Stueckliste einer Baustelle mit n Material-Einheiten.
static func bom(units: int) -> Dictionary:
	var out := {}
	for it in BOM_UNIT:
		out[it] = int(BOM_UNIT[it]) * units
	return out


func nominal_value(items: Dictionary) -> float:
	var v := 0.0
	for it in items:
		v += price(it, int(items[it])) * int(items[it])
	return v


# ------------------------------------------------------------------ Verkauf
## Material an eine Firma verkaufen. mode: "abholen" (Transportauftrag Bauhof -> Depot) oder "liefern" (frei Depot gegen Gebuehr).
## Das Eigentum geht sofort auf die Firma ueber; die Ware liegt zunaechst noch am Bauhof.
func sell(cid: int, items: Dictionary, mode: String, to_loc: int, note: String = "Material") -> Dictionary:
	var c := sim.company(cid)
	if not c.is_active():
		return {"ok": false, "msg": "Unternehmen unter Insolvenzverwaltung."}
	var cost := 0.0
	for it in items:
		if not MATERIALS.has(it):
			return {"ok": false, "msg": "Unbekanntes Material %s." % it}
		if int(items[it]) <= 0:
			return {"ok": false, "msg": "Menge muss positiv sein."}
		if stock_of(it) < int(items[it]):
			return {"ok": false, "msg": "Bauhof hat nur %d × %s vorrätig (benötigt %d). Nachschub folgt." % [stock_of(it), MATERIALS[it].name, int(items[it])]}
		cost += price(it, int(items[it])) * int(items[it])
	var fee := 0.0
	var units := 0
	for it in items:
		units += int(items[it])
	if mode == "liefern":
		fee = DELIVERY_FEE + DELIVERY_PER_UNIT * units
	if c.ledger.cash < cost + fee:
		return {"ok": false, "msg": "Nicht genug Bargeld: %s (Material %s + Lieferung %s)." % [Catalog.money(cost + fee), Catalog.money(cost), Catalog.money(fee)]}
	for it in items:
		sim.stock.move(it, int(items[it]), "T0", bauhof, "C%d" % cid, bauhof, "Handel (%s)" % note, sim.game_min)
	c.ledger.book("supplies", -cost, true, "%s vom Bauhof" % note, sim.game_min, "T0")
	stats.sales += cost
	if fee > 0.0:
		c.ledger.book("supplies", -fee, true, "Lieferung frei Depot", sim.game_min, "S0")
		var days := 1.0 + float(absi(sim.city.building(to_loc).road.x - sim.city.building(bauhof).road.x) + absi(sim.city.building(to_loc).road.y - sim.city.building(bauhof).road.y)) / 60.0
		deliveries.append({"cid": cid, "items": items.duplicate(), "to_loc": to_loc, "due": sim.game_min + GameCalendar.days_to_min(days)})
	return {"ok": true, "cost": cost, "fee": fee, "msg": "%s gekauft (%s%s)." % [_items_text(items), Catalog.money(cost), (" + Lieferung " + Catalog.money(fee)) if fee > 0.0 else ""]}


## Transportauftrag Bauhof -> Zielgebaeude (kein Umsatz, Ware gehoert bereits der Firma). Gibt die Auftrags-ID zurueck.
func make_shipment(cid: int, items: Dictionary, to_loc: int, internal: String = "", qty: int = 0) -> String:
	var plot_b: Dictionary = sim.city.building(to_loc)
	var src: Dictionary = sim.city.building(bauhof)
	var units := 0
	for it in items:
		units += int(items[it])
	var k := Contract.new()
	k.id = "A%d" % sim.market.next_id
	sim.market.next_id += 1
	k.pickup = bauhof
	k.dropoff = to_loc
	k.cargo = "baustoffe"
	k.label = "Material vom Bauhof (%s)" % _items_text(items)
	k.qty = qty if qty > 0 else maxi(1, int(ceil(units / 20.0)))
	k.reward = 0.0
	var sid := internal
	if sid == "":
		sid = "S%d" % _next_ship
		_next_ship += 1
	k.internal = sid
	k.owner = cid
	k.status = "accepted"
	k.created = sim.game_min
	k.accepted_at = sim.game_min
	k.deadline = sim.game_min + 99999.0
	k.offer_until = k.deadline
	k.distance = absi(src.road.x - plot_b.road.x) + absi(src.road.y - plot_b.road.y)
	sim.contracts[k.id] = k
	sim.company(cid).known[k.id] = true
	shipments[sid] = {"cid": cid, "items": items.duplicate(), "to_loc": to_loc, "contract": k.id}
	return k.id


## Transport kam an: Ware vom Bauhof an den Zielort verschieben. Gibt true zurueck, wenn es ein Handelstransport war.
func shipment_delivered(sid: String) -> bool:
	var s: Dictionary = shipments.get(sid, {})
	if s.is_empty():
		return false
	for it in s.items:
		sim.stock.move(it, int(s.items[it]), "C%d" % s.cid, bauhof, "C%d" % s.cid, int(s.to_loc), "Transport zum Depot", sim.game_min)
	shipments.erase(sid)
	sim.notify(s.cid, "Material (%s) ist am Ziel angekommen." % _items_text(s.items))
	return true


## Baustelle kauft fehlendes Material: Eigentum geht vom Bauhof auf die Firma ueber (Ware bleibt am Bauhof). Bezahlt wird im Aufrufer.
func transfer_for_build(cid: int, items: Dictionary, paid: float) -> void:
	for it in items:
		if int(items[it]) > 0:
			sim.stock.move(it, int(items[it]), "T0", bauhof, "C%d" % cid, bauhof, "Handel (Baustelle)", sim.game_min)
	stats.sales += paid


## Ankauf von Material einer Firma (Altmaterial, Ueberbestand). Zahlung aus dem Bargeld des Bauhofs.
func buy_back(cid: int, item: String, amount: int, loc: int) -> Dictionary:
	if not MATERIALS.has(item):
		return {"ok": false, "msg": "Unbekanntes Material."}
	var have := sim.stock.qty(item, "C%d" % cid, loc)
	amount = mini(amount, have)
	if amount <= 0:
		return {"ok": false, "msg": "Dort liegt kein %s von dir." % MATERIALS[item].name}
	var factor := 1.0 if item == "altmaterial" else BUYBACK_FACTOR
	var pay := snappedf(float(MATERIALS[item].base) * factor * amount, 0.01)
	if cash() < pay:
		return {"ok": false, "msg": "Der Bauhof hat gerade nicht genug Bargeld."}
	sim.stock.move(item, amount, "C%d" % cid, loc, "T0", bauhof, "Ankauf durch den Bauhof", sim.game_min)
	sim.company(cid).ledger.book("supplies", pay, true, "Verkauf %d × %s an den Bauhof" % [amount, MATERIALS[item].name], sim.game_min, "T0")
	stats.buyback += pay
	return {"ok": true, "msg": "%d × %s an den Bauhof verkauft (%s)." % [amount, MATERIALS[item].name, Catalog.money(pay)]}


## Nach einer Insolvenz: Material der Masse wird zum Ankaufspreis uebernommen (soweit der Bauhof zahlen kann), Rest verfaellt.
func liquidate_stock(cid: int) -> float:
	var total := 0.0
	for l in sim.stock.of_owner("C%d" % cid):
		var item: String = l.item
		var amount: int = int(l.qty)
		var pay := snappedf(float(MATERIALS[item].base) * 0.4 * amount, 0.01)
		if cash() >= pay:
			sim.stock.move(item, amount, "C%d" % cid, int(l.loc), "T0", bauhof, "Insolvenzmasse", sim.game_min)
			sim.company(cid).ledger.book("supplies", pay, true, "Materialverwertung", sim.game_min, "T0")
			total += pay
		else:
			sim.stock.consume(item, amount, "C%d" % cid, int(l.loc), "Verfall (Insolvenz)", sim.game_min)
	return total


func _items_text(items: Dictionary) -> String:
	var parts: Array = []
	for it in items:
		parts.append("%d × %s" % [int(items[it]), MATERIALS[it].name])
	return ", ".join(parts)


# ------------------------------------------------------------------ Tagesablauf
func on_day(_day: int) -> void:
	if bauhof < 0:
		return
	var now := sim.game_min
	# Lieferungen frei Depot
	for d in deliveries.duplicate():
		if now >= float(d.due):
			for it in d.items:
				sim.stock.move(it, int(d.items[it]), "C%d" % d.cid, bauhof, "C%d" % d.cid, int(d.to_loc), "Lieferung des Bauhofs", now)
			sim.notify(d.cid, "Der Bauhof hat geliefert: %s." % _items_text(d.items))
			deliveries.erase(d)
	# Importlieferungen
	for o in orders.duplicate():
		if now >= float(o.due):
			sim.stock.add(o.item, int(o.qty), "T0", bauhof, "Import", now)
			orders.erase(o)
	# Produktion
	for pid in PLANTS:
		_produce(pid)
	# Nachbestellung (Meldebestand), Export von Ueberschuessen
	for it in IMPORTED:
		var m: Dictionary = MATERIALS[it]
		var pending := 0
		for o in orders:
			if o.item == it:
				pending += int(o.qty)
		if stock_of(it) + pending < int(m.min) + (int(m.target) - int(m.min)) / 3:   # Meldebestand
			var want: int = int(m.target) - stock_of(it) - pending
			var unit := float(m.base) * IMPORT_FACTOR
			var afford := int(floor(maxf(0.0, cash() - 20000.0) / unit))   # Barreserve bleibt
			var qty := mini(want, afford)
			if qty > 0:
				var cost := unit * qty
				sim.economy.transfer("T0", "X0", cost)
				stats.imports += cost
				orders.append({"id": "I%d" % _next_order, "item": it, "qty": qty, "due": now + GameCalendar.days_to_min(float(m.lead)), "cost": cost})
				_next_order += 1
	for it in MATERIALS:
		var m2: Dictionary = MATERIALS[it]
		var over := stock_of(it) - int(m2.max)
		if over > 0:
			var qty2 := int(ceil(over * 0.5))
			sim.stock.consume(it, qty2, "T0", bauhof, "Export", now)
			var rev := float(m2.base) * EXPORT_FACTOR * qty2
			sim.economy.transfer("X0", "T0", rev)
			stats.exports += rev


func _produce(pid: String) -> void:
	var p: Dictionary = PLANTS[pid]
	var runs := 0
	for i in int(p.cycles):
		var ok := true
		for it in p["in"]:
			if stock_of(it) < int(p["in"][it]):
				ok = false
		# nur produzieren, solange der Zielbestand des Ausgangs nicht erreicht ist (keine Ueberproduktion auf Vorrat)
		for it in p.out:
			if stock_of(it) >= int(MATERIALS[it].target):
				ok = false
		if not ok or cash() < PLANT_ENERGY:
			break
		for it in p["in"]:
			sim.stock.consume(it, int(p["in"][it]), "T0", bauhof, "Produktion %s" % p.name, sim.game_min)
		for it in p.out:
			sim.stock.add(it, int(p.out[it]), "T0", bauhof, "Produktion %s" % p.name, sim.game_min)
		sim.economy.transfer("T0", "S0", PLANT_ENERGY)
		stats.energy += PLANT_ENERGY
		runs += 1
	produced[pid] = int(produced.get(pid, 0)) + runs


func on_month(_month: int) -> void:
	var wages := minf(WAGE_PER_MONTH * STAFF, maxf(0.0, cash()))
	sim.economy.transfer("T0", "H0", wages)
	stats.wages += wages
	var excess: float = cash() - 150000.0   # Gewinne ueber der Reserve gehen zur Haelfte an die Eigentuemer (Haushalte)
	if excess > 0.0:
		sim.economy.transfer("T0", "H0", excess * 0.5)


# ------------------------------------------------------------------ Anzeige
func summary() -> Dictionary:
	var prices := {}
	for it in MATERIALS:
		prices[it] = {"preis": price(it), "bestand": stock_of(it)}
	return {"bauhof_id": bauhof, "preise": prices}


func to_dict() -> Dictionary:
	return {"bauhof": bauhof, "orders": orders, "shipments": shipments, "deliveries": deliveries, "produced": produced, "stats": stats,
		"next_order": _next_order, "next_ship": _next_ship}


func from_dict(d: Dictionary) -> void:
	bauhof = int(d.get("bauhof", bauhof))
	orders = d.get("orders", [])
	for o in orders:
		o.qty = int(o.qty)
	shipments = d.get("shipments", {})
	for k in shipments:
		shipments[k].cid = int(shipments[k].cid)
		shipments[k].to_loc = int(shipments[k].to_loc)
		for it in shipments[k].items:
			shipments[k].items[it] = int(shipments[k].items[it])
	deliveries = d.get("deliveries", [])
	for dl in deliveries:
		dl.cid = int(dl.cid)
		dl.to_loc = int(dl.to_loc)
		for it in dl.items:
			dl.items[it] = int(dl.items[it])
	produced = d.get("produced", {})
	stats = d.get("stats", stats)
	_next_order = int(d.get("next_order", 1))
	_next_ship = int(d.get("next_ship", 1))
