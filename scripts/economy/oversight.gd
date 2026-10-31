class_name Oversight
extends RefCounted
## Gewerbeaufsicht und Einsaetze der Oeffentlichen Hand (Auftrag 4, Rest: B5, siehe docs/HOUSING_AND_MONEY.md).
##
## Gewerbeaufsicht: Monatlich prueft das Amt Betriebe (Firmeneinrichtungen und Geschaefte) zufaellig, aber deterministisch. Ist eine
## Einrichtung oder ein Geschaeftsgebaeude verwahrlost (Zustand unter CONDITION_MIN), erteilt es eine Auflage mit Frist. Wird der
## Zustand bis zur Frist nicht auf CONDITION_OK gebracht, folgt ein Bussgeld an die Stadtkasse.
## Einsaetze: Bei schweren Wetterereignissen schickt die Stadt einmal je Ereignis Kraefte (Kosten aus P0 an S0, Ressort Verkehr,
## Instandsetzung der am staerksten verfallenen Gebaeude).

const CONDITION_MIN := 25.0        # darunter: Beanstandung
const CONDITION_OK := 40.0         # ab hier gilt die Auflage als erfuellt
const INSPECT_CHANCE := 0.15       # je Betrieb und Monat
const DEADLINE_DAYS := 30
const FINE := 2500.0
const SHOP_FIX := 1500.0           # Instandsetzung durch den Betreiber eines Geschaefts
const EINSATZ := {
	"starkregen": {"label": "Pumpen und Straßenreinigung", "cost": 4000.0, "repair": 4.0},
	"sturm": {"label": "Sturmschäden beseitigen", "cost": 6000.0, "repair": 5.0},
	"glaette": {"label": "Streudienst", "cost": 2500.0, "repair": 0.0},
}
const REPAIR_BUILDINGS := 10        # so viele verfallene Gebaeude werden je Einsatz instand gesetzt

var sim: Simulation
var orders := {}                    # "A<n>" -> {id, target, what, label, found, deadline, status, fine}
var missions: Array = []            # {event, kind, day, cost, repaired}
var fines_total := 0.0
var mission_cost_total := 0.0
var _done_events := {}              # Ereignis-ID -> true
var _next := 1


func setup(s: Simulation) -> void:
	sim = s
	s.day_changed.connect(on_day)
	s.month_changed.connect(on_month)


func _today() -> int:
	return GameCalendar.day_of(sim.game_min)


## Zustand eines geprueften Objekts: "F<id>" = Firmeneinrichtung, "G<id>" = Gebaeude eines Geschaefts.
func condition_of(what: String) -> float:
	if what.begins_with("F"):
		return float(sim.estate.facilities.get(what.substr(1), {}).get("condition", 100.0))
	return sim.care.get_condition(int(what.substr(1)))


func open_for(target: String) -> Array:
	return orders.values().filter(func(o): return o.target == target and o.status == "offen")


func _has_open(what: String) -> bool:
	return orders.values().any(func(o): return o.what == what and o.status == "offen")


# ------------------------------------------------------------------ Gewerbeaufsicht
func on_month(month: int) -> void:
	for c in sim.companies:
		if c.status in ["insolvenz", "verwertung", "geschlossen"]:
			continue
		for f in sim.estate.facilities.values():
			if int(f.owner) == c.id and f.status == "fertig":
				_inspect("C%d" % c.id, "F" + str(f.id), "%s (%s)" % [Estate.FACILITIES[f.typ].name, c.company_name], month)
	for shop in sim.retail.shops.values():
		if shop.status != "geschlossen":
			_inspect(str(shop.id), "G%d" % int(shop.building), str(shop.name), month)


func _inspect(target: String, what: String, label: String, month: int) -> void:
	if _has_open(what) or Citizens.roll(target.hash(), month, 11) >= INSPECT_CHANCE:
		return
	var cond := condition_of(what)
	if cond >= CONDITION_MIN:
		return
	var o := {"id": "A%d" % _next, "target": target, "what": what, "label": label, "found": _today(), "deadline": _today() + DEADLINE_DAYS, "status": "offen", "fine": 0.0}
	_next += 1
	orders[o.id] = o
	sim.log_event("Gewerbeaufsicht: Auflage %s für %s – Zustand %d, Instandsetzung bis Tag %d." % [o.id, label, int(cond), int(o.deadline)], "warn")
	if target.begins_with("C"):
		sim.notify(int(target.substr(1)), "Gewerbeaufsicht beanstandet %s (Zustand %d). Frist bis Tag %d, sonst %s Bußgeld (fund_maintenance/commission_renovation)." % [label, int(cond), int(o.deadline), Catalog.money(FINE)])


