class_name Waste
extends RefCounted
## Muellabfuhr, Recycling und Mehrweg (Auftrag 5, Abschnitt 12; Auftrag 22 Phase 1, docs/INFRASTRUCTURE.md).
## Jedes bewohnte Haus und jeder Laden hat eine Tonne mit Fuellstand (kg). Taeglich kommt der Abfall der Einwohner der jeweiligen Stadt
## (Einwohner x KG_PER_PERSON_DAY, verteilt nach bewohnten Wohnungen) und die Verpackung der Kassenverkaeufe (auf die Laeden) hinein.
## Die Muellabfuhr jeder Stadt faehrt vom Rathaus aus Touren zu den vollsten Tonnen; erst beim Halt wird die Tonne wirklich geleert.
## Volle Wagen fahren zur gemeinsamen Deponie der Region, wo die Waage die Menge je Stadt erfasst: Wertstoffe (Recyclingquote) werden
## verkauft, der Rest wird abgelagert. Abholung und Ablagerung zahlt die Kasse der liefernden Stadt (an den Entsorger S0), die Gebuehr
## am Monatsende die Haushalte (H0) an ihre Stadt. Ueberquellende Tonnen senken die Versorgungszufriedenheit. Ist die Deponie zu
## EXPAND_AT gefuellt, wird sie erweitert; die Kosten teilen sich die Staedte nach ihren gewogenen Mengen.
## Mehrwegflaschen (siehe Retail: Pfand, Leergut, Wiederbefuellung) sparen Verpackungsabfall und erhoehen die Recyclingquote.

const KG_PER_PERSON_DAY := 0.9
const KG_PER_SALE := 0.35               # Verpackung je Kassenverkauf (Einheit)
const COLLECT_COST := 55.0              # EUR je Tonne Abholung
const DISPOSAL_COST := 70.0             # EUR je Tonne Restmuell
const RECYCLE_INCOME := 30.0            # EUR je Tonne Wertstoff
const BASE_RECYCLING := 0.35
const MEHRWEG_BONUS := 0.25             # zusaetzliche Quote bei vollstaendiger Mehrwegnutzung
const FEE_MARKUP := 1.1                 # Gebuehr = erwartete Kosten + 10 %
## Deponie und Muellabfuhr (sichtbar): Restmuell geht auf die gemeinsame Deponie, Muellwagen fahren Touren zu vollen Tonnen.
const LANDFILL_CAPACITY := 800.0        # Tonnen bis zur vollen Deponie beim Start (Spielwert)
const START_FILL := 0.25                # bestehende Deponie beim Start
const TRUCK_TONS := 2.0                 # Ladekapazitaet eines Muellwagens (t)
const TRIP_DAYS := 5.0                  # typische Tourdauer mit voller Ladung inkl. Fahrt zur Deponie (gemessen 2-9 Tage, tests/probe_waste.gd)
const MAX_TRUCKS := 8                   # hoechstens so viele Muellwagen je Stadt
const STOPS := 60                       # Halte je Tour (bis die Ladung voll ist)
const BIN_DAYS := 7.0                   # eine Tonne fasst den Abfall von so vielen Tagen
const MIN_BIN_KG := 20.0
const COLLECT_AT := 0.6                 # Tonnen ab diesem Fuellstand werden angefahren
const MIN_LOAD := 0.3                   # eine Tour startet ab diesem Anteil der Ladekapazitaet ...
const URGENT := 0.95                    # ... oder wenn die vollste Tonne so voll ist (kleine Orte: etwa woechentlich)
const EXPAND_AT := 0.8                  # Deponie-Erweiterung ab diesem Fuellstand
const EXPAND_T := 600.0
const EXPAND_COST := 90000.0
const EXPAND_DAYS := 20
const SCALE_LOG := 40                   # so viele Waegungen bleiben im Waagebuch

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
var capacity := LANDFILL_CAPACITY      # Fassungsvermoegen der Deponie (t), waechst mit jeder Erweiterung
var bins := {}                          # Gebaeude-ID -> Fuellstand (kg)
var bin_rate := {}                      # Gebaeude-ID -> kg je Tag (taeglich neu berechnet, nicht gespeichert)
var by_town := {}                       # Stadt -> {"month": {...}, "total": {...}} wie month/total
var scale_log: Array = []               # Waagebuch [{tag, stadt, t, rest}]
var expansion := {}                     # laufende Erweiterung {start, fertig, t, kosten}
var expansions := 0
var overflow_days := 0                  # Summe ueberquellender Tonnen je Tag (Kennzahl)
var _planned := {}                      # Gebaeude-ID -> true, Tonne ist einer laufenden Tour zugeteilt (nicht gespeichert)


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
		if not city.coastal() and not sim.prod._outskirts(p):
			continue
		var h := float(absi(hash([city.seed_value, p.id, "deponie"])) % 100000)
		if city.coastal():   # Kuestenort: an der Ortsgrenze, so weit wie moeglich vom Hafen (Strassen gibt es nur im Ort)
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
	return clampf(deposited / capacity, 0.0, 1.0)


