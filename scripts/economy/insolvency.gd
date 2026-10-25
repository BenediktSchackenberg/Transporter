class_name Insolvency
extends RefCounted
## Zahlungsfaehigkeit, Insolvenzverfahren, Auktionen, Glaeubigerverteilung und Neugruendung (docs/ECONOMY.md Abschnitte 6 und 7).
##
## Aktiv -> Liquiditaetswarnung -> Zahlungsverzug (Nachfrist) -> Insolvenz (Verwalter) -> Verwertung (Auktionen) -> Geschlossen
## Das Firmenbuch der insolventen Firma ist die Insolvenzmasse: alle Zahlungen laufen ueber ihr Ledger, daher bleibt das Geld erhalten.
## Nach der Schliessung besetzt nach einer Wartezeit ein neuer Unternehmer denselben Platz (neue Identitaet, Kapital aus dem Investorenpool I0).

signal company_refounded(cid: int)

const GRACE_DAYS := 15.0          # Nachfrist bei Zahlungsverzug
const PROCESS_DAYS := 2.0         # Verwalter inventarisiert
const AUCTION_DAYS := 5.0
const FOUNDING_WAIT_DAYS := 10.0
const FOUNDING_CAPITAL := 40000.0
const INVESTOR_INFLOW := 3000.0   # je Monat von X0 nach I0
const INVESTOR_CAP := 120000.0
const DEALER_BID := 0.55          # Fahrzeughaendler bietet diesen Anteil des Buchwerts
const COST_SHARE := 0.10          # Verwertungskosten (max. Anteil am Erloes)
const COST_MIN := 200.0
const CLEAR_COST := 0.15          # Raeumung ohne Bieter, Anteil der Investition
const MIN_RAISE := 1.05
const ADMINS := ["Dr. Weber", "Dr. Hartmann", "Frau Lindner", "Herr Albrecht", "Dr. Yilmaz", "Frau Krämer"]
const NAMES_FIRST := ["Anja", "Boris", "Carla", "Dennis", "Esra", "Falk", "Gesa", "Hakan", "Ingo", "Jule", "Kerem", "Lotte"]
const NAMES_LAST := ["Brandt", "Kaya", "Vogel", "Neumann", "Schäfer", "Demir", "Roth", "Winter", "Maurer", "Böhm"]
const FIRM_WORDS := ["Logistik", "Transporte", "Fracht", "Kurier", "Spedition", "Express"]

var sim: Simulation
var enabled := true
var auctions := {}        # Auktions-ID -> Dictionary
var archive: Array = []   # geschlossene Unternehmen (Historie, Ranglisten)
var liquidation := {}     # Firma -> {proceeds, secured: {Kredit: Betrag}, clear_cost, sold, claims}
var _next_auction := 1


func setup(s: Simulation) -> void:
	sim = s
	s.day_changed.connect(on_day)
	s.month_changed.connect(on_month)


# ------------------------------------------------------------------ Zahlungsfaehigkeit
## Pflichten der naechsten 30 Spieltage (Raten, Loehne, Mieten, Verwaltung).
func obligations_30d(c: Company) -> float:
	var minutes := GameCalendar.days_to_min(30.0)
	var rent: float = Catalog.EXTRA_DEPOT_RENT * c.depots.filter(func(site): return not sim.estate.is_plot(site)).size()
	var per_min: float = sim.personnel.wages_per_hour(c.id) / 60.0 + (rent + Catalog.SECURITY_PER_DAY[c.security_level]
		+ (Catalog.INSURANCE_PER_DAY if c.insurance else 0.0)) / 1440.0
	var due: float = per_min * minutes + float(CompanyForms.FORMS[c.form].admin)
	var month := GameCalendar.month_of(sim.game_min)
	for l in sim.banking.claims_of(c.id):
		for r in l.plan:
			if r.status != "bezahlt" and int(r.month) <= month + 1:
				due += float(r.pay)
	return due


