class_name Citizens
extends RefCounted
## Buerger und Arbeitsmarkt. Die Stadt hat mindestens POPULATION Einwohner; 80 % haben Arbeit. Die Mitarbeiter der KI-Firmen sind
## echte Arbeiter (Personnel); alle uebrigen Buerger sind schlanke Datensaetze mit Arbeitgeber (Rathaus, Baufirma, ...) oder arbeitslos.
## Monatlich: Arbeitgeber passen ihren Bedarf an (Entlassungen/Einstellungen), Buerger wechseln die Stelle oder werden arbeitslos,
## Loehne fliessen vom Arbeitgeberkonto an H0, Lohnsteuer und Sozialabgaben an P0, Arbeitslose erhalten Arbeitslosengeld von P0.

const POPULATION := 1200
const EMPLOYMENT_TARGET := 0.8
const HOURS_PER_MONTH := 60.0
const QUIT_CHANCE := 0.02          # freiwilliger Stellenwechsel je Monat
const DROP_CHANCE := 0.004         # Kuendigung ohne neue Stelle
const DEMAND_SWING := 0.12         # Schwankung des Personalbedarfs je Arbeitgeber und Monat (+/-)
const BENEFIT_RATE := 0.6          # Arbeitslosengeld in Anteil des mittleren Nettolohns
const SPEND_SHARE := 0.8           # Anteil des Nettos, der an S0 geht
const IMPORT_SHARE := 0.1          # Anteil fuer Importe (X0); der Rest wird gespart
## Arbeitgeber der uebrigen Buerger: Anteil an den Stellen, Stundenlohn, zahlendes Konto, Arbeitsviertel (Index in Catalog.DISTRICTS)
const EMPLOYERS := {
	"rathaus": {"label": "Rathaus", "share": 0.06, "wage": 15.0, "payer": "P0", "district": 0},
	"schule_klinik": {"label": "Schulen und Klinik", "share": 0.10, "wage": 14.0, "payer": "P0", "district": 1},
	"baufirma": {"label": "Baufirma", "share": 0.20, "wage": 15.0, "payer": "S0", "district": 5},
	"handel": {"label": "Handel und Gastronomie", "share": 0.32, "wage": 11.0, "payer": "S0", "district": 0},
	"industrie": {"label": "Industrie und Handwerk", "share": 0.32, "wage": 14.0, "payer": "S0", "district": 2},
	"stadtlager": {"label": "Stadtlager", "share": 0.008, "wage": 13.0, "payer": "P0", "district": 3},
}

var sim: Simulation
var people: Array = []             # {id, name, employer ("" = arbeitslos), wage, jobless_months}
var base_cap := {}                 # Arbeitgeber -> Grundbedarf an Stellen
var cap := {}                      # aktueller Bedarf
var stats := {"changes": 0, "layoffs": 0, "hires": 0, "quits": 0, "wages": 0.0, "tax": 0.0, "benefits": 0.0}
var last := {}                     # Kennzahlen des letzten Monatsabschlusses
var _next := 1
var _travel_places := {}
var _travel_revision := -1


