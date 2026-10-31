class_name Housing
extends RefCounted
## Wohnungsbestand, Mietverhaeltnisse und Raeumung (Auftrag 6, A1/A2, siehe docs/HOUSING_AND_MONEY.md).
##
## Die Karte enthaelt viel mehr Wohngebaeude, als die simulierte Bevoelkerung braucht. Nur ein Teil der Gebaeude (zufaellig, aber
## deterministisch aus dem Stadtsamen gewaehlt) wird mit Wohneinheiten belegt; alle uebrigen sind Kulisse ohne Bewohner und Miete.
## Jede Wohneinheit hat einen Mietvertrag mit einem Haushalt der Firmen ("H<n>") oder einer Buergergruppe (Buerger mit gleichem `home`).
## Die Miete fliesst von H0 an den Vermietersektor V0; V0 gibt sie als Instandhaltung (S0), Grundsteuer (P0) und
## Vermieterertrag (H0) weiter, es entsteht kein Geld. Nach EVICT_AFTER Monaten Rueckstand wird geraeumt.

const KINDS := {
	"house": {"units": 1, "area": 110.0},
	"semi": {"units": 2, "area": 80.0},
	"villa": {"units": 1, "area": 180.0},
	"apartment": {"units": 6, "area": 55.0},
	"highrise": {"units": 24, "area": 48.0},
}
const LANDLORD := "V0"
const RENT_PER_SQM := 2.6          # EUR je m2 und Spielmonat (Ausgangswert des Mietspiegels)
const VACANCY := 0.04              # Leerstand beim Start
const RESERVE_UNITS := 120         # zusaetzliche Einheiten fuer Firmenhaushalte und Zuzug
const EVICT_AFTER := 3             # Monate Mietrueckstand bis zur Raeumung
const MAINTENANCE_SHARE := 0.25    # Anteil der Mieteinnahmen fuer Instandhaltung (an S0)
const PROPERTY_TAX_SHARE := 0.10   # Grundsteuer (an P0); der Rest ist Vermieterertrag (an H0)

var sim: Simulation
var units := {}                    # "E<n>" -> {id, building, area, rent, tenant ("" | "H<n>" | "B" = Buergergruppe), arrears, paid}
var stats := {"rent": 0.0, "evictions": 0, "homeless": 0, "moves": 0}
var _next := 1


func setup(s: Simulation) -> void:
	sim = s
	s.month_changed.connect(on_month)


# ------------------------------------------------------------------ Bestand
## Legt den Bestand an und bringt alle Buerger und bereits vorhandene Firmenhaushalte unter.
func generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sim.city.seed_value) + 6006
	var people: Array = sim.citizens.people
	var groups: Array = []
	var i := 0
	while i < people.size():
		var g: Array = []
		for j in _group_size(rng):
			if i < people.size():
				g.append(people[i])
				i += 1
		groups.append(g)
	var need := ceili((groups.size() + RESERVE_UNITS) * (1.0 + VACANCY))
	var cands: Array = []
	for b in sim.city.buildings:
		if KINDS.has(b.type):
			cands.append(b)
	for k in range(cands.size() - 1, 0, -1):
		var j := rng.randi() % (k + 1)
		var t = cands[k]
		cands[k] = cands[j]
		cands[j] = t
	for b in cands:
		if units.size() >= need:
			break
		var k: Dictionary = KINDS[b.type]
		for n in int(k.units):
			var area: float = float(k.area) + (5.0 * (n % 3) if b.type == "apartment" or b.type == "highrise" else 0.0)
			var u := {"id": "E%d" % _next, "building": int(b.id), "area": area, "rent": roundf(area * RENT_PER_SQM), "tenant": "", "arrears": 0, "paid": 0.0}
			_next += 1
			units[u.id] = u
	# grosse Gruppen in grosse Einheiten
	groups.sort_custom(func(a, b): return a.size() > b.size())
	var free := vacant_units()
	free.sort_custom(func(a, b): return a.area > b.area or (a.area == b.area and a.id < b.id))
	for n in mini(groups.size(), free.size()):
		free[n].tenant = "B"
		for p in groups[n]:
			p.home = free[n].id
	for h in sim.households.homes.values():
		if str(h.get("unit", "")) == "":
			assign_household(h)


