class_name CentralHub
extends RefCounted
## Zentrales Grosslager (Auftrag 19, Etappe 2): neutraler Handelsplatz in der Kartenmitte (Gelaende: CityData.hub, Generator 3).
##
## Echter Bestand im StockBook (Eigentuemer L0, Ort = Hauptlager), begrenzte Kapazitaet, Preise nach Bestand und Nachfrage.
## Kaufen: der Kaeufer bezahlt, die Ware wechselt am Lager den Eigentuemer und wird fuer ihn reserviert; ein Transportauftrag holt sie ab
## (Unternehmen: nur mit eigenem Fahrzeug; Staedte: offener Marktauftrag fuer Transportfirmen). Verkaufen: der Verkaeufer bringt die Ware
## mit eigenem Fahrzeug, bezahlt wird bei Anlieferung. Nachschub: lokale Produzenten (Production.order) und Import ueber den Flughafen
## (Ware entsteht am Frachtterminal, ein Transportauftrag bringt sie ins Lager). Nichts wird teleportiert.

const ACCT := "L0"
const CAPACITY := 16000             # Einheiten im ganzen Lager (Hallen, Hochregal, Freilager)
const SELL_SHARE := 0.85            # Ankaufspreis des Lagers gegenueber dem Verkaufspreis
const RESTOCK_AT := 0.5             # Nachschub, wenn Bestand + unterwegs unter die Haelfte des Zielbestands faellt
const DEMAND_DECAY := 0.85          # Nachfragegedaechtnis je Tag
const FREIGHT_BASE := 60.0
## Sortiment: Artikel -> {g: Gruppe, t: Zielbestand}. Preis und Name aus dem Bauhof-Katalog (Trader.MATERIALS) bzw. CityGoods.
const GOODS := {
	"holz": {"g": "baumaterial", "t": 400}, "stahl": {"g": "baumaterial", "t": 240}, "beton": {"g": "baumaterial", "t": 360},
	"ziegel": {"g": "baumaterial", "t": 600}, "glas": {"g": "baumaterial", "t": 160}, "sand": {"g": "baumaterial", "t": 500},
	"kies": {"g": "baumaterial", "t": 500}, "asphalt": {"g": "baumaterial", "t": 240}, "pflaster": {"g": "baumaterial", "t": 300},
	"betonfertigteil": {"g": "baumaterial", "t": 160}, "rohr": {"g": "baumaterial", "t": 800}, "kabel": {"g": "baumaterial", "t": 1500},
	"installation": {"g": "baumaterial", "t": 120}, "naturstein": {"g": "baumaterial", "t": 120}, "bronze": {"g": "baumaterial", "t": 40},
	"naturstein_aufbereitet": {"g": "anlagen", "t": 80},
	"moebel": {"g": "handel", "t": 60}, "computer": {"g": "handel", "t": 30}, "erstehilfe": {"g": "handel", "t": 120},
	"hygiene": {"g": "handel", "t": 200}, "werkzeug": {"g": "handel", "t": 60}, "reifen": {"g": "handel", "t": 60},
	"schutzkleidung": {"g": "handel", "t": 60},
	"schrott": {"g": "baumaterial", "t": 0},   # nur Ankauf von den Recyclinghoefen (Auftrag 20), kein Nachschub per Import
	"spielgeraet": {"g": "anlagen", "t": 40}, "sportmaterial": {"g": "anlagen", "t": 40}, "pflanzen": {"g": "anlagen", "t": 600},
	"jungbaum": {"g": "anlagen", "t": 80}, "strassenleuchte": {"g": "anlagen", "t": 40}, "kunstwerk": {"g": "anlagen", "t": 6},
	"dekoration": {"g": "anlagen", "t": 120}, "marktstand": {"g": "anlagen", "t": 24}, "flutlicht": {"g": "anlagen", "t": 16},
	"tribuenenteil": {"g": "anlagen", "t": 30}, "sportbelag": {"g": "anlagen", "t": 600}, "zaun": {"g": "anlagen", "t": 400},
}
const GROUP_LABEL := {"baumaterial": "Baumaterial", "handel": "Handelsgüter", "anlagen": "Anlagen, Grün und Kunst"}