## Sichtbare Alltagswege aus bestehenden Wohn-, Arbeits- und Einkommensdaten.
## Die Bewegung selbst erzeugt keine zweite Lohn-, Miet- oder Konsumbuchung.
func travel_plan(person: Dictionary, hour: float = -1.0) -> Dictionary:
	if _travel_revision != sim.city.buildings.size():
		_travel_places.clear()
		_travel_revision = sim.city.buildings.size()
	if hour < 0.0:
		hour = Catalog.hour_of_day(sim.game_min)
	var unit: Dictionary = sim.housing.units.get(str(person.get("home", "")), {})
	var home := int(unit.get("building", -1))
	var employer := str(person.get("employer", ""))
	if home >= 0 and (hour < 6.0 or hour >= 20.0):
		return {"building": home, "purpose": "Nach Hause", "cell": sim.city.building(home).walk}
	var kind := "work:" + employer
	var purpose := "Zur Arbeit: " + str(EMPLOYERS.get(employer, {}).get("label", employer))
	var types: Array = {"rathaus": ["townhall"] if sim.town_hall.building >= 0 else ["office", "bank"], "schule_klinik": ["school", "kindergarten", "clinic"], "baufirma": ["construction", "warehouse"],
		"handel": ["shop", "restaurant"], "industrie": ["factory", "brewery", "bakery", "workshop"], "stadtlager": ["warehouse"]}.get(employer, ["office"])
	if employer == "":
		kind = "staffing"
		types = ["office"]
		purpose = "Zur Arbeitsvermittlung"
	elif hour >= 12.0 and hour < 14.0:
		kind = "shopping"
		types = ["shop", "supermarket", "bakery"]
		purpose = "Einkaufen fuer den Haushalt"
	elif hour >= 17.0 and hour < 20.0 and float(person.get("wage", 0.0)) > 0.0:
		kind = "restaurant"
		types = ["restaurant", "cafe", "hotel"]
		purpose = "Restaurantbesuch nach der Arbeit"
	if not _travel_places.has(kind):
		var places: Array = sim.city.buildings.filter(func(b): return (b.type in types or (kind == "staffing" and b.role == "staffing")) and sim.city.walkable(b.walk))
		if places.is_empty():
			places = sim.city.buildings.filter(func(b): return sim.city.walkable(b.walk) and b.type not in ["plot", "free_plot"])
		_travel_places[kind] = places.map(func(b): return int(b.id))
	var places: Array = _travel_places[kind]
	if places.is_empty():
		return {}
	var building := int(places[posmod(int(person.id), places.size())])
	return {"building": building, "purpose": purpose, "cell": sim.city.building(building).walk}


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)


## Erzeugt die Bevoelkerung nach dem Startpersonal der Firmen.
func generate() -> void:
	var real := _real_workers()
	var total := maxi(POPULATION, real + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.city.seed_value) + 4711
	var real_employed := 0
	for c in sim.companies:
		real_employed += sim.personnel.employed(c.id).size()
	var jobs := maxi(0, roundi(total * EMPLOYMENT_TARGET) - real_employed)
	for k in EMPLOYERS:
		base_cap[k] = roundi(jobs * float(EMPLOYERS[k].share))
	cap = base_cap.duplicate()
	for i in total - real:
		var first: Array = Residents.FEMALE if rng.randi() % 2 == 0 else Residents.MALE
		people.append({"id": _next, "name": "%s %s" % [first[rng.randi() % first.size()],
			CityGenerator.SURNAMES[rng.randi() % CityGenerator.SURNAMES.size()]], "employer": "", "wage": 0.0, "jobless_months": 0})
		_next += 1
	var assigned := 0
	for k in EMPLOYERS:
		for j in int(base_cap[k]):
			if assigned >= people.size():
				break
			_employ(people[assigned], k, rng.randf())
			assigned += 1


## Zuzug: neue, zunaechst arbeitslose Buerger (Haushalte, die eine Wohnung gefunden haben).
func immigrate(n: int, month: int, home: String = "") -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.city.seed_value) + 9100 + month
	for i in n:
		var first: Array = Residents.FEMALE if rng.randi() % 2 == 0 else Residents.MALE
		people.append({"id": _next, "name": "%s %s" % [first[rng.randi() % first.size()],
			CityGenerator.SURNAMES[rng.randi() % CityGenerator.SURNAMES.size()]], "employer": "", "wage": 0.0, "jobless_months": 0, "home": home})
		_next += 1


## Wegzug: alle Buerger der Wohneinheit verlassen die Stadt. Gibt ihre Zahl zurueck.
func emigrate(unit_id: String) -> int:
	var before := people.size()
	people = people.filter(func(p): return str(p.get("home", "")) != unit_id)
	return before - people.size()


func _employ(p: Dictionary, k: String, r: float) -> void:
	p.employer = k
	p.wage = snappedf(float(EMPLOYERS[k].wage) * (0.9 + 0.2 * r), 0.1)
	p.jobless_months = 0


