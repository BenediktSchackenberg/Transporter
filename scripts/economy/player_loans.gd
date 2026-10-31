class_name PlayerLoans
extends RefCounted
## Kredite zwischen Unternehmen (Auftrag 2, Spielerkredite, siehe docs/ECONOMY.md Abschnitt 3).
##
## Ein Unternehmen bietet einem anderen einen Kredit an (`offer`); die Gegenseite kann annehmen, ablehnen oder mit geaenderten Bedingungen
## antworten (`counter`, hoechstens MAX_COUNTERS Gegenangebote). Der Geber muss das Geld bei der Annahme besitzen; die Auszahlung erfolgt
## erst dann. Tilgung als Annuitaet wie bei den Banken (`Banking.schedule`). Optional haftet ein Fahrzeug des Nehmers als Sicherheit:
## nach DEFAULT_AFTER offenen Raten uebernimmt der Haendler es zu FORECLOSE_VALUE des Buchwerts, der Erloes geht an den Geber.
## Bargeld bewegt sich nur zwischen den Firmenbuechern (`Ledger.lend_to`, `receive_installment`); Zinsen sind Aufwand beim Nehmer und
## Ertrag beim Geber. Faellt eine Seite weg (Insolvenz, Schliessung), wird der Rest abgeschrieben.

const MAX_COUNTERS := 3
const MIN_AMOUNT := 500.0
const MAX_RATE := 0.3
const MAX_MONTHS := 36
const OFFER_DAYS := 10             # so lange gilt ein Angebot
const DEFAULT_AFTER := 3
const FORECLOSE_VALUE := 0.7
const DEAD := ["insolvenz", "verwertung", "geschlossen"]

var sim: Simulation
var loans := {}                    # "PL<n>" -> {id, lender, borrower, amount, rate, months, collateral, status, round, proposer, plan, outstanding, arrears, since}
var _next := 1


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)
	s.day_changed.connect(on_day)


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


func _alive(cid: int) -> bool:
	var c := sim.company(cid)
	return c != null and c.status not in DEAD


func pledged_to(vehicle_id: int) -> String:
	for l in loans.values():
		if int(l.collateral) == vehicle_id and l.status in ["angebot", "laufend", "rueckstand"]:
			return str(l.id)
	return ""


func _check_terms(lender: int, borrower: int, amount: float, rate: float, months: int, collateral: int, own_id: String = "") -> String:
	if lender == borrower or not _alive(lender) or not _alive(borrower):
		return "Geber und Nehmer müssen zwei verschiedene aktive Unternehmen sein."
	if amount < MIN_AMOUNT:
		return "Mindestbetrag %s." % Catalog.money(MIN_AMOUNT)
	if rate < 0.0 or rate > MAX_RATE:
		return "Zins muss zwischen 0 und %d %% liegen (als Anteil, z. B. 0.06)." % int(MAX_RATE * 100.0)
	if months < 1 or months > MAX_MONTHS:
		return "Laufzeit 1 bis %d Monate." % MAX_MONTHS
	if collateral >= 0:
		var v: FleetVehicle = sim.vehicles.get(collateral)
		if v == null or v.owner != borrower:
			return "Das Sicherheits-Fahrzeug gehört dem Nehmer nicht."
		var p := sim.banking.pledged_to(collateral)
		if p != "" and p != own_id:
			return "Fahrzeug %d ist bereits verpfändet (%s)." % [collateral, p]
	return ""