## Gruppengroesse 1-4 (Mittel ca. 2,3 Personen).
func _group_size(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	return 1 if r < 0.3 else (2 if r < 0.6 else (3 if r < 0.8 else 4))


func vacant_units() -> Array:
	return units.values().filter(func(u): return u.tenant == "")


func vacancy_rate() -> float:
	return float(vacant_units().size()) / maxf(1.0, float(units.size()))


## Ein Firmenhaushalt bekommt die freie Einheit, deren Flaeche am besten zur Haushaltsgroesse passt (35 m2 je Person).
func assign_household(h: Dictionary) -> Dictionary:
	var want := 35.0 * (1 + int(h.get("dependents", 0)) + maxi(0, h.members.size() - 1))
	var best: Dictionary = {}
	for u in vacant_units():
		if best.is_empty() or absf(u.area - want) < absf(best.area - want) or (absf(u.area - want) == absf(best.area - want) and u.id < best.id):
			best = u
	if best.is_empty():
		return {}
	best.tenant = str(h.id)
	best.arrears = 0
	h.unit = best.id
	h.address = int(best.building)
	return best


func unit_of_household(hid: String) -> Dictionary:
	var h: Dictionary = sim.households.homes.get(hid, {})
	return units.get(str(h.get("unit", "")), {})


func rent_of(hid: String) -> float:
	return float(unit_of_household(hid).get("rent", 0.0))


# ------------------------------------------------------------------ Mietzahlung
## Haushalt einer Firma zahlt (anteilig) seine Miete; `paid` ist der bereits von seinem Guthaben abgezogene Betrag.
func settle_household(hid: String, paid: float) -> void:
	var u := unit_of_household(hid)
	if u.is_empty():
		return
	if paid > 0.0:
		sim.economy.transfer("H0", LANDLORD, paid)
		stats.rent += paid
	u.paid = paid
	u.arrears = 0 if paid >= float(u.rent) - 0.01 else int(u.arrears) + 1


## Buergergruppen zahlen aus dem Netto ihrer Mitglieder (`net`, gesetzt von Citizens). Gibt die gezahlte Gesamtmiete zurueck.
func collect_citizen_rent() -> float:
	var occ := _citizen_occupants()
	var total := 0.0
	for uid in occ:
		var u: Dictionary = units[uid]
		var income := 0.0
		for p in occ[uid]:
			income += float(p.get("net", 0.0))
		var pay := minf(float(u.rent), income)
		if pay > 0.0:
			sim.economy.transfer("H0", LANDLORD, pay)
			total += pay
		u.paid = pay
		u.arrears = 0 if pay >= float(u.rent) - 0.01 else int(u.arrears) + 1
	stats.rent += total
	return total


func _citizen_occupants() -> Dictionary:
	var occ := {}
	for p in sim.citizens.people:
		var uid := str(p.get("home", ""))
		if uid != "" and units.has(uid):
			if not occ.has(uid):
				occ[uid] = []
			occ[uid].append(p)
	return occ


# ------------------------------------------------------------------ Monat
func on_month(_month: int) -> void:
	_distribute_landlord_income()
	_evict_overdue()
	_house_homeless()
	stats.homeless = homeless_count()


func _distribute_landlord_income() -> void:
	var cash := float(sim.economy.accounts.get(LANDLORD, 0.0))
	if cash <= 0.0:
		return
	sim.economy.transfer(LANDLORD, "S0", cash * MAINTENANCE_SHARE)
	sim.economy.transfer(LANDLORD, "P0", cash * PROPERTY_TAX_SHARE)
	sim.economy.transfer(LANDLORD, "H0", float(sim.economy.accounts[LANDLORD]))


func _evict_overdue() -> void:
	var occ := _citizen_occupants()
	for u in units.values():
		if u.tenant == "" or int(u.arrears) < EVICT_AFTER:
			continue
		var who := "Haushalt %s" % u.tenant
		if u.tenant == "B":
			who = "Familie in %s" % u.id
			for p in occ.get(u.id, []):
				p.home = ""
		elif sim.households.homes.has(u.tenant):
			sim.households.homes[u.tenant].unit = ""
		u.tenant = ""
		u.arrears = 0
		stats.evictions += 1
		sim.log_event("Räumung wegen Mietrückstand: %s verliert die Wohnung %s (Gebäude %d)." % [who, u.id, int(u.building)], "info")


## Wer ohne Wohnung ist (geraeumt oder zugezogen), bekommt die guenstigste freie Einheit.
func _house_homeless() -> void:
	var free := vacant_units()
	free.sort_custom(func(a, b): return a.rent < b.rent or (a.rent == b.rent and a.id < b.id))
	if free.is_empty():
		return
	var n := 0
	var seeking: Array = []
	for p in sim.citizens.people:
		if str(p.get("home", "")) == "":
			seeking.append(p)
	# Gruppen: jeweils bis zu vier Personen ohne Wohnung teilen sich eine Einheit
	var idx := 0
	while idx < seeking.size() and n < free.size():
		for j in 4:
			if idx < seeking.size():
				seeking[idx].home = free[n].id
				idx += 1
		free[n].tenant = "B"
		free[n].arrears = 0
		n += 1
		stats.moves += 1
	for h in sim.households.homes.values():
		if n >= free.size():
			break
		if str(h.get("unit", "")) == "":
			var u := assign_household(h)
			if not u.is_empty():
				n += 1
				stats.moves += 1


func homeless_count() -> int:
	var n := 0
	for p in sim.citizens.people:
		if str(p.get("home", "")) == "":
			n += 1
	return n


func summary() -> Dictionary:
	var occupied := units.size() - vacant_units().size()
	var rents := units.values().map(func(u): return float(u.rent))
	var avg := 0.0
	for r in rents:
		avg += r
	return {"einheiten": units.size(), "belegt": occupied, "leerstand": vacancy_rate(), "durchschnittsmiete": avg / maxf(1.0, float(rents.size())),
		"mieteinnahmen": stats.rent, "raeumungen": stats.evictions, "wohnungslos": homeless_count()}


func to_dict() -> Dictionary:
	return {"units": units, "stats": stats, "next": _next}


func from_dict(d: Dictionary) -> void:
	units = d.get("units", {})
	for u in units.values():
		u.building = int(u.building)
		u.arrears = int(u.arrears)
	stats = d.get("stats", stats)
	stats.evictions = int(stats.evictions)
	stats.homeless = int(stats.homeless)
	stats.moves = int(stats.moves)
	_next = int(d.get("next", 1))
