class_name StrategyEvaluator
extends RefCounted
## Bewertung eines Strategiezeitraums aus der vorhandenen Buchhaltung (Ledger) und den Auftragszaehlern der Firma.
## Strategiewert = (Gewinn Ende - Gewinn Start) / Spieltage. Kosten werden nicht erneut abgezogen: der Gewinn des Ledgers enthaelt sie bereits.
## Liquiditaetsprobleme (Bargeld unter null oder Zahlungsverzug) mindern den Wert um RISK_PENALTY.

const RISK_PENALTY := 300.0
const BUSY_STATES := ["to_pickup", "loading", "to_dropoff", "unloading", "returning", "waiting_bay"]
const EMPTY_STATES := ["to_pickup", "returning"]


## Stand zu Beginn eines Zeitraums.
static func snapshot(sim: Simulation, cid: int) -> Dictionary:
	var c: Company = sim.company(cid)
	return {"day": GameCalendar.day_of(sim.game_min), "profit": c.ledger.profit(), "cash": c.ledger.cash,
		"completed": int(c.stats.completed), "on_time": int(c.stats.on_time), "late": int(c.stats.late), "failed": int(c.stats.failed)}


## Stichprobe der Flotte (stuendlich): Anteil arbeitender und leer fahrender Fahrzeuge, niedrigstes Bargeld.
static func sample(sim: Simulation, cid: int, acc: Dictionary) -> void:
	var vs: Array = sim.company_vehicles(cid)
	var c: Company = sim.company(cid)
	acc.min_cash = minf(float(acc.get("min_cash", c.ledger.cash)), c.ledger.cash)
	if not Standings.solvent(c):
		acc.insolvent = true
	for v in vs:
		acc.vehicle_samples = int(acc.get("vehicle_samples", 0)) + 1
		if v.state in BUSY_STATES:
			acc.busy = int(acc.get("busy", 0)) + 1
		if v.state in EMPTY_STATES:
			acc.empty = int(acc.get("empty", 0)) + 1


## Bewertung des Zeitraums seit `start`. `situation` haelt den Kontext fest, in dem das Ergebnis gilt.
static func evaluate(sim: Simulation, cid: int, strategy: String, start: Dictionary, acc: Dictionary) -> Dictionary:
	var now := snapshot(sim, cid)
	var days := maxi(1, int(now.day) - int(start.day))
	var contracts := int(now.completed) - int(start.completed)
	var on_time := int(now.on_time) - int(start.on_time)
	var failed := int(now.failed) - int(start.failed)
	var samples := maxi(1, int(acc.get("vehicle_samples", 0)))
	var risk: bool = float(acc.get("min_cash", now.cash)) < 0.0 or bool(acc.get("insolvent", false))
	var per_day := (float(now.profit) - float(start.profit)) / float(days)
	var value := per_day - (RISK_PENALTY if risk else 0.0)
	var market_open := 0
	for k in sim.contracts.values():
		if k.status == "open":
			market_open += 1
	return {"strategy": strategy, "day_from": int(start.day), "day_to": int(now.day), "days": days,
		"value": snappedf(value, 0.01), "profit_per_day": snappedf(per_day, 0.01), "contracts": contracts, "failed": failed,
		"on_time_rate": snappedf(float(on_time) / float(contracts), 0.01) if contracts > 0 else -1.0,
		"utilization": snappedf(float(acc.get("busy", 0)) / float(samples), 0.01), "empty_share": snappedf(float(acc.get("empty", 0)) / float(samples), 0.01),
		"min_cash": snappedf(float(acc.get("min_cash", now.cash)), 0.01), "risk": risk,
		"situation": {"fleet_size": sim.company_vehicles(cid).size(), "cash": snappedf(float(start.cash), 1.0), "open_contracts": market_open,
			"drive_factor": snappedf(sim.wx.drive_factor(), 0.01)}}
