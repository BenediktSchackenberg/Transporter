class_name Commuting
extends RefCounted
## Pendeln und Umzuege zwischen den Staedten (Auftrag 17, Abschnitt 11) fuer das Firmenpersonal: Wohnung (Haushalt -> Wohneinheit ->
## Wohnstadt) und Arbeitsort (zugeordneter Betrieb, sonst Hauptsitz der Firma) sind bekannt.
## Monatlich: Wer in einer anderen Stadt arbeitet als er wohnt, pendelt (Fahrtkosten vom Haushaltsguthaben an den Handel S0, je Fahrweg;
## Motivation sinkt). Nach MOVE_AFTER Monaten zieht der Haushalt in eine freie, bezahlbare Wohnung der Arbeitsstadt: Auszug (alte Einheit
## frei) und Einzug in einem Schritt, Umzugswagen faehrt; keine neuen Personen, kein neues Geld (nur der Umzugspreis an S0).

const COST_PER_CELL := 0.4          # EUR je Feld Strassenweg und Monat (Hin- und Rueckfahrten pauschal)
const COST_MAX := 180.0
const MOVE_AFTER := 2
const MOVE_COST := 120.0
const MAX_RENT_SHARE := 0.45

var sim
var stats := {"pendler": 0, "kosten": 0.0, "umzuege": 0, "last": {}}   # last: Stadt -> {aus, ein}


func setup(simulation) -> void:
	sim = simulation
	sim.month_changed.connect(on_month)


func workplace(w) -> int:
	var b: Dictionary = sim.biz.get_b(str(w.business)) if str(w.business) != "" else {}
	if not b.is_empty():
		return int(b.site)
	var c = sim.company(int(w.employer))
	return int(c.depots[0]) if c != null and not c.depots.is_empty() else -1


func on_month(_m: int) -> void:
	if not sim.towns.is_region():
		return
	var flows := {}
	var n := 0
	var rail_pairs := {}
	var rail_n := 0
	for w in sim.personnel.workers.values():
		if w.lost or int(w.employer) < 0 or str(w.household) == "":
			continue
		var site := workplace(w)
		var h: Dictionary = sim.households.homes.get(str(w.household), {})
		var u: Dictionary = sim.housing.units.get(str(h.get("unit", "")), {})
		if site < 0 or h.is_empty() or u.is_empty():
			continue
		var home_t: int = sim.towns.of_building(int(u.building))
		var work_t: int = sim.towns.of_building(site)
		if home_t == work_t:
			h.erase("pendel_monate")
			continue
		n += 1
		var e: Dictionary = flows.get(home_t, {"aus": 0, "ein": 0})
		e.aus = int(e.aus) + 1
		flows[home_t] = e
		var e2: Dictionary = flows.get(work_t, {"aus": 0, "ein": 0})
		e2.ein = int(e2.ein) + 1
		flows[work_t] = e2
		if sim.trains != null and sim.trains.connects(home_t, work_t):
			# Auftrag 22 Phase 6 Schritt 3: Bahnpendler fahren Regionalbahn (Fahrgeld je Fahrt in RailTraffic), kein Auto, weniger Stress
			var pk := "%d|%d" % [home_t, work_t]
			rail_pairs[pk] = int(rail_pairs.get(pk, 0)) + 1
			rail_n += 1
			w.motivation = maxf(0.0, float(w.motivation) - 1.0)
		else:
			var dist: int = sim.nav.road_path(sim.city.building(int(u.building)).road, sim.city.building(site).road).size()
			var cost := minf(COST_MAX, COST_PER_CELL * float(dist))
			var pay := minf(cost, maxf(0.0, float(h.balance)))
			if pay > 0.0:
				h.balance = float(h.balance) - pay
				sim.economy.transfer("H0", "S0", pay)   # Bus/Benzin
				stats.kosten = float(stats.kosten) + pay
			w.motivation = maxf(0.0, float(w.motivation) - 2.0)
		h["pendel_monate"] = int(h.get("pendel_monate", 0)) + 1
		if int(h.pendel_monate) >= MOVE_AFTER:
			_move(h, work_t)
	stats.pendler = n
	stats.last = flows
	stats["bahn_pendler"] = rail_n
	stats["bahn_paare"] = rail_pairs


## Umzug in die Arbeitsstadt: passende freie Einheit, bezahlbar (Miete <= MAX_RENT_SHARE des Einkommens), Umzugspreis gedeckt.
func _move(h: Dictionary, town: int) -> bool:
	var income := maxf(1.0, float(h.get("last_income", h.get("income", 0.0))))
	var cands: Array = sim.housing.vacant_units().filter(func(x): return sim.towns.of_building(int(x.building)) == town and float(x.rent) <= MAX_RENT_SHARE * income)
	if cands.is_empty() or float(h.balance) < MOVE_COST:
		return false
	cands.sort_custom(func(a, b): return a.rent < b.rent or (a.rent == b.rent and a.id < b.id))
	var target: Dictionary = cands[0]
	var from: int = int(h.get("address", -1))
	h.balance = float(h.balance) - MOVE_COST
	sim.economy.transfer("H0", "S0", MOVE_COST)
	sim.housing.move_household(str(h.id), str(target.id))   # Auszug alt, Einzug neu (eine Hauptwohnung)
	h.erase("pendel_monate")
	stats.umzuege = int(stats.umzuege) + 1
	sim.fleet.send_moving(int(target.building), "Umzug")
	sim.log_event("Haushalt %s zieht von %s nach %s (Arbeitsplatz dort)." % [h.id, sim.towns.name_of(sim.towns.of_building(from)) if from >= 0 else "?", sim.towns.name_of(town)], "info")
	return true


func summary() -> Dictionary:
	return {"pendler": int(stats.pendler), "pendelkosten": int(stats.kosten), "umzuege": int(stats.umzuege), "je_stadt": stats.last}


func to_dict() -> Dictionary:
	return {"stats": stats.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	stats = d.get("stats", stats)
