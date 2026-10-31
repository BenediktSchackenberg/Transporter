class_name Retail
extends RefCounted
## Restaurants und Geschaefte des Alltags (Auftrag 5, Abschnitte 9-11). Jeder Betrieb hat ein eigenes Geschaeftskonto ("R<n>" in der Economy),
## einen eigenen Bestand im StockBook (Eigentuemer = Konto, Standort = Gebaeude), Personal, Miete und Preise.
##
## Warenkette: Produzent (F0) -> Lebensmittelgrosshandel (W0, Lager im Grosshandelsgebaeude) -> Betriebslager -> Kueche/Verkaufsflaeche -> Haushalt (H0).
## Nachschub entsteht aus dem Bestand: Unterschreitet Bestand + Bestelltes den Meldebestand, reserviert der Betrieb Ware beim Grosshandel und schreibt einen
## echten Transportauftrag aus (Zahler = Betriebskonto); jedes Transportunternehmen kann ihn uebernehmen, sonst faehrt der Lieferdienst des Grosshandels.
## Die Ware wird bei der Anlieferung bezahlt. Verkauf: Haushalt zahlt an der Kasse (H0 -> Betriebskonto), der Bestand sinkt. Fehlt eine Zutat,
## entfaellt das Gericht, fehlt eine Ware, bleibt das Regal leer (entgangener Umsatz wird gezaehlt). Verderbliches verdirbt (Verlust, kein Umsatz).
## Mehrweg: Flaschen tragen Pfand; Leergut geht mit dem naechsten Lieferwagen zurueck (keine Leerfahrt), der Grosshandel fuellt wieder auf.

const WHOLESALER := "W0"
const PRODUCER := "F0"
const FREIGHT_BASE := 18.0
const OFFER_DAYS := 1                # so lange wartet ein Transportauftrag auf ein Unternehmen
const STOCK_DAYS := 10               # Zielbestand in Tagesverbrauch
const REORDER_DAYS := 4              # Meldebestand in Tagesverbrauch
const WHOLESALE_MARKUP := 1.3        # Aufschlag des Grosshandels auf den Einkaufspreis beim Produzenten
const PFAND := 0.25
const RETURN_SHARE := 0.3            # Anteil des ausstehenden Leerguts, der taeglich zurueckkommt
const REFILL_COST := 0.4             # Wiederbefuellen kostet so viel wie dieser Anteil des Neupreises
const SPOIL_RATE := 0.08             # Anteil verderblicher Ware, der taeglich verdirbt
const MAX_PER_KIND := {"restaurant": 5, "baeckerei": 2, "lebensmittel": 2, "getraenke": 1, "drogerie": 1, "moebel": 1, "technik": 1, "baumarkt": 1}
const START_CAPITAL := 7000.0
const WHOLESALER_CAPITAL := 25000.0
const POP_REFERENCE := 1200.0