var sim
var enabled := false
var loc := -1                       # Hauptlager (Gebaeude-ID): Ort aller Bestaende
var deals := {}                     # "H<n>" -> {id, kind: kauf|verkauf|import|produzent, item, qty, party, dest, contract, status, price, day}
var incoming := {}                  # Artikel -> Menge unterwegs ins Lager
var demand := {}                    # Artikel -> geglaettete Nachfrage (Einheiten/Tag)
var stats := {"umsatz": 0.0, "ankauf": 0.0, "import": 0.0, "verkaeufe": 0, "ankaeufe": 0, "importe": 0, "knappheit": {}}
var _next := 1


func setup(simulation) -> void:
	sim = simulation
	enabled = sim.city != null and not sim.city.hub.is_empty()
	if not enabled:
		return
	loc = int(sim.city.hub.buildings.get("hauptlager", -1))
	if loc < 0:
		enabled = false
		return
	if not sim.economy.accounts.has(ACCT):
		sim.economy.accounts[ACCT] = 0.0
	for item in GOODS:
		if int(GOODS[item].t) > 0:   # Waren ohne Zielbestand (Schrott) kommen nur ueber Ankauf
			sim.stock.add(item, int(GOODS[item].t), ACCT, loc, "Erstausstattung Großlager")
	sim.day_changed.connect(on_day)


# ------------------------------------------------------------------ Katalog und Preise
static func item_name(item: String) -> String:
	if CityGoods.exists(item):
		return str(CityGoods.get_item(item).name)
	if Trader.MATERIALS.has(item):
		return str(Trader.MATERIALS[item].name)
	return item


static func base_price(item: String) -> float:
	if Trader.MATERIALS.has(item):
		return float(Trader.MATERIALS[item].base)
	if CityGoods.exists(item):
		return float(CityGoods.get_item(item).price)
	return 20.0


func stock_of(item: String) -> int:
	return sim.stock.available(item, ACCT, loc) if enabled else 0


func used() -> int:
	var n := 0
	for item in GOODS:
		n += sim.stock.qty(item, ACCT, loc) + int(incoming.get(item, 0))
	return n


func free_capacity() -> int:
	return maxi(0, CAPACITY - used())


## Verkaufspreis je Einheit: knapper Bestand und hohe Nachfrage machen teurer (0,75- bis 2-fach des Grundpreises).
func price(item: String) -> float:
	var t := float(GOODS.get(item, {"t": 100}).t)
	var f := clampf(1.6 - 0.6 * float(stock_of(item)) / maxf(1.0, t), 0.75, 1.9)
	f *= 1.0 + clampf(float(demand.get(item, 0.0)) / maxf(1.0, t * 0.2), 0.0, 1.0) * 0.1
	return snappedf(base_price(item) * f, 0.01)


func buy_price(item: String) -> float:
	return snappedf(price(item) * SELL_SHARE, 0.01)


func freight(from_b: int, to_b: int, qty: int) -> float:
	var a: Dictionary = sim.city.building(from_b)
	var b: Dictionary = sim.city.building(to_b)
	var dist := absi(int(a.road.x) - int(b.road.x)) + absi(int(a.road.y) - int(b.road.y))
	return snappedf(FREIGHT_BASE + float(dist) * 1.6 * (1.0 + float(_loads(qty)) / 8.0), 1.0)


static func _loads(qty: int) -> int:
	return maxi(1, int(ceil(float(qty) / 40.0)))


