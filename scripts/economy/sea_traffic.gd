class_name SeaTraffic
extends RefCounted
## Seeverkehr zwischen den Hafenstaedten der Region (neben dem Linienschiff je Hafen, Harbor):
## - Kreuzfahrtschiff: faehrt reihum die Haefen an; die Gaeste gehen von Bord, buchen Hotels im Zielort (Tourism) und geben dort Geld aus.
## - Autotransporter: bringt Neufahrzeuge zum Fahrzeughandel des Zielorts (zusaetzliche Angebote beim Haendler).
## Jede Etappe: Ablegen am Tagesbeginn + DEPART_MIN, Ankunft nach TRIP_MIN, Liegezeit DOCK_MIN. Die Fahrt selbst ist eine
## deterministische Funktion der Spieluhr (ShipView zeichnet sie entlang eines Wasserwegs); Wirkungen treten bei Ankunft ein.

const DEPART_MIN := 10.0
const TRIP_MIN := 110.0
const DOCK_MIN := 50.0
const FLEET := [
	{"id": "KS1", "kind": "kreuzfahrt", "name": "MS Aurora", "every": 3, "offset": 1},
	{"id": "AT1", "kind": "autotransporter", "name": "Autocarrier Hansa", "every": 4, "offset": 2},
]
const CARS_PER_CALL := 2
const PAX_MIN := 40
const PAX_MAX := 120

var sim
var enabled := false
var ports: Array = []              # Ortsnummern mit Hafen
var legs: Dictionary = {}          # Schiff-ID -> aktuelle/letzte Etappe {ship, kind, name, from, to, depart, arrive, done}
var next_port: Dictionary = {}     # Schiff-ID -> Index in ports
var stats := {"etappen": 0, "gaeste": 0, "hotelbuchungen": 0, "fahrzeuge": 0}


func setup(simulation) -> void:
	sim = simulation
	ports.clear()
	for k in sim.towns.count():
		if sim.towns.harbor(k).enabled:
			ports.append(k)
	enabled = ports.size() >= 2 or (sim.neubeginn and ports.size() >= 1)
	if enabled:
		sim.day_changed.connect(on_day)


# ------------------------------------------------------------------ Neubeginn: Siedlerschiff (Benedikt 17.11.2026)
## "Neue Menschen kommen per Schiff, wenn die Stadt attraktiv wird": hat eine Hafenstadt freie Wohnungen, laeuft ein Siedlerschiff
## sie an; wie viele Haushalte an Bord sind, haengt an der Attraktivitaet (freier Wohnraum, Einrichtungen, Laeden/Betriebe, Marketing).
const SETTLER_EVERY := 2            # hoechstens alle 2 Tage ein Schiff je Stadt
const SETTLER_MIN_SCORE := 50
func attractiveness(k: int) -> Dictionary:
	var M: Mayor = sim.towns.mayor(k)
	var free: int = M.town_units().filter(func(u): return u.tenant == "").size()
	var score := 40
	var why: Array = ["Küste und freies Land +40"]
	if free > 0:
		score += 15
		why.append("%d freie Wohnungen +15" % free)
	else:
		why.append("keine freie Wohnung – ohne Wohnraum kommt kein Schiff")
	var fac: int = sim.municipal.of_town(k).size() if sim.municipal != null else 0
	if fac > 0:
		score += mini(20, 5 * fac)
		why.append("%d städtische Einrichtungen +%d" % [fac, mini(20, 5 * fac)])
	var firms := 0
	for b in sim.biz.items.values():
		if b.status in Businesses.RUNNING and sim.towns.of_building(int(b.site)) == k:
			firms += 1
	if firms > 0:
		score += mini(15, 5 * firms)
		why.append("%d Betriebe/Läden +%d" % [firms, mini(15, 5 * firms)])
	if M.marketing_boost > 0.0 and GameCalendar.month_of(sim.game_min) <= M.marketing_until:
		score += 10
		why.append("Stadtmarketing +10")
	return {"punkte": score, "freie_wohnungen": free, "gruende": why}


func _settlers_day(day: int) -> void:
	for k in ports:
		var key := "SI%d" % k
		var leg: Dictionary = legs.get(key, {})
		if not leg.is_empty() and (not bool(leg.done) or day - int(leg.get("day", -99)) < SETTLER_EVERY):
			continue
		var at := attractiveness(k)
		if int(at.freie_wohnungen) <= 0 or int(at.punkte) < SETTLER_MIN_SCORE:
			continue
		var from: int = ports[(ports.find(k) + ports.size() - 1) % ports.size()] if ports.size() > 1 else k
		var start := GameCalendar.day_start(day) + DEPART_MIN + 40.0 * float(ports.find(k))
		var hh := clampi(1 + (int(at.punkte) - SETTLER_MIN_SCORE) / 10, 1, int(at.freie_wohnungen))
		legs[key] = {"ship": key, "kind": "siedler", "name": "Siedlerschiff Neue Heimat", "from": from, "to": k, "depart": start, "arrive": start + TRIP_MIN,
			"done": false, "day": day, "haushalte": hh}
		sim.log_event("Ein Siedlerschiff nimmt Kurs auf %s: %d Haushalte wollen dort leben (Attraktivität %d)." % [sim.towns.name_of(k), hh, int(at.punkte)], "good")


