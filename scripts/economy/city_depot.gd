class_name CityDepot
extends RefCounted
## Kommunales Zentrallager mit angeschlossenem Bauhof (Auftrag 5, Abschnitte 2-4). Die Stadtverwaltung (Konto P0) ist Eigentuemer, Einkaeufer und Auftraggeber.
## Der private Grosshaendler (T0) bleibt eigenstaendiger Anbieter. Waren liegen im StockBook (Eigentuemer "P0", Standort = Lagergebaeude).
##
## Beschaffung: Bedarf -> Budgetfreigabe -> Angebot/Bestellung -> Transportauftrag -> Anlieferung -> Warenpruefung -> Einlagerung -> Zahlung.
## Ein Transportauftrag ist ein echter Marktauftrag (Contract mit Zahler P0), den jedes Transportunternehmen annehmen kann; nimmt ihn niemand an,
## faehrt nach `FALLBACK_DAYS` der Stadtfuhrpark (langsamer, Lohn an S0). Bestellte Ware erzeugt erst bei der Anlieferung Bestand am Lager.
## Material fuer Projekte wird reserviert und der Baufirma als Auftragsmaterial ueberlassen (nicht verkauft, nicht nochmals abgerechnet).

const OWNER := "P0"
const APPROVAL_LIMIT := 15000.0     # darueber entscheidet die Buergermeisterebene; darunter genehmigt die Verwaltung routinemaessig
const AUTO_APPROVE_DAYS := 2        # ohne Entscheidung genehmigt die Verwaltung grosse Vorschlaege nicht von selbst (nur kritische nach 6 Tagen)
const FALLBACK_DAYS := 3            # so lange wartet ein Transportauftrag auf ein Unternehmen
const MAX_REISSUE := 2
const INSPECTION_DAYS := 1
const RAMPS_START := 2              # Entladerampen am Wareneingang
const MAX_RAMPS := 6
const RAMP_COST := 18000.0
const STAFF_MAX := 14
## Lagerrollen und ihre Tagesleistung (Einheiten) im Wareneingang bzw. in der Kommissionierung
const ROLES := {
	"vorarbeiter": {"label": "Vorarbeiter", "rate": 150},
	"stapler": {"label": "Staplerfahrer", "rate": 700},
	"lager": {"label": "Lagerarbeiter", "rate": 450},
	"kommission": {"label": "Kommissionierer", "rate": 300},
}
const ROLE_CYCLE := ["vorarbeiter", "stapler", "lager", "lager", "kommission", "lager", "stapler", "lager", "kommission", "lager", "lager", "stapler", "lager", "kommission"]
const REST_FATIGUE := 85.0
const SICK_CHANCE := 0.015
const BASE_USE_DIVISOR := 6.0       # Verbrauch je Tag = Katalogwert / dieser Wert
const SURPLUS_FACTOR := 1.5         # Ueberschuss: Bestand ueber dem 1,5-fachen Zielbestand
const SURPLUS_PRICE := 0.5          # Verkauf von Ueberschuessen zum halben Katalogpreis (an T0 oder Ausland)
const DEFECT := {"T0": 0.005, "X0": 0.02, "C": 0.015}
const FREIGHT_BASE := 80.0
const STATUS_ORDER := ["vorschlag", "bestellt", "transport", "unterwegs", "angeliefert", "eingelagert", "bezahlt"]
## Material je Erschliessungsteil und Grundstueck (Strassenbau, Stromnetz, Wasser, Abwasser)
const PROJECT_MATERIAL := {
	"strasse": {"schotter": 20, "kies": 15, "asphalt": 12, "bordstein": 40, "verkehrsschild": 1},
	"strom": {"kabel": 60, "verteilerkasten": 1, "strassenleuchte": 1},
	"wasser": {"rohr": 50, "armatur": 2, "dichtung": 10},
	"abwasser": {"rohr": 50, "kanaldeckel": 2, "dichtung": 10},
}

var sim
var building := -1                    # Zentrallager (Gebaeude-ID)
var port := -1                        # Anlieferpunkt fuer Importware
var orders := {}                      # "B<n>" -> Vorschlag/Bestellung
var offers := {}                      # "O<n>" -> Lieferangebot eines Unternehmens {cid, item, qty, price, lead}
var project_res := {}                 # Projekt-ID -> {items: {item: qty}, mode, value}
var issues: Array = []                # Ausgaben und Ueberlassungen {day, item, qty, to, mode, ref}
var shortages := {}                   # Artikel -> Tag der letzten Fehlmenge
var carry := {}                       # Artikel -> Rest des Tagesverbrauchs
var stats := {"purchases": 0.0, "freight": 0.0, "sold": 0.0, "scrapped": 0, "orders_done": 0, "fallback_trips": 0}
var ramps := RAMPS_START
var crew := {}                        # Buerger-ID -> {fatigue, sick_until, rest_until}
var waits := 0                        # Lkw, die auf eine freie Rampe warten mussten
var wait_days: Array = []             # Tage mit Wartezeiten (letzte 30)
var _next_order := 1
var _next_offer := 1


func setup(s) -> void:
	sim = s
	s.day_changed.connect(on_day)
	s.month_changed.connect(on_month)
	var center := Vector2(s.city.size, s.city.size) * 0.5
	var best_d := INF
	for b in s.city.buildings:
		if b.role == "plot" or b.id == s.trader.bauhof or b.type not in ["warehouse", "construction", "factory", "freight_shed"]:
			continue
		var d := Vector2(b.x, b.y).distance_to(center)
		if d < best_d:
			best_d = d
			building = b.id
	if building < 0:
		building = s.trader.bauhof
	if building != s.trader.bauhof:
		s.city.buildings[building].name = "Städtisches Zentrallager (mit Bauhof)"
	best_d = INF
	for b in s.city.buildings:
		if b.role != "plot" and b.id != building and b.type in ["airport_cargo", "freight_shed", "port_office", "containers"]:
			var d2 := Vector2(b.road - s.city.building(building).road).length()
			if d2 < best_d:
				best_d = d2
				port = b.id
	if port < 0:
		port = s.trader.bauhof
	_seed_stock()


