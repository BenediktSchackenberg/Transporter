class_name Households
extends RefCounted
## Haushalte der Mitarbeiter, verhandelte Loehne, Kaufkraft und Motivation (Auftrag 3).
##
## Jeder angestellte Mitarbeiter gehoert zu einem festen Haushalt mit Wohnadresse und 0-2 Angehoerigen. Der Nettolohn fliesst vom
## Firmenkonto ueber H0 auf das Haushaltskonto (Teilbuch von H0). Monatlich zahlt der Haushalt Lebenshaltung (an S0 und Importanteil
## an X0). Reicht das Geld nicht, entsteht ein Defizit; das senkt Motivation und kann zur Kuendigung fuehren.
## Vom Bruttolohn behaelt PublicSector Lohnsteuer und Sozialabgaben ein; der Haushalt erhaelt den Nettobetrag.

const COST_BASE := 600.0          # EUR je Haushalt und Spielmonat (ein Monat = 60 Spielstunden Lohn)
const COST_PER_DEPENDENT := 150.0
const IMPORT_SHARE := 0.2         # Anteil der Ausgaben fuer Importgueter
const QUIT_AFTER_MONTHS := 3      # Monate niedriger Motivation ohne Reaktion
const LOW_MOTIVATION := 25.0

var sim: Simulation
var homes := {}                   # "H<n>" -> {id, members, dependents, address, balance, shortfall, income, spent, deficit_months, low_months, asked}
var spent_total := 0.0
var _next := 1


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)


# ------------------------------------------------------------------ Zuordnung
func household_of(w: Worker) -> Dictionary:
	if w.household != "" and homes.has(w.household):
		return homes[w.household]
	var addr := _address()
	var h := {"id": "H%d" % _next, "members": [w.id], "dependents": int(hash(w.id)) % 3, "address": addr, "balance": 150.0,
		"shortfall": 0.0, "income": 0.0, "spent": 0.0, "deficit_months": 0, "low_months": 0, "asked": false}
	h.dependents = absi(h.dependents) % 3
	_next += 1
	homes[h.id] = h
	w.household = h.id
	# Startguthaben stammt aus dem Haushaltssektor (Teilbuch von H0), kein neues Geld
	return h


func _address() -> int:
	var cands: Array = []
	for b in sim.city.buildings:
		if b.type in ["house", "apartment", "semi", "villa"]:
			cands.append(b.id)
	if cands.is_empty():
		return 0
	return cands[(_next * 7919) % cands.size()]


func costs(h: Dictionary) -> float:
	return COST_BASE + COST_PER_DEPENDENT * int(h.dependents)


# ------------------------------------------------------------------ Lohn
## Gezahlter Lohn einer Firma wird auf die Haushalte der Mitarbeiter verteilt (anteilig zum vereinbarten Lohn).
func credit_company(cid: int, amount: float) -> void:
	if amount <= 0.0:
		return
	var staff: Array = sim.personnel.employed(cid)
	var total := 0.0
	for w in staff:
		total += w.wage
	if total <= 0.0:
		return
	for w in staff:
		var part: float = sim.public_sector.withhold(amount * w.wage / total)
		var h := household_of(w)
		h.balance = float(h.balance) + part
		h.income = float(h.income) + part


## Referenzlohn nach Faehigkeiten (Markt); Vorarbeiter erhalten einen Aufschlag.
func market_wage(w: Worker) -> float:
	var s := 0.0
	for k in w.skills:
		s += float(w.skills[k])
	return 11.0 + 1.1 * s + (4.0 if w.role == "foreman" else 0.0) + 0.02 * w.experience


## Mindestlohn, ab dem der Mitarbeiter zusagt: Markt (leicht darunter) oder der Bedarf seines Haushalts.
func reservation_wage(w: Worker) -> float:
	var h := household_of(w)
	var needs := costs(h) / 60.0 * 1.1    # EUR je Spielstunde, 10 % Puffer
	return maxf(market_wage(w) * 0.92, needs)


## Lohnverhandlung. Gibt {ok, msg, counter?} zurueck.
func negotiate(cid: int, wid: String, offer: float) -> Dictionary:
	var w: Worker = sim.personnel.workers.get(wid)
	if w == null or w.employer != cid or w.lost:
		return {"ok": false, "msg": "%s arbeitet nicht für dich." % wid}
	if offer <= 0.0 or offer > 120.0:
		return {"ok": false, "msg": "Lohn in EUR je Spielstunde (1 bis 120)."}
	var ask := snappedf(reservation_wage(w), 0.1)
	if offer < w.wage:
		return {"ok": false, "msg": "%s lehnt eine Lohnkürzung ab (aktuell %.1f EUR/h)." % [w.name, w.wage]}
	if is_equal_approx(offer, w.wage):
		return {"ok": false, "msg": "Der Lohn bleibt unverändert."}
	if offer + 0.05 < ask:
		w.motivation = maxf(0.0, w.motivation - 3.0)
		return {"ok": false, "counter": ask, "msg": "%s lehnt %.1f EUR/h ab und verlangt mindestens %.1f EUR/h (Haushalt %s, Markt %.1f)." % [
			w.name, offer, ask, household_of(w).id, market_wage(w)]}
	var old := w.wage
	w.wage = offer
	w.motivation = minf(100.0, w.motivation + 8.0)
	var h := household_of(w)
	h.asked = false
	h.low_months = 0
	sim.log_event("%s und %s einigen sich auf %.1f EUR/h (vorher %.1f)." % [sim.company(cid).company_name, w.name, offer, old], "info", cid)
	return {"ok": true, "msg": "%s nimmt %.1f EUR/h an (vorher %.1f). Mehrkosten %s je Spielmonat." % [w.name, offer, old, Catalog.money((offer - old) * 60.0)]}


