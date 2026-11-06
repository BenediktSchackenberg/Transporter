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
## Deponie und Muellabfuhr (sichtbar): Restmuell geht auf die Deponie am Stadtrand, Muellwagen fahren taeglich Touren.
const LANDFILL_CAPACITY := 800.0        # Tonnen bis zur vollen Deponie (Spielwert)
const START_FILL := 0.25                # bestehende Deponie beim Start
const TRUCK_TONS := 0.5                 # Tonnen je Tour
const MAX_TRUCKS := 4
const STOPS := 8                        # Halte je Tour

var sim: Simulation
var month := {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}
var total := {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0, "fees": 0.0}
var rate := BASE_RECYCLING
var last_month := {}
var _units_seen := 0
var _unpaid := 0.0                      # aufgelaufene Kosten, die der Stadtkasse noch zu begleichen sind (nur bei leerer Kasse)
var landfill_pid := ""                  # Parzelle der Deponie
var landfill_cells := {}                # Zelle -> Formfaktor 0..1 (Rand niedrig, Mitte hoch)
var landfill_road := Vector2i(-1, -1)   # Zufahrt (Abladestelle)
var deposited := 0.0                    # abgeladener Restmuell (t), bestimmt die Hoehe des Muellbergs
var tours := 0


func setup(s: Simulation) -> void:
	sim = s
	s.day_changed.connect(on_day)
	s.month_changed.connect(on_month)
	deposited = LANDFILL_CAPACITY * START_FILL
	_build_landfill()


## Deponie auf einer freien Parzelle am Stadtrand (nicht auf Lagerstaetten), deterministisch aus dem Stadtsamen. Die Flaeche ist nicht
## begehbar und nicht bebaubar; die Zufahrt ist die naechste Strassenzelle.
func _build_landfill() -> void:
	var city: CityData = sim.city
	var best := {}
	var best_h := INF
	for p in sim.parcels.items.values():
		if p.state != "frei" or not sim.parcels.is_buildable(p) or int(p.area) < 60 or sim.prod._deposits.has(p.id):
			continue
		if not bool(sim.parcels.utilities_of(p).strasse):
			continue
		if city.world != "kueste" and not sim.prod._outskirts(p):
			continue
		var h := float(absi(hash([city.seed_value, p.id, "deponie"])) % 100000)
		if city.world == "kueste":   # Kuestenort: an der Ortsgrenze, so weit wie moeglich vom Hafen (Strassen gibt es nur im Ort)
			h = -Vector2(float(p.rect[0]), float(p.rect[1])).distance_to(Vector2(city.building(city.start_depots[0]).road)) if not city.start_depots.is_empty() else h
		if h < best_h:
			best_h = h
			best = p
	if best.is_empty():
		return
	landfill_pid = best.id
	var r := Rect2i(int(best.rect[0]), int(best.rect[1]), int(best.rect[2]), int(best.rect[3]))
	var mid := Vector2(r.position) + Vector2(r.size) * 0.5
	var far := Vector2(r.size).length() * 0.5
	var bestd := 999
	for y in range(r.position.y - 3, r.end.y + 3):
		for x in range(r.position.x - 3, r.end.x + 3):
			var q := Vector2i(x, y)
			if city.inside(q) and city.is_road(q):
				var d := int(Vector2(q).distance_to(mid))
				if d < bestd:
					bestd = d
					landfill_road = q
	for y in range(r.position.y + 1, r.end.y - 1):
		for x in range(r.position.x + 1, r.end.x - 1):
			var c := Vector2i(x, y)
			if city.building_at[city.idx(c)] >= 0 or city.is_road(c) or city.g(c) == CityData.G.WATER:
				continue
			landfill_cells[c] = clampf(1.0 - Vector2(c).distance_to(mid) / far, 0.15, 1.0)
	best.state = "privat_gehalten"
	best.use = "deponie"
	for c in landfill_cells:
		city.blocked[city.idx(c)] = 1
		sim.nav.walk.set_point_solid(c, true)
	city.trees = city.trees.filter(func(t): return not landfill_cells.has(t[0]))


func fill_share() -> float:
	return clampf(deposited / LANDFILL_CAPACITY, 0.0, 1.0)


## Muellwagen auf Touren schicken: je Tour STOPS Wohn- und Geschaeftshaeuser eines Viertels, dann zur Deponie.
func _dispatch(tons: float) -> void:
	if landfill_road.x < 0:
		return
	var n := clampi(int(ceil(tons / TRUCK_TONS)), 1, MAX_TRUCKS)
	var homes: Array = sim.city.buildings.filter(func(b): return b.get("role", "") != "plot" and b.type in ["house", "semi", "villa", "apartment", "highrise", "shop", "restaurant"])
	if homes.is_empty():
		return
	for i in n:
		var seed_b: Dictionary = homes[absi(hash([GameCalendar.day_of(sim.game_min), i, "tour"])) % homes.size()]
		var near := homes.duplicate()
		near.sort_custom(func(a, b): return absi(a.x - seed_b.x) + absi(a.y - seed_b.y) < absi(b.x - seed_b.x) + absi(b.y - seed_b.y))
		var stops: Array = near.slice(0, STOPS).map(func(b): return {"road": b.road, "building": int(b.id)})
		sim.fleet.send_garbage(stops, landfill_road, tons / float(n), "Müllabfuhr Tour %d" % (tours + 1))
		tours += 1


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
	deposited += residual            # Restmuell kommt auf die Deponie (die Wagen fahren ihn sichtbar dorthin)
	_dispatch(tons)
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
	return {"month": month, "total": total, "rate": rate, "last": last_month, "units_seen": _units_seen, "unpaid": _unpaid, "deposited": deposited, "tours": tours}


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
	deposited = float(d.get("deposited", deposited))
	tours = int(d.get("tours", 0))