func liquid_funds(c: Company) -> float:
	var f := c.ledger.cash
	for d in sim.banking.deposits.values():
		if d.owner == c.id and d.kind == "tages":
			f += float(d.amount)
	return f


func has_arrears(c: Company) -> bool:
	for l in sim.banking.loans.values():
		if l.owner == c.id and l.status in ["rueckstand", "ausgefallen"] and float(l.outstanding) > 0.005 and l.purpose != "Überziehung":
			return true
	return false


func _set_status(c: Company, status: String, reason: String) -> void:
	if c.status == status:
		c.status_reason = reason
		return
	c.status = status
	c.status_since = sim.game_min
	c.status_reason = reason
	var labels := {"aktiv": "ist wieder zahlungsfähig", "warnung": "Liquiditätswarnung", "verzug": "Zahlungsverzug", "insolvenz": "Insolvenzverfahren eröffnet",
		"verwertung": "Verwertung beginnt", "geschlossen": "geschlossen"}
	sim.log_event("%s: %s – %s" % [c.company_name, labels[status], reason], "bad" if status in ["verzug", "insolvenz", "verwertung", "geschlossen"] else "info", c.id)
	c.add_key_event(labels[status].capitalize(), sim.game_min)


func _check_active(c: Company) -> void:
	var in_default := c.ledger.cash < 0.0 or has_arrears(c)
	if in_default:
		if c.status != "verzug":
			c.grace_until = sim.game_min + GameCalendar.days_to_min(GRACE_DAYS)
			_set_status(c, "verzug", "fällige Zahlung nicht möglich (Bargeld %s); Nachfrist bis %s" % [Catalog.money(c.ledger.cash),
				GameCalendar.short_text(c.grace_until)])
			sim.notify(c.id, "Zahlungsverzug! Nachfrist %d Spieltage: Forderungen einziehen, Vermögen verkaufen oder Finanzierung beschaffen." % int(GRACE_DAYS))
		elif sim.game_min >= c.grace_until:
			_open(c)
		return
	var need := obligations_30d(c)
	var liquid := liquid_funds(c)
	if liquid < need:
		_set_status(c, "warnung", "flüssige Mittel %s decken die Pflichten der nächsten 30 Tage (%s) nicht" % [Catalog.money(liquid), Catalog.money(need)])
	else:
		_set_status(c, "aktiv", "")
	c.grace_until = -1.0


# ------------------------------------------------------------------ Verfahren
func _open(c: Company) -> void:
	c.administrator = ADMINS[(c.id + sim.banking.loans.size() + int(sim.game_min)) % ADMINS.size()]
	_set_status(c, "insolvenz", "Verwalter %s übernimmt, Vermögen eingefroren" % c.administrator)
	sim.banking.record_overdraft(c.id)
	# Laufende Kundenauftraege werden geregelt abgebrochen und neu ausgeschrieben
	var n := 0
	for k in sim.contracts.values():
		if k.owner == c.id and k.status in ["accepted", "assigned", "loading", "in_transit"]:
			sim.logistics.close_contract(k)
			k.owner = -1
			k.status = "open"
			k.vehicle_id = -1
			k.picked = 0
			k.delivered_qty = 0
			k.offer_until = sim.game_min + 360.0
			k.exclusive_for = -1
			n += 1
	for v in sim.company_vehicles(c.id):
		v.stops.clear()
		v.queue.clear()
		v.contract_id = ""
		if v.state not in ["broken", "repairing"]:
			v.state = "idle"
		sim.logistics.sync_view(v)
	# Personal wird wieder verfuegbar
	for t in sim.personnel.tasks.values():
		if t.company == c.id and not t.is_final():
			sim.personnel.cancel_task(t, "Insolvenz")
	for w in sim.personnel.employed(c.id):
		w.employer = -1
		w.vehicle_id = -1
		w.task_id = ""
		w.foreman = ""
		w.supervised.clear()
		w.leaving = false
	for k in sim.customers:
		if sim.customers[k].get("loyal", -1) == c.id:
			sim.customers[k].loyal = -1
	for o in sim.social.offers.values():
		if o.status == "open" and (o.from == c.id or o.to == c.id):
			o.status = "expired"
	sim.log_event("Insolvenzverwalter %s: %d laufende Aufträge von %s werden neu ausgeschrieben." % [c.administrator, n, c.company_name], "bad", c.id)


