class_name Banking
extends RefCounted
## Drei Banken, Referenzzins, Annuitaetenkredite und Einlagen (siehe docs/ECONOMY.md, Abschnitte 3 und 4).
##
## Das Bargeld einer Bank ist ihr Konto in Economy (B1..B3). Kredite und Einlagen sind Forderungen bzw. Verbindlichkeiten.
## Eigenkapital = Bargeld + offene Kredite - Einlagen. Ausfaelle senken es.
## Firmenseitig: Ledger.debt = Summe der offenen Kredite, Ledger.deposits = Summe der Einlagen.

const RESERVE := 0.15            # Mindestreserve auf Einlagen
const SINGLE_LIMIT := 0.25       # Einzelkredit max. Anteil am Eigenkapital
const LATE_FEE := 0.01           # Verzugszuschlag auf die Rate
const EARLY_FEE := 0.01          # Vorfaelligkeitsentschaedigung
const DEFAULT_AFTER := 3         # offene Raten bis zum Ausfall
const FORECLOSE_VALUE := 0.7     # Verwertungserloes der Sicherheit (Anteil Buchwert)
const START_REF := 0.035
const BANKS := [
	{"id": "B1", "name": "Geschäftsbank", "margin": 0.020, "min_m": 1, "max_m": 12, "cover": 0.5, "free_limit": 15000.0, "cash": 400000.0,
		"focus": "Betriebsmittel, kurzfristig; kleine Beträge auch ohne Sicherheit"},
	{"id": "B2", "name": "Investitionsbank", "margin": 0.015, "min_m": 6, "max_m": 60, "cover": 0.5, "free_limit": 0.0, "cash": 600000.0,
		"focus": "Fahrzeuge, Gebäude, Maschinen; Sicherheit Pflicht (≥ 50 % Deckung)"},
	{"id": "B3", "name": "Handelsbank", "margin": 0.018, "min_m": 1, "max_m": 6, "cover": 0.3, "free_limit": 0.0, "cash": 300000.0,
		"focus": "Warenfinanzierung, bessere Anlagezinsen; Sicherheit ≥ 30 %"},
]

var sim: Simulation
var ref_rate := START_REF
var loans := {}          # Kredit-ID -> Dictionary
var deposits := {}       # Einlagen-ID -> Dictionary
var losses := {"B1": 0.0, "B2": 0.0, "B3": 0.0}   # Kreditverluste je Bank
var defaults_recent := 0
var _next_loan := 1
var _next_dep := 1


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)
	s.day_changed.connect(on_day)


static func bank_index(id_or_name: String) -> int:
	var k := id_or_name.strip_edges().to_lower()
	for i in BANKS.size():
		if k == BANKS[i].id.to_lower() or k == BANKS[i].name.to_lower() or BANKS[i].name.to_lower().begins_with(k) and k.length() >= 4:
			return i
	return -1


func bank_cash(i: int) -> float:
	return sim.economy.accounts[BANKS[i].id]


func loans_of_bank(i: int) -> float:
	var t := 0.0
	for l in loans.values():
		if l.bank == i and l.status != "getilgt":
			t += float(l.outstanding)
	return t


func deposits_of_bank(i: int) -> float:
	var t := 0.0
	for d in deposits.values():
		if d.bank == i:
			t += float(d.amount)
	return t


func equity(i: int) -> float:
	return bank_cash(i) + loans_of_bank(i) - deposits_of_bank(i)


func available(i: int) -> float:
	return maxf(0.0, bank_cash(i) - RESERVE * deposits_of_bank(i))


func liquidity_ratio(i: int) -> float:
	var assets := bank_cash(i) + loans_of_bank(i)
	return bank_cash(i) / assets if assets > 0.0 else 0.0


## Bonitaet 0..1 aus Gewinn, Ruf und Verschuldung.
func score(cid: int) -> float:
	var c := sim.company(cid)
	var nw := maxf(sim.net_worth(cid), 1000.0)
	var s := 0.5 + 0.25 * clampf(c.ledger.profit() / 20000.0, -1.0, 1.0) + 0.15 * clampf((c.reputation - 50.0) / 50.0, -1.0, 1.0) \
		- 0.2 * clampf(c.ledger.debt / nw, 0.0, 1.5)
	return clampf(s, 0.05, 1.0)


func company_defaults(cid: int) -> int:
	var n := 0
	for l in loans.values():
		if l.owner == cid and l.status == "ausgefallen":
			n += 1
	return n