## Anfangsbestand des Zentrallagers (70 % des Zielbestands, Geraete voll).
func _seed_stock() -> void:
	var items := CityGoods.items()
	for id in items:
		var it: Dictionary = items[id]
		var n := int(it.target) if it.class == "geraet" else int(round(float(it.target) * 0.7))
		if n > 0:
			sim.stock.add(id, n, OWNER, building, "Anfangsbestand")


# ------------------------------------------------------------------ Bestand
func stock_of(item: String) -> int:
	return sim.stock.available(item, OWNER, building)


func on_hand(item: String) -> int:
	return sim.stock.qty(item, OWNER, building)


## Menge, die bestellt oder unterwegs ist und noch nicht eingelagert wurde.
func incoming(item: String) -> int:
	var n := 0
	for o in orders.values():
		if o.item == item and o.status in ["bestellt", "transport", "unterwegs", "angeliefert"]:
			n += int(o.qty)
	return n


func open_proposal(item: String) -> bool:
	for o in orders.values():
		if o.item == item and o.status == "vorschlag":
			return true
	return false


func zone_used(zone: String) -> int:
	var n := 0
	for l in sim.stock.lots.values():
		if l.owner == OWNER and l.loc == building and str(CityGoods.get_item(l.item).get("zone", "")) == zone:
			n += int(l.qty)
	for o in orders.values():
		if o.status in ["bestellt", "transport", "unterwegs", "angeliefert"] and str(CityGoods.get_item(o.item).get("zone", "")) == zone:
			n += int(o.qty)
	return n


func zone_free(zone: String) -> int:
	return maxi(0, int(CityGoods.ZONES[zone].cap) - zone_used(zone))


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


# ------------------------------------------------------------------ Tagesablauf
func on_day(day: int) -> void:
	_crew_day(day)
	_consume(day)
	_propose(day)
	_decide(day)
	_advance_orders(day)
	_inspect(day)
	_top_up_projects()
	_prune(day)


func _prune(day: int) -> void:
	for id in orders.keys():
		var o: Dictionary = orders[id]
		if o.status in ["bezahlt", "abgelehnt"] and day - int(o.day) > 90:
			orders.erase(id)


func _consume(day: int) -> void:
	var cold: bool = sim.wx.is_cold() or sim.wx.is_icy()
	for id in CityGoods.items():
		var it: Dictionary = CityGoods.get_item(id)
		var use := float(it.use) / BASE_USE_DIVISOR
		if it.group == "winterdienst" and not cold:
			use = 0.0
		if it.group in ["strassenunterbau", "strassenoberflaechen", "leitungen"]:
			use = 0.0          # nur Projekte verbrauchen diese Waren
		if use <= 0.0:
			continue
		carry[id] = float(carry.get(id, 0.0)) + use
		var n := int(carry[id])
		if n <= 0:
			continue
		carry[id] = float(carry[id]) - n
		var got: int = sim.stock.consume(id, mini(n, stock_of(id)), OWNER, building, "Verbrauch Verwaltung", sim.game_min)
		if got < n:
			if int(shortages.get(id, -99)) < day - 10:
				sim.log_event("Stadtlager: %s ist aufgebraucht – Fehlmenge im Betrieb." % it.name, "warn")
			shortages[id] = day


## Beschaffungsvorschlag, wenn Bestand plus Bestelltes den Meldebestand (plus Verbrauch in der Lieferzeit) unterschreitet.
func _propose(day: int) -> void:
	for id in CityGoods.items():
		var it: Dictionary = CityGoods.get_item(id)
		if open_proposal(id):
			continue
		var position := on_hand(id) + incoming(id)
		var lead_use := int(ceil(float(it.use) / BASE_USE_DIVISOR * float(it.lead + 1)))
		if position > int(it.reorder) + lead_use:
			continue
		var qty := int(it.target) - position
		qty = mini(qty, zone_free(str(it.zone)))
		if qty <= 0:
			continue
		var o := _new_order(id, qty, "Bestand %d unter Meldebestand %d (bestellt/unterwegs %d)" % [on_hand(id), int(it.reorder), incoming(id)])
		o.crit = int(it.crit)
		orders[o.id] = o


func _new_order(item: String, qty: int, reason: String, project: String = "") -> Dictionary:
	var o := {"id": "B%d" % _next_order, "item": item, "qty": qty, "status": "vorschlag", "reason": reason, "project": project, "day": _today(), "crit": 1,
		"supplier": "", "unit_price": 0.0, "price": 0.0, "freight": 0.0, "committed": 0.0, "contract": "", "reissued": 0, "due": -1, "decision": "", "decided_by": "",
		"good": 0, "bad": 0, "history": []}
	_next_order += 1
	_log(o, "Vorschlag: %d × %s (%s)" % [qty, CityGoods.get_item(item).name, reason])
	return o


func _log(o: Dictionary, text: String) -> void:
	o.history.append({"day": _today(), "text": text})