## Artikel: Name, Einheit, Einkaufspreis (Grosshandel), Verkaufspreis, Haltbarkeit in Tagen (0 = unbegrenzt), Ladung, Korbgroesse, Pfand
const GOODS := {
	"gemuese": {"name": "Gemüse", "unit": "Port.", "cost": 1.2, "price": 0.0, "shelf": 5, "cargo": "lebensmittel"},
	"fleisch": {"name": "Fleisch", "unit": "Port.", "cost": 3.6, "price": 0.0, "shelf": 4, "cargo": "lebensmittel"},
	"teigwaren": {"name": "Nudeln und Reis", "unit": "Port.", "cost": 0.6, "price": 0.0, "shelf": 0, "cargo": "lebensmittel"},
	"milch_zutat": {"name": "Milchprodukte", "unit": "Port.", "cost": 1.0, "price": 0.0, "shelf": 6, "cargo": "lebensmittel"},
	"fassgetraenk": {"name": "Fassgetränke", "unit": "Port.", "cost": 0.7, "price": 0.0, "shelf": 0, "cargo": "getraenke"},
	"brot": {"name": "Brot und Brötchen", "unit": "Stk", "cost": 0.9, "price": 2.2, "shelf": 3, "cargo": "pakete", "basket": 4},
	"obst": {"name": "Obst und Gemüse", "unit": "kg", "cost": 1.4, "price": 3.0, "shelf": 5, "cargo": "lebensmittel", "basket": 3},
	"milch": {"name": "Milch und Käse", "unit": "Stk", "cost": 0.9, "price": 1.9, "shelf": 6, "cargo": "lebensmittel", "basket": 3},
	"konserve": {"name": "Konserven", "unit": "Stk", "cost": 0.8, "price": 1.9, "shelf": 0, "cargo": "pakete", "basket": 4},
	"flasche": {"name": "Mehrwegflaschen", "unit": "Fl.", "cost": 0.6, "price": 1.5, "shelf": 0, "cargo": "getraenke", "basket": 6, "pfand": true},
	"hygiene": {"name": "Drogerieartikel", "unit": "Stk", "cost": 1.6, "price": 3.8, "shelf": 0, "cargo": "pakete", "basket": 3},
	"haushalt": {"name": "Haushaltswaren", "unit": "Stk", "cost": 6.0, "price": 14.0, "shelf": 0, "cargo": "pakete", "basket": 2},
	"werkzeug": {"name": "Werkzeug", "unit": "Stk", "cost": 9.0, "price": 21.0, "shelf": 0, "cargo": "baustoffe", "basket": 2},
	"farbe": {"name": "Farbe", "unit": "Eimer", "cost": 14.0, "price": 29.0, "shelf": 0, "cargo": "baustoffe", "basket": 2},
	"moebelstueck": {"name": "Möbel", "unit": "Stk", "cost": 90.0, "price": 190.0, "shelf": 0, "cargo": "moebel", "basket": 1},
	"elektrogeraet": {"name": "Elektrogeräte", "unit": "Stk", "cost": 48.0, "price": 105.0, "shelf": 0, "cargo": "elektronik", "basket": 1},
	"leergut": {"name": "Leergut", "unit": "Fl.", "cost": 0.0, "price": 0.0, "shelf": 0, "cargo": "getraenke"},
}
## Gerichte: Name, Zutaten (je Portion), Preis
const DISHES := {
	"gemuesepfanne": {"name": "Gemüsepfanne", "uses": {"gemuese": 1, "teigwaren": 1}, "price": 9.5},
	"nudelgericht": {"name": "Nudeln mit Sauce", "uses": {"teigwaren": 1, "milch_zutat": 1, "gemuese": 1}, "price": 10.5},
	"braten": {"name": "Braten mit Gemüse", "uses": {"fleisch": 1, "gemuese": 1}, "price": 16.5},
	"getraenk": {"name": "Getränk vom Fass", "uses": {"fassgetraenk": 1}, "price": 3.5},
}
## Betriebsarten: Anzeigename, Kundschaft je Tag bei Referenzbevoelkerung, Personal, Miete je Monat, Sortiment
const KINDS := {
	"restaurant": {"label": "Restaurant", "base": 38, "staff": 3, "rent": 1100.0, "goods": ["gemuese", "fleisch", "teigwaren", "milch_zutat", "fassgetraenk"], "dishes": ["gemuesepfanne", "nudelgericht", "braten", "getraenk"]},
	"baeckerei": {"label": "Bäckerei", "base": 60, "staff": 2, "rent": 800.0, "goods": ["brot"]},
	"lebensmittel": {"label": "Lebensmittelgeschäft", "base": 80, "staff": 2, "rent": 1200.0, "goods": ["brot", "obst", "milch", "konserve", "flasche"]},
	"getraenke": {"label": "Getränkemarkt", "base": 40, "staff": 2, "rent": 900.0, "goods": ["flasche", "konserve"]},
	"drogerie": {"label": "Drogerie", "base": 36, "staff": 2, "rent": 900.0, "goods": ["hygiene", "haushalt"]},
	"baumarkt": {"label": "Baumarkt", "base": 20, "staff": 3, "rent": 1500.0, "goods": ["werkzeug", "farbe", "haushalt"]},
	"moebel": {"label": "Möbelgeschäft", "base": 4, "staff": 2, "rent": 1400.0, "goods": ["moebelstueck"]},
	"technik": {"label": "Technikgeschäft", "base": 8, "staff": 2, "rent": 1000.0, "goods": ["elektrogeraet"]},
}
## Zuordnung der Geschaefte nach Namen im Stadtplan
const SHOP_KIND := {"Bäckerei": "baeckerei", "Supermarkt": "lebensmittel", "Kiosk": "lebensmittel", "Getränkemarkt": "getraenke", "Möbelhaus": "moebel",
	"Elektro": "technik", "Technik": "technik", "Baumarkt": "baumarkt"}