func _real_workers() -> int:
	var n := 0
	for w in sim.personnel.workers.values():
		if not w.lost:
			n += 1
	return n


func population() -> int:
	return people.size() + _real_workers()


func employed_count(k: String) -> int:
	var n := 0
	for p in people:
		if p.employer == k:
			n += 1
	return n


func employed_total() -> int:
	var n := 0
	for c in sim.companies:
		n += sim.personnel.employed(c.id).size()
	for p in people:
		if p.employer != "":
			n += 1
	return n


func unemployed_total() -> int:
	return population() - employed_total()


func employment_rate() -> float:
	return float(employed_total()) / maxf(1.0, float(population()))


## Zufall ohne Zustand: gleiche Eingabe ergibt immer dieselbe Zahl (Wiederholung und Laden bleiben exakt).
static func roll(a: int, b: int, salt: int) -> float:
	return float(absi(hash(Vector3i(a, b, salt))) % 10000) / 10000.0


func on_month(month: int) -> void:
	stats = {"changes": 0, "layoffs": 0, "hires": 0, "quits": 0, "wages": 0.0, "tax": 0.0, "benefits": 0.0}
	_dynamics(month)
	_pay()
	last = summary()


func _vacancies() -> Dictionary:
	var v := {}
	for k in EMPLOYERS:
		v[k] = int(cap[k]) - employed_count(k)
	return v


func _dynamics(month: int) -> void:
	var keys: Array = EMPLOYERS.keys()
	for i in keys.size():
		var k: String = keys[i]
		cap[k] = maxi(0, roundi(float(base_cap[k]) * (1.0 + DEMAND_SWING * (roll(i, month, 1) * 2.0 - 1.0))))
		if k == "rathaus":
			cap[k] = sim.town_hall.total_target()   # der Buergermeister legt den Bedarf fest, keine Zufallsschwankung
	# Entlassungen bei sinkendem Bedarf (zuletzt Eingestellte zuerst)
	var count := {}
	for k in keys:
		count[k] = employed_count(k)
	for idx in range(people.size() - 1, -1, -1):
		var p: Dictionary = people[idx]
		if p.employer != "" and int(count[p.employer]) > int(cap[p.employer]):
			count[p.employer] = int(count[p.employer]) - 1
			p.employer = ""
			p.wage = 0.0
			stats.layoffs += 1
	# freiwillige Wechsel und Kuendigungen
	var vac := _vacancies()
	for p in people:
		if p.employer == "":
			continue
		var r := roll(int(p.id), month, 2)
		if r < QUIT_CHANCE:
			var target := ""
			var start := int(roll(int(p.id), month, 3) * keys.size())
			for j in keys.size():
				var k2: String = keys[(start + j) % keys.size()]
				if k2 != p.employer and int(vac[k2]) > 0:
					target = k2
					break
			if target != "":
				vac[p.employer] = int(vac[p.employer]) + 1
				vac[target] = int(vac[target]) - 1
				_employ(p, target, roll(int(p.id), month, 4))
				sim.housing.relocate_for_job(p, int(EMPLOYERS[target].district), month)
				stats.changes += 1
		elif r > 1.0 - DROP_CHANCE:
			vac[p.employer] = int(vac[p.employer]) + 1
			p.employer = ""
			p.wage = 0.0
			stats.quits += 1
	# Einstellungen: am laengsten Arbeitslose zuerst
	var jobless: Array = people.filter(func(q): return q.employer == "")
	jobless.sort_custom(func(a, b): return a.jobless_months > b.jobless_months or (a.jobless_months == b.jobless_months and a.id < b.id))
	for p in jobless:
		var best := ""
		for k in keys:
			if int(vac[k]) > 0 and (best == "" or int(vac[k]) > int(vac[best])):
				best = k
		if best == "":
			break
		vac[best] = int(vac[best]) - 1
		_employ(p, best, roll(int(p.id), month, 5))
		sim.housing.relocate_for_job(p, int(EMPLOYERS[best].district), month)
		stats.hires += 1
	for p in people:
		if p.employer == "":
			p.jobless_months = int(p.jobless_months) + 1