func _start_liquidation(c: Company) -> void:
	_set_status(c, "verwertung", "Vermögensverzeichnis erstellt, Auktionen laufen %d Spieltage" % int(AUCTION_DAYS))
	sim.banking.liquidate_deposits(c.id)
	var stock_proceeds: float = sim.trader.liquidate_stock(c.id)
	liquidation[c.id] = {"proceeds": stock_proceeds, "secured": {}, "clear_cost": 0.0, "sold": [], "claims": 0.0}
	var end := sim.game_min + GameCalendar.days_to_min(AUCTION_DAYS)
	for v in sim.company_vehicles(c.id):
		var a := _new_auction(c.id, "vehicle", v.id, "%s #%d" % [Catalog.model(v.model).name, v.id], v.book_value, end)
		a.bids.append({"by": -2, "amount": snappedf(v.book_value * DEALER_BID, 0.01)})   # Fahrzeughaendler
		var lid := sim.banking.pledged_to(v.id)
		if lid != "":
			a.loan = lid
	var plots := sim.estate.plot_of(c.id)
	if not plots.is_empty():
		var root := -1
		for p in plots:
			if int(p.parent) < 0:
				root = int(p.id)
				break
		var value := c.property_book + c.land_book
		var a2 := _new_auction(c.id, "site", maxi(root, int(plots[0].id)), "Standort %s mit Gebäuden" % sim.city.building(maxi(root, int(plots[0].id))).name, value, end)
		a2.min_price = snappedf(value * 0.2, 0.01)


func _new_auction(cid: int, kind: String, ref: int, title: String, value: float, end: float) -> Dictionary:
	var a := {"id": "A%d" % _next_auction, "cid": cid, "kind": kind, "ref": ref, "title": title, "value": snappedf(value, 0.01),
		"end": end, "bids": [], "status": "offen", "loan": "", "min_price": 0.0, "price": 0.0, "winner": -1}
	_next_auction += 1
	auctions[a.id] = a
	sim.log_event("Auktion %s: %s (Wert %s) aus der Insolvenzmasse von %s." % [a.id, title, Catalog.money(value), sim.company(cid).company_name], "info", cid)
	return a


func top_bid(a: Dictionary) -> Dictionary:
	var best := {"by": -1, "amount": 0.0}
	for b in a.bids:
		if float(b.amount) > float(best.amount):
			best = b
	return best


## Gebot eines Unternehmens. Das Geld wird erst beim Zuschlag bezahlt, muss dann aber vorhanden sein.
func bid(cid: int, auction_id: String, amount: float) -> Dictionary:
	var a: Dictionary = auctions.get(auction_id, {})
	if a.is_empty() or a.status != "offen":
		return {"ok": false, "msg": "Auktion %s ist nicht offen." % auction_id}
	var c := sim.company(cid)
	if not c.is_active():
		return {"ok": false, "msg": "Im Insolvenzverfahren kann nicht geboten werden."}
	if cid == a.cid:
		return {"ok": false, "msg": "Eigene Masse: Gebote nicht erlaubt."}
	var top := top_bid(a)
	if amount < float(a.min_price) or amount < float(top.amount) * MIN_RAISE or amount <= 0.0:
		return {"ok": false, "msg": "Gebot zu niedrig (höchstes Gebot %s, Mindeststeigerung 5 %%, Mindestpreis %s)." % [Catalog.money(top.amount), Catalog.money(a.min_price)]}
	if c.ledger.cash < amount:
		return {"ok": false, "msg": "Nicht genug Bargeld: %s benötigt." % Catalog.money(amount)}
	if a.kind == "vehicle" and c.vehicle_ids.size() >= c.fleet_limit():
		return {"ok": false, "msg": "Kein freier Stellplatz."}
	a.bids.append({"by": cid, "amount": snappedf(amount, 0.01)})
	sim.log_event("%s bietet %s auf %s (%s)." % [c.company_name, Catalog.money(amount), a.id, a.title], "info", cid)
	return {"ok": true, "msg": "Gebot %s auf %s abgegeben." % [Catalog.money(amount), a.id]}