## Angebote fuer Artikel und Menge: private Grosshaendler, Import, Unternehmen. Sortiert nach Bewertung (Preis, Lieferzeit, Kritikalitaet).
func quote(item: String, qty: int, crit: int = 1) -> Array:
	var it: Dictionary = CityGoods.get_item(item)
	var out: Array = []
	var cat_price := float(it.price)
	if Trader.MATERIALS.has(item) and sim.trader.stock_of(item) >= qty:
		out.append({"supplier": "T0", "unit_price": sim.trader.price(item, qty), "lead": 0, "loc": sim.trader.bauhof, "name": "Bauhof (privater Großhandel)"})
	out.append({"supplier": "X0", "unit_price": snappedf(cat_price * CityGoods.IMPORT_FACTOR, 0.01), "lead": int(it.lead) + CityGoods.IMPORT_LEAD, "loc": port, "name": "Import (Ausland)"})
	for of in offers.values():
		if of.item == item and int(of.left) >= qty and sim.stock.available(item, "C%d" % of.cid, int(of.loc)) >= qty:
			out.append({"supplier": "C%d" % of.cid, "unit_price": float(of.price), "lead": int(of.lead), "loc": int(of.loc), "name": sim.company(int(of.cid)).company_name, "offer": of.id})
	for q in out:
		q["total"] = snappedf(float(q.unit_price) * qty, 0.01)
		q["score"] = float(q.total) * (1.0 + 0.02 * float(q.lead) * float(crit))   # kritische Ware: Lieferzeit zaehlt mehr
	out.sort_custom(func(a, b): return a.score < b.score)
	return out


## Unternehmen bietet eigene Ware (im StockBook am angegebenen Ort) der Stadt an.
func offer_supply(cid: int, item: String, qty: int, price: float, lead: int = 1) -> Dictionary:
	var c = sim.company(cid)
	if c == null or not c.is_active():
		return {"ok": false, "msg": "Unternehmen kann nicht liefern."}
	if not CityGoods.exists(item):
		return {"ok": false, "msg": "%s steht nicht im Katalog der Stadt." % item}
	if qty <= 0 or price <= 0.0:
		return {"ok": false, "msg": "Menge und Preis müssen positiv sein."}
	var loc := int(c.depots[0])
	if sim.stock.available(item, "C%d" % cid, loc) < qty:
		return {"ok": false, "msg": "Im Depot liegen nur %d × %s." % [sim.stock.available(item, "C%d" % cid, loc), item]}
	var of := {"id": "O%d" % _next_offer, "cid": cid, "item": item, "qty": qty, "left": qty, "price": price, "lead": lead, "loc": loc, "day": _today()}
	_next_offer += 1
	offers[of.id] = of
	return {"ok": true, "msg": "Angebot %s: %d × %s zu %s." % [of.id, qty, item, Catalog.money(price)], "id": of.id}


# ------------------------------------------------------------------ Freigabe und Bestellung
func _decide(day: int) -> void:
	for o in orders.values():
		if o.status != "vorschlag":
			continue
		var best := quote(o.item, int(o.qty), int(o.crit))
		var value := float(best[0].total) if not best.is_empty() else 0.0
		o["estimate"] = value
		var wait := day - int(o.day)
		if value > APPROVAL_LIMIT:
			# grosse Vorhaben entscheidet die Buergermeisterebene; kritische Ware wird nach 6 Tagen notfalls routinemaessig genehmigt
			if not (int(o.crit) >= 3 and wait >= 6):
				continue
		elif wait < 1 and int(o.crit) < 3:
			continue
		approve(o.id, "Verwaltung (Routine)")


## Budgetfreigabe und Bestellung. Gibt {ok, msg} zurueck. `by`: wer entscheidet (Buergermeister oder Verwaltung).
func approve(order_id: String, by: String, reason: String = "") -> Dictionary:
	var o: Dictionary = orders.get(order_id, {})
	if o.is_empty() or o.status != "vorschlag":
		return {"ok": false, "msg": "Vorschlag %s ist nicht offen." % order_id}
	var qty := int(o.qty)
	qty = mini(qty, zone_free(str(CityGoods.get_item(o.item).zone)))
	if qty <= 0:
		return {"ok": false, "msg": "Kein Lagerplatz im Bereich %s." % CityGoods.ZONES[CityGoods.get_item(o.item).zone].label}
	var quotes := quote(o.item, qty, int(o.crit))
	if quotes.is_empty():
		return {"ok": false, "msg": "Kein Anbieter für %s." % o.item}
	var best: Dictionary = quotes[0]
	var freight := _freight(o.item, qty, int(best.loc))
	var cost := float(best.total) + freight
	var M: Mayor = sim.mayor
	if M.available_budget() < cost:
		_log(o, "Budgetfreigabe nicht möglich: %s nötig, %s verfügbar" % [Catalog.money(cost), Catalog.money(M.available_budget())])
		o.decision = "Budget fehlt"
		return {"ok": false, "msg": "Budget reicht nicht: %s nötig, %s verfügbar." % [Catalog.money(cost), Catalog.money(M.available_budget())]}
	o.qty = qty
	o.supplier = best.supplier
	o.unit_price = float(best.unit_price)
	o.price = float(best.total)
	o.freight = freight
	o.committed = cost
	o["loc"] = int(best.loc)
	o["offer"] = best.get("offer", "")
	o.due = _today() + int(best.lead) + 4
	o["ordered"] = _today()
	o.decided_by = by
	o.decision = reason if reason != "" else "Bedarf, Budget und Lieferzeit geprüft"
	M.commitments += cost
	if best.supplier == "X0":
		o.status = "bestellt"
	else:
		var owner: String = str(best.supplier)
		if not sim.stock.reserve("order:" + str(o.id), o.item, qty, owner, int(best.loc)):
			M.commitments = maxf(0.0, M.commitments - cost)
			o.committed = 0.0
			return {"ok": false, "msg": "Anbieter %s hat %s nicht mehr verfügbar." % [owner, o.item]}
		if best.has("offer"):
			offers[best.offer].left = int(offers[best.offer].left) - qty
		o.status = "bestellt"
	_log(o, "%s genehmigt: %d × %s bei %s für %s + Transport %s" % [by, qty, CityGoods.get_item(o.item).name, best.name, Catalog.money(o.price), Catalog.money(freight)])
	sim.log_event("Stadtlager bestellt %d × %s bei %s (%s)." % [qty, CityGoods.get_item(o.item).name, best.name, Catalog.money(cost)], "info")
	return {"ok": true, "msg": "Bestellung %s: %d × %s bei %s, %s." % [o.id, qty, CityGoods.get_item(o.item).name, best.name, Catalog.money(cost)]}


