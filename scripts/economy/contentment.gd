class_name Contentment
extends RefCounted
## Zufriedenheit der Bewohner (Auftrag 6, A5, siehe docs/HOUSING_AND_MONEY.md).
##
## Index 0-100 je Wohneinheit (`sat`) aus vier Teilen: Wohnung (Gebaeudezustand, Mietbelastung, Rueckstand), Arbeit (Beschaeftigung,
## Motivation), Versorgung (offene Geschaefte, Muellabfuhr) und Verkehr (Zeitverlust). Wirkung: Der Konsum der Buerger folgt dem
## Stadtmittel (`spend_factor`), die Motivation der Firmenmitarbeiter dem Index ihres Haushalts, und wer drei Monate unter
## EMIGRATE_BELOW liegt, zieht mit einer Wahrscheinlichkeit aus der Stadt weg (Buerger verlassen die Stadt, die Wohnung wird frei).

const W_HOUSING := 0.35
const W_WORK := 0.30
const W_SUPPLY := 0.20
const W_TRAFFIC := 0.15
const NEUTRAL := 60.0              # Stadtmittel, bei dem der Konsum unveraendert bleibt
const EMIGRATE_BELOW := 25.0
const EMIGRATE_AFTER := 3          # Monate unter der Schwelle
const EMIGRATE_CHANCE := 0.25      # je Monat danach

var sim: Simulation
var mean := NEUTRAL               # Stadtmittel ueber alle belegten Einheiten
var by_district := {}              # Viertelname -> Mittelwert
var parts := {"wohnung": 0.0, "arbeit": 0.0, "versorgung": 0.0, "verkehr": 0.0}   # Stadtmittel je Teil
var emigrated := 0


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)


## Faktor fuer den Konsum der Buerger (0.85 bis 1.1).
func spend_factor() -> float:
	return clampf(1.0 + (mean - NEUTRAL) / 200.0, 0.85, 1.1)


## Index der Wohneinheit eines Firmenhaushalts (50 ohne Wohnung).
func of_household(hid: String) -> float:
	return float(sim.housing.unit_of_household(hid).get("sat", 50.0))


## Stadtweite Teile: Versorgung (Anteil offener Geschaefte, Muellabfuhr ohne Rueckstau) und Verkehr (Zeitverlust).
func supply_score() -> float:
	var open := 0
	for s in sim.retail.shops.values():
		if s.status == "offen":
			open += 1
	var shops_ok := float(open) / maxf(1.0, float(sim.retail.shops.size()))
	var waste_ok := 1.0 if float(sim.waste._unpaid) <= 0.0 else 0.6
	return 100.0 * (0.7 * shops_ok + 0.3 * waste_ok)


func traffic_score() -> float:
	return clampf(100.0 * (1.0 - 4.0 * (1.0 - sim.traffic_flow.avg_speed())), 0.0, 100.0)


func housing_score(u: Dictionary, income: float) -> float:
	var cond: float = sim.care.get_condition(int(u.building))
	var burden := 0.0 if income <= 0.0 else float(u.rent) / income
	var burden_score := clampf(100.0 * (0.6 - burden) / 0.4, 0.0, 100.0)
	return clampf(0.5 * cond + 0.5 * burden_score - 20.0 * minf(2.0, float(u.arrears)), 0.0, 100.0)


func work_score(members: Array) -> float:
	if members.is_empty():
		return 50.0
	var t := 0.0
	for p in members:
		if p.employer != "":
			t += 80.0
		else:
			t += maxf(5.0, 35.0 - 6.0 * minf(5.0, float(p.jobless_months)))
	return t / members.size()


func on_month(month: int) -> void:
	var supply := supply_score()
	var traffic := traffic_score()
	var occ := sim.housing._citizen_occupants()
	var sum := 0.0
	var n := 0
	var psum := {"wohnung": 0.0, "arbeit": 0.0}
	var dsum := {}
	var dn := {}
	var leaving: Array = []
	for u in sim.housing.units.values():
		if u.tenant == "":
			u.sat = 0.0
			u.low = 0
			continue
		var members: Array = occ.get(u.id, [])
		var income := 0.0
		var work := 50.0
		if u.tenant == "B":
			for p in members:
				income += float(p.get("net", 0.0))
			work = work_score(members)
		elif sim.households.homes.has(u.tenant):
			var h: Dictionary = sim.households.homes[u.tenant]
			income = float(h.get("last_income", 0.0))
			work = 20.0 + 0.8 * _motivation(h)
		var hs := housing_score(u, income)
		u.sat = snappedf(W_HOUSING * hs + W_WORK * work + W_SUPPLY * supply + W_TRAFFIC * traffic, 0.1)
		u.low = int(u.get("low", 0)) + 1 if float(u.sat) < EMIGRATE_BELOW else 0
		if u.tenant == "B" and int(u.low) > EMIGRATE_AFTER and Citizens.roll(u.id.hash(), month, 7) < EMIGRATE_CHANCE:
			leaving.append(u)
		sum += float(u.sat)
		n += 1
		psum.wohnung += hs
		psum.arbeit += work
		var d: String = Catalog.DISTRICTS[int(sim.city.building(int(u.building)).get("district", 0))]
		dsum[d] = float(dsum.get(d, 0.0)) + float(u.sat)
		dn[d] = int(dn.get(d, 0)) + 1
	if n > 0:
		mean = sum / n
		parts = {"wohnung": psum.wohnung / n, "arbeit": psum.arbeit / n, "versorgung": supply, "verkehr": traffic}
	by_district = {}
	for d in dsum:
		by_district[d] = snappedf(float(dsum[d]) / int(dn[d]), 0.1)
	for u in leaving:
		_emigrate(u)


func _motivation(h: Dictionary) -> float:
	var t := 0.0
	var k := 0
	for wid in h.members:
		var w: Worker = sim.personnel.workers.get(wid)
		if w != null:
			t += w.motivation
			k += 1
	return t / k if k > 0 else 50.0


func _emigrate(u: Dictionary) -> void:
	var gone := sim.citizens.emigrate(u.id)
	u.tenant = ""
	u.arrears = 0
	u.low = 0
	u.sat = 0.0
	emigrated += gone
	sim.log_event("%d Bewohner verlassen die Stadt (Zufriedenheit unter %d, Wohnung %s, Gebäude %d)." % [gone, int(EMIGRATE_BELOW), u.id, int(u.building)], "bad")


func to_dict() -> Dictionary:
	return {"mean": mean, "by_district": by_district, "parts": parts, "emigrated": emigrated}


func from_dict(d: Dictionary) -> void:
	mean = float(d.get("mean", NEUTRAL))
	by_district = d.get("by_district", {})
	parts = d.get("parts", parts)
	emigrated = int(d.get("emigrated", 0))