func bin_capacity(bid: int) -> float:
	return maxf(MIN_BIN_KG, float(bin_rate.get(bid, 0.0)) * BIN_DAYS)


## Tonnen, die ueber ihr Fassungsvermoegen gefuellt sind (Stadt k oder alle).
func overflowing(k: int = -1) -> Array:
	return bins.keys().filter(func(bid): return float(bins[bid]) > bin_capacity(bid) and (k < 0 or sim.towns.of_building(bid) == k))


## Anteil ueberquellender Tonnen (0..1) fuer die Versorgungszufriedenheit.
func overflow_share() -> float:
	return float(overflowing().size()) / maxf(1.0, float(bins.size()))


## Abfall des Tages in die Tonnen: Einwohner je Stadt verteilt nach bewohnten Wohnungen, Verpackung auf die geoeffneten Laeden.
## Ohne bewohnte Wohnung landet der Abfall der Stadt in der Tonne am Rathaus. Gibt die erzeugten Tonnen zurueck.
func _produce() -> float:
	var weights := {}   # Stadt -> {Gebaeude-ID: Wohnungen}
	for u in sim.housing.units.values():
		if str(u.get("tenant", "")) == "":
			continue
		var bid := int(u.building)
		var k: int = sim.towns.of_building(bid)
		if not weights.has(k):
			weights[k] = {}
		weights[k][bid] = int(weights[k].get(bid, 0)) + 1
	bin_rate = {}
	var made := 0.0
	for k in sim.towns.count():
		var kg := float(sim.citizens.population_of(k)) * KG_PER_PERSON_DAY
		var w: Dictionary = weights.get(k, {})
		if w.is_empty():
			var th := int(sim.towns.get_t(k).get("town_hall", -1))
			if th < 0 or kg <= 0.0:
				continue
			w = {th: 1}
		var sum := 0
		for bid in w:
			sum += int(w[bid])
		for bid in w:
			_put(bid, kg * float(w[bid]) / float(sum))
		made += kg
	var units: int = int(sim.retail.stats.units)
	var pack := float(units - _units_seen) * KG_PER_SALE
	_units_seen = units
	var shops: Array = sim.retail.shops.values().filter(func(s): return s.status == "offen")
	if pack > 0.0 and not shops.is_empty():
		for s in shops:
			_put(int(s.building), pack / float(shops.size()))
		made += pack
	return made / 1000.0


func _put(bid: int, kg: float) -> void:
	bins[bid] = float(bins.get(bid, 0.0)) + kg
	bin_rate[bid] = float(bin_rate.get(bid, 0.0)) + kg


func _dist(a: int, sb: Dictionary) -> int:
	var b: Dictionary = sim.city.building(a)
	return absi(int(b.x) - int(sb.x)) + absi(int(b.y) - int(sb.y))


## Muellwagen der Stadt k: so viele, dass der Tagesabfall (Haushalte und Verpackung) bei typischer Tourdauer abgefahren wird (+30 % Reserve).
func trucks_for(k: int) -> int:
	var kg := 0.0
	for bid in bin_rate:
		if sim.towns.of_building(bid) == k:
			kg += float(bin_rate[bid])
	var t_day := kg / 1000.0
	return clampi(ceili(t_day * TRIP_DAYS / TRUCK_TONS * 1.3), 1, MAX_TRUCKS)


## Tonne der Stadt k voll genug fuer die Abfuhr und noch keiner Tour zugeteilt?
func _due(bid: int, k: int) -> bool:
	return not _planned.has(bid) and sim.towns.of_building(bid) == k and float(bins[bid]) >= COLLECT_AT * bin_capacity(bid) and not sim.city.building(bid).is_empty()


