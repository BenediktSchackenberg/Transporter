class_name Citizens
extends RefCounted
## Buerger und Arbeitsmarkt. Die Stadt hat mindestens POPULATION Einwohner; 80 % haben Arbeit. Die Mitarbeiter der KI-Firmen sind
## echte Arbeiter (Personnel); alle uebrigen Buerger sind schlanke Datensaetze mit Arbeitgeber (Rathaus, Baufirma, ...) oder arbeitslos.
## Monatlich: Arbeitgeber passen ihren Bedarf an (Entlassungen/Einstellungen), Buerger wechseln die Stelle oder werden arbeitslos,
## Loehne fliessen vom Arbeitgeberkonto an H0, Lohnsteuer und Sozialabgaben an P0, Arbeitslose erhalten Arbeitslosengeld von P0.

const POPULATION := 1200            # nur Rueckfall; massgeblich ist config/residents.json (Population.cfg)
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
	"polizei": {"label": "Polizei", "share": 0.03, "wage": 16.0, "payer": "P0", "district": 0},
	"gesundheit": {"label": "Ärzte und Pflege", "share": 0.04, "wage": 17.0, "payer": "P0", "district": 1},
	"baufirma": {"label": "Baufirma", "share": 0.20, "wage": 15.0, "payer": "S0", "district": 5},
	"handel": {"label": "Handel und Gastronomie", "share": 0.25, "wage": 11.0, "payer": "S0", "district": 0},
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
	var types: Array = {"rathaus": ["townhall"] if sim.town_hall.building >= 0 else ["office", "bank"], "schule_klinik": ["school", "kindergarten", "clinic"], "polizei": ["police"], "gesundheit": ["doctor", "clinic"], "baufirma": ["construction", "warehouse"],
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
	var total := maxi(int(Population.cfg().get("bevoelkerung", POPULATION)), real + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.city.seed_value) + 4711
	var real_employed := 0
	for c in sim.companies:
		real_employed += sim.personnel.employed(c.id).size()
	var jobs := maxi(0, roundi(total * employment_target()) - real_employed)
	for k in EMPLOYERS:
		base_cap[k] = roundi(jobs * float(EMPLOYERS[k].share))
	cap = base_cap.duplicate()
	for i in total - real:
		var first: Array = Residents.FEMALE if rng.randi() % 2 == 0 else Residents.MALE
		people.append({"id": _next, "name": "%s %s" % [first[rng.randi() % first.size()],
			CityGenerator.SURNAMES[rng.randi() % CityGenerator.SURNAMES.size()]], "employer": "", "wage": 0.0, "jobless_months": 0})
		_next += 1
	# Bildung vor der Vergabe: Rathaus und Schulen/Klinik zuerst, Hoeherqualifizierte zuerst (Vorlage: Buero/Verwaltung bevorzugt hoehere Bildung)
	sim.population.assign_attributes(people)
	var by_edu: Array = people.duplicate()
	by_edu.sort_custom(func(a, b): return int(a.education) > int(b.education) or (int(a.education) == int(b.education) and int(a.id) < int(b.id)))
	var assigned := 0
	for k in EMPLOYERS:
		for j in int(base_cap[k]):
			if assigned >= by_edu.size():
				break
			_employ(by_edu[assigned], k, rng.randf())
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
	sim.population.init_people(people.slice(people.size() - n), month)


## Wegzug: alle Buerger der Wohneinheit verlassen die Stadt. Gibt ihre Zahl zurueck.
func emigrate(unit_id: String) -> int:
	var before := people.size()
	sim.population.on_emigrate(people.filter(func(p): return str(p.get("home", "")) == unit_id))
	people = people.filter(func(p): return str(p.get("home", "")) != unit_id)
	return before - people.size()


func _employ(p: Dictionary, k: String, r: float) -> void:
	p.employer = k
	p.wage = snappedf(float(EMPLOYERS[k].wage) * (0.9 + 0.2 * r) * Population.wage_factor(p), 0.1)
	p.jobless_months = 0


func _real_workers() -> int:
	var n := 0
	for w in sim.personnel.workers.values():
		if not w.lost:
			n += 1
	return n


func population() -> int:
	return people.size() + _real_workers()


## Beschaeftigungsziel aus der Konfiguration (Population.cfg), Standard 0,9.
static func employment_target() -> float:
	return float(Population.cfg().get("beschaeftigungsquote", EMPLOYMENT_TARGET))


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
	_pay(month)
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
	var jail_day: int = GameCalendar.day_of(sim.game_min)
	var jobless: Array = people.filter(func(q): return q.employer == "" and not PublicSafety.in_prison(q, jail_day))
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


## Monatszyklus der Buerger in fester Reihenfolge (docs/RESIDENTS.md): 1 Loehne, 2 Grundsicherung, 3 Miete, 4 Grundsteuer,
## 5 Konsum, 6 Beduerfnisse und Protokoll. Alle Zahlungen laufen ueber die Personenkonten (Sektorkonto R0).
func _pay(month: int = 0) -> void:
	# Die Haushaltsabrechnung (Households) leitet Auslandseinkommen aus den H0-Abfluessen ab; Buergerzahlungen zaehlen dort nicht mit.
	var outflow_h0 := float(sim.economy.outflow.get("H0", 0.0))
	var P: Population = sim.population
	var start_bal := {}
	for p in people:
		start_bal[int(p.id)] = float(p.get("balance", 0.0))
	# 1) Loehne je Arbeitgeberkonto (Rathaus aus der Stadtkasse), dann Lohnsteuer und Sozialabgaben
	var by_payer := {}
	var gross := 0.0
	var employed := 0
	for p in people:
		if p.employer == "":
			continue
		var w: float = float(p.wage) * HOURS_PER_MONTH
		var payer: String = EMPLOYERS[p.employer].payer
		if not by_payer.has(payer):
			by_payer[payer] = []
		by_payer[payer].append([p, w])
		gross += w
		employed += 1
	for payer in by_payer:
		P.pay_in(payer, by_payer[payer])
	var net := 0.0
	var net_share := 0.0
	if gross > 0.0:
		net_share = 1.0 - PublicSector.INCOME_TAX - PublicSector.SOCIAL_RATE
		for payer in by_payer:
			for e in by_payer[payer]:
				e[0].balance = float(e[0].balance) - float(e[1]) * (1.0 - net_share)
		net = sim.public_sector.withhold(gross, Population.ACCOUNT)
		stats.tax = gross - net
	stats.wages = gross
	# 2) Grundsicherung: Anteil des mittleren Nettolohns fuer jeden Arbeitslosen
	var jobless: Array = people.filter(func(q): return q.employer == "" and not PublicSafety.in_prison(q, GameCalendar.day_of(sim.game_min)))
	var benefit := 0.0
	var benefit_each := 0.0
	if employed > 0 and not jobless.is_empty():
		benefit_each = BENEFIT_RATE * net / employed
		benefit = P.pay_in("P0", jobless.map(func(q): return [q, benefit_each]))
		sim.public_sector.benefits_total += benefit
		sim.public_sector.departments.Soziales += benefit
	stats.benefits = benefit
	_set_net_income(net_share, benefit_each)
	# 3) Miete (Mieter -> Eigentuemer bzw. Vermietersektor), 4) Grundsteuer der Eigentuemer
	var rent := sim.housing.collect_citizen_rent()
	var prop_tax := P.collect_property_tax(month)
	# 5) Konsum aus dem Monatseinkommen nach Miete, hoechstens das Guthaben: Handel (S0), Kassenkaeufe (bereits ueber H0), Importe (X0)
	var factor: float = SPEND_SHARE * sim.contentment.spend_factor()
	var spend_entries: Array = []
	var import_entries: Array = []
	var spend := 0.0
	var imports := 0.0
	for p in people:
		var income_left := maxf(0.0, float(p.balance) - float(start_bal.get(int(p.id), 0.0)))
		var s := minf(income_left * factor, maxf(0.0, float(p.balance)))
		var imp := minf(income_left * IMPORT_SHARE, maxf(0.0, float(p.balance) - s))
		spend_entries.append([p, s])
		import_entries.append([p, imp])
		spend += s
		imports += imp
	var at_tills := minf(spend, sim.retail.take_month_sales())   # was an den Kassen der Betriebe bezahlt wurde, lief schon ueber H0
	var paid_spend := P.pay_out("S0", spend_entries)
	if at_tills > 0.0:
		sim.economy.transfer("S0", "H0", minf(at_tills, paid_spend))   # Kassenkaeufe: der Haushaltssektor wird entlastet, nicht doppelt belastet
	sim.public_sector.consumption_tax(paid_spend)
	var paid_imports := P.pay_out("X0", import_entries)
	sim.economy.transfer("X0", "S0", paid_imports)   # Ausfuhren der Stadtwirtschaft gleichen die Importe aus
	sim.economy.outflow["H0"] = outflow_h0
	# 6) Beduerfnisse und Monatsprotokoll
	P.update_needs()
	P.month_log.append({"monat": month, "loehne": snappedf(gross, 1.0), "abgaben": snappedf(gross - net, 1.0), "grundsicherung": snappedf(benefit, 1.0),
		"miete": snappedf(rent, 1.0), "grundsteuer": snappedf(prop_tax, 1.0), "konsum": snappedf(paid_spend, 1.0), "importe": snappedf(paid_imports, 1.0),
		"guthaben": snappedf(float(sim.economy.accounts.get(Population.ACCOUNT, 0.0)), 1.0)})
	if P.month_log.size() > 36:
		P.month_log.pop_front()


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