## Angebot des Gebers an den Nehmer.
func offer(lender: int, borrower: int, amount: float, rate: float, months: int, collateral: int = -1) -> Dictionary:
	var err := _check_terms(lender, borrower, amount, rate, months, collateral)
	if err == "":
		var held: float = 0.0
		for l in loans.values():
			if int(l.lender) == lender and l.status == "angebot":
				held += float(l.amount)
		if sim.company(lender).ledger.cash < amount + held:
			err = "Du besitzt das Geld nicht (Bargeld %s, bereits angeboten %s)." % [Catalog.money(sim.company(lender).ledger.cash), Catalog.money(held)]
	if err != "":
		return {"ok": false, "msg": err}
	var l := {"id": "PL%d" % _next, "lender": lender, "borrower": borrower, "amount": amount, "rate": rate, "months": months, "collateral": collateral,
		"status": "angebot", "round": 0, "proposer": lender, "plan": [], "outstanding": 0.0, "arrears": 0, "since": _today()}
	_next += 1
	loans[l.id] = l
	_notify(borrower, "%s bietet dir einen Kredit an: %s zu %.2f %% p. a., %d Monate (%s). Antwort mit accept_loan, counter_loan oder decline_loan." % [
		sim.company(lender).company_name, Catalog.money(amount), rate * 100.0, months, l.id])
	return {"ok": true, "msg": "Angebot %s an %s: %s zu %.2f %% p. a., %d Monate." % [l.id, sim.company(borrower).company_name, Catalog.money(amount), rate * 100.0, months], "loan_id": l.id}


## Gegenangebot der jeweils anderen Seite; ersetzt die Bedingungen (nicht angegebene Werte bleiben).
func counter(id: String, caller: int, amount: float = -1.0, rate: float = -1.0, months: int = -1) -> Dictionary:
	var l: Dictionary = loans.get(id, {})
	var err := _party_error(l, caller)
	if err != "":
		return {"ok": false, "msg": err}
	if int(l.round) >= MAX_COUNTERS:
		return {"ok": false, "msg": "Nach %d Gegenangeboten bleibt nur annehmen oder ablehnen." % MAX_COUNTERS}
	var a := float(l.amount) if amount < 0.0 else amount
	var r := float(l.rate) if rate < 0.0 else rate
	var m := int(l.months) if months < 0 else months
	err = _check_terms(int(l.lender), int(l.borrower), a, r, m, int(l.collateral), str(l.id))
	if err != "":
		return {"ok": false, "msg": err}
	l.amount = a
	l.rate = r
	l.months = m
	l.round = int(l.round) + 1
	l.proposer = caller
	l.since = _today()
	var other := int(l.borrower) if caller == int(l.lender) else int(l.lender)
	_notify(other, "%s macht ein Gegenangebot zu %s: %s zu %.2f %% p. a., %d Monate." % [sim.company(caller).company_name, l.id, Catalog.money(a), r * 100.0, m])
	return {"ok": true, "msg": "Gegenangebot zu %s: %s zu %.2f %% p. a., %d Monate (Runde %d)." % [l.id, Catalog.money(a), r * 100.0, m, l.round]}


func decline(id: String, caller: int) -> Dictionary:
	var l: Dictionary = loans.get(id, {})
	var err := _party_error(l, caller, true)
	if err != "":
		return {"ok": false, "msg": err}
	l.status = "abgelehnt"
	_notify(int(l.proposer), "%s lehnt das Kreditangebot %s ab." % [sim.company(caller).company_name, l.id])
	return {"ok": true, "msg": "Angebot %s abgelehnt." % l.id}


## Annahme durch die Seite, die das letzte Angebot nicht gemacht hat. Auszahlung sofort.
func accept(id: String, caller: int) -> Dictionary:
	var l: Dictionary = loans.get(id, {})
	var err := _party_error(l, caller)
	if err != "":
		return {"ok": false, "msg": err}
	var lender: Company = sim.company(int(l.lender))
	var borrower: Company = sim.company(int(l.borrower))
	err = _check_terms(lender.id, borrower.id, float(l.amount), float(l.rate), int(l.months), int(l.collateral), str(l.id))
	if err == "" and lender.ledger.cash < float(l.amount):
		err = "Der Geber besitzt das Geld nicht mehr (Bargeld %s)." % Catalog.money(lender.ledger.cash)
	if err == "" and borrower.ledger.debt + float(l.amount) > sim.max_loan(borrower.id):
		err = "Kreditrahmen des Nehmers überschritten (max. %s)." % Catalog.money(sim.max_loan(borrower.id))
	if err != "":
		return {"ok": false, "msg": err}
	l.plan = Banking.schedule(float(l.amount), float(l.rate), int(l.months), GameCalendar.month_of(sim.game_min) + 1)
	l.outstanding = float(l.amount)
	l.status = "laufend"
	l.since = _today()
	lender.ledger.lend_to(borrower.ledger, float(l.amount))
	sim.log_event("%s leiht %s %s (%.2f %% p. a., %d Monate)." % [lender.company_name, borrower.company_name, Catalog.money(l.amount), float(l.rate) * 100.0, int(l.months)], "info", borrower.id)
	return {"ok": true, "msg": "Kredit %s: %s ausgezahlt, Rate %s." % [l.id, Catalog.money(l.amount), Catalog.money(l.plan[0].pay)]}