func _pay() -> void:
	# Die Haushaltsabrechnung (Households) leitet Auslandseinkommen aus den H0-Abfluessen ab; Buergerzahlungen zaehlen dort nicht mit.
	var outflow_h0 := float(sim.economy.outflow.get("H0", 0.0))
	var by_payer := {}
	var gross := 0.0
	var employed := 0
	for p in people:
		if p.employer == "":
			continue
		var w: float = float(p.wage) * HOURS_PER_MONTH
		var payer: String = EMPLOYERS[p.employer].payer
		by_payer[payer] = float(by_payer.get(payer, 0.0)) + w
		gross += w
		employed += 1
	for payer in by_payer:
		sim.economy.transfer(payer, "H0", by_payer[payer])
	var net := 0.0
	if gross > 0.0:
		net = sim.public_sector.withhold(gross)
		stats.tax = gross - net
	stats.wages = gross
	# Arbeitslosengeld: Anteil des mittleren Nettolohns
	var jobless := people.size() - employed
	var benefit := 0.0
	if employed > 0 and jobless > 0:
		benefit = BENEFIT_RATE * net / employed * jobless
		sim.economy.transfer("P0", "H0", benefit)
		sim.public_sector.benefits_total += benefit
		sim.public_sector.departments.Soziales += benefit
	stats.benefits = benefit
	_set_net_income(net / gross if gross > 0.0 else 0.0, benefit / jobless if jobless > 0 else 0.0)
	var rent := sim.housing.collect_citizen_rent()   # Miete zuerst; den Rest geben die Buerger aus
	var disposable := maxf(0.0, net + benefit - rent)
	# Konsum der Buerger: Handel (S0) und Importe (X0)
	var spend := disposable * SPEND_SHARE * sim.contentment.spend_factor()   # zufriedene Buerger geben mehr aus
	var at_tills := minf(spend, sim.retail.take_month_sales())   # was an den Kassen der Betriebe bezahlt wurde, zahlt der Haushalt nicht noch einmal pauschal
	sim.economy.transfer("H0", "S0", spend - at_tills)
	sim.public_sector.consumption_tax(spend)
	var imports := disposable * IMPORT_SHARE
	sim.economy.transfer("H0", "X0", imports)
	sim.economy.transfer("X0", "S0", imports)   # Ausfuhren der Stadtwirtschaft gleichen die Importe aus
	sim.economy.outflow["H0"] = outflow_h0


## Netto je Person fuer die Mietzahlung: Beschaeftigte Lohn mal Nettoanteil, Arbeitslose ihr Arbeitslosengeld.
func _set_net_income(net_share: float, benefit_each: float) -> void:
	for p in people:
		p.net = float(p.wage) * HOURS_PER_MONTH * net_share if p.employer != "" else benefit_each


func summary() -> Dictionary:
	var by := {}
	for c in sim.companies:
		by[c.company_name] = sim.personnel.employed(c.id).size()
	for k in EMPLOYERS:
		by[EMPLOYERS[k].label] = employed_count(k)
	return {"einwohner": population(), "beschaeftigt": employed_total(), "arbeitslos": unemployed_total(), "quote": employment_rate(),
		"arbeitgeber": by, "wechsel": stats.changes, "entlassungen": stats.layoffs, "einstellungen": stats.hires, "kuendigungen": stats.quits,
		"lohnsumme": stats.wages, "abgaben": stats.tax, "arbeitslosengeld": stats.benefits}


func to_dict() -> Dictionary:
	return {"people": people, "base_cap": base_cap, "cap": cap, "stats": stats, "next": _next}


func from_dict(d: Dictionary) -> void:
	people = d.get("people", [])
	for p in people:
		p.id = int(p.id)
		p.jobless_months = int(p.jobless_months)
	base_cap = d.get("base_cap", {})
	cap = d.get("cap", {})
	for k in base_cap:
		base_cap[k] = int(base_cap[k])
	for k in cap:
		cap[k] = int(cap[k])
	stats = d.get("stats", stats)
	_next = int(d.get("next", 1))