## Touren je Stadt: die vollste Tonne ist der erste Halt; von dort faehrt der Wagen jeweils die naechstgelegene volle Tonne an,
## bis die Ladung voll ist (Nachbarschaftsroute statt Zickzack; die Fahrt zur Deponie lohnt sich nur mit voller Ladung).
func _dispatch() -> void:
	if landfill_road.x < 0:
		return
	for k in sim.towns.count():
		var cand: Array = bins.keys().filter(func(bid): return _due(bid, k))
		cand.sort_custom(func(a, b): return float(bins[a]) / bin_capacity(a) > float(bins[b]) / bin_capacity(b))
		while not cand.is_empty():
			var seed_b: Dictionary = sim.city.building(cand[0])
			var pool: Array = cand.duplicate()
			var stops: Array = []
			var kg := 0.0
			var at: Dictionary = seed_b
			while not pool.is_empty() and stops.size() < STOPS:
				var here: Dictionary = at
				var bid: int = pool.reduce(func(best, x): return x if _dist(x, here) < _dist(best, here) else best, pool[0])
				if not stops.is_empty() and kg + float(bins[bid]) > TRUCK_TONS * 1000.0:
					break
				pool.erase(bid)
				at = sim.city.building(bid)
				stops.append({"road": at.road, "building": bid})
				kg += float(bins[bid])
			if kg < MIN_LOAD * TRUCK_TONS * 1000.0 and float(bins[cand[0]]) < URGENT * bin_capacity(cand[0]):
				break   # lohnt die Fahrt zur Deponie noch nicht und keine Tonne droht ueberzulaufen
			if not sim.fleet.send_garbage(stops, landfill_road, TRUCK_TONS, "Müllabfuhr %s Tour %d" % [sim.towns.name_of(k), tours + 1], k):
				break
			tours += 1
			for st in stops:
				_planned[int(st.building)] = true
				cand.erase(int(st.building))


## Halt eines Muellwagens: Tonne leeren, hoechstens room_kg. Gibt die geladenen kg zurueck.
func empty_bin(bid: int, room_kg: float) -> float:
	_planned.erase(bid)
	var take := minf(float(bins.get(bid, 0.0)), maxf(0.0, room_kg))
	if take > 0.0:
		bins[bid] = float(bins[bid]) - take
	return take


## Wagen voll oder Tour abgebrochen: zugeteilte Tonnen wieder freigeben.
func release(bids: Array) -> void:
	for bid in bids:
		_planned.erase(int(bid))


## Waage der Deponie: Menge der Stadt k erfassen, Wertstoffe verkaufen, Rest ablagern, Kosten der Stadtkasse buchen.
func weigh_in(k: int, tons: float) -> void:
	if tons <= 0.0:
		return
	var recycled := tons * rate
	var residual := tons - recycled
	deposited += residual
	var acct := Towns.account_of(k)
	var cost := tons * COLLECT_COST + residual * DISPOSAL_COST
	var income := recycled * RECYCLE_INCOME
	var pay := minf(cost, maxf(0.0, float(sim.economy.accounts.get(acct, 0.0))))
	sim.economy.transfer(acct, "S0", pay)            # Entsorger holt ab und behandelt
	_unpaid += cost - pay
	sim.economy.transfer("X0", acct, income)         # Wertstoffe gehen in den Verkauf
	var tk: Dictionary = _town_stats(k)
	for d in [month, total, tk.month, tk.total]:
		d.tons = float(d.tons) + tons
		d.recycled = float(d.recycled) + recycled
		d.cost = float(d.cost) + pay
		d.income = float(d.income) + income
	scale_log.append({"tag": GameCalendar.day_of(sim.game_min), "stadt": k, "t": tons, "rest": residual})
	if scale_log.size() > SCALE_LOG:
		scale_log = scale_log.slice(-SCALE_LOG)


func _town_stats(k: int) -> Dictionary:
	var key := str(k)
	if not by_town.has(key):
		by_town[key] = {"month": {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}, "total": {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0, "fees": 0.0}}
	return by_town[key]