func reject(order_id: String, by: String, reason: String) -> Dictionary:
	var o: Dictionary = orders.get(order_id, {})
	if o.is_empty() or o.status != "vorschlag":
		return {"ok": false, "msg": "Vorschlag %s ist nicht offen." % order_id}
	o.status = "abgelehnt"
	o.decided_by = by
	o.decision = reason
	_log(o, "%s lehnt ab: %s" % [by, reason])
	return {"ok": true, "msg": "Vorschlag %s abgelehnt." % order_id}


func _freight(item: String, qty: int, from_loc: int) -> float:
	var src: Dictionary = sim.city.building(from_loc)
	var dst: Dictionary = sim.city.building(building)
	var dist := absi(src.road.x - dst.road.x) + absi(src.road.y - dst.road.y)
	var cq := _cargo_qty(qty)
	return snappedf(FREIGHT_BASE + float(dist) * 3.2 * (1.0 + float(cq) / 8.0) * 0.85 * 0.5, 1.0)


func _cargo_qty(qty: int) -> int:
	return maxi(1, int(ceil(float(qty) / 40.0)))


static func cargo_of(item: String) -> String:
	match str(CityGoods.get_item(item).get("group", "")):
		"elektro", "verwaltung":
			return "elektronik"
		"schule":
			return "lebensmittel" if item == "verpflegung" else "moebel"
		"fuhrpark", "geraete", "einsatz":
			return "maschinenteile"
		"betriebsmittel":
			return "getraenke"
	return "baustoffe"


# ------------------------------------------------------------------ Transport
func _advance_orders(day: int) -> void:
	for o in orders.values():
		match o.status:
			"bestellt":
				if o.supplier == "X0":
					if day >= int(o.get("ordered", o.day)) + int(CityGoods.get_item(o.item).lead) + CityGoods.IMPORT_LEAD:
						# Importware trifft am Anlieferpunkt ein und gehoert bis zur Anlieferung dem Ausland
						sim.stock.add(o.item, int(o.qty), "X0", port, "Import Stadtlager")
						sim.stock.reserve("order:" + str(o.id), o.item, int(o.qty), "X0", port)
						_issue_contract(o)
				else:
					_issue_contract(o)
			"transport", "unterwegs":
				_watch_contract(o, day)


func _issue_contract(o: Dictionary) -> void:
	var src: Dictionary = sim.city.building(int(o.loc))
	var dst: Dictionary = sim.city.building(building)
	var k := Contract.new()
	k.id = "A%d" % sim.market.next_id
	sim.market.next_id += 1
	k.pickup = int(o.loc)
	k.dropoff = building
	k.cargo = cargo_of(o.item)
	k.label = "Stadtlager: %d × %s" % [int(o.qty), CityGoods.get_item(o.item).name]
	k.qty = _cargo_qty(int(o.qty))
	k.reward = float(o.freight)
	k.status = "open"
	k.payer = OWNER
	k.order_ref = str(o.id)
	k.created = sim.game_min
	k.offer_until = sim.game_min + GameCalendar.days_to_min(float(FALLBACK_DAYS))
	k.deadline = sim.game_min + GameCalendar.days_to_min(float(FALLBACK_DAYS + 3))
	k.distance = absi(src.road.x - dst.road.x) + absi(src.road.y - dst.road.y)
	sim.contracts[k.id] = k
	o.contract = k.id
	o.status = "transport"
	_log(o, "Transportauftrag %s ausgeschrieben (Vergütung %s)" % [k.id, Catalog.money(float(o.freight))])


func _watch_contract(o: Dictionary, day: int) -> void:
	var k: Contract = sim.contracts.get(o.contract)
	if k != null and k.status in ["accepted", "assigned", "loading", "in_transit"]:
		if o.status == "transport":
			o.status = "unterwegs"
			_log(o, "Transport übernommen von %s" % sim.company(k.owner).company_name)
		return
	if k != null and k.status == "open":
		if sim.game_min <= k.offer_until:
			return
		k.status = "expired"       # nicht uebernommen (der Markt markiert dies sonst erst zur naechsten Spielminute)
	if k != null and k.status == "delivered":
		return              # Anlieferung wird ueber contract_delivered() gebucht
	# abgelaufen, gescheitert, storniert oder aus dem Speicher entfernt
	if int(o.reissued) < MAX_REISSUE and o.status == "transport":
		o.reissued = int(o.reissued) + 1
		_log(o, "Transportauftrag nicht ausgeführt, neu ausgeschrieben")
		_issue_contract(o)
	else:
		_fallback_trip(o)


## Stadtfuhrpark fuehrt den Transport aus, wenn kein Unternehmen ihn uebernommen hat. Lohn an S0.
func _fallback_trip(o: Dictionary) -> void:
	var ref := "order:" + str(o.id)
	var pay := minf(float(o.freight) * 0.7, maxf(0.0, float(sim.economy.accounts.P0)))
	sim.economy.transfer(OWNER, "S0", pay)
	stats.freight += pay
	stats.fallback_trips += 1
	o.freight_paid = pay
	_log(o, "Stadtfuhrpark liefert (Kosten %s)" % Catalog.money(pay))
	_receive(o, ref)


## Vom Simulationskern aufgerufen, wenn ein Unternehmen den Transport abgeliefert hat. `paid` = ausgezahlte Verguetung.
func contract_delivered(k: Contract) -> void:
	var o: Dictionary = orders.get(k.order_ref, {})
	if o.is_empty() or o.status not in ["transport", "unterwegs"]:
		return
	o.freight_paid = k.paid
	stats.freight += k.paid
	_log(o, "Anlieferung durch %s (Vergütung %s)" % [sim.company(k.owner).company_name, Catalog.money(k.paid)])
	_receive(o, "order:" + str(o.id))