## Gebundene Fahrzeuge (Sicherheit) -> Kredit-ID.
func pledged_to(vehicle_id: int) -> String:
	for l in loans.values():
		if l.collateral == vehicle_id and l.status in ["laufend", "rueckstand"]:
			return l.id
	return ""


## Bestes ungebundenes Fahrzeug als Sicherheit.
func best_collateral(cid: int) -> int:
	var best := -1
	var bv := 0.0
	for v in sim.company_vehicles(cid):
		if pledged_to(v.id) == "" and v.book_value > bv:
			bv = v.book_value
			best = v.id
	return best


## Angebot einer Bank. Ergebnis: {ok, msg, rate, monthly, total_interest, parts, bank, months, amount, cover}
func quote(bank: int, cid: int, amount: float, months: int, collateral: int = -1) -> Dictionary:
	var B: Dictionary = BANKS[bank]
	var c := sim.company(cid)
	var q := {"ok": false, "bank": bank, "amount": amount, "months": months, "msg": ""}
	if amount < 500.0:
		q.msg = "Mindestbetrag 500."
		return q
	if months < B.min_m or months > B.max_m:
		q.msg = "%s vergibt Laufzeiten von %d bis %d Monaten." % [B.name, B.min_m, B.max_m]
		return q
	if c.ledger.debt + amount > sim.max_loan(cid):
		q.msg = "Kreditrahmen überschritten (max. %s, bereits %s)." % [Catalog.money(sim.max_loan(cid)), Catalog.money(c.ledger.debt)]
		return q
	if amount > SINGLE_LIMIT * maxf(equity(bank), 0.0):
		q.msg = "%s: Einzelkreditgrenze (25 %% des Eigenkapitals = %s) überschritten." % [B.name, Catalog.money(SINGLE_LIMIT * maxf(equity(bank), 0.0))]
		return q
	if amount > available(bank):
		q.msg = "%s hat nicht genug freies Bargeld (verfügbar %s)." % [B.name, Catalog.money(available(bank))]
		return q
	var cover := 0.0
	if collateral >= 0:
		var v: FleetVehicle = sim.vehicles.get(collateral)
		if v == null or v.owner != cid:
			q.msg = "Fahrzeug %d gehört dir nicht." % collateral
			return q
		if pledged_to(collateral) != "":
			q.msg = "Fahrzeug %d ist bereits verpfändet." % collateral
			return q
		cover = v.book_value / amount
	var needs: bool = float(B.cover) > 0.0 and amount > float(B.free_limit)
	if needs and cover < float(B.cover):
		q.msg = "%s verlangt Sicherheit mit %d %% Deckung (Fahrzeug als Pfand; vorhanden %d %%)." % [B.name, int(float(B.cover) * 100.0), int(cover * 100.0)]
		return q
	var sc := score(cid)
	var nw := maxf(sim.net_worth(cid), 1000.0)
	var parts := {
		"Referenz": ref_rate, "Bankmarge": float(B.margin), "Bonität": (1.0 - sc) * 0.04,
		"Laufzeit": 0.002 * months / 12.0, "Verschuldung": 0.02 * clampf((c.ledger.debt + amount) / nw, 0.0, 2.0),
		"Ausfallhistorie": 0.01 * company_defaults(cid), "Sicherheit": -0.01 * minf(cover, 1.0),
		"Liquidität": 0.02 * maxf(0.0, 0.3 - liquidity_ratio(bank)) / 0.3,
	}
	var rate := 0.0
	for k in parts:
		rate += parts[k]
	rate = maxf(rate, ref_rate + 0.01)
	var plan := schedule(amount, rate, months, GameCalendar.month_of(sim.game_min) + 1)
	q.ok = true
	q.rate = rate
	q.parts = parts
	q.cover = cover
	q.plan = plan
	q.monthly = plan[0].pay if not plan.is_empty() else 0.0
	q.total_interest = 0.0
	for r in plan:
		q.total_interest += r.interest
	q.msg = "%s: %.2f %% Jahreszins (%.2f %% je Monat), Rate %s, Zinsen gesamt %s." % [B.name, rate * 100.0, rate * 100.0 / 12.0,
		Catalog.money(q.monthly), Catalog.money(q.total_interest)]
	return q