func on_day(_day: int) -> void:
	var today := _today()
	for o in orders.values():
		if o.status != "offen":
			continue
		var is_shop: bool = not str(o.target).begins_with("C")
		if is_shop and today >= int(o.found) + 10:
			_fix_shop(o)   # Betreiber setzt sein Geschaeft nach zehn Tagen selbst instand, wenn die Kasse reicht
		if condition_of(o.what) >= CONDITION_OK:
			o.status = "erfuellt"
			sim.log_event("Gewerbeaufsicht: Auflage %s für %s erfüllt." % [o.id, o.label], "info")
		elif today >= int(o.deadline):
			_fine(o)
	_missions(today)
	if orders.size() > 120:   # alte Vorgaenge verfallen aus der Liste
		for id in orders.keys():
			if orders[id].status != "offen" and orders.size() > 100:
				orders.erase(id)


func _fix_shop(o: Dictionary) -> void:
	var shop: Dictionary = sim.retail.shops.get(o.target, {})
	if shop.is_empty() or float(sim.economy.accounts.get(o.target, 0.0)) < SHOP_FIX:
		return
	sim.economy.transfer(o.target, "S0", SHOP_FIX)
	var id := int(str(o.what).substr(1))
	sim.care.condition[id] = minf(100.0, sim.care.get_condition(id) + 30.0)


func _fine(o: Dictionary) -> void:
	var amount := FINE
	if str(o.target).begins_with("C"):
		var c := sim.company(int(str(o.target).substr(1)))
		amount = minf(FINE, maxf(0.0, c.ledger.cash)) if c != null else 0.0
		if c != null and amount > 0.0:
			c.ledger.book("fines", -amount, true, "Gewerbeaufsicht: Auflage %s nicht erfüllt" % o.id, sim.game_min)
	else:
		amount = minf(FINE, maxf(0.0, float(sim.economy.accounts.get(o.target, 0.0))))
		if amount > 0.0:
			sim.economy.transfer(o.target, "P0", amount)
	o.status = "bussgeld"
	o.fine = amount
	fines_total += amount
	sim.log_event("Gewerbeaufsicht: Bußgeld %s gegen %s (Auflage %s nicht erfüllt)." % [Catalog.money(amount), o.label, o.id], "bad")


# ------------------------------------------------------------------ Einsaetze
func _missions(today: int) -> void:
	for e in sim.events.events:
		if e.status != "aktiv" or _done_events.has(e.id) or int(e.get("schwere", 0)) < 2 or not EINSATZ.has(str(e.typ)):
			continue
		_done_events[e.id] = true
		var spec: Dictionary = EINSATZ[e.typ]
		var cost := minf(float(spec.cost), maxf(0.0, float(sim.economy.accounts.P0)))
		if cost > 0.0:
			sim.economy.transfer("P0", "S0", cost)
			sim.public_sector.departments.Verkehr += cost
			mission_cost_total += cost
		var repaired := _repair(float(spec.repair)) if cost >= float(spec.cost) else 0
		missions.append({"event": e.id, "kind": e.typ, "day": today, "cost": cost, "repaired": repaired})
		if missions.size() > 40:
			missions.pop_front()
		sim.log_event("Einsatz der Stadt (%s): %s, Kosten %s%s." % [e.typ, spec.label, Catalog.money(cost), ", %d Gebäude instand gesetzt" % repaired if repaired > 0 else ""], "info")


## Setzt die am staerksten verfallenen Gebaeude um `points` Zustandspunkte instand; gibt ihre Zahl zurueck.
func _repair(points: float) -> int:
	if points <= 0.0:
		return 0
	var ids: Array = sim.care.condition.keys()
	ids.sort_custom(func(a, b): return float(sim.care.condition[a]) < float(sim.care.condition[b]) or (float(sim.care.condition[a]) == float(sim.care.condition[b]) and a < b))
	var n := 0
	for id in ids.slice(0, REPAIR_BUILDINGS):
		sim.care.condition[id] = minf(100.0, float(sim.care.condition[id]) + points)
		n += 1
	return n


func summary() -> Dictionary:
	var by := {"offen": 0, "erfuellt": 0, "bussgeld": 0}
	for o in orders.values():
		by[o.status] = int(by.get(o.status, 0)) + 1
	return {"auflagen": by, "bussgelder": fines_total, "einsaetze": missions.size(), "einsatzkosten": mission_cost_total}


func to_dict() -> Dictionary:
	return {"orders": orders, "missions": missions, "fines_total": fines_total, "mission_cost_total": mission_cost_total, "done": _done_events.keys(), "next": _next}


func from_dict(d: Dictionary) -> void:
	orders = d.get("orders", {})
	for o in orders.values():
		o.found = int(o.found)
		o.deadline = int(o.deadline)
	missions = d.get("missions", [])
	fines_total = float(d.get("fines_total", 0.0))
	mission_cost_total = float(d.get("mission_cost_total", 0.0))
	_done_events = {}
	for id in d.get("done", []):
		_done_events[str(id)] = true
	_next = int(d.get("next", 1))