var sim: Simulation
var shops := {}                      # Konto -> Betrieb
var wholesale_building := -1
var orders := {}                     # "RO<n>" -> Nachschubbestellung
var stats := {"sales": 0.0, "units": 0, "lost": 0, "orders": 0, "delivered": 0, "fallback": 0, "spoiled": 0, "bottles_reused": 0, "bottles_returned": 0, "bottles_sold": 0, "freight": 0.0, "wholesale_buys": 0.0}
var month_sales := 0.0               # Kassenumsatz im laufenden Monat (mindert den pauschalen Konsum, siehe Citizens)
var _next_order := 1
var _day := 0


func setup(s: Simulation) -> void:
	sim = s
	s.day_changed.connect(on_day)
	s.month_changed.connect(on_month)
	for acct in [WHOLESALER, PRODUCER]:
		if not s.economy.accounts.has(acct):
			s.economy.accounts[acct] = 0.0
	wholesale_building = _pick_wholesale()
	var per_kind := {}
	for b in s.city.buildings:
		if b.role == "plot":
			continue
		var kind := ""
		if b.type == "restaurant":
			kind = "restaurant"
		elif b.type == "pharmacy":
			kind = "drogerie"
		elif b.type == "shop":
			kind = str(SHOP_KIND.get(str(b.name).split(" ")[0], ""))
		if kind != "" and int(per_kind.get(kind, 0)) < int(MAX_PER_KIND[kind]):
			per_kind[kind] = int(per_kind.get(kind, 0)) + 1
			_open_shop(b, kind)
	s.economy.transfer("I0", WHOLESALER, WHOLESALER_CAPITAL)
	_stock_wholesale(0)


func _pick_wholesale() -> int:
	for b in sim.city.buildings:
		if b.role != "plot" and b.type == "warehouse" and b.id != sim.city_depot.building and b.id != sim.trader.bauhof:
			return b.id
	return sim.trader.bauhof


func _open_shop(b: Dictionary, kind: String) -> void:
	var id := shops.size() + 1
	var acct := "R%d" % id
	sim.economy.accounts[acct] = 0.0
	sim.economy.transfer("I0", acct, START_CAPITAL)
	var spec: Dictionary = KINDS[kind]
	shops[acct] = {"id": acct, "kind": kind, "building": b.id, "name": str(b.name), "staff": int(spec.staff), "price_factor": 1.0, "status": "offen",
		"revenue": 0.0, "cogs": 0.0, "wages": 0.0, "rent": 0.0, "freight": 0.0, "units": 0, "lost": 0, "day_sales": 0.0, "day_lost": 0, "month_lost": 0, "month_units": 0,
		"use": {}, "out_bottles": 0, "last_event": "", "missing": [], "closed_months": 0}
	for g in spec.goods:
		shops[acct].use[g] = _start_use(kind, g)
		var start := int(ceil(float(shops[acct].use[g]) * float(STOCK_DAYS) * 0.6))
		if start > 0:
			sim.stock.add(g, start, acct, b.id, "Erstausstattung %s" % b.name, sim.game_min)
	sim.log_event("%s (%s) eröffnet mit Geschäftskonto %s." % [b.name, KINDS[kind].label, acct], "info")


## Anfangsschaetzung des Tagesverbrauchs je Artikel (Stueck/Portionen).
func _start_use(kind: String, item: String) -> float:
	var spec: Dictionary = KINDS[kind]
	var base := float(spec.base)
	if kind == "restaurant":
		return base * (0.45 if item in ["gemuese", "fassgetraenk"] else 0.3)
	var g: Dictionary = GOODS[item]
	return maxf(1.0, base * float(g.get("basket", 1)) * 0.5 / float(spec.goods.size()) * 1.4)


