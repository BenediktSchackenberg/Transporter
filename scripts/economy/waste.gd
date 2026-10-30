class_name Waste
extends RefCounted
## Muellabfuhr, Recycling und Mehrweg (Auftrag 5, Abschnitt 12). Haushalte und Betriebe erzeugen taeglich Abfall (Tonnen); die Stadt (P0) laesst ihn
## von einem Entsorger (S0) abholen. Wertstoffe (Recyclingquote) werden verkauft, der Rest kostet Behandlung. Die Gebuehr zahlen die Haushalte (H0).
## Mehrwegflaschen (siehe Retail: Pfand, Leergut, Wiederbefuellung) sparen Verpackungsabfall und erhoehen die Recyclingquote.

const KG_PER_PERSON_DAY := 0.9
const KG_PER_SALE := 0.35               # Verpackung je Kassenverkauf (Einheit)
const COLLECT_COST := 55.0              # EUR je Tonne Abholung
const DISPOSAL_COST := 70.0             # EUR je Tonne Restmuell
const RECYCLE_INCOME := 30.0            # EUR je Tonne Wertstoff
const BASE_RECYCLING := 0.35
const MEHRWEG_BONUS := 0.25             # zusaetzliche Quote bei vollstaendiger Mehrwegnutzung
const FEE_MARKUP := 1.1                 # Gebuehr = erwartete Kosten + 10 %

var sim: Simulation
var month := {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}
var total := {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0, "fees": 0.0}
var rate := BASE_RECYCLING
var last_month := {}
var _units_seen := 0
var _unpaid := 0.0                      # aufgelaufene Kosten, die der Stadtkasse noch zu begleichen sind (nur bei leerer Kasse)


func setup(s: Simulation) -> void:
	sim = s
	s.day_changed.connect(on_day)
	s.month_changed.connect(on_month)


## Anteil der Getraenkeflaschen, die als Mehrweg zurueckkommen (0..1).
func mehrweg_share() -> float:
	var sold := int(sim.retail.stats.bottles_sold)
	return 0.0 if sold <= 0 else clampf(float(sim.retail.stats.bottles_returned) / float(sold), 0.0, 1.0)


func on_day(_day: int) -> void:
	var units: int = int(sim.retail.stats.units)
	var tons := float(sim.citizens.population()) * KG_PER_PERSON_DAY / 1000.0 + float(units - _units_seen) * KG_PER_SALE / 1000.0
	_units_seen = units
	rate = BASE_RECYCLING + MEHRWEG_BONUS * mehrweg_share()
	var recycled := tons * rate
	var residual := tons - recycled
	var cost := tons * COLLECT_COST + residual * DISPOSAL_COST
	var income := recycled * RECYCLE_INCOME
	var pay := minf(cost, maxf(0.0, float(sim.economy.accounts.P0)))
	sim.economy.transfer("P0", "S0", pay)            # Entsorger holt ab und behandelt
	_unpaid += cost - pay
	sim.economy.transfer("X0", "P0", income)         # Wertstoffe gehen in den Verkauf
	for d in [month, total]:
		d.tons += tons
		d.recycled += recycled
		d.cost += pay
		d.income += income


func on_month(_m: int) -> void:
	# Gebuehr: die Haushalte tragen die Kosten des abgelaufenen Monats (plus Aufschlag), abzueglich Wertstofferloes
	var due: float = maxf(0.0, (float(month.cost) - float(month.income)) * FEE_MARKUP)
	if due > 0.0:
		sim.economy.transfer("H0", "P0", due)
		total.fees += due
	last_month = month.duplicate()
	last_month["fee"] = due
	last_month["quote"] = float(month.recycled) / maxf(0.001, float(month.tons))
	sim.log_event("Müllabfuhr: %.1f t gesammelt, Recyclingquote %d %% (Mehrweg %d %%), Gebühr %s." % [float(month.tons), roundi(float(last_month.quote) * 100.0),
		roundi(mehrweg_share() * 100.0), Catalog.money(due)], "info")
	month = {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}


func to_dict() -> Dictionary:
	return {"month": month, "total": total, "rate": rate, "last": last_month, "units_seen": _units_seen, "unpaid": _unpaid}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	for k in d.get("month", {}):
		month[k] = float(d.month[k])
	for k in d.get("total", {}):
		total[k] = float(d.total[k])
	rate = float(d.get("rate", BASE_RECYCLING))
	last_month = d.get("last", {})
	_units_seen = int(d.get("units_seen", 0))
	_unpaid = float(d.get("unpaid", 0.0))