func open_auctions() -> Array:
	return auctions.values().filter(func(a): return a.status == "offen")


# ------------------------------------------------------------------ Zeitablauf
func on_day(_day: int) -> void:
	if not enabled:
		return
	CompanyForms.finish_due(sim)
	for c in sim.companies:
		match c.status:
			"aktiv", "warnung", "verzug":
				_check_active(c)
			"insolvenz":
				if sim.game_min >= c.status_since + GameCalendar.days_to_min(PROCESS_DAYS):
					_start_liquidation(c)
			"verwertung":
				if open_auctions().filter(func(a): return a.cid == c.id).is_empty():
					_settle(c)
			"geschlossen":
				_maybe_refound(c)
	for a in open_auctions():
		if sim.game_min >= a.end:
			_close_auction(a)


func on_month(_month: int) -> void:
	# Investorenpool: kleiner, gedeckelter Zufluss aus dem Ausland
	var room := maxf(0.0, INVESTOR_CAP - sim.economy.accounts.I0)
	sim.economy.transfer("X0", "I0", minf(INVESTOR_INFLOW, room))
	CompanyForms.monthly(sim, _month)


func _close_auction(a: Dictionary) -> void:
	var c := sim.company(a.cid)
	var bids: Array = a.bids.duplicate()
	bids.sort_custom(func(x, y): return float(x.amount) > float(y.amount))
	for b in bids:
		if b.by == -2:
			_sell_to_dealer(c, a, float(b.amount))
			return
		var buyer := sim.company(int(b.by))
		if not buyer.is_active() or buyer.ledger.cash < float(b.amount):
			continue
		if a.kind == "vehicle":
			if buyer.vehicle_ids.size() >= buyer.fleet_limit():
				continue
			_sell_vehicle(c, a, buyer, float(b.amount))
		else:
			_sell_site(c, a, buyer, float(b.amount))
		return
	a.status = "ohne_gebot"
	if a.kind == "site":
		_clear_site(c, a)
	else:
		_sell_to_dealer(c, a, snappedf(float(a.value) * 0.4, 0.01))   # Notverkauf an den Haendler


func _record_sale(c: Company, a: Dictionary, price: float, winner: int) -> void:
	a.status = "verkauft"
	a.price = price
	a.winner = winner
	var L: Dictionary = liquidation[c.id]
	L.proceeds += price
	if a.loan != "":
		L.secured[a.loan] = float(L.secured.get(a.loan, 0.0)) + price
		var loan: Dictionary = sim.banking.loans[a.loan]
		loan.collateral = -1
	sim.log_event("Zuschlag %s: %s für %s an %s." % [a.id, a.title, Catalog.money(price), "den Händler" if winner < 0 else sim.company(winner).company_name], "info", c.id)


func _release_vehicle(v: FleetVehicle) -> void:
	v.operator = -1
	v.stops.clear()
	v.queue.clear()
	v.load.clear()
	v.contract_id = ""


func _sell_to_dealer(c: Company, a: Dictionary, price: float) -> void:
	if a.kind == "vehicle":
		var v: FleetVehicle = sim.vehicles.get(a.ref)
		if v != null:
			c.ledger.divest(price, "S0")
			c.ledger.book("asset_result", price - v.book_value, false, "Auktion %s" % a.id, sim.game_min)
			_release_vehicle(v)
			sim.remove_vehicle(v)
		_record_sale(c, a, price, -1)


