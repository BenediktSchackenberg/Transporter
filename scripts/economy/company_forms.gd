class_name CompanyForms
extends RefCounted
## Unternehmensformen (Spielregeln, siehe docs/ECONOMY.md Abschnitt 5).

const FORMS := {
	"einzel": {"name": "Einzelunternehmen", "found_cost": 0.0, "min_equity": 0.0, "admin": 0.0, "report": "keine", "loan_factor": 0.8, "private_reserve": 15000.0},
	"ug": {"name": "UG (haftungsbeschränkt)", "found_cost": 500.0, "min_equity": 1.0, "admin": 80.0, "report": "jährlich", "loan_factor": 1.0, "private_reserve": 0.0},
	"gmbh": {"name": "GmbH", "found_cost": 2000.0, "min_equity": 25000.0, "admin": 250.0, "report": "vierteljährlich", "loan_factor": 1.2, "private_reserve": 0.0},
}
const MIN_AGE_MONTHS := 3
const PROCESS_DAYS := 15.0


static func name_of(form: String) -> String:
	return FORMS.get(form, FORMS.einzel).name


static func loan_factor(c: Company) -> float:
	return float(FORMS[c.form].loan_factor)


## Formwechsel beantragen. Kosten sofort, Wirksamkeit nach 15 Tagen Bearbeitung.
static func request_change(sim: Simulation, cid: int, form: String) -> Dictionary:
	var c := sim.company(cid)
	if not FORMS.has(form):
		return {"ok": false, "msg": "Unbekannte Form (einzel, ug, gmbh)."}
	if form == c.form:
		return {"ok": false, "msg": "Das Unternehmen ist bereits %s." % name_of(form)}
	if c.pending_form != "":
		return {"ok": false, "msg": "Ein Formwechsel zu %s ist bereits in Bearbeitung." % name_of(c.pending_form)}
	var age := GameCalendar.month_of(sim.game_min) - GameCalendar.month_of(c.founded_min)
	if age < MIN_AGE_MONTHS:
		return {"ok": false, "msg": "Formwechsel frühestens nach %d Monaten (bisher %d)." % [MIN_AGE_MONTHS, age]}
	for l in sim.banking.loans.values():
		if l.owner == cid and l.status in ["rueckstand", "ausgefallen"]:
			return {"ok": false, "msg": "Formwechsel nicht möglich: Kredit %s hat Rückstände." % l.id}
	if c.status != "aktiv":
		return {"ok": false, "msg": "Formwechsel nur bei ordentlicher Lage (Status: %s)." % c.status}
	var spec: Dictionary = FORMS[form]
	if sim.net_worth(cid) < float(spec.min_equity):
		return {"ok": false, "msg": "%s verlangt Eigenkapital ab %s (vorhanden %s)." % [spec.name, Catalog.money(spec.min_equity), Catalog.money(sim.net_worth(cid))]}
	if c.ledger.cash < float(spec.found_cost):
		return {"ok": false, "msg": "Kosten des Formwechsels: %s." % Catalog.money(spec.found_cost)}
	c.ledger.book("admin", -float(spec.found_cost), true, "Formwechsel zu " + spec.name, sim.game_min)
	c.pending_form = form
	c.pending_form_due = sim.game_min + GameCalendar.days_to_min(PROCESS_DAYS)
	return {"ok": true, "msg": "Formwechsel zu %s beantragt (Kosten %s), wirksam in %d Spieltagen." % [spec.name, Catalog.money(spec.found_cost), int(PROCESS_DAYS)]}


## Taeglich: abgeschlossene Formwechsel wirksam machen.
static func finish_due(sim: Simulation) -> void:
	for c in sim.companies:
		if c.pending_form != "" and sim.game_min >= c.pending_form_due:
			var old := name_of(c.form)
			c.form = c.pending_form
			c.pending_form = ""
			sim.log_event("%s wechselt von %s zur Rechtsform %s." % [c.company_name, old, name_of(c.form)], "info", c.id)
			c.add_key_event("Formwechsel zu " + name_of(c.form), sim.game_min)


## Monatlich: Verwaltungskosten; Berichte gemaess Berichtspflicht.
static func monthly(sim: Simulation, month: int) -> void:
	for c in sim.companies:
		if not c.is_active():
			continue
		var spec: Dictionary = FORMS[c.form]
		c.ledger.book("admin", -float(spec.admin), true, "Verwaltung " + spec.name, sim.game_min)
		var due: bool = (c.form == "gmbh" and month % 3 == 2) or (c.form == "ug" and month % 12 == 11)
		if due:
			sim.log_event("%s veröffentlicht den %s: Gewinn %s, Bargeld %s, Schulden %s." % [c.company_name,
				"Quartalsbericht" if c.form == "gmbh" else "Jahresabschluss", Catalog.money(c.ledger.profit()), Catalog.money(c.ledger.cash),
				Catalog.money(c.ledger.debt)], "info", c.id)