## Ware am Wareneingang: Eigentum geht auf die Stadt ueber, Zustand "pruefung" (nicht verfuegbar bis zur Einlagerung).
func _receive(o: Dictionary, ref: String) -> void:
	var moved: int = sim.stock.move_reserved(ref, OWNER, building, "Anlieferung Stadtlager %s" % o.id, sim.game_min, "pruefung")
	o.arrived = _today()
	o.status = "angeliefert"
	o.qty_received = moved
	_log(o, "Wareneingang: %d × %s zur Prüfung" % [moved, CityGoods.get_item(o.item).name])


# ------------------------------------------------------------------ Lagerpersonal, Rampen, Geraete (Abschnitt 7)
## Lagerpersonal sind Buerger der Stadt mit Arbeitgeber "stadtlager": derselbe Arbeitsvertrag, Lohn (P0), Lohnsteuer und Sozialabgaben wie sonst.
func roster() -> Array:
	var out: Array = []
	var i := 0
	for p in sim.citizens.people:
		if p.employer != "stadtlager":
			continue
		var st: Dictionary = crew.get(int(p.id), {"fatigue": 0.0, "sick_until": -1, "rest_until": -1})
		var role: String = ROLE_CYCLE[i % ROLE_CYCLE.size()]
		out.append({"id": int(p.id), "name": p.name, "role": role, "role_label": ROLES[role].label, "wage": float(p.wage), "fatigue": float(st.fatigue),
			"state": _state_of(st), "available": _state_of(st) == "verfügbar"})
		i += 1
	return out


func _state_of(st: Dictionary) -> String:
	var day := _today()
	if int(st.sick_until) >= day:
		return "krank"
	if int(st.rest_until) >= day:
		return "erschöpft (Pause)"
	return "verfügbar"


func _crew_day(day: int) -> void:
	for w in roster():
		var st: Dictionary = crew.get(w.id, {"fatigue": 0.0, "sick_until": -1, "rest_until": -1})
		if int(st.sick_until) < day and int(st.rest_until) < day:
			st.fatigue = float(st.fatigue) + 7.0
			if float(st.fatigue) >= REST_FATIGUE:
				st.rest_until = day + 1
				st.fatigue = 30.0
			elif float(absi(hash([w.id, day, "krank"])) % 1000) / 1000.0 < SICK_CHANCE:
				st.sick_until = day + 2 + absi(hash([w.id, day])) % 3
		else:
			st.fatigue = maxf(0.0, float(st.fatigue) - 10.0)
		crew[w.id] = st


func forklifts() -> int:
	return sim.stock.qty("gabelstapler", OWNER, building)


func hand_trucks() -> int:
	return sim.stock.qty("hubwagen", OWNER, building)


## Einheiten, die der Wareneingang heute pruefen und einlagern kann: Leistung des verfuegbaren Personals, Staplerfahrer nur mit freiem Stapler,
## Hubwagen und ein Vorarbeiter (Organisation) erhoehen sie.
func dock_capacity() -> int:
	var total := 0.0
	var free_forklifts := forklifts()
	var foreman := false
	for w in roster():
		if not w.available:
			continue
		if w.role == "stapler":
			if free_forklifts <= 0:
				total += float(ROLES.lager.rate)     # ohne Stapler arbeitet er von Hand
				continue
			free_forklifts -= 1
		if w.role == "vorarbeiter":
			foreman = true
		total += float(ROLES[w.role].rate)
	total *= 1.0 + 0.05 * float(mini(hand_trucks(), 4))
	if foreman:
		total *= 1.15
	return int(total)


func available_staff() -> int:
	return roster().filter(func(w): return w.available).size()


## Faktor fuer die Entladedauer eines Lkw am Wareneingang: viel Personal und Geraete verkuerzen, wenig verlaengert (0,6 bis 3).
func unload_factor() -> float:
	var hands := 0.0
	for w in roster():
		if w.available and w.role in ["lager", "stapler", "vorarbeiter"]:
			hands += 1.0
	return clampf(3.0 / maxf(hands, 0.5), 0.6, 3.0) * (0.8 if forklifts() > 0 else 1.0)


## Fahrzeuge am Wareneingang: entladend bzw. wartend (Fahrzeuge mit Stopp am Zentrallager).
func trucks_here(states: Array) -> Array:
	var out: Array = []
	for v in sim.vehicles.values():
		if v.state in states and not v.stops.is_empty():
			var k: Contract = sim.contracts.get(v.stops[0].contract_id)
			if k != null and k.order_ref != "" and k.dropoff == building:
				out.append(v)
	return out


func ramps_free() -> int:
	return maxi(0, ramps - trucks_here(["unloading"]).size())


func truck_waits(v) -> void:
	waits += 1
	var day := _today()
	if wait_days.is_empty() or int(wait_days[-1]) != day:
		wait_days.append(day)
		if wait_days.size() > 30:
			wait_days.pop_front()
		sim.log_event("Stadtlager: Lkw von %s wartet wegen belegter Entladerampe." % sim.company(v.owner).company_name, "warn")


func recent_waits() -> int:
	return wait_days.filter(func(d): return d >= _today() - 10).size()


## Rueckstau am Wareneingang: Einheiten, die auf Pruefung und Einlagerung warten.
func backlog_units() -> int:
	var n := 0
	for o in orders.values():
		if o.status == "angeliefert":
			n += int(o.get("qty_received", o.qty))
	return n