func _sell_vehicle(c: Company, a: Dictionary, buyer: Company, price: float) -> void:
	var v: FleetVehicle = sim.vehicles.get(a.ref)
	if v == null:
		return
	buyer.ledger.pay_to(c.ledger, price)
	c.ledger.book("asset_result", price - v.book_value, false, "Auktion %s" % a.id, sim.game_min)
	var model := v.model
	var cond := v.condition
	var tile := v.tile()
	_release_vehicle(v)
	sim.remove_vehicle(v)
	var nv: FleetVehicle = sim.add_vehicle(buyer.id, model, price, tile)
	nv.condition = cond
	_record_sale(c, a, price, buyer.id)
	buyer.add_key_event("Ersteigert: %s" % a.title, sim.game_min)


func _site_plots(cid: int) -> Array:
	return sim.estate.plot_of(cid)


func _sell_site(c: Company, a: Dictionary, buyer: Company, price: float) -> void:
	buyer.ledger.pay_to(c.ledger, price)
	var est: Estate = sim.estate
	for p in _site_plots(c.id):
		p.owner = buyer.id
		p.mode = "kauf"
		p.rent = 0.0
		if int(p.parent) < 0:
			sim.depot_owner[int(p.id)] = buyer.id
			buyer.depots.append(int(p.id))
	for f in est.facilities.values():
		if f.owner == c.id:
			f.owner = buyer.id
	buyer.property_cost += c.property_cost
	buyer.property_book += price
	c.ledger.book("asset_result", price - (c.property_book + c.land_book), false, "Auktion %s" % a.id, sim.game_min)
	_zero_property(c)
	est._refresh_company(buyer.id)
	_record_sale(c, a, price, buyer.id)
	buyer.add_key_event("Ersteigert: %s" % a.title, sim.game_min)


func _zero_property(c: Company) -> void:
	c.property_book = 0.0
	c.property_cost = 0.0
	c.land_book = 0.0


## Kein Bieter: Gebaeude werden geraeumt (kostet Geld), die Flaeche wird als freies Baufeld angeboten.
func _clear_site(c: Company, a: Dictionary) -> void:
	var est: Estate = sim.estate
	var invest := 0.0
	for fid in est.facilities.keys():
		if est.facilities[fid].owner == c.id:
			invest += float(est.facilities[fid].invest)
			est.facilities.erase(fid)
	for p in _site_plots(c.id):
		p.owner = -1
		p.mode = ""
		p.rent = 0.0
		sim.depot_owner.erase(int(p.id))
	for l in est.leases.values():
		if l.owner == c.id:
			l.status = "beendet"
	liquidation[c.id].clear_cost += invest * CLEAR_COST
	c.ledger.book("asset_result", -(c.property_book + c.land_book), false, "Räumung %s" % a.id, sim.game_min)
	_zero_property(c)
	est._refresh_company(c.id)
	a.status = "geraeumt"
	sim.log_event("Kein Gebot für %s: Der Standort wird geräumt und als freies Baufeld angeboten." % a.title, "info", c.id)


# ------------------------------------------------------------------ Verteilung
func _pay_claim(c: Company, l: Dictionary, amount: float) -> float:
	var pay := minf(snappedf(amount, 0.01), minf(float(l.outstanding), maxf(0.0, c.ledger.cash)))
	if pay <= 0.0:
		return 0.0
	c.ledger.repay(pay, Banking.BANKS[l.bank].id)
	l.outstanding = snappedf(float(l.outstanding) - pay, 0.01)
	return pay