## Zielbestand im Grosshandel: guenstige Massenware viel, teure Ware wenig.
static func wholesale_target(item: String) -> int:
	var cost := float(GOODS[item].cost)
	if cost >= 40.0:
		return 24
	if cost >= 5.0:
		return 120
	return 500


func _stock_wholesale(day: int) -> void:
	for item in GOODS:
		if item == "leergut":
			continue
		var have := sim.stock.qty(item, WHOLESALER, wholesale_building)
		var target := wholesale_target(item)
		var demand := 0.0
		for s in shops.values():
			demand += float(s.use.get(item, 0.0))
		target = maxi(target, int(ceil(demand * float(STOCK_DAYS) * 1.2)))   # genug fuer alle Betriebe, die den Artikel fuehren
		if have >= target / 2:
			continue
		var need := target - have
		var unit_cost: float = GOODS[item].cost
		var buy := need
		var refill := 0
		if item == "flasche":
			refill = mini(need, sim.stock.qty("leergut", WHOLESALER, wholesale_building))
			if refill > 0:
				sim.stock.consume("leergut", refill, WHOLESALER, wholesale_building, "Wiederbefüllung", sim.game_min)
				stats.bottles_reused += refill
			buy = need - refill
		var cost := float(buy) * unit_cost + float(refill) * unit_cost * REFILL_COST
		var cash: float = maxf(0.0, float(sim.economy.accounts[WHOLESALER]))
		if cost > cash:
			var f := cash / cost
			buy = int(float(buy) * f)
			refill = int(float(refill) * f)
			cost = float(buy) * unit_cost + float(refill) * unit_cost * REFILL_COST
		if buy + refill <= 0:
			continue
		sim.economy.transfer(WHOLESALER, PRODUCER, cost)
		stats.wholesale_buys += cost
		sim.stock.add(item, buy + refill, WHOLESALER, wholesale_building, "Einkauf beim Produzenten" if refill == 0 else "Produzent und Wiederbefüllung", sim.game_min)


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


func spec_of(s: Dictionary) -> Dictionary:
	return KINDS[s.kind]


func shop_of_building(bid: int) -> Dictionary:
	for s in shops.values():
		if int(s.building) == bid:
			return s
	return {}


func stock_of(s: Dictionary, item: String) -> int:
	return sim.stock.available(item, s.id, int(s.building))


func incoming(s: Dictionary, item: String) -> int:
	var n := 0
	for o in orders.values():
		if o.shop == s.id and o.item == item and o.status in ["bestellt", "transport", "unterwegs"]:
			n += int(o.qty)
	return n


# ------------------------------------------------------------------ Tagesablauf
func on_day(day: int) -> void:
	_day = day
	_stock_wholesale(day)
	for s in shops.values():
		if s.status == "geschlossen":
			continue
		_spoil(s)
		_serve(s, day)
		_returns(s)
		_reorder(s)
	_advance_orders(day)