## Ausbau: "ramp" (zusaetzliche Entladerampe), "staff" (Lagerkraft einstellen), "forklift" (Gabelstapler kaufen). Kosten aus der Stadtkasse.
func expand(kind: String, by: String = "Verwaltung") -> Dictionary:
	var M: Mayor = sim.mayor
	match kind:
		"ramp":
			if ramps >= MAX_RAMPS:
				return {"ok": false, "msg": "Das Zentrallager hat bereits %d Rampen (Höchstzahl)." % MAX_RAMPS}
			if M.available_budget() < RAMP_COST:
				return {"ok": false, "msg": "Budget reicht nicht für eine Rampe (%s)." % Catalog.money(RAMP_COST)}
			sim.economy.transfer(OWNER, "K0", RAMP_COST)      # Bauleistung der Baufirmen
			ramps += 1
			sim.log_event("Stadtlager: %s lässt eine %d. Entladerampe bauen (%s)." % [by, ramps, Catalog.money(RAMP_COST)], "info")
			return {"ok": true, "msg": "Rampe %d gebaut (%s)." % [ramps, Catalog.money(RAMP_COST)]}
		"forklift":
			var price := float(CityGoods.get_item("gabelstapler").price)
			if M.available_budget() < price:
				return {"ok": false, "msg": "Budget reicht nicht für einen Gabelstapler (%s)." % Catalog.money(price)}
			sim.economy.transfer(OWNER, "X0", price)
			sim.stock.add("gabelstapler", 1, OWNER, building, "Kauf Gabelstapler")
			return {"ok": true, "msg": "Gabelstapler gekauft (%s)." % Catalog.money(price)}
		"staff":
			if roster().size() >= STAFF_MAX:
				return {"ok": false, "msg": "Das Lagerpersonal ist mit %d Stellen ausgelastet." % STAFF_MAX}
			for p in sim.citizens.people:
				if p.employer == "":
					sim.citizens._employ(p, "stadtlager", 0.5)
					sim.citizens.cap["stadtlager"] = int(sim.citizens.cap.get("stadtlager", 0)) + 1
					sim.log_event("Stadtlager: %s stellt %s als Lagerkraft ein." % [by, p.name], "info")
					return {"ok": true, "msg": "%s eingestellt." % p.name}
			return {"ok": false, "msg": "Es gibt keine arbeitslosen Bewerber."}
	return {"ok": false, "msg": "Unbekannte Maßnahme %s (ramp, staff, forklift)." % kind}


## Laufende Kosten je Monat: Loehne des Lagerpersonals und Betrieb der Rampen.
func running_costs() -> Dictionary:
	var wages := 0.0
	for w in roster():
		wages += float(w.wage) * Citizens.HOURS_PER_MONTH
	return {"loehne": wages, "betrieb": 400.0 * float(ramps), "summe": wages + 400.0 * float(ramps)}


## Aktuelle Taetigkeiten am Zentrallager fuer Anzeige und Lageruebersicht. Jede Person und jeder Stapler hoechstens einmal.
## Rueckgabe: {tasks: [{worker, name, role, task, item, ref}], waiting: [Beschreibung], blockers: [Ursachen]}
func current_tasks() -> Dictionary:
	var staff: Array = roster().filter(func(w): return w.available)
	var used := {}
	var forklift_free := forklifts()
	var tasks: Array = []
	var blockers: Array = []
	var wanted: Array = []
	for v in trucks_here(["unloading"]):
		var k: Contract = sim.contracts.get(v.stops[0].contract_id)
		wanted.append({"task": "entlädt", "roles": ["lager", "stapler"], "item": str(orders.get(k.order_ref, {}).get("item", "")), "ref": k.order_ref})
	for o in orders.values():
		if o.status == "angeliefert":
			wanted.append({"task": "prüft Ware", "roles": ["kommission", "lager"], "item": o.item, "ref": o.id})
			wanted.append({"task": "bringt Palette ins Lager", "roles": ["stapler", "lager"], "item": o.item, "ref": o.id, "forklift": true})
	for i in issues.slice(-3):
		if int(i.day) == _today():
			wanted.append({"task": "stellt Lieferung zusammen", "roles": ["kommission", "lager"], "item": i.item, "ref": str(i.ref)})
			wanted.append({"task": "verlädt Ware", "roles": ["stapler", "lager"], "item": i.item, "ref": str(i.ref), "forklift": true})
	for want in wanted:
		var done := false
		for role in want.roles:
			for w in staff:
				if used.has(w.id) or w.role != role:
					continue
				if want.get("forklift", false) and role == "stapler":
					if forklift_free <= 0:
						continue
					forklift_free -= 1
				used[w.id] = true
				tasks.append({"worker": w.id, "name": w.name, "role": w.role, "task": want.task, "item": want.item, "ref": want.ref})
				done = true
				break
			if done:
				break
		if not done:
			blockers.append("%s: kein freier %s" % [want.task, " oder ".join(want.roles.map(func(r): return ROLES[r].label))])
	for w in staff:
		if not used.has(w.id):
			tasks.append({"worker": w.id, "name": w.name, "role": w.role, "task": "organisiert den Ablauf" if w.role == "vorarbeiter" else "bereit", "item": "", "ref": ""})
	var waiting: Array = []
	for v in trucks_here(["waiting_bay"]):
		waiting.append("Lkw von %s wartet auf eine freie Rampe" % sim.company(v.owner).company_name)
	if ramps_free() == 0 and not waiting.is_empty():
		blockers.append("alle %d Rampen belegt" % ramps)
	if forklifts() <= 0:
		blockers.append("kein Gabelstapler vorhanden")
	if available_staff() < roster().size():
		blockers.append("%d Mitarbeiter krank oder in Pause" % (roster().size() - available_staff()))
	return {"tasks": tasks, "waiting": waiting, "blockers": blockers}