# ------------------------------------------------------------------ Kaufen und Verkaufen
## Kauf durch ein Unternehmen ("C<n>") oder eine Stadt (Konto der Stadt, Towns.account_of). Ziel: Gebaeude-ID der Anlieferung.
func buy(buyer: String, item: String, qty: int, dest: int, note: String = "") -> Dictionary:
	if not enabled:
		return {"ok": false, "msg": "Es gibt kein Großlager auf dieser Karte."}
	if not GOODS.has(item):
		return {"ok": false, "msg": "%s führt das Großlager nicht. Sortiment: %s." % [item, ", ".join(GOODS.keys())]}
	if qty <= 0:
		return {"ok": false, "msg": "Menge muss positiv sein."}
	var have := stock_of(item)
	if have < qty:
		_shortage(item, qty - have)
		return {"ok": false, "msg": "Nur %d × %s auf Lager (Nachschub ist bestellt)." % [have, item_name(item)], "verfuegbar": have}
	var unit := price(item)
	var amount := snappedf(unit * float(qty), 0.01)
	var company := buyer.begins_with("C")
	if company:
		var c = sim.company(int(buyer.substr(1)))
		if c == null or not c.is_active():
			return {"ok": false, "msg": "Unternehmen kann nicht kaufen."}
		if c.ledger.cash < amount:
			return {"ok": false, "msg": "Nicht genug Bargeld: %s nötig." % Catalog.money(amount)}
		c.ledger.book("supplies", -amount, true, "Großlager: %d × %s" % [qty, item_name(item)], sim.game_min, ACCT)
	else:
		if float(sim.economy.accounts.get(buyer, 0.0)) < amount:
			return {"ok": false, "msg": "Kasse reicht nicht: %s nötig." % Catalog.money(amount)}
		sim.economy.transfer(buyer, ACCT, amount)
	var id := "H%d" % _next
	_next += 1
	sim.stock.move(item, qty, ACCT, loc, buyer, loc, "Kauf im Großlager %s" % id, sim.game_min)
	sim.stock.reserve("hub:" + id, item, qty, buyer, loc)
	var d := {"id": id, "kind": "kauf", "item": item, "qty": qty, "party": buyer, "dest": dest, "contract": "", "status": "abholbereit",
		"price": amount, "unit": unit, "day": _today(), "note": note}
	deals[id] = d
	demand[item] = float(demand.get(item, 0.0)) + float(qty)
	stats.umsatz = float(stats.umsatz) + amount
	stats.verkaeufe = int(stats.verkaeufe) + 1
	_issue(d, loc, dest, buyer if company else "")
	sim.log_event("Großlager: %s kauft %d × %s für %s." % [_party_name(buyer), qty, item_name(item), Catalog.money(amount)], "info")
	return {"ok": true, "msg": "Gekauft: %d × %s für %s (%s je Einheit). %s" % [qty, item_name(item), Catalog.money(amount), Catalog.money(unit),
		"Abholung mit eigenem Fahrzeug: Auftrag %s." % d.contract if company else "Transportauftrag %s ist ausgeschrieben." % d.contract], "ref": id, "contract": d.contract}


## Verkauf eines Unternehmens an das Lager: Ware aus dem eigenen Depot, Anlieferung mit eigenem Fahrzeug, Zahlung bei Ankunft.
func sell(cid: int, item: String, qty: int) -> Dictionary:
	if not enabled:
		return {"ok": false, "msg": "Es gibt kein Großlager auf dieser Karte."}
	if not GOODS.has(item):
		return {"ok": false, "msg": "%s kauft das Großlager nicht an." % item}
	var c = sim.company(cid)
	if c == null or not c.is_active() or c.depots.is_empty():
		return {"ok": false, "msg": "Unternehmen kann nicht verkaufen."}
	var from := int(c.depots[0])
	var own := "C%d" % cid
	if qty <= 0 or sim.stock.available(item, own, from) < qty:
		return {"ok": false, "msg": "Im Depot liegen nur %d × %s." % [sim.stock.available(item, own, from), item_name(item)]}
	if free_capacity() < qty:
		return {"ok": false, "msg": "Das Großlager ist voll (frei %d Einheiten)." % free_capacity()}
	var id := "H%d" % _next
	_next += 1
	var unit := buy_price(item)
	sim.stock.reserve("hub:" + id, item, qty, own, from)
	var d := {"id": id, "kind": "verkauf", "item": item, "qty": qty, "party": own, "dest": loc, "contract": "", "status": "anlieferung",
		"price": snappedf(unit * float(qty), 0.01), "unit": unit, "day": _today(), "from": from}
	deals[id] = d
	incoming[item] = int(incoming.get(item, 0)) + qty
	_issue(d, from, loc, own)
	return {"ok": true, "msg": "Verkauf vereinbart: %d × %s zu %s je Einheit, bezahlt bei Anlieferung (Auftrag %s, eigenes Fahrzeug)." % [qty, item_name(item),
		Catalog.money(unit), d.contract], "ref": id, "contract": d.contract}