func _settle(c: Company) -> void:
	var L: Dictionary = liquidation.get(c.id, {"proceeds": 0.0, "secured": {}, "clear_cost": 0.0, "sold": [], "claims": 0.0})
	var claims: Array = sim.banking.claims_of(c.id)
	var total_claims := 0.0
	for l in claims:
		total_claims += float(l.outstanding)
	var private := 0.0
	if CompanyForms.FORMS[c.form].private_reserve > 0.0 and total_claims > c.ledger.cash:
		private = minf(float(CompanyForms.FORMS[c.form].private_reserve), total_claims - maxf(c.ledger.cash, 0.0))
		c.ledger.take_private(private)
	# 1. Verwertungskosten
	var cost := minf(maxf(float(L.proceeds) * COST_SHARE, COST_MIN) + float(L.clear_cost), maxf(c.ledger.cash, 0.0))
	if cost > 0.0:
		c.ledger.book("property_costs", -cost, true, "Verwertungskosten (Verwalter %s)" % c.administrator, sim.game_min, "S0")
	# 2. Gesicherte Forderungen aus ihrer Sicherheit
	var recovered := 0.0
	for lid in L.secured:
		recovered += _pay_claim(c, sim.banking.loans[lid], float(L.secured[lid]))
	# 3. Uebrige Forderungen anteilig aus dem Rest
	var rest := maxf(c.ledger.cash, 0.0)
	var open_total := 0.0
	for l in claims:
		open_total += float(l.outstanding)
	if open_total > 0.0 and rest > 0.0:
		var share := minf(1.0, rest / open_total)
		for l in claims:
			recovered += _pay_claim(c, l, float(l.outstanding) * share)
	# Restschulden erlassen (ohne Gewinnbonus), Banken tragen den Verlust
	var lost := 0.0
	for l in claims:
		lost += float(l.outstanding)
		sim.banking.write_off(l)
	# Ueberschuss an die Eigentuemer
	if c.ledger.cash > 0.005:
		c.ledger.pay_out_owner(c.ledger.cash, "H0" if c.form == "einzel" else "I0")
	var quota := 0.0 if total_claims <= 0.0 else 1.0 - recovered / total_claims
	var entry := {"cid": c.id, "name": c.company_name, "owner": c.player_name, "form": c.form, "generation": c.generation, "founded": c.founded_min,
		"closed": sim.game_min, "reason": c.status_reason, "profit": c.ledger.profit(), "claims": total_claims, "recovered": recovered, "lost": lost,
		"quota": quota, "private": private, "proceeds": L.proceeds, "completed": c.stats.completed, "reputation": c.reputation}
	archive.append(entry)
	liquidation.erase(c.id)
	_set_status(c, "geschlossen", "Ausfallquote der Gläubiger %d %% (Forderungen %s, erlöst %s, abgeschrieben %s)" % [int(quota * 100.0),
		Catalog.money(total_claims), Catalog.money(recovered), Catalog.money(lost)])


# ------------------------------------------------------------------ Neugruendung
func free_site() -> int:
	var cands: Array = sim.city.start_depots.duplicate()
	for p in sim.estate.plots.values():
		if int(p.parent) < 0 and int(p.id) not in cands:
			cands.append(int(p.id))
	for s in cands:
		var p: Dictionary = sim.estate.plots.get(s, {})
		if not p.is_empty() and p.owner < 0 and int(p.parent) < 0 and not sim.depot_owner.has(s):
			return s
	return -1


func _maybe_refound(c: Company) -> void:
	if sim.game_min < c.status_since + GameCalendar.days_to_min(FOUNDING_WAIT_DAYS):
		return
	if sim.economy.accounts.I0 < FOUNDING_CAPITAL:
		return
	var site := free_site()
	if site < 0:
		return
	refound(c.id, site)