## Annuitaetenplan auf Cent gerundet; letzte Rate gleicht Rundungsreste aus.
static func schedule(principal: float, annual_rate: float, months: int, first_month: int) -> Array:
	var i := annual_rate / 12.0
	var r := principal / months if i <= 0.0 else principal * i / (1.0 - pow(1.0 + i, -months))
	r = snappedf(r, 0.01)
	var bal := snappedf(principal, 0.01)
	var out: Array = []
	for n in range(1, months + 1):
		var interest := snappedf(bal * i, 0.01)
		var princ := bal if n == months else minf(snappedf(r - interest, 0.01), bal)
		out.append({"n": n, "month": first_month + n - 1, "interest": interest, "principal": princ, "pay": snappedf(interest + princ, 0.01),
			"balance": snappedf(bal - princ, 0.01), "status": "offen"})
		bal = snappedf(bal - princ, 0.01)
	return out


## Kredit nach gepruefter Anfrage auszahlen.
func grant(q: Dictionary, cid: int, collateral: int, purpose: String = "") -> Dictionary:
	var c := sim.company(cid)
	var B: Dictionary = BANKS[q.bank]
	var l := {"id": "K%d" % _next_loan, "bank": q.bank, "owner": cid, "principal": q.amount, "outstanding": q.amount, "rate": q.rate,
		"months": q.months, "plan": q.plan, "collateral": collateral, "status": "laufend", "arrears": 0, "since": sim.game_min, "purpose": purpose,
		"fees_due": 0.0}
	_next_loan += 1
	loans[l.id] = l
	c.ledger.borrow(q.amount, B.id)
	sim.log_event("%s nimmt bei der %s einen Kredit über %s auf (%.2f %% p. a., %d Monate)." % [c.company_name, B.name, Catalog.money(q.amount), q.rate * 100.0, q.months], "info", cid)
	return l


func next_due(l: Dictionary) -> Dictionary:
	for r in l.plan:
		if r.status != "bezahlt":
			return r
	return {}


## Vorzeitige (Teil-)Rueckzahlung; neuer Plan ueber die Restlaufzeit, 1 % Gebuehr auf den getilgten Betrag.
func early_repay(loan_id: String, amount: float, caller: int = -1) -> Dictionary:
	var l: Dictionary = loans.get(loan_id, {})
	if l.is_empty() or l.status not in ["laufend", "rueckstand"]:
		return {"ok": false, "msg": "Kredit %s ist nicht offen." % loan_id}
	if caller >= 0 and int(l.owner) != caller:
		return {"ok": false, "msg": "Kredit %s gehört dir nicht." % loan_id}
	var c := sim.company(l.owner)
	# Ueberfaellige Raten samt Verzugszuschlag werden zuerst eingezogen; sonst gingen sie bei der Ablösung verloren.
	var arrears := 0.0
	for r in l.plan:
		if r.status == "rueckstand":
			arrears += float(r.pay)
	var overdue := arrears + float(l.fees_due)
	var principal_overdue := 0.0
	for r in l.plan:
		if r.status == "rueckstand":
			principal_overdue += float(r.principal)
	amount = minf(amount, maxf(0.0, float(l.outstanding) - principal_overdue))
	var fee := snappedf(amount * EARLY_FEE, 0.01)
	if c.ledger.cash < overdue + amount + fee:
		return {"ok": false, "msg": "Nicht genug Bargeld: %s (überfällig %s inkl. Zuschlag, Tilgung %s, Gebühr %s)." % [
			Catalog.money(overdue + amount + fee), Catalog.money(overdue), Catalog.money(amount), Catalog.money(fee)]}
	var B: Dictionary = BANKS[l.bank]
	for r in l.plan:
		if r.status == "rueckstand":
			c.ledger.book("interest", -float(r.interest), true, "Kreditzins %s Rate %d (überfällig)" % [l.id, r.n], sim.game_min, B.id)
			c.ledger.repay(float(r.principal), B.id)
			l.outstanding = snappedf(float(l.outstanding) - float(r.principal), 0.01)
			r.status = "bezahlt"
			if l.arrears > 0:
				l.arrears -= 1
	if float(l.fees_due) > 0.0:
		c.ledger.book("interest", -float(l.fees_due), true, "Verzugszuschlag " + l.id, sim.game_min, B.id)
		l.fees_due = 0.0
	if amount > 0.0:
		c.ledger.repay(amount, B.id)
		c.ledger.book("interest", -fee, true, "Vorfälligkeitsentschädigung " + l.id, sim.game_min, B.id)
	l.outstanding = snappedf(float(l.outstanding) - amount, 0.01)
	if l.status == "rueckstand" and l.arrears == 0:
		l.status = "laufend"
	var open: Array = l.plan.filter(func(r): return r.status != "bezahlt")
	if l.outstanding <= 0.005:
		for r in open:
			r.status = "bezahlt"
		_close(l)
	elif not open.is_empty():
		var np := schedule(l.outstanding, l.rate, open.size(), int(open[0].month))
		var done: Array = l.plan.filter(func(r): return r.status == "bezahlt")
		for r in np:
			r.n = done.size() + int(r.n)
		l.plan = done + np
	return {"ok": true, "msg": "%s getilgt (Gebühr %s). Restschuld %s." % [Catalog.money(amount), Catalog.money(fee), Catalog.money(l.outstanding)]}