## Erweiterung der Deponie: Start ab EXPAND_AT Fuellstand, Kosten nach den bisher gewogenen Mengen je Stadt, fertig nach EXPAND_DAYS.
func _check_expansion(day: int) -> void:
	if not expansion.is_empty():
		if day >= int(expansion.fertig):
			capacity += float(expansion.t)
			expansions += 1
			sim.log_event("Deponie erweitert: Fassungsvermögen jetzt %.0f t (Füllstand %d %%)." % [capacity, roundi(fill_share() * 100.0)], "info")
			expansion = {}
		return
	if fill_share() < EXPAND_AT:
		return
	var shares := {}
	var sum := 0.0
	for k in sim.towns.count():
		shares[k] = float(_town_stats(k).total.tons)
		sum += float(shares[k])
	var parts: Array = []
	for k in shares:
		var part := EXPAND_COST * (float(shares[k]) / sum if sum > 0.0 else 1.0 / float(shares.size()))
		var acct := Towns.account_of(k)
		var pay := minf(part, maxf(0.0, float(sim.economy.accounts.get(acct, 0.0))))
		sim.economy.transfer(acct, "S0", pay)
		_unpaid += part - pay
		parts.append("%s %s" % [sim.towns.name_of(k), Catalog.money(part)])
	expansion = {"start": day, "fertig": day + EXPAND_DAYS, "t": EXPAND_T, "kosten": EXPAND_COST}
	sim.log_event("Deponie zu %d %% voll – Erweiterung um %.0f t beginnt (fertig in %d Tagen; Kosten nach Liefermengen: %s)." % [
		roundi(fill_share() * 100.0), EXPAND_T, EXPAND_DAYS, ", ".join(parts)], "warn")


## Anteil der Getraenkeflaschen, die als Mehrweg zurueckkommen (0..1).
func mehrweg_share() -> float:
	var sold := int(sim.retail.stats.bottles_sold)
	return 0.0 if sold <= 0 else clampf(float(sim.retail.stats.bottles_returned) / float(sold), 0.0, 1.0)


func on_day(day: int) -> void:
	rate = BASE_RECYCLING + MEHRWEG_BONUS * mehrweg_share()
	var first := bins.is_empty()
	_produce()
	if first:   # Spielbeginn: die Tonnen sind unterschiedlich voll (wie die vorhandene Deponie), damit die Abfuhr gleich Arbeit hat
		for bid in bins:
			bins[bid] = float(bins[bid]) + bin_capacity(bid) * float(absi(hash([sim.city.seed_value, bid, "tonne"])) % 80) / 100.0
	_dispatch()
	overflow_days += overflowing().size()
	_check_expansion(day)


func on_month(_m: int) -> void:
	# Gebuehr je Stadt: die Haushalte tragen die Kosten des abgelaufenen Monats (plus Aufschlag), abzueglich Wertstofferloes
	var due_all := 0.0
	for key in by_town:
		var tm: Dictionary = by_town[key].month
		var due: float = maxf(0.0, (float(tm.cost) - float(tm.income)) * FEE_MARKUP)
		if due > 0.0:
			sim.economy.transfer("H0", Towns.account_of(int(key)), due)
			by_town[key].total.fees = float(by_town[key].total.fees) + due
			due_all += due
		by_town[key].month = {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}
	total.fees += due_all
	last_month = month.duplicate()
	last_month["fee"] = due_all
	last_month["quote"] = float(month.recycled) / maxf(0.001, float(month.tons))
	last_month["ueberquellend"] = overflowing().size()
	sim.log_event("Müllabfuhr: %.1f t gewogen, Recyclingquote %d %% (Mehrweg %d %%), Gebühr %s, %d Tonnen quellen über." % [float(month.tons),
		roundi(float(last_month.quote) * 100.0), roundi(mehrweg_share() * 100.0), Catalog.money(due_all), int(last_month.ueberquellend)], "info")
	month = {"tons": 0.0, "recycled": 0.0, "cost": 0.0, "income": 0.0}


func to_dict() -> Dictionary:
	var b := {}
	for bid in bins:
		b[str(bid)] = bins[bid]
	return {"month": month, "total": total, "rate": rate, "last": last_month, "units_seen": _units_seen, "unpaid": _unpaid, "deposited": deposited, "tours": tours,
		"capacity": capacity, "bins": b, "by_town": by_town.duplicate(true), "scale_log": scale_log.duplicate(true), "expansion": expansion.duplicate(),
		"expansions": expansions, "overflow_days": overflow_days}


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
	capacity = float(d.get("capacity", LANDFILL_CAPACITY))
	bins = {}
	for key in d.get("bins", {}):
		bins[int(key)] = float(d.bins[key])
	by_town = d.get("by_town", {})
	scale_log = d.get("scale_log", [])
	expansion = d.get("expansion", {})
	expansions = int(d.get("expansions", 0))
	overflow_days = int(d.get("overflow_days", 0))
	_planned = {}   # Muellwagen werden nicht gespeichert: laufende Touren entfallen, die Tonnen bleiben voll und werden neu angefahren