## Neuer Unternehmer auf dem Platz der geschlossenen Firma (gleiche Nummer, neue Identitaet).
func refound(cid: int, site: int) -> Company:
	var old := sim.company(cid)
	var n := Company.new()
	n.id = cid
	n.generation = old.generation + 1
	n.player_name = "%s %s" % [NAMES_FIRST[sim.rng.randi() % NAMES_FIRST.size()], NAMES_LAST[sim.rng.randi() % NAMES_LAST.size()]]
	n.company_name = "%s %s" % [n.player_name.split(" ")[1], FIRM_WORDS[sim.rng.randi() % FIRM_WORDS.size()]]
	n.color = old.color
	n.avatar_style = old.avatar_style
	n.personality = Catalog.PERSONALITIES.keys()[sim.rng.randi() % Catalog.PERSONALITIES.size()]
	n.form = ["einzel", "ug", "gmbh"][sim.rng.randi() % 3]
	n.founded_min = sim.game_min
	n.ledger = Ledger.new(0.0)
	sim.companies[cid] = n
	sim.economy.attach(n.ledger, "C%d" % cid)
	n.ledger.inject(FOUNDING_CAPITAL)   # aus dem Investorenpool
	n.ledger.book("admin", -float(CompanyForms.FORMS[n.form].found_cost), true, "Gründung " + CompanyForms.name_of(n.form), sim.game_min)
	sim.depot_owner[site] = cid
	n.depots.append(site)
	sim.city.buildings[site].name = n.company_name + " (Betriebshof)"
	sim.estate.grant_start(cid, site)
	for k in sim.contracts:
		if sim.contracts[k].status == "open":
			n.known[k] = true
	var v := sim._create_vehicle(cid, "van", Catalog.model("van").price, sim.depot_road(cid))
	n.ledger.invest(v.purchase_price)
	var av: Avatar = sim.avatars[cid]
	av.pos = sim.city.tile_center(sim.city.building(site).walk)
	av.path.clear()
	av.state = "idle"
	av.pending = {}
	sim.personnel.start_staff(cid, v.id)
	sim.personnel.seen[cid] = {}
	sim._fuel[cid] = 0.0
	sim.action_results[cid] = []
	sim.memory.books[cid] = {"events": [], "experiences": [], "next": 1}
	sim.plans.plans.erase(cid)
	n.ledger.sample(sim.game_min)
	sim.log_event("Neugründung: %s (%s) übernimmt den Platz von %s und startet am Standort %s." % [n.company_name, CompanyForms.name_of(n.form),
		old.company_name, sim.city.building(site).name], "info", cid)
	n.add_key_event("Gegründet als " + CompanyForms.name_of(n.form), sim.game_min)
	company_refounded.emit(cid)
	return n


# ------------------------------------------------------------------ Anzeige
func summary_of(cid: int) -> Dictionary:
	var c := sim.company(cid)
	var out := {"rechtsform": CompanyForms.name_of(c.form), "status": c.status, "gruender_nr": c.generation}
	if c.status_reason != "":
		out["status_grund"] = c.status_reason
	if c.status == "verzug":
		out["nachfrist_bis"] = GameCalendar.short_text(c.grace_until)
	if c.pending_form != "":
		out["formwechsel_zu"] = CompanyForms.name_of(c.pending_form)
	return out


func auction_list(limit: int = 6) -> Array:
	var out: Array = []
	for a in open_auctions().slice(0, limit):
		var t := top_bid(a)
		out.append({"id": a.id, "art": "Fahrzeug" if a.kind == "vehicle" else "Standort", "bezeichnung": a.title, "wert": int(a.value),
			"hoechstgebot": int(t.amount), "mindestpreis": int(a.min_price), "endet": GameCalendar.short_text(a.end), "aus_masse_von": sim.company(a.cid).company_name})
	return out


func to_dict() -> Dictionary:
	return {"enabled": enabled, "auctions": auctions, "archive": archive, "liquidation": liquidation, "next_auction": _next_auction}


func from_dict(d: Dictionary) -> void:
	enabled = bool(d.get("enabled", true))
	auctions = {}
	for id in d.get("auctions", {}):
		var a: Dictionary = d.auctions[id]
		a.cid = int(a.cid)
		a.ref = int(a.ref)
		a.winner = int(a.winner)
		for b in a.bids:
			b.by = int(b.by)
		auctions[id] = a
	archive = d.get("archive", [])
	liquidation = {}
	for k in d.get("liquidation", {}):
		liquidation[int(k)] = d.liquidation[k]
	_next_auction = int(d.get("next_auction", 1))