func _close(l: Dictionary) -> void:
	l.status = "getilgt"
	l.outstanding = 0.0


# ------------------------------------------------------------------ Einlagen
func deposit_rates(months: int) -> Dictionary:
	var call := maxf(0.0, ref_rate - 0.015)
	var term := minf(ref_rate - 0.005, call + 0.001 * months) if months > 0 else call
	return {"tages": call, "fest": maxf(call, term)}


func deposit(cid: int, bank: int, amount: float, kind: String, months: int) -> Dictionary:
	var c := sim.company(cid)
	if amount < 100.0:
		return {"ok": false, "msg": "Mindestanlage 100."}
	if c.ledger.cash < amount:
		return {"ok": false, "msg": "Nicht genug Bargeld."}
	if kind == "fest" and (months < 3 or months > 24):
		return {"ok": false, "msg": "Festgeld läuft 3 bis 24 Monate."}
	var rates := deposit_rates(months if kind == "fest" else 0)
	var bonus := 0.002 if bank == 2 else 0.0   # Handelsbank zahlt etwas besser
	var rate := minf(float(rates[kind]) + bonus, maxf(0.0, ref_rate - 0.005))
	var d := {"id": "E%d" % _next_dep, "bank": bank, "owner": cid, "amount": amount, "kind": kind, "rate": rate,
		"due_month": GameCalendar.month_of(sim.game_min) + months if kind == "fest" else -1, "owed": 0.0, "since": sim.game_min}
	_next_dep += 1
	deposits[d.id] = d
	c.ledger.deposit_in(amount, BANKS[bank].id)
	return {"ok": true, "msg": "%s als %s bei %s angelegt (%.2f %% p. a.)." % [Catalog.money(amount), "Tagesgeld" if kind == "tages" else "Festgeld", BANKS[bank].name, rate * 100.0], "id": d.id}


func withdraw(cid: int, dep_id: String, forced: bool = false) -> Dictionary:
	var d: Dictionary = deposits.get(dep_id, {})
	if d.is_empty() or d.owner != cid:
		return {"ok": false, "msg": "Einlage %s nicht gefunden." % dep_id}
	var c := sim.company(cid)
	var B: Dictionary = BANKS[d.bank]
	if bank_cash(d.bank) < d.amount:
		return {"ok": false, "msg": "%s hat gerade nicht genug Bargeld für die Auszahlung." % B.name}
	var fee := 0.0
	if not forced and d.kind == "fest" and GameCalendar.month_of(sim.game_min) < int(d.due_month):
		fee = snappedf(float(d.amount) * 0.01, 0.01)   # Festgeld vorzeitig: Zinsen verfallen, 1 % Gebuehr
		d.owed = 0.0
	c.ledger.deposit_out(d.amount, B.id)
	if d.owed > 0.0:
		_pay_interest(d, c)
	if fee > 0.0:
		c.ledger.book("interest", -fee, true, "Gebühr vorzeitige Auflösung " + d.id, sim.game_min, B.id)
	deposits.erase(dep_id)
	return {"ok": true, "msg": "Einlage %s aufgelöst%s." % [dep_id, (" (Gebühr %s)" % Catalog.money(fee)) if fee > 0.0 else ""]}


func _pay_interest(d: Dictionary, c: Company) -> void:
	var B: Dictionary = BANKS[d.bank]
	var pay := minf(float(d.owed), maxf(0.0, bank_cash(d.bank)))
	if pay <= 0.0:
		return
	c.ledger.book("interest_income", pay, true, "Einlagenzins " + d.id, sim.game_min, B.id)
	d.owed = float(d.owed) - pay


## Offene Forderungen der Banken gegen eine Firma.
func claims_of(cid: int) -> Array:
	return loans.values().filter(func(l): return l.owner == cid and l.status in ["laufend", "rueckstand", "ausgefallen"] and float(l.outstanding) > 0.005)