## Transportauftrag fuer einen Handel: Unternehmen fahren selbst (exklusiv, ohne Verguetung), sonst offener Marktauftrag.
func _issue(d: Dictionary, from_b: int, to_b: int, own_party: String) -> void:
	var a: Dictionary = sim.city.building(from_b)
	var b: Dictionary = sim.city.building(to_b)
	var k := Contract.new()
	k.id = "A%d" % sim.market.next_id
	sim.market.next_id += 1
	k.pickup = from_b
	k.dropoff = to_b
	k.cargo = CityDepot.cargo_of(str(d.item)) if CityGoods.exists(str(d.item)) else "baustoffe"
	k.label = "Großlager: %d × %s" % [int(d.qty), item_name(str(d.item))]
	k.qty = mini(_loads(int(d.qty)), CityDepot.CONTRACT_MAX_UNITS)
	k.distance = absi(int(a.road.x) - int(b.road.x)) + absi(int(a.road.y) - int(b.road.y))
	k.reward = freight(from_b, to_b, int(d.qty))
	k.status = "open"
	k.order_ref = "hub:" + str(d.id)
	k.created = sim.game_min
	k.offer_until = sim.game_min + GameCalendar.days_to_min(4.0)
	k.deadline = sim.game_min + GameCalendar.days_to_min(8.0)
	if own_party.begins_with("C"):
		var cid := int(own_party.substr(1))
		k.payer = "firm:%d" % cid      # eigene Ware mit eigenem Fahrzeug: keine Verguetung (Simulation._deliver)
		k.exclusive_for = cid
		k.exclusive_until = k.deadline
		sim.companies[cid].known[k.id] = true
	else:
		k.payer = str(d.party) if d.kind == "kauf" and not str(d.party).begins_with("C") else ACCT   # Stadt zahlt ihre Fracht, sonst das Lager
	sim.contracts[k.id] = k
	d.contract = k.id


func contract_delivered(k: Contract) -> void:
	var id := k.order_ref.trim_prefix("hub:")
	var d: Dictionary = deals.get(id, {})
	if d.is_empty() or d.status in ["geliefert", "storniert"]:
		return
	match str(d.kind):
		"kauf":
			sim.stock.move_reserved("hub:" + id, str(d.party), int(d.dest), "Lieferung aus dem Großlager %s" % id, sim.game_min)
		"verkauf":
			sim.stock.move_reserved("hub:" + id, ACCT, loc, "Ankauf Großlager %s" % id, sim.game_min)
			var c = sim.company(int(str(d.party).substr(1)))
			var pay := minf(float(d.price), maxf(0.0, float(sim.economy.accounts.get(ACCT, 0.0))))
			c.ledger.book("trade_income", pay, true, "Verkauf an das Großlager %s" % id, sim.game_min, ACCT)
			stats.ankauf = float(stats.ankauf) + pay
			stats.ankaeufe = int(stats.ankaeufe) + 1
			incoming[d.item] = maxi(0, int(incoming.get(d.item, 0)) - int(d.qty))
		"import":
			sim.stock.move_reserved("hub:" + id, ACCT, loc, "Import über den Flughafen %s" % id, sim.game_min)
			incoming[d.item] = maxi(0, int(incoming.get(d.item, 0)) - int(d.qty))
	d.status = "geliefert"
	d["done"] = _today()


# ------------------------------------------------------------------ Tageslauf: Nachschub, Nachfrage, Aufraeumen
func on_day(day: int) -> void:
	if not enabled:
		return
	for item in demand.keys():
		demand[item] = float(demand[item]) * DEMAND_DECAY
	for item in GOODS:
		var t := int(GOODS[item].t)
		var have: int = sim.stock.qty(item, ACCT, loc) + int(incoming.get(item, 0)) + _from_producers(item)
		if have < int(float(t) * RESTOCK_AT):
			_restock(item, t - have)
	_watch(day)
	for id in deals.keys():
		if deals[id].status in ["geliefert", "storniert"] and day - int(deals[id].get("done", deals[id].day)) > 30:
			deals.erase(id)


## Nachschub: zuerst lokale Produzenten (eigener Liefervertrag ueber Production), der Rest als Import ueber den Flughafen.
func _restock(item: String, want: int) -> void:
	want = mini(want, free_capacity())
	if want <= 0:
		return
	if not Production.art(item).is_empty():
		var got: int = sim.prod.order(ACCT, loc, "", item, want, base_price(item) * 1.2, false)
		want -= got   # Liefervertraege der Produzenten: unterwegs zaehlt _from_producers
	if want <= 0:
		return
	var ap := _airport_cargo()
	if ap < 0:
		return
	var cost := snappedf(base_price(item) * CityGoods.IMPORT_FACTOR * float(want), 0.01)
	if float(sim.economy.accounts.get(ACCT, 0.0)) < cost:
		return
	sim.economy.transfer(ACCT, "X0", cost)
	var id := "H%d" % _next
	_next += 1
	sim.stock.add(item, want, ACCT, ap, "Import über den Flughafen (Großlager %s)" % id, sim.game_min)
	sim.stock.reserve("hub:" + id, item, want, ACCT, ap)
	var d := {"id": id, "kind": "import", "item": item, "qty": want, "party": ACCT, "dest": loc, "contract": "", "status": "anlieferung",
		"price": cost, "day": _today(), "from": ap}
	deals[id] = d
	incoming[item] = int(incoming.get(item, 0)) + want
	stats.import = float(stats.import) + cost
	stats.importe = int(stats.importe) + 1
	_issue(d, ap, loc, "")