func _rng(s: Dictionary, day: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([s.id, day, sim.city.seed_value])
	return r


## Kundschaft des Tages: Bevoelkerung, Beschaeftigung, Wetter, Preisniveau.
func customers(s: Dictionary, r: RandomNumberGenerator) -> int:
	var base := float(spec_of(s).base)
	var pop := float(sim.citizens.population()) / POP_REFERENCE
	var power := clampf(sim.citizens.employment_rate() / 0.8, 0.6, 1.2)
	var wx := 1.0
	if s.kind == "restaurant" and sim.wx.is_rain():
		wx = 0.85
	elif s.kind != "restaurant" and sim.wx.is_heavy_rain():
		wx = 0.9
	var elastic := pow(1.0 / maxf(0.5, float(s.price_factor)), 1.6)
	var location := sim.contentment.building_factor(int(s.building))   # attraktive Viertel haben mehr Kundschaft
	return maxi(0, int(round(base * pop * power * wx * elastic * location * r.randf_range(0.8, 1.2))))


func _serve(s: Dictionary, day: int) -> void:
	var r := _rng(s, day)
	var n := customers(s, r)
	var spec: Dictionary = spec_of(s)
	s.day_sales = 0.0
	s.day_lost = 0
	var missing := {}
	var sold_units := {}
	for i in n:
		if s.kind == "restaurant":
			var d: Dictionary = DISHES[spec.dishes[r.randi() % spec.dishes.size()]]
			var can := true
			for it in d.uses:
				if stock_of(s, it) < int(d.uses[it]):
					can = false
					missing[it] = true
			if not can:
				s.day_lost += 1
				continue
			for it in d.uses:
				sim.stock.consume(it, int(d.uses[it]), s.id, int(s.building), "Küche: %s" % d.name, sim.game_min)
				s.cogs += float(GOODS[it].cost) * WHOLESALE_MARKUP * float(d.uses[it])
			_sell(s, float(d.price) * float(s.price_factor), 1)
		else:
			var item: String = spec.goods[r.randi() % spec.goods.size()]
			var g: Dictionary = GOODS[item]
			var want := 1 + r.randi() % int(g.get("basket", 1))
			var have := stock_of(s, item)
			if have <= 0:
				s.day_lost += 1
				missing[item] = true
				sold_units[item] = int(sold_units.get(item, 0)) + want   # entgangene Nachfrage zaehlt zum Bedarf, sonst bricht die Schaetzung bei leerem Regal ein
				continue
			var q := mini(want, have)
			sim.stock.consume(item, q, s.id, int(s.building), "Verkauf", sim.game_min)
			s.cogs += float(g.cost) * WHOLESALE_MARKUP * float(q)
			var pf := PFAND * float(q) if g.get("pfand", false) else 0.0
			_sell(s, float(g.price) * float(s.price_factor) * float(q) + pf, q)
			if pf > 0.0:
				s.out_bottles = int(s.out_bottles) + q
				stats.bottles_sold += q
			sold_units[item] = int(sold_units.get(item, 0)) + q
	s.missing = missing.keys()
	s.lost += int(s.day_lost)
	s.month_lost += int(s.day_lost)
	stats.lost += int(s.day_lost)
	# Verbrauchsschaetzung je Artikel folgt dem tatsaechlichen Absatz (gleitender Mittelwert)
	for item in spec.goods:
		var sold := float(_kitchen_use(s, item, n)) if s.kind == "restaurant" else float(sold_units.get(item, 0))
		s.use[item] = maxf(_start_use(str(s.kind), item) * 0.5, lerpf(float(s.use[item]), sold, 0.2))
	if int(s.day_lost) > 0:
		s.last_event = "Tag %d: %d Gäste/Kunden gingen leer aus (fehlt: %s)." % [day, int(s.day_lost), ", ".join(missing.keys().map(func(k): return GOODS[k].name))]


## Gesamtverbrauch einer Zutat in der Kueche an diesem Tag (aus den Gerichten, die tatsaechlich gekocht wurden: Naeherung ueber die Kundschaft).
func _kitchen_use(s: Dictionary, item: String, n: int) -> float:
	var spec: Dictionary = spec_of(s)
	var per := 0.0
	for dn in spec.dishes:
		per += float(DISHES[dn].uses.get(item, 0))
	return per / float(spec.dishes.size()) * float(n)


func _sell(s: Dictionary, amount: float, units: int) -> void:
	sim.economy.transfer("H0", s.id, amount)
	s.revenue += amount
	s.units += units
	s.month_units += units
	s.day_sales += amount
	stats.sales += amount
	stats.units += units
	month_sales += amount


## Verderb: ein Teil der verderblichen Ware wird taeglich entsorgt (bezahlt, aber nicht verkauft).
func _spoil(s: Dictionary) -> void:
	for item in spec_of(s).goods:
		var shelf := int(GOODS[item].shelf)
		if shelf <= 0:
			continue
		var have := sim.stock.qty(item, s.id, int(s.building))
		var lose := int(floor(float(have) * SPOIL_RATE * (5.0 / float(shelf)) * 0.5 + 0.5))
		if lose > 0:
			lose = sim.stock.consume(item, lose, s.id, int(s.building), "Verderb", sim.game_min)
			stats.spoiled += lose
			s.cogs += float(GOODS[item].cost) * WHOLESALE_MARKUP * float(lose)


## Pfandflaschen kommen zurueck: Erstattung an den Haushalt, Leergut liegt im Betriebslager (Eigentum des Betriebs).
func _returns(s: Dictionary) -> void:
	var out := int(s.out_bottles)
	if out <= 0:
		return
	var back := int(ceil(float(out) * RETURN_SHARE))
	var refund := float(back) * PFAND
	sim.economy.transfer(s.id, "H0", refund)
	s.out_bottles = out - back
	sim.stock.add("leergut", back, s.id, int(s.building), "Rückgabe durch Kunden", sim.game_min)
	stats.bottles_returned += back


# ------------------------------------------------------------------ Nachschub
func _reorder(s: Dictionary) -> void:
	for item in spec_of(s).goods:
		var use := float(s.use[item])
		var have := stock_of(s, item) + incoming(s, item)
		if float(have) >= use * float(REORDER_DAYS):
			continue
		var qty := int(ceil(use * float(STOCK_DAYS))) - have
		var wl := sim.stock.available(item, WHOLESALER, wholesale_building)
		qty = mini(qty, wl)
		if qty <= 0:
			continue
		var freight := _freight(s, qty)
		var unit := float(GOODS[item].cost) * WHOLESALE_MARKUP + (PFAND if GOODS[item].get("pfand", false) else 0.0)
		var cash := float(sim.economy.accounts[s.id])
		while qty > 0 and float(qty) * unit + freight > cash:
			qty = int(qty / 2)
		if qty <= 0:
			s.last_event = "Tag %d: Nachbestellung %s nicht möglich, Liquidität fehlt." % [_day, GOODS[item].name]
			continue
		_order(s, item, qty, unit, freight)


func _freight(s: Dictionary, qty: int) -> float:
	var src: Dictionary = sim.city.building(wholesale_building)
	var dst: Dictionary = sim.city.building(int(s.building))
	var dist := absi(src.road.x - dst.road.x) + absi(src.road.y - dst.road.y)
	return snappedf(FREIGHT_BASE + float(dist) * 1.0 * (1.0 + float(_cargo_qty(qty)) / 8.0), 1.0)


func _cargo_qty(qty: int) -> int:
	return maxi(1, int(ceil(float(qty) / 60.0)))


func _order(s: Dictionary, item: String, qty: int, unit: float, freight: float) -> void:
	var id := "RO%d" % _next_order
	_next_order += 1
	var ref := "shop:" + id
	if not sim.stock.reserve(ref, item, qty, WHOLESALER, wholesale_building):
		return
	var o := {"id": id, "shop": s.id, "item": item, "qty": qty, "unit": unit, "freight": freight, "status": "bestellt", "day": _day, "contract": "", "reissued": 0}
	orders[id] = o
	stats.orders += 1
	_issue_contract(o, s)
	sim.log_event("%s bestellt %d × %s nach." % [s.name, qty, GOODS[item].name], "info")


func _issue_contract(o: Dictionary, s: Dictionary) -> void:
	var src: Dictionary = sim.city.building(wholesale_building)
	var dst: Dictionary = sim.city.building(int(s.building))
	var k := Contract.new()
	k.id = "A%d" % sim.market.next_id
	sim.market.next_id += 1
	k.pickup = wholesale_building
	k.dropoff = int(s.building)
	k.cargo = str(GOODS[o.item].cargo)
	k.label = "%s: %d × %s" % [s.name, int(o.qty), GOODS[o.item].name]
	k.qty = _cargo_qty(int(o.qty))
	k.reward = float(o.freight)
	k.status = "open"
	k.payer = str(s.id)
	k.order_ref = "shop:" + str(o.id)
	k.created = sim.game_min
	k.offer_until = sim.game_min + GameCalendar.days_to_min(float(OFFER_DAYS))
	k.deadline = sim.game_min + GameCalendar.days_to_min(float(OFFER_DAYS + 2))
	k.distance = absi(src.road.x - dst.road.x) + absi(src.road.y - dst.road.y)
	k.needs_cold = bool(Catalog.CARGO[k.cargo].refrigerated)
	sim.contracts[k.id] = k
	o.contract = k.id
	o.status = "transport"


func _advance_orders(day: int) -> void:
	for o in orders.values():
		if o.status not in ["transport", "unterwegs"]:
			continue
		var k: Contract = sim.contracts.get(o.contract)
		if k != null and k.status in ["accepted", "assigned", "loading", "in_transit"]:
			o.status = "unterwegs"
			continue
		if k != null and k.status == "open" and sim.game_min <= k.offer_until:
			continue
		if k != null and k.status == "delivered":
			continue
		var s: Dictionary = shops[o.shop]
		if int(o.reissued) < 1 and k != null and k.status in ["open", "expired", "failed"]:
			o.reissued = int(o.reissued) + 1
			if k.status == "open":
				k.status = "expired"
			_issue_contract(o, s)
			continue
		_fallback(o, s)


## Lieferdienst des Grosshandels, wenn kein Transportunternehmen den Auftrag uebernommen hat (Lohn an S0).
func _fallback(o: Dictionary, s: Dictionary) -> void:
	var pay := minf(float(o.freight) * 0.7, maxf(0.0, float(sim.economy.accounts[s.id])))
	sim.economy.transfer(s.id, "S0", pay)
	o.freight_paid = pay
	s.freight += pay
	stats.freight += pay
	stats.fallback += 1
	var k: Contract = sim.contracts.get(o.contract)
	if k != null and k.status in ["open", "expired"]:
		k.status = "cancelled"
	_receive(o, s)


## Vom Simulationskern aufgerufen, wenn ein Unternehmen den Transport abgeliefert hat.
func contract_delivered(k: Contract) -> void:
	var id := k.order_ref.trim_prefix("shop:")
	var o: Dictionary = orders.get(id, {})
	if o.is_empty() or o.status not in ["transport", "unterwegs"]:
		return
	var s: Dictionary = shops[o.shop]
	o.freight_paid = k.paid
	s.freight += k.paid
	stats.freight += k.paid
	_receive(o, s)


## Ware kommt an: Eigentum geht auf den Betrieb ueber, der Grosshandel wird bezahlt (Pfand auf Mehrwegflaschen inklusive), Leergut faehrt zurueck.
func _receive(o: Dictionary, s: Dictionary) -> void:
	var item: String = o.item
	var moved := sim.stock.move_reserved("shop:" + str(o.id), s.id, int(s.building), "Anlieferung %s" % o.id, sim.game_min)
	var amount := float(moved) * float(o.unit)
	var pay := minf(amount, maxf(0.0, float(sim.economy.accounts[s.id])))
	sim.economy.transfer(s.id, WHOLESALER, pay)
	o.qty_received = moved
	o.status = "geliefert"
	o.arrived = _today()
	stats.delivered += 1
	if item == "flasche":
		_return_empties(s)
	sim.log_event("%s: %d × %s angeliefert (%s bezahlt)." % [s.name, moved, GOODS[item].name, Catalog.money(pay)], "info")


func _return_empties(s: Dictionary) -> void:
	var n := sim.stock.qty("leergut", s.id, int(s.building))
	if n <= 0:
		return
	var moved := sim.stock.move("leergut", n, s.id, int(s.building), WHOLESALER, wholesale_building, "Rücktransport Leergut im Lieferwagen", sim.game_min)
	var refund := minf(float(moved) * PFAND, maxf(0.0, float(sim.economy.accounts[WHOLESALER])))
	sim.economy.transfer(WHOLESALER, s.id, refund)


# ------------------------------------------------------------------ Monat
## Kassenumsatz des Monats; Citizens zieht ihn vom pauschalen Konsum ab (damit die Haushalte nicht doppelt zahlen). Setzt den Zaehler zurueck.
func take_month_sales() -> float:
	var v := month_sales
	month_sales = 0.0
	return v


func on_month(_month: int) -> void:
	for s in shops.values():
		if s.status == "geschlossen":
			continue
		var spec: Dictionary = spec_of(s)
		var wages := float(s.staff) * float(Citizens.EMPLOYERS.handel.wage) * Citizens.HOURS_PER_MONTH
		var cash := maxf(0.0, float(sim.economy.accounts[s.id]))
		var pay_w := minf(wages, cash)
		sim.economy.transfer(s.id, "S0", pay_w)   # S0 zahlt die Loehne des Handels (Citizens, Arbeitgeber "handel")
		s.wages += pay_w
		var rent := minf(float(spec.rent), maxf(0.0, float(sim.economy.accounts[s.id])))
		sim.economy.transfer(s.id, "P0", rent)
		s.rent += rent
		if pay_w < wages or rent < float(spec.rent):
			s.status = "zahlungsschwach"
			s.closed_months = int(s.closed_months) + 1
			s.last_event = "Monat: Löhne/Miete nicht voll bezahlt."
			if int(s.closed_months) >= 4:
				s.status = "geschlossen"
				sim.log_event("%s schließt wegen dauerhafter Zahlungsunfähigkeit." % s.name, "bad")
		else:
			s.status = "offen"
			s.closed_months = 0
			_adjust_price(s)
		s.month_lost = 0
		s.month_units = 0
	# Produzenten zahlen ihren Beschaeftigten Lohn (Lohnsteuer und Sozialabgaben wie ueberall)
	var f := maxf(0.0, float(sim.economy.accounts[PRODUCER]))
	if f > 1.0:
		sim.economy.transfer(PRODUCER, "H0", f * 0.8)
		sim.public_sector.withhold(f * 0.8)


## Preisregel des Betreibers: oft leere Regale -> Preis leicht hoeher, volle Regale ohne Absatz -> Preis niedriger (Spielraum 0,85-1,25).
func _adjust_price(s: Dictionary) -> void:
	var units := maxf(1.0, float(s.month_units))
	var lost_ratio := float(s.month_lost) / (units + float(s.month_lost))
	var old := float(s.price_factor)
	if lost_ratio > 0.15:
		s.price_factor = minf(1.25, old + 0.03)
	elif lost_ratio < 0.02 and float(sim.economy.accounts[s.id]) > START_CAPITAL * 2.0:
		s.price_factor = maxf(0.85, old - 0.03)


## Strategie des Betreibers (KI oder Zuschauer): Preisniveau setzen.
func set_price_factor(id: String, f: float) -> Dictionary:
	if not shops.has(id):
		return {"ok": false, "msg": "Betrieb %s gibt es nicht." % id}
	shops[id].price_factor = clampf(f, 0.7, 1.5)
	return {"ok": true, "msg": "%s: Preisniveau %.2f." % [shops[id].name, shops[id].price_factor]}


func profit_of(s: Dictionary) -> float:
	return float(s.revenue) - float(s.cogs) - float(s.wages) - float(s.rent) - float(s.freight)


func summary() -> Dictionary:
	var open := 0
	var cash := 0.0
	for s in shops.values():
		if s.status != "geschlossen":
			open += 1
		cash += float(sim.economy.accounts[s.id])
	return {"betriebe": shops.size(), "offen": open, "umsatz": stats.sales, "verkauft": stats.units, "entgangen": stats.lost, "bestellungen": stats.orders,
		"geliefert": stats.delivered, "eigene_lieferfahrten": stats.fallback, "verdorben": stats.spoiled, "mehrweg_wiederbefuellt": stats.bottles_reused, "kasse": cash}


func to_dict() -> Dictionary:
	return {"shops": shops, "orders": orders, "stats": stats, "month_sales": month_sales, "next": _next_order, "wholesale": wholesale_building}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	shops = d.get("shops", {})
	for s in shops.values():
		s.building = int(s.building)
		s.staff = int(s.staff)
		s.units = int(s.units)
		s.lost = int(s.lost)
		s.month_lost = int(s.month_lost)
		s.month_units = int(s.month_units)
		s.out_bottles = int(s.out_bottles)
		s.closed_months = int(s.closed_months)
		s.day_lost = int(s.day_lost)
	orders = d.get("orders", {})
	for o in orders.values():
		o.qty = int(o.qty)
		o.reissued = int(o.reissued)
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k] if stats.get(k) is float else int(st[k])
	month_sales = float(d.get("month_sales", 0.0))
	_next_order = int(d.get("next", 1))
	wholesale_building = int(d.get("wholesale", wholesale_building))