func _party_error(l: Dictionary, caller: int, allow_proposer: bool = false) -> String:
	if l.is_empty() or l.status != "angebot":
		return "Kein offenes Kreditangebot mit dieser ID."
	if caller != int(l.lender) and caller != int(l.borrower):
		return "Das Angebot betrifft dein Unternehmen nicht."
	if caller == int(l.proposer) and not allow_proposer:
		return "Du hast das letzte Angebot selbst gemacht; die Gegenseite muss antworten."
	return ""


func _notify(cid: int, text: String) -> void:
	sim.notify(cid, text)


func on_day(_day: int) -> void:
	for l in loans.values():
		if l.status == "angebot" and _today() - int(l.since) > OFFER_DAYS:
			l.status = "abgelaufen"
		elif l.status in ["laufend", "rueckstand", "ausgefallen"] and not (_alive(int(l.lender)) and _alive(int(l.borrower))):
			_write_off(l)


func on_month(month: int) -> void:
	for l in loans.values():
		if l.status in ["laufend", "rueckstand", "ausgefallen"]:
			_collect(l, month)


func _collect(l: Dictionary, month: int) -> void:
	var lender: Company = sim.company(int(l.lender))
	var borrower: Company = sim.company(int(l.borrower))
	var blocked := false
	for r in l.plan:
		if r.status == "bezahlt" or int(r.month) > month:
			continue
		if not blocked and borrower.ledger.cash >= float(r.pay):
			lender.ledger.receive_installment(borrower.ledger, float(r.principal), float(r.interest), "Kredit %s Rate %d" % [l.id, r.n], sim.game_min)
			l.outstanding = snappedf(float(l.outstanding) - float(r.principal), 0.01)
			if r.status == "rueckstand":
				l.arrears = maxi(0, int(l.arrears) - 1)
			r.status = "bezahlt"
		else:
			if r.status != "rueckstand":
				r.status = "rueckstand"
				l.arrears = int(l.arrears) + 1
				sim.log_event("%s kann die Rate %d für Kredit %s an %s nicht zahlen (%s)." % [borrower.company_name, r.n, l.id, lender.company_name, Catalog.money(r.pay)], "info", borrower.id)
			blocked = true
	if l.plan.all(func(r): return r.status == "bezahlt") or float(l.outstanding) <= 0.005:
		l.status = "getilgt"
		l.outstanding = 0.0
		l.arrears = 0
		for r in l.plan:
			r.status = "bezahlt"
		sim.log_event("%s hat Kredit %s an %s zurückgezahlt." % [borrower.company_name, l.id, lender.company_name], "info", borrower.id)
	elif int(l.arrears) >= DEFAULT_AFTER and l.status != "ausgefallen":
		_default(l)
	elif l.status != "ausgefallen":
		l.status = "rueckstand" if int(l.arrears) > 0 else "laufend"
	elif int(l.arrears) == 0:
		l.status = "laufend"