## Menge aus laufenden Liefervertraegen lokaler Produzenten an das Lager (Production.deals).
func _from_producers(item: String) -> int:
	var n := 0
	for d in sim.prod.deals.values():
		if str(d.buyer) == ACCT and str(d.item) == item and str(d.status) in ["transport", "unterwegs"]:
			n += int(d.qty)
	return n


## Flughafen-Frachtterminal, das dem Lager am naechsten liegt (Auftrag 19: Flughafenimport speist das Lager).
func _airport_cargo() -> int:
	var best := -1
	var best_d := 1 << 30
	var hc: Array = sim.city.hub.center
	for ap in sim.towns.airports:
		if ap == null or not ap.enabled or ap.cargo_building < 0:
			continue
		var b: Dictionary = sim.city.building(ap.cargo_building)
		var dd := absi(int(b.x) - int(hc[0])) + absi(int(b.y) - int(hc[1]))
		if dd < best_d:
			best_d = dd
			best = int(ap.cargo_building)
	return best


## Liegengebliebene Transporte neu ausschreiben (Lieferungen gehen nie verloren).
func _watch(_day: int) -> void:
	for d in deals.values():
		if d.status in ["geliefert", "storniert"] or str(d.contract) == "":
			continue
		var k: Contract = sim.contracts.get(str(d.contract))
		if k != null and k.status in ["open", "accepted", "assigned", "loading", "in_transit", "delivered"]:
			if k.status == "open" and sim.game_min > k.offer_until:
				k.status = "expired"
			else:
				continue
		var from := loc if d.kind == "kauf" else int(d.get("from", loc))
		var to := int(d.dest) if d.kind == "kauf" else loc
		var own := str(d.party) if str(d.party).begins_with("C") else ""
		if own != "" and d.kind == "kauf":
			own = ""   # Unternehmen hat nicht abgeholt: das Lager schreibt die Lieferung frei aus (Kaeufer zahlt nichts extra)
		_issue(d, from, to, own)


func _shortage(item: String, missing: int) -> void:
	stats.knappheit[item] = int(stats.knappheit.get(item, 0)) + missing
	demand[item] = float(demand.get(item, 0.0)) + float(missing)


func _party_name(acct: String) -> String:
	if acct.begins_with("C"):
		return sim.company(int(acct.substr(1))).company_name
	for k in sim.towns.count():
		if Towns.account_of(k) == acct:
			return "Stadt %s" % sim.towns.name_of(k)
	return acct


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


# ------------------------------------------------------------------ Beobachtung und Speichern
## Marktuebersicht fuer Unternehmen und Buergermeister: Bestand, Preise, knappe Waren.
func summary(groups: Array = []) -> Dictionary:
	if not enabled:
		return {}
	var items: Array = []
	for item in GOODS:
		if not groups.is_empty() and str(GOODS[item].g) not in groups:
			continue
		var t := float(GOODS[item].t)
		items.append({"artikel": item, "name": item_name(item), "gruppe": GROUP_LABEL[GOODS[item].g], "bestand": stock_of(item),
			"kaufpreis": price(item), "ankaufpreis": buy_price(item), "knapp": float(stock_of(item)) < t * 0.3})
	return {"ort": "Großlager (Gebäude %d)" % loc, "kapazitaet_frei": free_capacity(), "waren": items,
		"hinweis": "hub_buy item,qty (Abholung nur mit eigenem Fahrzeug) · hub_sell item,qty (Ware aus deinem Depot, Zahlung bei Anlieferung)"}


func to_dict() -> Dictionary:
	return {"deals": deals, "incoming": incoming, "demand": demand, "stats": stats, "next": _next}


func from_dict(d: Dictionary) -> void:
	deals = d.get("deals", {})
	for x in deals.values():
		x.qty = int(x.qty)
		x.dest = int(x.dest)
	incoming = {}
	for k in d.get("incoming", {}):
		incoming[k] = int(d.incoming[k])
	demand = d.get("demand", {})
	stats.merge(d.get("stats", {}), true)
	_next = int(d.get("next", 1))