# ------------------------------------------------------------------ Monatsabschluss
## Kreislauf der uebrigen Stadtbevoelkerung: Die Haushalte erhalten aus der Aussenwirtschaft (Pendlerloehne, Exporterloese) fast so viel,
## wie sie im Monat ausgegeben haben. Das ist die einzige Stelle, an der der Haushaltssektor Geld von aussen bekommt.
const EXTERNAL_INCOME_SHARE := 0.95


func on_month(_month: int) -> void:
	var spent_prev: float = sim.economy.take_outflow("H0")
	sim.economy.transfer("X0", "H0", spent_prev * EXTERNAL_INCOME_SHARE)
	sim.economy.outflow["X0"] = 0.0
	# Rest der Stadtwirtschaft: Haushalte geben ueberschuessiges Geld aus (an S0), S0 zahlt ueberschuessige Mittel als Loehne zurueck.
	# Beide Konten laufen so auf ihre Ausgangswerte zu, statt davonzudriften.
	var h_excess: float = float(sim.economy.accounts.H0) - float(Economy.SEED.H0)
	if h_excess > 0.0:
		sim.economy.transfer("H0", "S0", 0.4 * h_excess)
	var s_excess: float = float(sim.economy.accounts.S0) - float(Economy.SEED.S0)
	if s_excess > 0.0:
		sim.economy.transfer("S0", "H0", 0.6 * s_excess)
	sim.economy.outflow["H0"] = 0.0
	for h in homes.values():
		var members: Array = []
		for wid in h.members:
			var w: Worker = sim.personnel.workers.get(wid)
			if w != null:
				members.append(w)
		var need := costs(h)
		var pay := minf(need, maxf(0.0, float(h.balance)))
		if pay > 0.0:
			h.balance = float(h.balance) - pay
			var imp := pay * IMPORT_SHARE
			sim.economy.transfer("H0", "X0", imp)
			sim.economy.transfer("H0", "S0", pay - imp)
			h.spent = float(h.spent) + pay
			spent_total += pay
		h.shortfall = maxf(0.0, need - pay)
		h.deficit_months = int(h.deficit_months) + 1 if float(h.shortfall) > 0.0 else 0
		h.income = 0.0
		for w in members:
			_update_motivation(w, h)


func _update_motivation(w: Worker, h: Dictionary) -> void:
	if w.employer < 0:
		return
	var rel := w.wage / maxf(market_wage(w), 1.0) - 1.0
	var target := 55.0 + 60.0 * clampf(rel, -0.5, 0.5)
	if int(h.deficit_months) > 0:
		target -= 12.0 + 6.0 * minf(3.0, int(h.deficit_months))
	elif float(h.balance) > 2.0 * costs(h):
		target += 6.0
	target -= 0.15 * w.fatigue
	target -= 0.12 * (100.0 - w.health)
	target -= 8.0 if sim.company(w.employer).ledger.payables > 1.0 else 0.0
	w.motivation = clampf(w.motivation + 0.35 * (target - w.motivation), 0.0, 100.0)
	if w.motivation < LOW_MOTIVATION:
		h.low_months = int(h.low_months) + 1
		if not h.asked:
			h.asked = true
			sim.notify(w.employer, "%s ist unzufrieden (Motivation %d) und verlangt mehr Lohn: mindestens %.1f EUR/h (negotiate_wage)." % [
				w.name, int(w.motivation), snappedf(reservation_wage(w), 0.1)])
			sim.log_event("%s bittet %s um eine Lohnerhöhung." % [w.name, sim.company(w.employer).company_name], "info", w.employer)
		elif int(h.low_months) >= QUIT_AFTER_MONTHS:
			var cid := w.employer
			sim.personnel.release(w)
			h.asked = false
			h.low_months = 0
			w.motivation = 50.0
			sim.log_event("%s kündigt bei %s (Lohn zu niedrig, Haushalt im Defizit)." % [w.name, sim.company(cid).company_name], "bad", cid)
			sim.company(cid).add_key_event("Kündigung: " + w.name, sim.game_min)
	else:
		h.low_months = 0


# ------------------------------------------------------------------ Anzeige
func summary_of(cid: int) -> Dictionary:
	var staff: Array = sim.personnel.employed(cid)
	var low := 0
	var deficit := 0
	var avg := 0.0
	for w in staff:
		var h := household_of(w)
		avg += w.motivation
		if w.motivation < LOW_MOTIVATION:
			low += 1
		if float(h.shortfall) > 0.0:
			deficit += 1
	return {"mitarbeiter": staff.size(), "motivation_mittel": int(avg / maxf(staff.size(), 1)), "unzufrieden": low, "haushalte_im_defizit": deficit,
		"lohnrueckstand": int(sim.company(cid).ledger.payables)}


func total_balance() -> float:
	var t := 0.0
	for h in homes.values():
		t += float(h.balance)
	return t


func to_dict() -> Dictionary:
	return {"homes": homes, "next": _next, "spent_total": spent_total}


func from_dict(d: Dictionary) -> void:
	homes = d.get("homes", {})
	for h in homes.values():
		h.dependents = int(h.dependents)
		h.address = int(h.address)
		h.deficit_months = int(h.deficit_months)
		h.low_months = int(h.low_months)
	_next = int(d.get("next", 1))
	spent_total = float(d.get("spent_total", 0.0))