# ------------------------------------------------------------------ Warenpruefung, Einlagerung, Zahlung
func _inspect(day: int) -> void:
	var capacity := dock_capacity()
	var full := capacity
	var due: Array = orders.values().filter(func(o): return o.status == "angeliefert" and day - int(o.arrived) >= INSPECTION_DAYS)
	due.sort_custom(func(a, b): return int(a.arrived) < int(b.arrived))
	for o in due:
		var qty := int(o.get("qty_received", o.qty))
		if capacity <= 0:
			break
		if capacity < qty and capacity < full:
			continue            # Wareneingang ausgelastet (zu wenig Personal oder Geraete): wartet bis zum naechsten Tag
		capacity -= qty
		var kind := "C" if str(o.supplier).begins_with("C") else str(o.supplier)
		var rate := float(DEFECT.get(kind, 0.01))
		var bad := int(floor(float(qty) * rate + float(absi(hash(str(o.id))) % 100) / 100.0)) if qty >= 20 else 0
		bad = clampi(bad, 0, qty)
		var good := qty - bad
		if bad > 0:
			sim.stock.consume(o.item, bad, OWNER, building, "Ausschuss Wareneingang %s" % o.id, sim.game_min)   # nicht bezahlt, entsorgt
			stats.scrapped += bad
			_log(o, "Warenprüfung: %d × beschädigt, nicht bezahlt und entsorgt" % bad)
		var stored: int = sim.stock.set_state(o.item, good, OWNER, building, "pruefung", "ok")
		o.good = stored
		o.bad = bad
		o.status = "eingelagert"
		_log(o, "Eingelagert: %d × %s" % [stored, CityGoods.get_item(o.item).name])
		_pay(o)


func _pay(o: Dictionary) -> void:
	var M: Mayor = sim.mayor
	var amount := snappedf(float(o.unit_price) * float(o.good), 0.01)
	var sup: String = str(o.supplier)
	if amount > 0.0:
		var pay := minf(amount, maxf(0.0, float(sim.economy.accounts.P0)))
		if sup.begins_with("C"):
			var c = sim.company(int(sup.substr(1)))
			c.ledger.book("trade_income", pay, true, "Lieferung an das Stadtlager %s" % o.id, sim.game_min, OWNER)
		else:
			sim.economy.transfer(OWNER, sup, pay)
		o.paid = pay
		stats.purchases += pay
	# Reservierung der Ware beim Anbieter: T0 erhaelt den Verkaufserloes, die Menge ist bereits beim Anlieferpunkt uebergegangen
	M.commitments = maxf(0.0, M.commitments - float(o.committed))
	o.committed = 0.0
	o.status = "bezahlt"
	stats.orders_done += 1
	_log(o, "Bezahlt: %s an %s" % [Catalog.money(amount), sup])
	sim.log_event("Stadtlager: %d × %s eingelagert (%s bezahlt)." % [int(o.good), CityGoods.get_item(o.item).name, Catalog.money(amount)], "info")


# ------------------------------------------------------------------ Projekte (Abschnitt 2)
## Material fuer ein Erschliessungsprojekt (Teile x Grundstuecke).
static func material_need(parts: Array, parcels: int) -> Dictionary:
	var out := {}
	for part in parts:
		var m: Dictionary = PROJECT_MATERIAL.get(part, {})
		for it in m:
			out[it] = int(out.get(it, 0)) + int(m[it]) * parcels
	return out


func value_of(items: Dictionary) -> float:
	var v := 0.0
	for it in items:
		v += float(CityGoods.get_item(it).price) * int(items[it])
	return v


## Fehlendes Material fuer das Projekt reservieren. mode: "ueberlassen" (Auftragsmaterial, bleibt bis zur Verwendung Eigentum der Stadt),
## "verkauft" oder "geliehen". Gibt die fehlenden Mengen zurueck (Beschaffungsvorschlaege entstehen dafuer).
func reserve_for_project(project_id: String, items: Dictionary, mode: String = "ueberlassen") -> Dictionary:
	var res: Dictionary = project_res.get(project_id, {"items": items.duplicate(), "mode": mode, "reserved": {}, "value": 0.0})
	res.items = items.duplicate()
	var missing := {}
	for it in items:
		var have := int(res.reserved.get(it, 0))
		var want := int(items[it]) - have
		if want <= 0:
			continue
		var take := mini(want, stock_of(it))
		if take > 0 and sim.stock.reserve("projekt:%s:%s:%d" % [project_id, it, have], it, take, OWNER, building):
			res.reserved[it] = have + take
		var still := int(items[it]) - int(res.reserved.get(it, 0))
		if still > 0:
			missing[it] = still
	var value := 0.0
	for it in res.reserved:
		value += float(CityGoods.get_item(it).price) * int(res.reserved[it])
	res.value = value
	project_res[project_id] = res
	for it in missing:
		if not open_proposal(it) and incoming(it) < int(missing[it]):
			var o := _new_order(it, maxi(int(missing[it]) - incoming(it), 1), "Material für Projekt %s fehlt" % project_id, project_id)
			o.crit = 3
			orders[o.id] = o
	return missing


func project_complete(project_id: String) -> bool:
	var res: Dictionary = project_res.get(project_id, {})
	if res.is_empty():
		return true
	for it in res.items:
		if int(res.reserved.get(it, 0)) < int(res.items[it]):
			return false
	return true


func _top_up_projects() -> void:
	for pid in project_res.keys():
		var res: Dictionary = project_res[pid]
		if res.get("done", false):
			continue
		if not project_complete(pid):
			reserve_for_project(pid, res.items, res.mode)


## Material wird verwendet (Projekt abgeschlossen): reservierte Mengen verbrauchen und die Ausgabe protokollieren.
func consume_project(project_id: String, to: String) -> Dictionary:
	var res: Dictionary = project_res.get(project_id, {})
	if res.is_empty():
		return {}
	var used := {}
	for ref in sim.stock.reservations.keys():
		if str(ref).begins_with("projekt:%s:" % project_id):
			var r: Dictionary = sim.stock.reservations[ref]
			var n: int = sim.stock.consume_reserved(ref, "Projekt %s (%s)" % [project_id, res.mode], sim.game_min)
			used[r.item] = int(used.get(r.item, 0)) + n
			issues.append({"day": _today(), "item": r.item, "qty": n, "to": to, "mode": res.mode, "ref": project_id})
	if issues.size() > 200:
		issues = issues.slice(-200)
	res["done"] = true
	return used