func _default(l: Dictionary) -> void:
	l.status = "ausgefallen"
	var borrower: Company = sim.company(int(l.borrower))
	var lender: Company = sim.company(int(l.lender))
	sim.log_event("Kredit %s von %s an %s ist ausgefallen (Restschuld %s)." % [l.id, borrower.company_name, lender.company_name, Catalog.money(l.outstanding)], "bad", borrower.id)
	borrower.add_key_event("Kredit %s ausgefallen" % l.id, sim.game_min)
	var v: FleetVehicle = sim.vehicles.get(int(l.collateral))
	if v == null:
		return
	if v.state not in ["idle", "returning"] or not v.stops.is_empty() or not v.load.is_empty():
		return   # im Einsatz: Verwertung wird bei der naechsten Rate wiederholt
	var proceeds := minf(snappedf(v.book_value * FORECLOSE_VALUE, 0.01), float(l.outstanding))
	borrower.ledger.book("asset_result", proceeds - v.book_value, false, "Verwertung #%d für Kredit %s" % [v.id, l.id], sim.game_min)
	sim.remove_vehicle(v)
	borrower.ledger.settle_debt(proceeds)
	lender.ledger.receivables -= proceeds
	lender.ledger._move(proceeds, "S0")
	l.outstanding = snappedf(float(l.outstanding) - proceeds, 0.01)
	l.collateral = -1
	# Restschuld ueber die verbleibenden Raten neu planen
	var open: Array = l.plan.filter(func(r): return r.status != "bezahlt")
	if float(l.outstanding) > 0.005 and not open.is_empty():
		var np := Banking.schedule(float(l.outstanding), float(l.rate), open.size(), int(open[0].month))
		var done: Array = l.plan.filter(func(r): return r.status == "bezahlt")
		for r in np:
			r.n = done.size() + int(r.n)
		l.plan = done + np
		l.arrears = 0
	sim.log_event("Fahrzeug #%d von %s wird verwertet (Erlös %s an %s)." % [v.id, borrower.company_name, Catalog.money(proceeds), lender.company_name], "info", borrower.id)


## Eine Seite ist weggefallen: Forderung beim Geber abgeschrieben, Schuld beim Nehmer erlassen (ohne Gewinnwirkung).
func _write_off(l: Dictionary) -> void:
	var lender: Company = sim.company(int(l.lender))
	var borrower: Company = sim.company(int(l.borrower))
	var x := float(l.outstanding)
	lender.ledger.book("asset_result", -x, false, "Abschreibung Kredit %s" % l.id, sim.game_min)
	lender.ledger.receivables -= x
	borrower.ledger.forgive_debt(x)
	l.outstanding = 0.0
	l.status = "abgeschrieben"
	sim.log_event("Kredit %s zwischen %s und %s wird abgeschrieben (%s)." % [l.id, lender.company_name, borrower.company_name, Catalog.money(x)], "info", lender.id)


## Beobachtung: eigene Angebote und Kredite.
func summary_of(cid: int) -> Dictionary:
	var offers: Array = []
	var running: Array = []
	for l in loans.values():
		if int(l.lender) != cid and int(l.borrower) != cid:
			continue
		var row := {"id": l.id, "geber": int(l.lender), "nehmer": int(l.borrower), "betrag": int(l.amount), "zins_pa": snappedf(float(l.rate) * 100.0, 0.01), "monate": int(l.months),
			"pfand_fahrzeug": int(l.collateral), "status": l.status}
		if l.status == "angebot":
			row["du_antwortest"] = int(l.proposer) != cid
			row["gegenangebote"] = int(l.round)
			offers.append(row)
		elif l.status in ["laufend", "rueckstand", "ausgefallen"]:
			row["restschuld"] = int(l.outstanding)
			running.append(row)
	return {"angebote": offers, "laufend": running}


func to_dict() -> Dictionary:
	return {"loans": loans, "next": _next}


func from_dict(d: Dictionary) -> void:
	loans = d.get("loans", {})
	for l in loans.values():
		for k in ["lender", "borrower", "months", "collateral", "round", "proposer", "arrears", "since"]:
			l[k] = int(l[k])
		for r in l.plan:
			r.n = int(r.n)
			r.month = int(r.month)
	_next = int(d.get("next", 1))