## Ueberziehung (negatives Bargeld) wird als ungesicherte Forderung der Geschaeftsbank erfasst; das Bargeld wird 0.
func record_overdraft(cid: int) -> void:
	var c := sim.company(cid)
	if c.ledger.cash >= 0.0:
		return
	var amount := -c.ledger.cash   # ungerundet, damit das Bargeld exakt 0 wird
	c.ledger.borrow(amount, BANKS[0].id)
	var l := {"id": "K%d" % _next_loan, "bank": 0, "owner": cid, "principal": amount, "outstanding": amount, "rate": 0.0, "months": 0,
		"plan": [], "collateral": -1, "status": "ausgefallen", "arrears": 0, "since": sim.game_min, "purpose": "Überziehung", "fees_due": 0.0}
	_next_loan += 1
	loans[l.id] = l


## Einlagen einer Firma aufloesen (Insolvenz): ohne Gebuehr, soweit die Bank zahlen kann.
func liquidate_deposits(cid: int) -> void:
	for id in deposits.keys():
		if deposits[id].owner == cid:
			withdraw(cid, id, true)


# ------------------------------------------------------------------ Zeitablauf
func on_day(_day: int) -> void:
	for l in loans.values():
		if l.status == "ausgefallen" and l.collateral >= 0 and l.outstanding > 0.0:
			_foreclose(l)
	for d in deposits.values():   # Zinsen laufen taeglich auf
		d.owed = float(d.owed) + float(d.amount) * float(d.rate) / 360.0


func on_month(month: int) -> void:
	for id in loans.keys():
		var l: Dictionary = loans[id]
		if l.status in ["laufend", "rueckstand"]:
			_collect(l, month)
	for id in deposits.keys():
		var d: Dictionary = deposits[id]
		var c := sim.company(d.owner)
		_pay_interest(d, c)
		if d.kind == "fest" and month >= int(d.due_month):
			withdraw(d.owner, id)
	_update_ref_rate()


func _collect(l: Dictionary, month: int) -> void:
	var c := sim.company(l.owner)
	var B: Dictionary = BANKS[l.bank]
	# Alle bis jetzt faelligen, noch nicht bezahlten Raten (aelteste zuerst)
	var blocked := false
	for r in l.plan:
		if r.status == "bezahlt" or int(r.month) > month:
			continue
		var due: float = float(r.pay) + (float(l.fees_due) if r.status == "rueckstand" else 0.0)
		if not blocked and c.ledger.cash >= due:
			c.ledger.book("interest", -float(r.interest), true, "Kreditzins %s Rate %d" % [l.id, r.n], sim.game_min, B.id)
			c.ledger.repay(float(r.principal), B.id)
			if float(l.fees_due) > 0.0 and r.status == "rueckstand":
				c.ledger.book("interest", -float(l.fees_due), true, "Verzugszuschlag " + l.id, sim.game_min, B.id)
				l.fees_due = 0.0
			l.outstanding = snappedf(float(l.outstanding) - float(r.principal), 0.01)
			r.status = "bezahlt"
			if l.arrears > 0:
				l.arrears -= 1
		else:
			if r.status != "rueckstand":
				r.status = "rueckstand"
				l.arrears += 1
				l.fees_due = float(l.fees_due) + snappedf(float(r.pay) * LATE_FEE, 0.01)
				sim.log_event("%s kann die Rate %d für Kredit %s nicht zahlen (%s)." % [c.company_name, r.n, l.id, Catalog.money(r.pay)], "info", l.owner)
			blocked = true   # nie spaetere Raten vor aelteren bezahlen
	if next_due(l).is_empty() or l.outstanding <= 0.005:
		_close(l)
		sim.log_event("%s hat Kredit %s vollständig zurückgezahlt." % [c.company_name, l.id], "info", l.owner)
	elif l.arrears >= DEFAULT_AFTER:
		_default(l)
	elif l.arrears > 0:
		l.status = "rueckstand"
	else:
		l.status = "laufend"


func _default(l: Dictionary) -> void:
	var c := sim.company(l.owner)
	l.status = "ausgefallen"
	defaults_recent += 1
	c.add_key_event("Kredit %s ausgefallen" % l.id, sim.game_min)
	sim.log_event("Kredit %s von %s ist ausgefallen (Restschuld %s). Die Bank kündigt." % [l.id, c.company_name, Catalog.money(l.outstanding)], "info", l.owner)
	_foreclose(l)


