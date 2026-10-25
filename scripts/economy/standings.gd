class_name Standings
extends RefCounted
## Ranglisten, Etappensieger und Zeitreihen (docs/ECONOMY.md Abschnitt 12).
##
## Wertung: kumulierter Nettogewinn. Endsieger ist das aktive, zahlungsfaehige Unternehmen mit dem hoechsten Gewinn.
## Etappensieger (je Spielmonat) bleiben erhalten, auch wenn die Firma spaeter insolvent wird. Offene Verpflichtungen,
## Wertberichtigungen und Insolvenzverluste werden ausgewiesen.

const MAX_MONTHS := 240

var sim: Simulation
var stage_winners: Array = []   # {month, cid, name, owner, form, generation, profit}
var series: Array = []          # je Monat: [{cid, name, profit, cash, net_worth, debt, status}]


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)


## Zahlungsfaehig = aktiv oder nur mit Liquiditaetswarnung.
static func solvent(c: Company) -> bool:
	return c.status in ["aktiv", "warnung"]


func leader() -> Company:
	var r := sim.ranking()
	return r[0] if not r.is_empty() else null


## Endsieger: aktives, zahlungsfaehiges Unternehmen mit dem hoechsten kumulierten Nettogewinn (null, wenn keines existiert).
func winner() -> Company:
	for c in sim.ranking():
		if solvent(c):
			return c
	return null


func on_month(new_month: int) -> void:
	var month := new_month - 1   # der gerade abgeschlossene Monat (0 = erster)
	var row: Array = []
	for c in sim.companies:
		row.append({"cid": c.id, "name": c.company_name, "profit": c.ledger.profit(), "cash": c.ledger.cash,
			"net_worth": sim.net_worth(c.id), "debt": c.ledger.debt, "status": c.status})
	series.append({"month": month, "rows": row})
	if series.size() > MAX_MONTHS:
		series.pop_front()
	var lead := leader()
	if lead != null and solvent(lead):
		stage_winners.append({"month": month, "cid": lead.id, "name": lead.company_name, "owner": lead.player_name, "form": lead.form,
			"generation": lead.generation, "profit": lead.ledger.profit()})
		sim.log_event("Etappensieger Monat %d: %s (Gewinn %s)." % [month + 1, lead.company_name, Catalog.money(lead.ledger.profit())], "info", lead.id)


## Offene Verpflichtungen der naechsten 30 Tage und Insolvenzverluste insgesamt.
func obligations(c: Company) -> float:
	return sim.insolvency.obligations_30d(c)


func insolvency_losses() -> float:
	var t := 0.0
	for e in sim.insolvency.archive:
		t += float(e.lost)
	return t


## Zeitreihe eines Wertes ("profit", "cash", "net_worth") fuer einen Platz, als [[Monat, Wert], ...].
func values(cid: int, key: String) -> Array:
	var out: Array = []
	for m in series:
		for r in m.rows:
			if r.cid == cid:
				out.append([m.month, r[key]])
	return out


func to_dict() -> Dictionary:
	return {"stage_winners": stage_winners, "series": series}


func from_dict(d: Dictionary) -> void:
	stage_winners = d.get("stage_winners", [])
	for w in stage_winners:
		w.month = int(w.month)
		w.cid = int(w.cid)
		w.generation = int(w.generation)
	series = d.get("series", [])
	for m in series:
		m.month = int(m.month)
		for r in m.rows:
			r.cid = int(r.cid)