func _settlers_arrive(leg: Dictionary) -> void:
	var k := int(leg.to)
	var M: Mayor = sim.towns.mayor(k)
	var free: Array = M.town_units().filter(func(u): return u.tenant == "")
	free.sort_custom(func(a, b): return a.id < b.id)
	var n := mini(int(leg.get("haushalte", 1)), free.size())
	var month := GameCalendar.month_of(sim.game_min)
	for i in n:
		sim.citizens.immigrate(int(round(Mayor.PERSONS_PER_UNIT)), month, str(free[i].id))
		free[i].tenant = "B"
		free[i].arrears = 0
	leg["angekommen"] = n
	stats["siedler"] = int(stats.get("siedler", 0)) + n
	sim.log_event("Das Siedlerschiff legt in %s an: %d Haushalte ziehen ein." % [sim.towns.name_of(k), n] if n > 0 else
		"Das Siedlerschiff legt in %s an, aber alle Wohnungen sind inzwischen belegt – die Siedler fahren weiter." % sim.towns.name_of(k), "good" if n > 0 else "warn")


func ship_def(id: String) -> Dictionary:
	for s in FLEET:
		if s.id == id:
			return s
	return {}


## Tageswechsel: Ankuenfte der laufenden Etappen wirken lassen, faellige Schiffe zur naechsten Hafenstadt schicken.
func on_day(day: int) -> void:
	if not enabled:
		return
	tick(sim.game_min)
	if sim.neubeginn:
		_settlers_day(day)
		return   # Neubeginn: noch keine Kreuzfahrt- und Autotransporter-Linien (keine Hotels, keine Haendler in den Orten)
	for s in FLEET:
		var leg: Dictionary = legs.get(s.id, {})
		if (day + int(s.offset)) % int(s.every) != 0:
			continue
		if not leg.is_empty() and not bool(leg.done):
			continue
		var i := int(next_port.get(s.id, int(s.offset) % ports.size()))
		var from: int = ports[i % ports.size()] if leg.is_empty() else int(leg.to)
		var to_i := (ports.find(from) + 1) % ports.size()
		var to: int = ports[to_i]
		next_port[s.id] = to_i
		var start := GameCalendar.day_start(day) + DEPART_MIN
		legs[s.id] = {"ship": s.id, "kind": s.kind, "name": s.name, "from": from, "to": to, "depart": start, "arrive": start + TRIP_MIN, "done": false}
		sim.log_event("%s legt in %s ab, Ziel %s." % [s.name, sim.towns.name_of(from), sim.towns.name_of(to)], "info")


## Je Spielminute: angekommene Schiffe wirken lassen.
func tick(now: float) -> void:
	if not enabled:
		return
	for leg in legs.values():
		if not bool(leg.done) and now >= float(leg.arrive):
			_arrive(leg)


## Etappen, die gerade sichtbar sind (unterwegs oder am Kai), fuer die Ansicht.
func visible_legs(now: float) -> Array:
	return legs.values().filter(func(l): return now >= float(l.depart) and now <= float(l.arrive) + DOCK_MIN)


func _arrive(leg: Dictionary) -> void:
	leg.done = true
	stats.etappen = int(stats.etappen) + 1
	var to := int(leg.to)
	if leg.kind == "siedler":
		_settlers_arrive(leg)
		return
	if leg.kind == "kreuzfahrt":
		var pax := PAX_MIN + posmod(int(stats.etappen) * 37 + to * 11, PAX_MAX - PAX_MIN)
		stats.gaeste = int(stats.gaeste) + pax
		var booked := 0
		for b in sim.biz.items.values():   # Gruppen von bis zu 8 Gaesten uebernachten in Hotels des Zielorts
			if b.branch != "hotel" or b.status not in Businesses.RUNNING or sim.towns.of_building(int(b.site)) != to:
				continue
			var persons := mini(8, pax - booked * 8)
			if persons <= 0:
				break
			if sim.tourism.book(str(b.id), persons, 1, 140.0 * persons).get("ok", false):
				booked += 1
		stats.hotelbuchungen = int(stats.hotelbuchungen) + booked
		leg["gaeste"] = pax
		sim.log_event("%s legt in %s an: %d Kreuzfahrtgäste gehen an Land%s." % [leg.name, sim.towns.name_of(to), pax,
			(", %d Gruppen buchen Hotels" % booked) if booked > 0 else ""], "good")
	else:
		var n := 0
		for b in sim.city.buildings:
			if b.role == "dealer" and sim.towns.of_building(int(b.id)) == to:
				for i in CARS_PER_CALL:
					sim.resources._new_offer(int(b.id))
					n += 1
				break
		stats.fahrzeuge = int(stats.fahrzeuge) + n
		leg["fahrzeuge"] = n
		sim.log_event("%s löscht in %s %d Neufahrzeuge für den Fahrzeughandel." % [leg.name, sim.towns.name_of(to), n], "info")


func summary() -> Dictionary:
	return {"aktiv": enabled, "haefen": ports.map(func(k): return sim.towns.name_of(k)), "schiffe": legs.values().map(func(l): return {"name": l.name, "art": l.kind,
		"von": sim.towns.name_of(int(l.from)), "nach": sim.towns.name_of(int(l.to)), "angekommen": l.done}), "statistik": stats}


func to_dict() -> Dictionary:
	return {"legs": legs, "next_port": next_port, "stats": stats}


func from_dict(d: Dictionary) -> void:
	legs = d.get("legs", {})
	next_port = d.get("next_port", {})
	for k in next_port:
		next_port[k] = int(next_port[k])
	stats = d.get("stats", stats)
	for l in legs.values():
		for key in ["from", "to"]:
			l[key] = int(l[key])