## Verwertung der Sicherheit: Fahrzeug an den Haendler, Erloes geht an die Bank und mindert die Schuld.
func _foreclose(l: Dictionary) -> void:
	var v: FleetVehicle = sim.vehicles.get(l.collateral)
	if v == null:
		l.collateral = -1
		return
	if v.state not in ["idle", "returning"] or not v.stops.is_empty() or not v.load.is_empty():
		return   # im Einsatz: naechster Tag
	var c := sim.company(l.owner)
	var proceeds := minf(snappedf(v.book_value * FORECLOSE_VALUE, 0.01), float(l.outstanding))
	var B: Dictionary = BANKS[l.bank]
	c.ledger.book("asset_result", proceeds - v.book_value, false, "Verwertung #%d durch %s" % [v.id, B.name], sim.game_min)
	sim.remove_vehicle(v)
	c.ledger.settle_debt(proceeds, B.id)
	sim.economy.transfer("S0", B.id, proceeds)   # Haendler zahlt an die Bank
	l.outstanding = snappedf(float(l.outstanding) - proceeds, 0.01)
	l.collateral = -1
	sim.log_event("Die %s verwertet Fahrzeug #%d von %s (Erlös %s)." % [B.name, v.id, c.company_name, Catalog.money(proceeds)], "info", l.owner)


## Restforderung abschreiben (Insolvenz): mindert das Eigenkapital der Bank.
func write_off(l: Dictionary) -> void:
	losses[BANKS[l.bank].id] += float(l.outstanding)
	var c := sim.company(l.owner)
	c.ledger.forgive_debt(float(l.outstanding))
	l.outstanding = 0.0
	l.status = "abgeschrieben"


func _update_ref_rate() -> void:
	var lent := 0.0
	var cash := 0.0
	for i in BANKS.size():
		lent += loans_of_bank(i)
		cash += bank_cash(i)
	var util := lent / maxf(lent + cash, 1.0)
	var target := START_REF + 0.06 * (util - 0.3) + 0.01 * defaults_recent
	ref_rate = clampf(ref_rate + clampf(target - ref_rate, -0.0025, 0.0025), 0.01, 0.12)   # langsame Anpassung
	defaults_recent = maxi(0, defaults_recent - 1)


# ------------------------------------------------------------------ Anzeige/Beobachtung
func summary_of(cid: int) -> Dictionary:
	var ls: Array = []
	for l in loans.values():
		if l.owner == cid and l.status in ["laufend", "rueckstand", "ausgefallen"]:
			var n := next_due(l)
			ls.append({"id": l.id, "bank": BANKS[l.bank].name, "restschuld": int(l.outstanding), "zins_pa": snappedf(l.rate * 100.0, 0.01),
				"naechste_rate": int(n.get("pay", 0.0)), "faellig_monat": int(n.get("month", 0)) + 1, "status": l.status,
				"pfand_fahrzeug": l.collateral})
	var ds: Array = []
	for d in deposits.values():
		if d.owner == cid:
			ds.append({"id": d.id, "bank": BANKS[d.bank].name, "betrag": int(d.amount), "art": d.kind, "zins_pa": snappedf(d.rate * 100.0, 0.01)})
	return {"referenzzins_pa": snappedf(ref_rate * 100.0, 0.01), "kredite": ls, "einlagen": ds}


func to_dict() -> Dictionary:
	return {"ref_rate": ref_rate, "loans": loans, "deposits": deposits, "losses": losses, "defaults_recent": defaults_recent,
		"next_loan": _next_loan, "next_dep": _next_dep}


func from_dict(d: Dictionary) -> void:
	ref_rate = float(d.get("ref_rate", START_REF))
	loans = {}
	for id in d.get("loans", {}):
		var l: Dictionary = d.loans[id]
		for k in ["bank", "owner", "months", "arrears", "collateral"]:
			l[k] = int(l[k])
		for r in l.plan:
			r.n = int(r.n)
			r.month = int(r.month)
		loans[id] = l
	deposits = {}
	for id in d.get("deposits", {}):
		var e: Dictionary = d.deposits[id]
		e.bank = int(e.bank)
		e.owner = int(e.owner)
		e.due_month = int(e.due_month)
		deposits[id] = e
	losses = d.get("losses", losses)
	defaults_recent = int(d.get("defaults_recent", 0))
	_next_loan = int(d.get("next_loan", 1))
	_next_dep = int(d.get("next_dep", 1))