func release_project(project_id: String) -> void:
	for ref in sim.stock.reservations.keys():
		if str(ref).begins_with("projekt:%s:" % project_id):
			sim.stock.release(ref)
	project_res.erase(project_id)


## Material an eigene Mitarbeiter ausgeben (Verbrauch im Dienst).
func issue_to_staff(item: String, qty: int, to: String, reason: String) -> Dictionary:
	if not CityGoods.exists(item):
		return {"ok": false, "msg": "Artikel %s unbekannt." % item}
	var n: int = sim.stock.consume(item, mini(qty, stock_of(item)), OWNER, building, "Ausgabe an %s: %s" % [to, reason], sim.game_min)
	if n <= 0:
		return {"ok": false, "msg": "%s ist nicht vorrätig." % item}
	issues.append({"day": _today(), "item": item, "qty": n, "to": to, "mode": "ausgegeben", "ref": reason})
	return {"ok": true, "msg": "%d × %s an %s ausgegeben." % [n, item, to], "qty": n}


# ------------------------------------------------------------------ Monat: Ueberschuesse verkaufen
## Transparente Regel: Bestand ueber dem 1,5-fachen Zielbestand wird zum halben Katalogpreis verkauft (Grosshaendler T0, sonst Ausland).
func on_month(_month: int) -> void:
	for id in CityGoods.items():
		var it: Dictionary = CityGoods.get_item(id)
		if it.class == "geraet":
			continue
		var limit := int(float(it.target) * SURPLUS_FACTOR)
		var over := stock_of(id) - limit
		if over <= 0:
			continue
		var buyer := "T0" if Trader.MATERIALS.has(id) and float(sim.economy.accounts.T0) > 5000.0 else "X0"
		var amount := snappedf(float(it.price) * SURPLUS_PRICE * float(over), 0.01)
		if buyer == "T0":
			amount = minf(amount, float(sim.economy.accounts.T0) - 5000.0)
			sim.stock.move(id, over, OWNER, building, "T0", sim.trader.bauhof, "Verkauf Überbestand Stadtlager", sim.game_min)
		else:
			sim.stock.consume(id, over, OWNER, building, "Verkauf Überbestand (Export)", sim.game_min)
		sim.economy.transfer(buyer, OWNER, amount)
		stats.sold += amount
		sim.log_event("Stadtlager verkauft Überbestand: %d × %s für %s." % [over, it.name, Catalog.money(amount)], "info")


# ------------------------------------------------------------------ Abfragen
func status_of_item(id: String) -> Dictionary:
	var it: Dictionary = CityGoods.get_item(id)
	return {"id": id, "name": it.name, "gruppe": it.group_label, "einheit": it.unit, "bestand": on_hand(id), "frei": stock_of(id), "unterwegs": incoming(id), "meldebestand": it.reorder,
		"zielbestand": it.target, "mindestbestand": it.min, "kritikalitaet": it.crit}


## Kritische Artikel: unter Mindestbestand oder aufgebraucht.
func critical_items() -> Array:
	var out: Array = []
	for id in CityGoods.items():
		var it: Dictionary = CityGoods.get_item(id)
		if on_hand(id) < int(it.min) and it.use > 0.0:
			out.append(status_of_item(id))
	return out


func open_orders() -> Array:
	return orders.values().filter(func(o): return o.status in ["vorschlag", "bestellt", "transport", "unterwegs", "angeliefert"])


func summary() -> Dictionary:
	var by := {}
	for o in orders.values():
		by[o.status] = int(by.get(o.status, 0)) + 1
	var zones := {}
	for z in CityGoods.ZONES:
		zones[z] = {"belegt": zone_used(z) , "kapazitaet": int(CityGoods.ZONES[z].cap)}
	return {"bestellungen": by, "kritisch": critical_items().size(), "zonen": zones, "einkauf": stats.purchases, "fracht": stats.freight, "verkauft": stats.sold}


func to_dict() -> Dictionary:
	return {"ramps": ramps, "crew": crew, "waits": waits, "wait_days": wait_days, "building": building, "port": port, "orders": orders, "offers": offers, "project_res": project_res, "issues": issues.slice(-80), "shortages": shortages, "carry": carry,
		"stats": stats, "next": [_next_order, _next_offer]}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		if sim.stock.of_owner(OWNER).filter(func(l): return l.loc == building).is_empty():
			_seed_stock()          # Spielstand aus der Zeit vor dem Stadtlager
		return
	ramps = int(d.get("ramps", RAMPS_START))
	crew = {}
	for k in d.get("crew", {}):
		var c: Dictionary = d.crew[k]
		crew[int(k)] = {"fatigue": float(c.fatigue), "sick_until": int(c.sick_until), "rest_until": int(c.rest_until)}
	waits = int(d.get("waits", 0))
	wait_days = d.get("wait_days", []).map(func(x): return int(x))
	building = int(d.get("building", building))
	port = int(d.get("port", port))
	orders = d.get("orders", {})
	for o in orders.values():
		for k in ["qty", "crit", "reissued", "due", "day", "good", "bad", "loc", "arrived", "qty_received", "ordered"]:
			if o.has(k):
				o[k] = int(o[k])
	offers = d.get("offers", {})
	for of in offers.values():
		for k in ["cid", "qty", "left", "lead", "loc", "day"]:
			of[k] = int(of[k])
	project_res = d.get("project_res", {})
	for r in project_res.values():
		for k in r.items:
			r.items[k] = int(r.items[k])
		for k in r.reserved:
			r.reserved[k] = int(r.reserved[k])
	issues = d.get("issues", [])
	shortages = d.get("shortages", {})
	carry = d.get("carry", {})
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[k] = st[k]
	var nx: Array = d.get("next", [1, 1])
	_next_order = int(nx[0])
	_next_offer = int(nx[1])
